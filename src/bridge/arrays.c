#include "bridge_internal.h"
#include <string.h>

// --- Array Wrappers (Zero-Copy) ---

void* fj_wrap_array_1d(void* data, long dim1) {
    if (!check_thread()) return NULL;
    jl_value_t *array_type = jl_apply_array_type((jl_value_t*)jl_float64_type, 1);
    jl_array_t *arr = jl_ptr_to_array_1d(array_type, data, dim1, 0);
    if (check_julia_exception()) return NULL;
    return (void*)arr;
}

void* fj_wrap_array_2d(void* data, long dim1, long dim2) {
    if (!check_thread()) return NULL;
    jl_value_t *array_type = jl_apply_array_type((jl_value_t*)jl_float64_type, 2);
    
    jl_value_t *dims_tuple = NULL;
    JL_GC_PUSH1(&dims_tuple);
    
    jl_function_t *tuple_func = jl_get_function(jl_base_module, "tuple");
    jl_value_t *v_d1 = jl_box_long(dim1);
    jl_value_t *v_d2 = jl_box_long(dim2);
    
    dims_tuple = jl_call2(tuple_func, v_d1, v_d2);
    
    jl_array_t *arr = jl_ptr_to_array(array_type, data, dims_tuple, 0);
    
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return (void*)arr;
}

void* fj_wrap_array_3d(void* data, long dim1, long dim2, long dim3) {
    if (!check_thread()) return NULL;
    jl_value_t *array_type = jl_apply_array_type((jl_value_t*)jl_float64_type, 3);
    
    jl_value_t *dims_tuple = NULL;
    JL_GC_PUSH1(&dims_tuple);
    
    jl_function_t *tuple_func = jl_get_function(jl_base_module, "tuple");
    jl_value_t *v_d1 = jl_box_long(dim1);
    jl_value_t *v_d2 = jl_box_long(dim2);
    jl_value_t *v_d3 = jl_box_long(dim3);
    
    dims_tuple = jl_call3(tuple_func, v_d1, v_d2, v_d3);
    
    jl_array_t *arr = jl_ptr_to_array(array_type, data, dims_tuple, 0);
    
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return (void*)arr;
}

// --- Array Deep Copies (Alloc + Memcpy) ---

void* fj_copy_array_1d(void* data, long dim1) {
    if (!check_thread()) return NULL;
    jl_value_t *array_type = jl_apply_array_type((jl_value_t*)jl_float64_type, 1);
    
    // Allocate new array in Julia (managed by GC)
    jl_array_t *arr = jl_alloc_array_1d(array_type, dim1);
    
    // Copy data
    double* raw_data = (double*)jl_array_data(arr);
    memcpy(raw_data, data, dim1 * sizeof(double));
    
    if (check_julia_exception()) return NULL;
    return (void*)arr;
}

void* fj_copy_array_2d(void* data, long dim1, long dim2) {
    if (!check_thread()) return NULL;
    jl_value_t *array_type = jl_apply_array_type((jl_value_t*)jl_float64_type, 2);
    
    jl_value_t *dims_tuple = NULL;
    JL_GC_PUSH1(&dims_tuple);
    
    jl_function_t *tuple_func = jl_get_function(jl_base_module, "tuple");
    jl_value_t *v_d1 = jl_box_long(dim1);
    jl_value_t *v_d2 = jl_box_long(dim2);
    
    dims_tuple = jl_call2(tuple_func, v_d1, v_d2);
    
    // Alloc 2D
    jl_array_t *arr = jl_alloc_array_2d(array_type, dim1, dim2);
    // Note: jl_alloc_array_2d exists in API usually, or use jl_new_array(type, dims_tuple)
    // jl_alloc_array_2d is available in julia.h
    
    // Copy data
    double* raw_data = (double*)jl_array_data(arr);
    memcpy(raw_data, data, dim1 * dim2 * sizeof(double));
    
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return (void*)arr;
}

void* fj_copy_array_3d(void* data, long dim1, long dim2, long dim3) {
    if (!check_thread()) return NULL;
    jl_value_t *array_type = jl_apply_array_type((jl_value_t*)jl_float64_type, 3);
    
    jl_value_t *dims_tuple = NULL;
    JL_GC_PUSH1(&dims_tuple);
    
    jl_function_t *tuple_func = jl_get_function(jl_base_module, "tuple");
    jl_value_t *v_d1 = jl_box_long(dim1);
    jl_value_t *v_d2 = jl_box_long(dim2);
    jl_value_t *v_d3 = jl_box_long(dim3);
    
    dims_tuple = jl_call3(tuple_func, v_d1, v_d2, v_d3);
    
    // Alloc 3D
    jl_array_t *arr = jl_alloc_array_3d(array_type, dim1, dim2, dim3);
    
    // Copy data
    double* raw_data = (double*)jl_array_data(arr);
    memcpy(raw_data, data, dim1 * dim2 * dim3 * sizeof(double));
    
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return (void*)arr;
}