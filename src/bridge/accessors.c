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
    jl_value_t *v_i = NULL;
    jl_value_t *v_j = NULL;
    JL_GC_PUSH3(&v_obj, &v_i, &v_j);

    v_i = jl_box_int64(i);
    v_j = jl_box_int64(j);
    jl_value_t *ret = jl_call3(FuncGetIndex2D, v_obj, v_i, v_j);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    
    JL_GC_POP();
    return ret;
}

void fj_set_index_ii(void* obj, long long i, long long j, void* val) {
    if (!check_thread()) return;
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_val = (jl_value_t*)val;
    jl_value_t *v_i = NULL;
    jl_value_t *v_j = NULL;
    JL_GC_PUSH4(&v_obj, &v_val, &v_i, &v_j);

    // jl_call4 does not exist, use jl_call with array
    v_i = jl_box_int64(i);
    v_j = jl_box_int64(j);
    jl_value_t *args[4] = { v_obj, v_i, v_j, v_val };
    jl_call(FuncSetIndex2D, args, 4);
    
    check_julia_exception();
    JL_GC_POP();
}

void* fj_get_index_iii(void* obj, long long i, long long j, long long k) {
    if (!check_thread()) return NULL;
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_i = NULL;
    jl_value_t *v_j = NULL;
    jl_value_t *v_k = NULL;
    JL_GC_PUSH4(&v_obj, &v_i, &v_j, &v_k);

    v_i = jl_box_int64(i);
    v_j = jl_box_int64(j);
    v_k = jl_box_int64(k);
    jl_value_t *args[4] = { v_obj, v_i, v_j, v_k };
    jl_value_t *ret = jl_call(FuncGetIndex3D, args, 4);
    
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return ret;
}

void fj_set_index_iii(void* obj, long long i, long long j, long long k, void* val) {
    if (!check_thread()) return;
    jl_value_t *v_obj = (jl_value_t*)obj;
    jl_value_t *v_val = (jl_value_t*)val;
    jl_value_t *v_i = NULL;
    jl_value_t *v_j = NULL;
    jl_value_t *v_k = NULL;
    JL_GC_PUSH5(&v_obj, &v_val, &v_i, &v_j, &v_k);

    v_i = jl_box_int64(i);
    v_j = jl_box_int64(j);
    v_k = jl_box_int64(k);
    jl_value_t *args[5] = { v_obj, v_i, v_j, v_k, v_val };
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
    jl_value_t *v_dim = NULL;
    JL_GC_PUSH2(&v_obj, &v_dim);
    v_dim = jl_box_int64(dim);
    jl_value_t *ret = jl_call2(FuncSize, v_obj, v_dim);
    if (check_julia_exception()) { JL_GC_POP(); return -1; }
    long long sz = jl_unbox_int64(ret);
    JL_GC_POP();
    return sz;
}

void* fj_make_unitrange(long long start, long long stop) {
    if (!check_thread()) return NULL;
    jl_value_t *v_start = NULL;
    jl_value_t *v_stop = NULL;
    JL_GC_PUSH2(&v_start, &v_stop);
    v_start = jl_box_int64(start);
    v_stop = jl_box_int64(stop);
    jl_value_t *ret = jl_call2(FuncMakeUnitRange, v_start, v_stop);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return ret;
}

// --- Native Float64 Array Access (direct jl_array_data, no boxing) ---
// Reads/writes Array{Float64,N} data in place: no boxing, no helper call, no
// per-element retain. Indices are 1-based (Fortran order); memory layout is
// 0-based column-major, matching both Julia and Fortran.

// Cached Array{Float64,N} type objects. jl_apply_array_type returns immortal
// cache-owned instances for concrete element types, so they are safe as C
// statics without GC rooting; do NOT push them. Small per-file duplicates are
// intentional (arrays.c keeps its own). Lazy init is safe because all bridge
// calls run on the init thread (see check_thread).
static jl_value_t *arr_f64_1d = NULL, *arr_f64_2d = NULL, *arr_f64_3d = NULL;

// Lazily build the Array{Float64,N} type and verify obj is exactly that type.
// Returns obj as jl_array_t* on success, NULL (with error set) on failure.
static jl_array_t* check_f64_array(void* obj, int rank, jl_value_t** cache, const char* api) {
    if (!*cache) {
        jl_value_t *t = jl_apply_array_type((jl_value_t*)jl_float64_type, rank);
        if (check_julia_exception()) return NULL;
        *cache = t;
    }
    if (!jl_typeis((jl_value_t*)obj, *cache)) {
        char err[128];
        snprintf(err, sizeof(err), "%s: object is not Array{Float64,%d}", api, rank);
        set_error(err);
        return NULL;
    }
    return (jl_array_t*)obj;
}

