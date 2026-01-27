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
│   ├── bridge/         # C Bridge Layer (Runtime & Type Management)
│   ├── lib_support/    # Fortran Interfaces
│   ├── middleware/     # Julia Helper Modules
│   └── julia_sdk.f90   # Main Fortran SDK
├── examples/           # Progressive Tutorial Suite
│   ├── 01_basics/      # Hello World, Arrays, Data Types
│   ├── 02_intermediate/# Math Ops, Kwargs
│   ├── 03_deployment/  # Sysimage, Compiled Libraries
│   ├── 04_performance/ # Call Overhead, Zero-Copy, Batching, Benchmarks
│   └── 05_hpc_parallel/# Multithreading, MPI
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
    # Basic
    ./examples/ex01_quickstart
    
    # Performance Demo
    ./examples/ex_perf_suite
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
