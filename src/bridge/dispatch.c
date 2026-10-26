#include <stdio.h>
#include "bridge_internal.h"

// --- Function Name Cache (OPT-2) ---
// Caches func_name -> jl_function_t* so repeated calls skip jl_get_function
// and, for dotted names, the per-call jl_eval_string parse+eval.
//
// GC safety: a C static is NOT a GC root, so every cached function is routed
// through fj_retain() before it becomes reachable from the table below; the
// Julia-side root set (GCManager.PTR_CACHE) keeps it alive. Keys are heap
// copies; fj_clear_function_cache() frees the keys and releases the roots.
//
// Lifetime: fj_shutdown() clears this cache first (freeing the keys and
// releasing the roots) before tombstoning any C statics; calling
// fj_clear_function_cache() manually remains valid at any time.
//
// Threading: all bridge calls run on the init thread (check_thread enforces
// this), so the statics below need no locking.
#define FJ_FUNC_CACHE_CAP 256

typedef struct {
    char*          name;   // NULL => empty slot
    jl_function_t* func;
} fj_func_cache_slot_t;

static fj_func_cache_slot_t fj_func_cache[FJ_FUNC_CACHE_CAP];

// Julia-side counterpart of the clear below: FortranBridge.clear_kw_cache!
// (empties FunctionRegistry.KW_CACHE). Resolved lazily on first use;
// OPTIONAL -- an older FortranBridge build (e.g. a stale sysimage without
// the export) simply keeps the pre-change kwargs-cache behavior.
static jl_function_t* FuncClearKwCache = NULL;

static unsigned fj_func_cache_hash(const char* s) {
    unsigned h = 2166136261u; // FNV-1a
    while (*s) {
        h ^= (unsigned char)*s++;
        h *= 16777619u;
    }
    return h;
}

static jl_function_t* fj_func_cache_find(const char* name) {
    unsigned idx = fj_func_cache_hash(name) % FJ_FUNC_CACHE_CAP;
    for (int i = 0; i < FJ_FUNC_CACHE_CAP; i++) {
        fj_func_cache_slot_t *slot = &fj_func_cache[(idx + i) % FJ_FUNC_CACHE_CAP];
        if (slot->name == NULL) return NULL; // empty slot: name not cached
        if (strcmp(slot->name, name) == 0) return slot->func;
    }
    return NULL; // table full, no match
}

// Insert name->func. Roots func via fj_retain before storing. Ordering is:
// probe for a slot, copy the key, then retain -- so every failure path leaves
// nothing behind and the pointer is rooted the moment the table can reach it.
// Returns 1 on success; 0 if the table is full (eviction-free: the name just
// stays uncached), the key copy cannot be allocated, or fj_retain fails
// (error set by it) -- then the caller must treat func as unrooted, exactly
// as before the cache existed.
static int fj_func_cache_insert(const char* name, jl_function_t* func) {
    unsigned idx = fj_func_cache_hash(name) % FJ_FUNC_CACHE_CAP;
    fj_func_cache_slot_t *slot = NULL;
    for (int i = 0; i < FJ_FUNC_CACHE_CAP; i++) {
        fj_func_cache_slot_t *s = &fj_func_cache[(idx + i) % FJ_FUNC_CACHE_CAP];
        if (s->name == NULL) { slot = s; break; }
        if (strcmp(s->name, name) == 0) return 1; // already cached
    }
    if (!slot) return 0;
    slot->name = (char*)malloc(strlen(name) + 1);
    if (!slot->name) return 0;
    strcpy(slot->name, name);
    void* rooted = fj_retain((jl_value_t*)func);
    if (!rooted) {
        free(slot->name);
        slot->name = NULL;
        return 0;
    }
    slot->func = (jl_function_t*)rooted;
    return 1;
}

// Drop every redefinition-sensitive name cache:
//   1. the C-side function-name cache below (keys freed, GC roots released
//      via fj_release -- entries only exist while the runtime is live);
//   2. the Julia-side FunctionRegistry.KW_CACHE, via the optional
//      FortranBridge.clear_kw_cache! hook (see FuncClearKwCache above).
// Called from fj_shutdown (first, while the runtime still honors
// fj_release), automatically after every fj_eval_string (on BOTH outcome
// paths: top-level expressions commit as they evaluate, so an eval that
// rebinds names and then throws has still performed the rebinding), and
// manually via the Fortran SDK's julia_clear_function_cache. Julia-side
// work only runs while the runtime is live on the init thread.
void fj_clear_function_cache(void) {
    for (int i = 0; i < FJ_FUNC_CACHE_CAP; i++) {
        if (fj_func_cache[i].name != NULL) {
            free(fj_func_cache[i].name);
            fj_func_cache[i].name = NULL;
            if (fj_func_cache[i].func != NULL) {
                fj_release((void*)fj_func_cache[i].func);
                fj_func_cache[i].func = NULL;
            }
        }
    }
    if (fj_ready() && check_thread()) {
        if (FuncClearKwCache == NULL)
            FuncClearKwCache = jl_get_function(FortranBridgeMod, "clear_kw_cache!");
        if (FuncClearKwCache != NULL) {
            jl_call0(FuncClearKwCache);
            if (jl_exception_occurred()) jl_exception_clear();
        }
    }
}

