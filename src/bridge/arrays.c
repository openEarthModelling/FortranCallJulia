#include "bridge_internal.h"

// --- Array Wrappers ---

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
