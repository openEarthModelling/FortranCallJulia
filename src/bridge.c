#include <julia.h>
#include <stdio.h>
#include <stdlib.h>
#include "bridge.h"

// Define this only once in the executable/main library
JULIA_DEFINE_FAST_TLS

// Global reference to the FortranBridge module in Julia
jl_module_t* FortranBridgeMod = NULL;
jl_function_t* FuncRetain = NULL;
jl_function_t* FuncRelease = NULL;
jl_function_t* FuncRegister = NULL;

void check_julia_exception() {
    if (jl_exception_occurred()) {
        jl_value_t *ex = jl_exception_occurred();
        fprintf(stderr, "Julia Exception Occurred: %s\n", jl_typeof_str(ex));
        
        // Try to print the error object using 'showerror' or 'println'
        // Simple way: call show(stderr, ex)
        jl_function_t *show = jl_get_function(jl_base_module, "show");
        if (show) {
            jl_call2(show, jl_stderr_obj(), ex);
            fprintf(stderr, "\n");
        }
    }
}

void fj_init(const char* image_path) {
    if (jl_is_initialized()) return;

    if (image_path != NULL) {
        jl_init_with_image(NULL, image_path);
    } else {
        jl_init();
    }

    // Load the middleware logic
    // In a real deployment, this might be precompiled into the sysimage.
    // Here we load it dynamically.
    jl_eval_string("include(\"middleware.jl\")");
    jl_eval_string("using .FortranBridge");
    check_julia_exception();

    // Cache the module and key functions
    jl_value_t* mod_val = jl_eval_string("FortranBridge");
    check_julia_exception();
    
    if (mod_val && jl_is_module(mod_val)) {
        FortranBridgeMod = (jl_module_t*)mod_val;
        FuncRetain = jl_get_function(FortranBridgeMod, "retain_obj");
        FuncRelease = jl_get_function(FortranBridgeMod, "release_obj");
        FuncRegister = jl_get_function(FortranBridgeMod, "register_f2");
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
    if (val == NULL) return NULL;
    
    // Call FortranBridge.retain_obj(val)
    // We must protect 'val' before this call just in case, though it's likely already protected by caller context.
    // But strictly speaking, if 'val' came from a previous call without retention, it might be at risk if we alloc.
    
    JL_GC_PUSH1(&val);
    jl_call1(FuncRetain, val);
    check_julia_exception();
    JL_GC_POP();

    return (void*)val;
}

void fj_release(void* ptr) {
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
    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) {
        // Try looking in FortranBridge just in case
        func = jl_get_function(FortranBridgeMod, func_name);
    }
    
    if (!func) {
        fprintf(stderr, "Function %s not found.\n", func_name);
        return NULL;
    }

    jl_value_t* ret = jl_call0(func);
    check_julia_exception();
    return ret;
}

jl_value_t* fj_call1_float64(const char* func_name, double arg1) {
    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) {
        func = jl_get_function(FortranBridgeMod, func_name);
    }

    if (!func) {
        fprintf(stderr, "Function %s not found.\n", func_name);
        return NULL;
    }

    // Secure argument boxing
    jl_value_t *arg1_val = NULL;
    JL_GC_PUSH1(&arg1_val);
    
    arg1_val = jl_box_float64(arg1);
    
    jl_value_t* ret = jl_call1(func, arg1_val);
    check_julia_exception();
    
    JL_GC_POP();
    return ret;
}

jl_value_t* fj_call1_obj(const char* func_name, void* arg_obj) {
    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) {
        func = jl_get_function(FortranBridgeMod, func_name);
    }

    if (!func) {
        fprintf(stderr, "Function %s not found.\n", func_name);
        return NULL;
    }

    jl_value_t *arg_val = (jl_value_t*)arg_obj;
    // arg_val should be rooted by caller (Fortran JuliaValue), but pushing it is safe/cheap.
    JL_GC_PUSH1(&arg_val);
    
    jl_value_t* ret = jl_call1(func, arg_val);
    check_julia_exception();
    
    JL_GC_POP();
    return ret;
}


// --- Fast Path ---

void* fj_get_function_pointer(const char* func_name) {
    // Call register_f2(func_name, return_type, arg_types)
    // For simplicity in this demo, let's assume register_f2 knows the types or defaults to something.
    // Actually, to make this generic from C is hard without passing type info.
    // For the demo, I will hardcode a call to register 'julia_add' (Float64, Float64) -> Float64
    // or let the Julia side handle the registration via a specific helper if needed.
    
    // Better approach for the demo:
    // Let's call a specific helper in Julia that does the registration for a specific known signature.
    // Or we assume func_name refers to a function we know how to register.
    
    // To strictly follow the plan: "implement get_f2_pointer calling Julia registration"
    // We will call: FortranBridge.register_f2(:func_name, Float64, (Float64, Float64))
    // Just for the 'julia_add' example.
    
    jl_sym_t *sym = jl_symbol(func_name);
    jl_value_t *rtype = (jl_value_t*)jl_float64_type;
    
    // Tuple type creation is complex in C.
    // Easier: Eval a string command to do the registration if possible, or construct tuple.
    // "register_f2(:func_name, Float64, (Float64, Float64))"
    
    // Constructing the call via jl_call3
    // We need a tuple type (Float64, Float64).
    jl_value_t *float_type = (jl_value_t*)jl_float64_type;
    jl_value_t *tuple_type = jl_apply_tuple_type_v(&float_type, 1); // 1 arg example?
    // Wait, julia_add is 2 args.
    
    // Let's just use eval_string for the specific example registration to keep C code simple for now.
    // In production, you'd want robust type passing.
    
    char cmd[256];
    snprintf(cmd, 256, "FortranBridge.register_f2(:%s, Float64, (Float64, Float64))", func_name);
    
    jl_value_t *ret_ptr = jl_eval_string(cmd);
    check_julia_exception();
    
    if (ret_ptr) {
        return jl_unbox_voidpointer(ret_ptr);
    }
    return NULL;
}

// --- Array Handling ---

jl_value_t* fj_wrap_array_1d(void* data, int64_t length) {
    // jl_ptr_to_array_1d(jl_value_t *atype, void *data, size_t nel, int own_buffer);
    
    jl_value_t *array_type = jl_apply_array_type((jl_value_t*)jl_float64_type, 1);
    
    // We do NOT own the buffer (Fortran owns it)
    jl_array_t *arr = jl_ptr_to_array_1d(array_type, data, length, 0);
    
    return (jl_value_t*)arr;
}
