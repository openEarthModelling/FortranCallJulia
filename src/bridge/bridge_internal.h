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

// Helpers
void set_error(const char* msg);
int check_thread();
int check_julia_exception();

#endif
