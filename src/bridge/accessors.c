#include "bridge_internal.h"

// --- Field Access (Struct / NamedTuple) ---

void* fj_get_field(void* obj, const char* name) {
    if (!check_thread()) return NULL;
    if (!obj) return NULL;
    
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_name = NULL;
    
    JL_GC_PUSH2(&v_obj, &v_name);
    
    v_name = jl_cstr_to_string(name);
    jl_value_t *ret = jl_call2(FuncGetField, v_obj, v_name);
    
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    
    JL_GC_POP();
    return ret;
}

void fj_set_field(void* obj, const char* name, void* val) {
    if (!check_thread()) return;
    if (!obj) return; // val can be NULL (nothing/missing)? Julia Any usually isn't NULL pointer in C except when we handle it.
                      // Here val is a jl_value_t* really.
    
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_val = (jl_value_t*)val; // If NULL, what to do? Usually we box it before passing.
    jl_value_t *v_name = NULL;

    JL_GC_PUSH3(&v_obj, &v_val, &v_name);
    
    v_name = jl_cstr_to_string(name);
    jl_call3(FuncSetField, v_obj, v_name, v_val);
    
    check_julia_exception();
    JL_GC_POP();
}

// --- Index Access (Array / Tuple) ---

void* fj_get_index_i(void* obj, long long idx) {
    if (!check_thread()) return NULL;
    if (!obj) return NULL;

    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_idx = NULL;
    
    JL_GC_PUSH2(&v_obj, &v_idx);
    
    v_idx = jl_box_int64(idx);
    jl_value_t *ret = jl_call2(FuncGetIndex, v_obj, v_idx);
    
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return ret;
}

void fj_set_index_i(void* obj, long long idx, void* val) {
    if (!check_thread()) return;
    if (!obj) return;
    
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_val = (jl_value_t*)val;
    jl_value_t *v_idx = NULL;
    
    JL_GC_PUSH3(&v_obj, &v_val, &v_idx);
    
    v_idx = jl_box_int64(idx);
    jl_call3(FuncSetIndex, v_obj, v_idx, v_val);
    
    check_julia_exception();
    JL_GC_POP();
}
