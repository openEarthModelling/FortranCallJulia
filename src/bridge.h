#ifndef FORT_JULIA_BRIDGE_H
#define FORT_JULIA_BRIDGE_H

#include <julia.h>

// Initialize Julia Runtime
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

// Call a Julia function with N arguments
jl_value_t* fj_call_general(const char* func_name, void** args, int32_t nargs);


// --- Fast Path (Low-Level API) ---
void* fj_get_function_pointer(const char* func_name, const char* ret_type, const char* arg_types);

// --- Error Handling ---
const char* fj_get_last_error();

// --- Boxing (C primitive -> Julia Object) ---
void* fj_box_float64(double val);
void* fj_box_int32(int val);
void* fj_box_int64(long long val);
void* fj_box_bool(int val); // 0 or 1
void* fj_box_string(const char* val);
void* fj_box_complex(double re, double im);

// --- Unboxing (Julia Object -> C primitive) ---
double fj_unbox_float64(void* obj);
long long fj_unbox_int64(void* obj);
int fj_unbox_int32(void* obj);
int fj_unbox_bool(void* obj);
const char* fj_unbox_string(void* obj);
double fj_unbox_complex_real(void* obj);
double fj_unbox_complex_imag(void* obj);

// --- Arrays ---
void* fj_wrap_array_1d(void* data, long dim1);
void* fj_wrap_array_2d(void* data, long dim1, long dim2);
void* fj_wrap_array_3d(void* data, long dim1, long dim2, long dim3);

#endif // BRIDGE_H