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

// Call a Julia function by name with 0 arguments
// Returns a pointer to the result (already retained? No, usually temporary. 
// We should probably retain it if it's going back to Fortran OOP, but for now let's return raw jl_value_t*)
jl_value_t* fj_call0(const char* func_name);

// Call with 1 argument (Float64 example for now, but generic logic applies)
jl_value_t* fj_call1_float64(const char* func_name, double arg1);

// Call with 1 object argument
jl_value_t* fj_call1_obj(const char* func_name, void* arg_obj);


// --- Fast Path (Low-Level API) ---

// Get a raw C function pointer for a registered Julia function
// ret_type: String describing return type (e.g. "Float64")
// arg_types: String describing argument types tuple (e.g. "(Float64, Float64)")
void* fj_get_function_pointer(const char* func_name, const char* ret_type, const char* arg_types);

// --- Error Handling ---

// Get the last error message recorded by the bridge
const char* fj_get_last_error();


// --- Array Handling ---

// Create a Julia array wrapper around existing C/Fortran memory (Zero-Copy)
// dims: array of dimension sizes
// ndims: number of dimensions
jl_value_t* fj_wrap_array_1d(void* data, int64_t length);

#endif
