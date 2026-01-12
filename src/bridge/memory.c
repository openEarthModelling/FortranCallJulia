#include "bridge_internal.h"

// --- Object Management ---

void* fj_retain(jl_value_t* val) {
    if (!check_thread()) return NULL;
    if (val == NULL) return NULL;
    
    // Call FortranBridge.retain_obj(ptr, obj)
    // We pass the raw pointer address as the first argument (boxed as Ptr{Cvoid})
    // and the object itself as the second argument.
    
    jl_value_t *v_ptr = NULL;
    JL_GC_PUSH2(&val, &v_ptr); // Ensure val is rooted, and v_ptr
    
    v_ptr = jl_box_voidpointer(val);
    
    jl_call2(FuncRetain, v_ptr, val);
    
    if (check_julia_exception()) {
        JL_GC_POP();
        return NULL;
    }
    JL_GC_POP();

    return (void*)val;
}

void fj_release(void* ptr) {
    if (!check_thread()) return;
    if (ptr == NULL) return;
    
    jl_value_t* box_ptr = jl_box_voidpointer(ptr);
    JL_GC_PUSH1(&box_ptr);
    jl_call1(FuncRelease, box_ptr);
    check_julia_exception();
    JL_GC_POP();
}
