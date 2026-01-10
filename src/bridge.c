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
jl_function_t* FuncRegisterStr = NULL; // New for string-based registration

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
        
        // Try to stringify the exception
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

    // Check if FortranBridge is already loaded (from sysimage)
    jl_value_t* mod_check = jl_eval_string("isdefined(Main, :FortranBridge)");
    int is_loaded = (mod_check && jl_unbox_bool(mod_check));

    if (!is_loaded) {
        // Not loaded, so include it dynamically (Development Mode)
        // printf("[C Bridge] Loading middleware.jl dynamically...\n");
        jl_eval_string("include(\"middleware.jl\")");
        jl_eval_string("using .FortranBridge");
    } else {
        // Loaded from sysimage
        // printf("[C Bridge] Using precompiled FortranBridge.\n");
        jl_eval_string("using Main.FortranBridge");
    }

    if (check_julia_exception()) {
        fprintf(stderr, "Error: Julia initialization failed (Loading FortranBridge).\nLast Error: %s\n", fj_get_last_error());
        exit(1);
    }

    // Cache the module and key functions
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
    
    JL_GC_PUSH1(&val);
    jl_call1(FuncRetain, val);
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
    
    // Call FortranBridge.release_obj(ptr)
    // Pass the pointer as a Ptr{Cvoid} (boxed)
    
    // Box the pointer to pass it to Julia
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
    if (!func) {
        // Try looking in FortranBridge just in case
        func = jl_get_function(FortranBridgeMod, func_name);
    }
    
    if (!func) {
        char err[256];
        snprintf(err, 256, "Function %s not found.", func_name);
        set_error(err);
        return NULL;
    }

    jl_value_t* ret = jl_call0(func);
    if (check_julia_exception()) return NULL;
    return ret;
}

jl_value_t* fj_call1_float64(const char* func_name, double arg1) {
    if (!check_thread()) return NULL;

    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) {
        func = jl_get_function(FortranBridgeMod, func_name);
    }

    if (!func) {
        char err[256];
        snprintf(err, 256, "Function %s not found.", func_name);
        set_error(err);
        return NULL;
    }

    // Secure argument boxing
    jl_value_t *arg1_val = NULL;
    JL_GC_PUSH1(&arg1_val);
    
    arg1_val = jl_box_float64(arg1);
    
    jl_value_t* ret = jl_call1(func, arg1_val);
    
    if (check_julia_exception()) {
        JL_GC_POP();
        return NULL;
    }
    
    JL_GC_POP();
    return ret;
}

jl_value_t* fj_call1_obj(const char* func_name, void* arg_obj) {
    if (!check_thread()) return NULL;

    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) {
        func = jl_get_function(FortranBridgeMod, func_name);
    }

    if (!func) {
        char err[256];
        snprintf(err, 256, "Function %s not found.", func_name);
        set_error(err);
        return NULL;
    }

    jl_value_t *arg_val = (jl_value_t*)arg_obj;
    // arg_val should be rooted by caller (Fortran JuliaValue), but pushing it is safe/cheap.
    JL_GC_PUSH1(&arg_val);
    
    jl_value_t* ret = jl_call1(func, arg_val);
    
    if (check_julia_exception()) {
        JL_GC_POP();
        return NULL;
    }
    
    JL_GC_POP();
    return ret;
}

jl_value_t* fj_eval_string(const char* cmd) {
    if (!check_thread()) return NULL;
    
    jl_value_t *ret = jl_eval_string(cmd);
    
    if (check_julia_exception()) return NULL;
    return ret;
}


// --- Fast Path ---

void* fj_get_function_pointer(const char* func_name, const char* ret_type, const char* arg_types) {
    if (!check_thread()) return NULL;

    if (!FuncRegisterStr) {
        set_error("register_f2_string function not loaded.");
        return NULL;
    }
    
    // Call FortranBridge.register_f2_string(func_name, ret_type, arg_types)
    
    jl_value_t **args;
    JL_GC_PUSHARGS(args, 3);
    
    args[0] = jl_cstr_to_string(func_name);
    args[1] = jl_cstr_to_string(ret_type);
    args[2] = jl_cstr_to_string(arg_types);
    
    jl_value_t *ret_ptr = jl_call3(FuncRegisterStr, args[0], args[1], args[2]);
    
    if (check_julia_exception()) {
        JL_GC_POP();
        return NULL;
    }
    
    JL_GC_POP();
    
    if (ret_ptr) {
        return jl_unbox_voidpointer(ret_ptr);
    }
    return NULL;
}

// --- Array Handling ---

jl_value_t* fj_wrap_array_1d(void* data, int64_t length) {
    if (!check_thread()) return NULL;

    // jl_ptr_to_array_1d(jl_value_t *atype, void *data, size_t nel, int own_buffer);
    
    jl_value_t *array_type = jl_apply_array_type((jl_value_t*)jl_float64_type, 1);
    
    // We do NOT own the buffer (Fortran owns it)
    jl_array_t *arr = jl_ptr_to_array_1d(array_type, data, length, 0);
    
    if (check_julia_exception()) return NULL;
    return (jl_value_t*)arr;
}