double fj_get_real(void* arr, long long i) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return 0.0; }
    if (!check_thread()) return 0.0;
    if (!arr) { set_error("fj_get_real: NULL array"); return 0.0; }

    jl_value_t *v_arr = (jl_value_t*)arr;
    JL_GC_PUSH1(&v_arr);

    jl_array_t *a = check_f64_array(arr, 1, &arr_f64_1d, "fj_get_real");
    if (!a) { JL_GC_POP(); return 0.0; }

    long long n = (long long)jl_array_nrows(a);
    if (i < 1 || i > n) { set_error("fj_get_real: index out of bounds"); JL_GC_POP(); return 0.0; }

    double v = jl_array_data(a, double)[i - 1];
    JL_GC_POP();
    return v;
}

void fj_set_real(void* arr, long long i, double v) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return; }
    if (!check_thread()) return;
    if (!arr) { set_error("fj_set_real: NULL array"); return; }

    jl_value_t *v_arr = (jl_value_t*)arr;
    JL_GC_PUSH1(&v_arr);

    jl_array_t *a = check_f64_array(arr, 1, &arr_f64_1d, "fj_set_real");
    if (!a) { JL_GC_POP(); return; }

    long long n = (long long)jl_array_nrows(a);
    if (i < 1 || i > n) { set_error("fj_set_real: index out of bounds"); JL_GC_POP(); return; }

    jl_array_data(a, double)[i - 1] = v;
    JL_GC_POP();
}

double fj_get_real2(void* arr, long long i, long long j) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return 0.0; }
    if (!check_thread()) return 0.0;
    if (!arr) { set_error("fj_get_real2: NULL array"); return 0.0; }

    jl_value_t *v_arr = (jl_value_t*)arr;
    JL_GC_PUSH1(&v_arr);

    jl_array_t *a = check_f64_array(arr, 2, &arr_f64_2d, "fj_get_real2");
    if (!a) { JL_GC_POP(); return 0.0; }

    long long d1 = (long long)jl_array_dim(a, 0);
    long long d2 = (long long)jl_array_dim(a, 1);
    if (i < 1 || i > d1 || j < 1 || j > d2) { set_error("fj_get_real2: index out of bounds"); JL_GC_POP(); return 0.0; }

    double v = jl_array_data(a, double)[(i - 1) + (j - 1) * d1];
    JL_GC_POP();
    return v;
}

void fj_set_real2(void* arr, long long i, long long j, double v) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return; }
    if (!check_thread()) return;
    if (!arr) { set_error("fj_set_real2: NULL array"); return; }

    jl_value_t *v_arr = (jl_value_t*)arr;
    JL_GC_PUSH1(&v_arr);

    jl_array_t *a = check_f64_array(arr, 2, &arr_f64_2d, "fj_set_real2");
    if (!a) { JL_GC_POP(); return; }

    long long d1 = (long long)jl_array_dim(a, 0);
    long long d2 = (long long)jl_array_dim(a, 1);
    if (i < 1 || i > d1 || j < 1 || j > d2) { set_error("fj_set_real2: index out of bounds"); JL_GC_POP(); return; }

    jl_array_data(a, double)[(i - 1) + (j - 1) * d1] = v;
    JL_GC_POP();
}

double fj_get_real3(void* arr, long long i, long long j, long long k) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return 0.0; }
    if (!check_thread()) return 0.0;
    if (!arr) { set_error("fj_get_real3: NULL array"); return 0.0; }

    jl_value_t *v_arr = (jl_value_t*)arr;
    JL_GC_PUSH1(&v_arr);

    jl_array_t *a = check_f64_array(arr, 3, &arr_f64_3d, "fj_get_real3");
    if (!a) { JL_GC_POP(); return 0.0; }

    long long d1 = (long long)jl_array_dim(a, 0);
    long long d2 = (long long)jl_array_dim(a, 1);
    long long d3 = (long long)jl_array_dim(a, 2);
    if (i < 1 || i > d1 || j < 1 || j > d2 || k < 1 || k > d3) { set_error("fj_get_real3: index out of bounds"); JL_GC_POP(); return 0.0; }

    double v = jl_array_data(a, double)[(i - 1) + (j - 1) * d1 + (k - 1) * d1 * d2];
    JL_GC_POP();
    return v;
}

void fj_set_real3(void* arr, long long i, long long j, long long k, double v) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return; }
    if (!check_thread()) return;
    if (!arr) { set_error("fj_set_real3: NULL array"); return; }

    jl_value_t *v_arr = (jl_value_t*)arr;
    JL_GC_PUSH1(&v_arr);

    jl_array_t *a = check_f64_array(arr, 3, &arr_f64_3d, "fj_set_real3");
    if (!a) { JL_GC_POP(); return; }

    long long d1 = (long long)jl_array_dim(a, 0);
    long long d2 = (long long)jl_array_dim(a, 1);
    long long d3 = (long long)jl_array_dim(a, 2);
    if (i < 1 || i > d1 || j < 1 || j > d2 || k < 1 || k > d3) { set_error("fj_set_real3: index out of bounds"); JL_GC_POP(); return; }

    jl_array_data(a, double)[(i - 1) + (j - 1) * d1 + (k - 1) * d1 * d2] = v;
    JL_GC_POP();
}