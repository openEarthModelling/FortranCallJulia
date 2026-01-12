#include <julia.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include "bridge_internal.h"

// Define this only once in the executable/main library
JULIA_DEFINE_FAST_TLS

// Global reference to the FortranBridge module in Julia
jl_module_t* FortranBridgeMod = NULL;
jl_function_t* FuncRetain = NULL;
jl_function_t* FuncRelease = NULL;
jl_function_t* FuncRegister = NULL;
jl_function_t* FuncRegisterStr = NULL;
jl_function_t* FuncGetField = NULL;
jl_function_t* FuncSetField = NULL;
jl_function_t* FuncGetIndex = NULL;
jl_function_t* FuncSetIndex = NULL;
jl_function_t* FuncCallKwargs = NULL;

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
        FuncGetField = jl_get_function(FortranBridgeMod, "helper_getfield");
        FuncSetField = jl_get_function(FortranBridgeMod, "helper_setfield");
        FuncGetIndex = jl_get_function(FortranBridgeMod, "helper_getindex");
        FuncSetIndex = jl_get_function(FortranBridgeMod, "helper_setindex");
        FuncCallKwargs = jl_get_function(FortranBridgeMod, "helper_call_kwargs");
        
        if (!FuncRetain || !FuncRelease || !FuncRegister || !FuncRegisterStr ||
            !FuncGetField || !FuncSetField || !FuncGetIndex || !FuncSetIndex || !FuncCallKwargs) {
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
