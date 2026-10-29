#include "bridge_internal.h"

// --- Callback Bridge (Fortran RHS -> Julia callable) ---
//
// fcj_create_callback wraps a Fortran bind(c) RHS subroutine pointer into a
// Julia closure built by FortranBridge.Callbacks.create_callback, and binds
// that SAME closure object to Main.FJ_CALLBACK (latest created wins) so
// eval-ed solver code can reach it by name.
//
// GC hazards honored here:
//  - the @cfunction trampoline address is only ever BOXED as Ptr{Cvoid};
//    it is never treated as a Julia object;
//  - a C static is NOT a GC root: the cached module bindings below are
//    routed through fcj_retain before the statics can reach them (same
//    pattern as the function-name cache in dispatch.c);
//  - the returned closure handle goes through fcj_retain before it leaves
//    this function (C-side root set in memory.c).
//
// Kept self-contained like the other bridge modules: per-file statics,
// lazy resolution on first use. Lazy init is safe because all bridge calls
// run on the init thread (check_thread in core.c enforces it).
static jl_function_t* FuncCreateCallback = NULL; // FortranBridge.create_callback
static jl_function_t* FuncBindCallback = NULL;   // FortranBridge.bind_callback

// Resolve + retain the Callbacks bindings once. Returns 0 on success,
// -1 (with the last error set) on failure.
static int fcj_callbacks_resolve(void) {
    if (FuncCreateCallback && FuncBindCallback) return 0;

    jl_function_t* create = jl_get_function(FortranBridgeMod, "create_callback");
    jl_function_t* bindcb = jl_get_function(FortranBridgeMod, "bind_callback");
    if (!create || !bindcb) {
        set_error("fcj_create_callback: FortranBridge.create_callback/bind_callback not found (stale FortranBridge package build?)");
        return -1;
    }

    // Root before the statics can reach them.
    void* rooted_create = fcj_retain((jl_value_t*)create);
    if (!rooted_create) return -1;
    void* rooted_bind = fcj_retain((jl_value_t*)bindcb);
    if (!rooted_bind) return -1;

    FuncCreateCallback = (jl_function_t*)rooted_create;
    FuncBindCallback = (jl_function_t*)rooted_bind;
    return 0;
}

void* fcj_create_callback(void* fnptr, void* ctx) {
    if (!fcj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    if (fnptr == NULL) { set_error("fcj_create_callback: NULL Fortran RHS function pointer"); return NULL; }
    if (fcj_callbacks_resolve() != 0) return NULL;

    jl_value_t* v_fnptr = NULL;
    jl_value_t* v_ctx = NULL;
    jl_value_t* closure = NULL;
    JL_GC_PUSH3(&v_fnptr, &v_ctx, &closure);

    // Box the raw trampoline/context addresses as Ptr{Cvoid}; Julia never
    // dereferences them as objects.
    v_fnptr = jl_box_voidpointer(fnptr);
    v_ctx = jl_box_voidpointer(ctx);

    closure = jl_call2(FuncCreateCallback, v_fnptr, v_ctx);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    if (closure == NULL) {
        set_error("fcj_create_callback: create_callback returned NULL");
        JL_GC_POP();
        return NULL;
    }

    // Root the closure BEFORE it becomes reachable from C: the handle we
    // return must survive any GC after this function returns.
    void* handle = fcj_retain(closure);
    if (!handle) { JL_GC_POP(); return NULL; }

    // Bind Main.FJ_CALLBACK to the SAME closure object the handle points at.
    jl_call1(FuncBindCallback, (jl_value_t*)handle);
    if (check_julia_exception()) {
        fcj_release(handle); // drop the root we just took; report failure
        JL_GC_POP();
        return NULL;
    }

    JL_GC_POP();
    return handle;
}

// Invalidate the module caches. Called from fcj_shutdown: the pointers are
// only tombstoned (the objects die with the runtime at jl_atexit_hook(0));
// see the lifecycle note in bridge_internal.h.
void fcj_callbacks_clear_cache(void) {
    FuncCreateCallback = NULL;
    FuncBindCallback = NULL;
}
