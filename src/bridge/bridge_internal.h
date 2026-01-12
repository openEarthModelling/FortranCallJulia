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

// Helpers
void set_error(const char* msg);
int check_thread();
int check_julia_exception();

#endif
