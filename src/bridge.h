#ifndef FORT_JULIA_BRIDGE_H
#define FORT_JULIA_BRIDGE_H

#include <julia.h>

// Initialize Julia Runtime
// If image_path is NULL, initializes default system image.
void fj_init(const char* image_path);

// Shutdown Julia Runtime
void fj_shutdown();

// --- Object Management (High-Level API) ---

// Retain a Julia object (prevent GC). Returns a raw pointer that can be stored in Fortran.
void* fj_retain(jl_value_t* val);

// Release a Julia object (allow GC).
void fj_release(void* ptr);


// --- Generic Call Interface (High-Level API) ---

jl_value_t* fj_call0(const char* func_name);
jl_value_t* fj_call1_float64(const char* func_name, double arg1);
jl_value_t* fj_call1_obj(const char* func_name, void* arg_obj);
jl_value_t* fj_call2_obj_double(const char* func_name, void* arg_obj, double arg2);
jl_value_t* fj_eval_string(const char* cmd);


// --- Fast Path (Low-Level API) ---

// Get a raw C function pointer for a registered Julia function
// ret_type: String describing return type (e.g. "Float64")
// arg_types: String describing argument types tuple (e.g. "(Float64, Float64)")
void* fj_get_function_pointer(const char* func_name, const char* ret_type, const char* arg_types);

// --- Error Handling ---

// Get the last error message recorded by the bridge
const char* fj_get_last_error();


// Array Handling
jl_value_t* fj_wrap_array_1d(void* data, int64_t length);
jl_value_t* fj_wrap_array_2d(void* data, int64_t rows, int64_t cols);

#endif // BRIDGE_H
