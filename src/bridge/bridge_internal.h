#ifndef BRIDGE_INTERNAL_H
#define BRIDGE_INTERNAL_H

#include <julia.h>
#include <pthread.h>
#include "bridge.h" 

// Global Variables
extern jl_module_t* FortranBridgeMod;
extern jl_function_t* FuncRetain;
extern jl_function_t* FuncRelease;
extern jl_function_t* FuncRegister;
extern jl_function_t* FuncRegisterStr;
extern jl_function_t* FuncGetField;
extern jl_function_t* FuncSetField;
extern jl_function_t* FuncGetIndex;
extern jl_function_t* FuncSetIndex;
extern jl_function_t* FuncCallKwargs;

extern jl_function_t* FuncGetIndex2D;
extern jl_function_t* FuncSetIndex2D;
extern jl_function_t* FuncGetIndex3D;
extern jl_function_t* FuncSetIndex3D;
extern jl_function_t* FuncGetIndexString;
extern jl_function_t* FuncSetIndexString;
extern jl_function_t* FuncLength;
extern jl_function_t* FuncNdims;
extern jl_function_t* FuncSize;
extern jl_function_t* FuncMakeUnitRange;

// Native Float64 array element accessors (direct jl_array_data, no boxing;
// 1-based indices, column-major layout). Bound by the Fortran SDK.
double fj_get_real(void* arr, long long i);
void fj_set_real(void* arr, long long i, double v);
double fj_get_real2(void* arr, long long i, long long j);
void fj_set_real2(void* arr, long long i, long long j, double v);
double fj_get_real3(void* arr, long long i, long long j, long long k);
void fj_set_real3(void* arr, long long i, long long j, long long k, double v);

// Helpers
void set_error(const char* msg);
int check_thread();
int check_julia_exception();

#endif
