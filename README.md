# Fortran-Julia High-Performance Middleware

A robust cross-language middleware that allows Fortran programs to efficiently call Julia functions through a C bridge layer. Designed for high-performance scientific computing, this project enables seamless integration between legacy Fortran codebases and the modern Julia ecosystem.

## Key Features

*   **Hybrid Architecture:** 
    *   **High-Level OOP:** Use `JuliaValue` objects in Fortran for convenient, automatic memory-managed interactions (GC-safe).
    *   **Fast Path:** Access raw function pointers for high-performance tight loops (10-100x faster than generic calls).
*   **Zero-Copy Arrays:** Efficiently pass Fortran arrays to Julia without data duplication.
*   **Robustness:** Comprehensive exception handling and lifecycle management.

## Project Structure

```text
.
├── src/                # Core Source Code
│   ├── bridge.c        # C Bridge Layer (Runtime & Type Management)
│   ├── julia_sdk.f90   # Fortran SDK (OOP Wrapper & iso_c_binding)
│   └── middleware.jl   # Julia Side Registration & GC Protection
├── examples/           # Tutorial & Examples
│   ├── 01_hello.f90    # Basic Initialization
│   ├── 02_math_oop.f90 # OOP Interface & Math
│   ├── 03_performance.f90 # Fast Path Performance Demo
│   ├── 04_arrays.f90   # Zero-Copy Array Passing
│   ├── 05_errors.f90   # Error Handling
│   └── 06_sysimage.f90 # AOT / Sysimage Loading
└── CMakeLists.txt      # Build Configuration
```

## Prerequisites

*   **Julia:** Version 1.6 or higher.
*   **Fortran Compiler:** `gfortran` (recommended) or `ifort`.
*   **C Compiler:** `gcc` or `clang`.
*   **CMake:** Version 3.10 or higher.

## Building

### Standard Build (Library + Examples)

1.  **Create a Build Directory:**
    ```bash
    mkdir build && cd build
    ```

2.  **Configure:**
    ```bash
    cmake -DBUILD_EXAMPLES=ON ..
    ```

3.  **Compile:**
    ```bash
    make
    ```

4.  **Run Examples:**
    ```bash
    ./examples/ex01_hello
    ./examples/ex03_performance
    ```

### Separated Compilation (Install Library, Build Examples Standalone)

1.  **Build and Install Library:**
    ```bash
    mkdir build && cd build
    cmake -DCMAKE_INSTALL_PREFIX=../install_dist ..
    make install
    ```

2.  **Build Examples Standalone:**
    ```bash
    cd ../examples
    mkdir build && cd build
    cmake -DCMAKE_PREFIX_PATH=../../install_dist ..
    make
    ```

## Usage Example

### 1. Initialize & High-Level Call
```fortran
use julia_high_level

call julia_init()

block
    type(JuliaValue) :: ctx, res
    ! Call OOP method
    res = ctx%call_method_1_real("sqrt", 2.0d0)
end block

call julia_shutdown()
```

### 2. Fast Path (Function Pointers)
```fortran
type(c_funptr) :: c_ptr
procedure(proto), pointer :: f_ptr

! Get raw function pointer from Julia
c_ptr = get_function_pointer("julia_add", "Float64", "(Float64, Float64)")
call c_f_procpointer(c_ptr, f_ptr)

! Zero-overhead call
res = f_ptr(10.0d0, 20.0d0)
```
