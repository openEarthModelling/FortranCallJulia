#include "bridge_internal.h"

// Cached ComplexF64 type, resolved lazily in fj_box_complex and used by the unbox guards
static jl_datatype_t* complex_f64_type = NULL;

// --- Boxing (Primitive -> Object) ---

void* fj_box_float64(double val) {
    if (!check_thread()) return NULL;
    return jl_box_float64(val);
}

void* fj_box_int64(long long val) {
    if (!check_thread()) return NULL;
    return jl_box_int64(val);
}

void* fj_box_int32(int val) {
    if (!check_thread()) return NULL;
    return jl_box_int32(val);
}

void* fj_box_bool(int val) {
    if (!check_thread()) return NULL;
    return jl_box_bool(val);
}

void* fj_box_string(const char* val) {
    if (!check_thread()) return NULL;
    return jl_cstr_to_string(val);
}

void* fj_box_complex(double re, double im) {
    if (!check_thread()) return NULL;
    jl_value_t *v_re = NULL;
    jl_value_t *v_im = NULL;
    JL_GC_PUSH2(&v_re, &v_im);
    v_re = jl_box_float64(re);
    v_im = jl_box_float64(im);
    
    if (!complex_f64_type) {
         jl_value_t* t = jl_eval_string("ComplexF64");
         if (t && jl_is_datatype(t)) complex_f64_type = (jl_datatype_t*)t;
    }
    
    jl_value_t *ret = NULL;
    if (complex_f64_type) {
        ret = jl_new_struct(complex_f64_type, v_re, v_im);
    }
    
    JL_GC_POP();
    return ret;
}


// --- Unboxing (Object -> Primitive) ---

double fj_unbox_float64(void* obj) {
    if (!obj) return 0.0;
    if (!jl_typeis((jl_value_t*)obj, jl_float64_type)) {
        set_error("fj_unbox_float64: object is not Float64");
        return 0.0;
    }
    return jl_unbox_float64((jl_value_t*)obj);
}

long long fj_unbox_int64(void* obj) {
    if (!obj) return 0;
    if (!jl_typeis((jl_value_t*)obj, jl_int64_type)) {
        set_error("fj_unbox_int64: object is not Int64");
        return 0;
    }
    return jl_unbox_int64((jl_value_t*)obj);
}

int fj_unbox_int32(void* obj) {
    if (!obj) return 0;
    if (!jl_typeis((jl_value_t*)obj, jl_int32_type)) {
        set_error("fj_unbox_int32: object is not Int32");
        return 0;
    }
    return jl_unbox_int32((jl_value_t*)obj);
}

int fj_unbox_bool(void* obj) {
    if (!obj) return 0;
    if (!jl_typeis((jl_value_t*)obj, jl_bool_type)) {
        set_error("fj_unbox_bool: object is not Bool");
        return 0;
    }
    return jl_unbox_bool((jl_value_t*)obj);
}

const char* fj_unbox_string(void* obj) {
    if (!obj) return NULL;
    if (!jl_is_string((jl_value_t*)obj)) return NULL;
    return jl_string_ptr((jl_value_t*)obj);
}

double fj_unbox_complex_real(void* obj) {
    if (!obj) return 0.0;
    if (complex_f64_type && !jl_typeis((jl_value_t*)obj, complex_f64_type)) {
        set_error("fj_unbox_complex_real: object is not ComplexF64");
        return 0.0;
    }
    return *(double*)jl_data_ptr((jl_value_t*)obj);
}

double fj_unbox_complex_imag(void* obj) {
    if (!obj) return 0.0;
    if (complex_f64_type && !jl_typeis((jl_value_t*)obj, complex_f64_type)) {
        set_error("fj_unbox_complex_imag: object is not ComplexF64");
        return 0.0;
    }
    return *(((double*)jl_data_ptr((jl_value_t*)obj)) + 1);
}
