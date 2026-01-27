#include <stdio.h>
#include "bridge_internal.h"

// --- Internal Lookup Helper ---

static jl_function_t* lookup_function(const char* func_name) {
    jl_function_t *func = jl_get_function(jl_main_module, func_name);
    if (!func) func = jl_get_function(FortranBridgeMod, func_name);
    
    // Fallback: If name contains dots, it might be a module-qualified name.
    // We use jl_eval_string to resolve it.
    if (!func && strchr(func_name, '.')) {
        jl_value_t *val = jl_eval_string(func_name);
        if (val) {
            func = (jl_function_t*)val;
        }
    }
    return func;
}

// --- Generic Calls ---

jl_value_t* fj_call0(const char* func_name) {
    if (!check_thread()) return NULL;
    jl_function_t *func = lookup_function(func_name);
    if (!func) {
        char err[256]; snprintf(err, 256, "Function %s not found.", func_name); set_error(err); return NULL;
    }
    jl_value_t* ret = jl_call0(func);
    if (check_julia_exception()) return NULL;
    return ret;
}

jl_value_t* fj_call1_float64(const char* func_name, double arg1) {
    if (!check_thread()) return NULL;
    jl_function_t *func = lookup_function(func_name);
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
    jl_function_t *func = lookup_function(func_name);
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
    jl_function_t *func = lookup_function(func_name);
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
    jl_function_t *func = lookup_function(func_name);
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

// --- Keyword Argument Calls ---

jl_value_t* fj_call_kwargs(const char* func_name, void** args, int32_t nargs, 
                           const char** kw_keys, void** kw_vals, int32_t nkw) {
    if (!check_thread()) return NULL;
    
    jl_array_t *jl_args = NULL;
    jl_array_t *jl_keys = NULL;
    jl_array_t *jl_vals = NULL;
    jl_value_t *v_func_name = NULL;
    
    JL_GC_PUSH4(&jl_args, &jl_keys, &jl_vals, &v_func_name);
    
    // 1. Prepare Arguments Array (Vector{Any})
    jl_value_t *arg_array_type = jl_apply_array_type((jl_value_t*)jl_any_type, 1);
    jl_args = jl_alloc_array_1d(arg_array_type, nargs);
    
    for (int i = 0; i < nargs; i++) {
        jl_arrayset(jl_args, (jl_value_t*)args[i], i);
    }
    
    // 2. Prepare Keys Array (Vector{String})
    jl_value_t *str_array_type = jl_apply_array_type((jl_value_t*)jl_string_type, 1);
    jl_keys = jl_alloc_array_1d(str_array_type, nkw);
    
    for (int i = 0; i < nkw; i++) {
        jl_arrayset(jl_keys, jl_cstr_to_string(kw_keys[i]), i);
    }
    
    // 3. Prepare Values Array (Vector{Any})
    jl_vals = jl_alloc_array_1d(arg_array_type, nkw);
    
    for (int i = 0; i < nkw; i++) {
        jl_arrayset(jl_vals, (jl_value_t*)kw_vals[i], i);
    }
    
    // 4. Call Helper
    v_func_name = jl_cstr_to_string(func_name);
    
    jl_value_t *call_args[4] = { v_func_name, (jl_value_t*)jl_args, (jl_value_t*)jl_keys, (jl_value_t*)jl_vals };
    jl_value_t *ret = jl_call(FuncCallKwargs, call_args, 4);
    
    if (check_julia_exception()) {
        JL_GC_POP();
        return NULL;
    }
    
    JL_GC_POP();
    return ret;
}
