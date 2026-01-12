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
    if (!obj) return;
    
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_val = (jl_value_t*)val;
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

// --- Extended Accessors ---

void* fj_get_index_ii(void* obj, long long i, long long j) {
    if (!check_thread()) return NULL;
    jl_value_t *v_obj = (jl_value_t*)obj;
    JL_GC_PUSH1(&v_obj);
    
    jl_value_t *ret = jl_call3(FuncGetIndex2D, v_obj, jl_box_int64(i), jl_box_int64(j));
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    
    JL_GC_POP();
    return ret;
}

void fj_set_index_ii(void* obj, long long i, long long j, void* val) {
    if (!check_thread()) return;
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_val = (jl_value_t*)val;
    JL_GC_PUSH2(&v_obj, &v_val);
    
    // jl_call4 does not exist, use jl_call with array
    jl_value_t *args[4] = { v_obj, jl_box_int64(i), jl_box_int64(j), v_val };
    jl_call(FuncSetIndex2D, args, 4);
    
    check_julia_exception();
    JL_GC_POP();
}

void* fj_get_index_iii(void* obj, long long i, long long j, long long k) {
    if (!check_thread()) return NULL;
    jl_value_t *v_obj = (jl_value_t*)obj;
    JL_GC_PUSH1(&v_obj);
    
    jl_value_t *args[4] = { v_obj, jl_box_int64(i), jl_box_int64(j), jl_box_int64(k) };
    jl_value_t *ret = jl_call(FuncGetIndex3D, args, 4);
    
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return ret;
}

void fj_set_index_iii(void* obj, long long i, long long j, long long k, void* val) {
    if (!check_thread()) return;
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_val = (jl_value_t*)val;
    JL_GC_PUSH2(&v_obj, &v_val);
    
    jl_value_t *args[5] = { v_obj, jl_box_int64(i), jl_box_int64(j), jl_box_int64(k), v_val };
    jl_call(FuncSetIndex3D, args, 5);
    
    check_julia_exception();
    JL_GC_POP();
}

void* fj_get_index_s(void* obj, const char* key) {
    if (!check_thread()) return NULL;
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_key = NULL;
    JL_GC_PUSH2(&v_obj, &v_key);
    
    v_key = jl_cstr_to_string(key);
    jl_value_t *ret = jl_call2(FuncGetIndexString, v_obj, v_key);
    
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return ret;
}

void fj_set_index_s(void* obj, const char* key, void* val) {
    if (!check_thread()) return;
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_val = (jl_value_t*)val;
    jl_value_t *v_key = NULL;
    JL_GC_PUSH3(&v_obj, &v_val, &v_key);
    
    v_key = jl_cstr_to_string(key);
    jl_call3(FuncSetIndexString, v_obj, v_key, v_val);
    
    check_julia_exception();
    JL_GC_POP();
}

// --- Introspection ---

long long fj_length(void* obj) {
    if (!check_thread()) return -1;
    jl_value_t *v_obj = (jl_value_t*)obj;
    JL_GC_PUSH1(&v_obj);
    jl_value_t *ret = jl_call1(FuncLength, v_obj);
    if (check_julia_exception()) { JL_GC_POP(); return -1; }
    long long len = jl_unbox_int64(ret);
    JL_GC_POP();
    return len;
}

long long fj_ndims(void* obj) {
    if (!check_thread()) return -1;
    jl_value_t *v_obj = (jl_value_t*)obj;
    JL_GC_PUSH1(&v_obj);
    jl_value_t *ret = jl_call1(FuncNdims, v_obj);
    if (check_julia_exception()) { JL_GC_POP(); return -1; }
    long long nd = jl_unbox_int64(ret);
    JL_GC_POP();
    return nd;
}

long long fj_size(void* obj, int dim) {
    if (!check_thread()) return -1;
    jl_value_t *v_obj = (jl_value_t*)obj;
    JL_GC_PUSH1(&v_obj);
    jl_value_t *ret = jl_call2(FuncSize, v_obj, jl_box_int64(dim));
    if (check_julia_exception()) { JL_GC_POP(); return -1; }
    long long sz = jl_unbox_int64(ret);
    JL_GC_POP();
    return sz;
}

void* fj_make_unitrange(long long start, long long stop) {
    if (!check_thread()) return NULL;
    jl_value_t *ret = jl_call2(FuncMakeUnitRange, jl_box_int64(start), jl_box_int64(stop));
    if (check_julia_exception()) return NULL;
    return ret;
}