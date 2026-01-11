#include <julia.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include "bridge.h"

// Define this only once in the executable/main library
JULIA_DEFINE_FAST_TLS

// Global reference to the FortranBridge module in Julia
jl_module_t* FortranBridgeMod = NULL;
jl_function_t* FuncRetain = NULL;
jl_function_t* FuncRelease = NULL;
jl_function_t* FuncRegister = NULL;
jl_function_t* FuncRegisterStr = NULL;

static pthread_t main_thread_id;
static char last_error_msg[2048] = "No error";

// --- Helper Functions ---

void set_error(const char* msg) {
    snprintf(last_error_msg, sizeof(last_error_msg), "%s", msg);
}

const char* fj_get_last_error() {
    return last_error_msg;
}

int check_thread() {
    if (pthread_self() != main_thread_id) {
        set_error("Thread Error: Julia functions called from wrong thread.");
        return 0; // Fail
    }
    return 1; // OK
}

#ifndef JULIA_BINDIR
#define JULIA_BINDIR NULL
#endif

int check_julia_exception() {
    if (jl_exception_occurred()) {
        jl_value_t *ex = jl_exception_occurred();
        jl_function_t *sprint = jl_get_function(jl_base_module, "sprint");
        jl_function_t *showerror = jl_get_function(jl_base_module, "showerror");
        
        if (sprint && showerror) {
            jl_value_t *err_str_val = jl_call2(sprint, showerror, ex);
            if (jl_is_string(err_str_val)) {
                set_error(jl_string_ptr(err_str_val));
            } else {
                set_error("Julia Exception Occurred (sprint failed)");
            }
        } else {
            fprintf(stderr, "Julia Exception: %s\n", jl_typeof_str(ex));
            set_error("Julia Exception Occurred (sprint/showerror not found)");
        }
        return 1; // Exception occurred
    }
    return 0; // No exception
}

void fj_init(const char* image_path) {
    if (jl_is_initialized()) return;

    main_thread_id = pthread_self();

    if (image_path != NULL) {
        jl_init_with_image(JULIA_BINDIR, image_path);
    } else {
        jl_init();
    }

    jl_value_t* mod_check = jl_eval_string("isdefined(Main, :FortranBridge)");
    int is_loaded = (mod_check && jl_unbox_bool(mod_check));

    if (!is_loaded) {
        jl_eval_string("include(\"middleware.jl\")");
        jl_eval_string("using .FortranBridge");
    } else {
        jl_eval_string("using Main.FortranBridge");
    }

    if (check_julia_exception()) {
        fprintf(stderr, "Error: Julia initialization failed (Loading FortranBridge).\nLast Error: %s\n", fj_get_last_error());
        exit(1);
    }

    jl_value_t* mod_val = jl_eval_string("FortranBridge");
    if (check_julia_exception()) {
        fprintf(stderr, "Error: Julia initialization failed (Getting FortranBridge module).\nLast Error: %s\n", fj_get_last_error());
        exit(1);
    }
    
    if (mod_val && jl_is_module(mod_val)) {
        FortranBridgeMod = (jl_module_t*)mod_val;
        FuncRetain = jl_get_function(FortranBridgeMod, "retain_obj");
        FuncRelease = jl_get_function(FortranBridgeMod, "release_obj");
        FuncRegister = jl_get_function(FortranBridgeMod, "register_f2");
        FuncRegisterStr = jl_get_function(FortranBridgeMod, "register_f2_string");
        
        if (!FuncRetain || !FuncRelease || !FuncRegister || !FuncRegisterStr) {
             fprintf(stderr, "Error: One or more FortranBridge functions could not be loaded.\n");
             exit(1);
        }
    } else {
        fprintf(stderr, "Error: Could not load FortranBridge module.\n");
        exit(1);
    }
}

void fj_shutdown() {
    jl_atexit_hook(0);
}

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

// --- Generic Calls ---

jl_value_t* fj_call0(const char* func_name) {
    if (!check_thread()) return NULL;
    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) func = jl_get_function(FortranBridgeMod, func_name);
    if (!func) {
        char err[256]; snprintf(err, 256, "Function %s not found.", func_name); set_error(err); return NULL;
    }
    jl_value_t* ret = jl_call0(func);
    if (check_julia_exception()) return NULL;
    return ret;
}

jl_value_t* fj_call1_float64(const char* func_name, double arg1) {
    if (!check_thread()) return NULL;
    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) func = jl_get_function(FortranBridgeMod, func_name);
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
    if (!check_thread()) return NULL;
    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) func = jl_get_function(FortranBridgeMod, func_name);
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
    if (!check_thread()) return NULL;
    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) func = jl_get_function(FortranBridgeMod, func_name);
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
    if (!check_thread()) return NULL;
    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) func = jl_get_function(FortranBridgeMod, func_name);
    if (!func) {
        char err[256]; snprintf(err, 256, "Function %s not found.", func_name); set_error(err); return NULL;
    }
    jl_value_t* ret = jl_call(func, (jl_value_t**)args, nargs);
    if (check_julia_exception()) return NULL;
    return ret;
}

jl_value_t* fj_eval_string(const char* cmd) {
    if (!check_thread()) return NULL;
    jl_value_t *ret = jl_eval_string(cmd);
    if (check_julia_exception()) return NULL;
    return ret;
}

void* fj_get_function_pointer(const char* func_name, const char* ret_type, const char* arg_types) {
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
    
    static jl_datatype_t* complex_f64_type = NULL;
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
    return jl_unbox_float64((jl_value_t*)obj);
}

long long fj_unbox_int64(void* obj) {
    if (!obj) return 0;
    return jl_unbox_int64((jl_value_t*)obj);
}

int fj_unbox_int32(void* obj) {
    if (!obj) return 0;
    return jl_unbox_int32((jl_value_t*)obj);
}

int fj_unbox_bool(void* obj) {
    if (!obj) return 0;
    return jl_unbox_bool((jl_value_t*)obj);
}

const char* fj_unbox_string(void* obj) {
    if (!obj) return NULL;
    if (!jl_is_string((jl_value_t*)obj)) return NULL;
    return jl_string_ptr((jl_value_t*)obj);
}

double fj_unbox_complex_real(void* obj) {
    if (!obj) return 0.0;
    return *(double*)jl_data_ptr((jl_value_t*)obj);
}

double fj_unbox_complex_imag(void* obj) {
    if (!obj) return 0.0;
    return *(((double*)jl_data_ptr((jl_value_t*)obj)) + 1);
}

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