// --- Internal Lookup Helper ---

static jl_function_t* lookup_function(const char* func_name) {
    // OPT-2: consult the function-name cache first.
    jl_function_t *cached = fj_func_cache_find(func_name);
    if (cached) return cached;

    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) func = jl_get_function(FortranBridgeMod, func_name);

    // Fallback: If name contains dots, it might be a module-qualified name.
    // We use jl_eval_string to resolve it.
    if (!func && strchr(func_name, '.')) {
        jl_value_t *val = jl_eval_string(func_name);
        if (val) {
            func = (jl_function_t*)val;
        }
    }

    // Cache fill on miss: fj_func_cache_insert retains func before it becomes
    // reachable from the static table (a C global is not a GC root).
    if (func) fj_func_cache_insert(func_name, func);
    return func;
}

// --- Generic Calls ---

jl_value_t* fj_call0(const char* func_name) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_function_t *func = lookup_function(func_name);
    if (!func) {
        char err[256]; snprintf(err, 256, "Function %s not found.", func_name); set_error(err); return NULL;
    }
    jl_value_t* ret = jl_call0(func);
    if (check_julia_exception()) return NULL;
    return ret;
}

jl_value_t* fj_call1_float64(const char* func_name, double arg1) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_function_t *func = lookup_function(func_name);
    if (!func) {
        char err[256]; snprintf(err, 256, "Function %s not found.", func_name); set_error(err); return NULL;
    }
    jl_value_t *arg1_val = NULL;
    JL_GC_PUSH1(&arg1_val);
    arg1_val = jl_box_float64(arg1);
    jl_value_t* ret = jl_call1(func, arg1_val);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return ret;
}

jl_value_t* fj_call1_obj(const char* func_name, void* arg_obj) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_function_t *func = lookup_function(func_name);
    if (!func) {
        char err[256]; snprintf(err, 256, "Function %s not found.", func_name); set_error(err); return NULL;
    }
    jl_value_t *arg_val = (jl_value_t*)arg_obj;
    JL_GC_PUSH1(&arg_val);
    jl_value_t* ret = jl_call1(func, arg_val);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return ret;
}

jl_value_t* fj_call2_obj_double(const char* func_name, void* arg_obj, double arg2) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_function_t *func = lookup_function(func_name);
    if (!func) {
        char err[256]; snprintf(err, 256, "Function %s not found.", func_name); set_error(err); return NULL;
    }
    jl_value_t *arg1_val = (jl_value_t*)arg_obj;
    jl_value_t *arg2_val = NULL;
    JL_GC_PUSH2(&arg1_val, &arg2_val);
    arg2_val = jl_box_float64(arg2);
    jl_value_t* ret = jl_call2(func, arg1_val, arg2_val);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return ret;
}

jl_value_t* fj_call_general(const char* func_name, void** args, int32_t nargs) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_function_t *func = lookup_function(func_name);
    if (!func) {
        char err[256]; snprintf(err, 256, "Function %s not found.", func_name); set_error(err); return NULL;
    }
    jl_value_t* ret = jl_call(func, (jl_value_t**)args, nargs);
    if (check_julia_exception()) return NULL;
    return ret;
}

// --- Function Handle API (OPT-2) ---

void* fj_resolve_function(const char* func_name) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_function_t *func = lookup_function(func_name);
    if (!func) {
        char err[256]; snprintf(err, 256, "Function %s not found.", func_name); set_error(err); return NULL;
    }
    // Return an OWNED reference rooted independently in the C-side root set
    // (fj_retain): eval-triggered cache invalidation releases the cache's
    // root, so a handle kept alive only by its cache entry would dangle
    // after any later eval. The caller owns this reference and balances it
    // with fj_release (the Fortran SDK's JuliaValue finalizer does exactly
    // that -- this now matches the SDK's documented ownership rule).
    void* rooted = fj_retain((jl_value_t*)func);
    return rooted;
}

