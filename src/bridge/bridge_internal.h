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

// Module cache invalidation for fj_shutdown. Each bridge module keeps
// lazily-resolved C statics (function bindings, cached types). They are
// rooted or immortal while the runtime lives; on shutdown the pointers are
// tombstoned so nothing dangles and post-shutdown calls hit the fj_ready
// guard with a clean slate. The runtime itself dies at jl_atexit_hook(0) --
// same-process re-initialization is not supported, so no Julia-side release
// is attempted here (the function-name cache is the exception: its C-side
// keys must be freed, and fj_shutdown releases it while the runtime can
// still honor fj_release).
void fj_callbacks_clear_cache(void);
void fj_extract_clear_cache(void);
void fj_arrays_clear_cache(void);
void fj_accessors_clear_cache(void);
void fj_memory_clear_cache(void);

#endif