jl_value_t* fj_call_function(void* func_handle, void** args, int32_t nargs) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    if (!func_handle) { set_error("fj_call_function: NULL function handle"); return NULL; }
    jl_function_t *func = (jl_function_t*)func_handle;
    jl_value_t* ret;
    if (nargs == 0) {
        ret = jl_call0(func); // args may be NULL here
    } else {
        ret = jl_call(func, (jl_value_t**)args, nargs);
    }
    if (check_julia_exception()) return NULL;
    return ret;
}

// Evaluate Julia source. fj_clear_function_cache() runs on BOTH outcome
// paths (top-level expressions commit as they evaluate, so a throwing eval
// can still have rebound names), so name-based calls observe any top-level
// rebinding the eval performed. See fj_clear_function_cache above for the
// rebinding paths this covers and the ones it cannot see.
jl_value_t* fj_eval_string(const char* cmd) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_value_t *ret = NULL;
    JL_GC_PUSH1(&ret); // the invalidation below can GC; keep the result rooted
    ret = jl_eval_string(cmd);
    int failed = check_julia_exception();
    fj_clear_function_cache();
    if (failed) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return ret;
}

void* fj_get_function_pointer(const char* func_name, const char* ret_type, const char* arg_types) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    if (!FuncRegisterStr) { set_error("register_f2_string function not loaded."); return NULL; }
    jl_value_t **args;
    JL_GC_PUSHARGS(args, 3);
    args[0] = jl_cstr_to_string(func_name);
    args[1] = jl_cstr_to_string(ret_type);
    args[2] = jl_cstr_to_string(arg_types);
    jl_value_t *ret_ptr = jl_call3(FuncRegisterStr, args[0], args[1], args[2]);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    if (ret_ptr) return jl_unbox_voidpointer(ret_ptr);
    return NULL;
}

// --- Keyword Argument Calls ---

// OPT-6: Vector{Any}/Vector{String} array types are immortal type-cache
// objects; build them once (lazily, on the first kwargs call) instead of on
// every call. Single-thread contract: only the init thread touches these.
static jl_value_t* kwarg_any_array_type = NULL;
static jl_value_t* kwarg_str_array_type = NULL;

jl_value_t* fj_call_kwargs(const char* func_name, void** args, int32_t nargs,
                           const char** kw_keys, void** kw_vals, int32_t nkw) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;

    if (!kwarg_any_array_type) kwarg_any_array_type = jl_apply_array_type((jl_value_t*)jl_any_type, 1);
    if (!kwarg_str_array_type) kwarg_str_array_type = jl_apply_array_type((jl_value_t*)jl_string_type, 1);

    jl_array_t *jl_args = NULL;
    jl_array_t *jl_keys = NULL;
    jl_array_t *jl_vals = NULL;
    jl_value_t *v_func_name = NULL;

    JL_GC_PUSH4(&jl_args, &jl_keys, &jl_vals, &v_func_name);

    // 1. Prepare Arguments Array (Vector{Any})
    jl_args = jl_alloc_array_1d(kwarg_any_array_type, nargs);
    
    for (int i = 0; i < nargs; i++) {
        jl_array_ptr_set(jl_args, i, (jl_value_t*)args[i]);
    }
    
    // 2. Prepare Keys Array (Vector{String})
    jl_keys = jl_alloc_array_1d(kwarg_str_array_type, nkw);
    
    for (int i = 0; i < nkw; i++) {
        jl_array_ptr_set(jl_keys, i, jl_cstr_to_string(kw_keys[i]));
    }
    
    // 3. Prepare Values Array (Vector{Any})
    jl_vals = jl_alloc_array_1d(kwarg_any_array_type, nkw);
    
    for (int i = 0; i < nkw; i++) {
        jl_array_ptr_set(jl_vals, i, (jl_value_t*)kw_vals[i]);
    }
    
    // 4. Call Helper
    v_func_name = jl_cstr_to_string(func_name);
    
    jl_value_t *call_args[4] = { v_func_name, (jl_value_t*)jl_args, (jl_value_t*)jl_keys, (jl_value_t*)jl_vals };
    jl_value_t *ret = jl_call(FuncCallKwargs, call_args, 4);
    
    if (check_julia_exception()) {
        JL_GC_POP();
        return NULL;
    }
    
    JL_GC_POP();
    return ret;
}

// --- %call Semantics Support ---

// True when the handle is a Julia Function object. The Fortran SDK uses this
// to route obj%call(...) on a function object to call_value(...) (true method
// call) instead of the legacy name-based global lookup.
int fj_is_function(void* handle) {
    if (!fj_ready()) return 0;
    if (!check_thread()) return 0;
    if (!handle) return 0;
    return jl_isa((jl_value_t*)handle, (jl_value_t*)jl_function_type) ? 1 : 0;
}
