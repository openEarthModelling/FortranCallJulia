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
├── examples/           # Example Applications
│   └── main.f90        # Demonstration of OOP and Fast Path usage
├── cmake/              # CMake modules
└── CMakeLists.txt      # Build Configuration
```

## Prerequisites

*   **Julia:** Version 1.6 or higher.
*   **Fortran Compiler:** `gfortran` (recommended) or `ifort`.
*   **C Compiler:** `gcc` or `clang`.
*   **CMake:** Version 3.10 or higher.

## Building and Running

1.  **Create a Build Directory:**
    ```bash
    mkdir build
    cd build
    ```

2.  **Configure with CMake:**
    ```bash
    cmake ..
    ```
    *Note: CMake will automatically attempt to find your `julia` executable in your PATH.*

3.  **Compile:**
    ```bash
    make
    ```

4.  **Run the Test Application:**
    ```bash
    ./test_app
    ```

## Usage Example

### 1. Initialize & High-Level Call
```fortran
type(julia_env) :: env
type(julia_value) :: val

call env%init()
val = env%eval("println(""Hello from Julia!"")")
```

### 2. Fast Path (Function Pointers)
```fortran
type(c_funptr) :: f_add
real(c_double) :: res

! Register function in Julia: @cfunction(add, Float64, (Float64, Float64))
f_add = env%get_func_ptr("add")

! Direct call via C pointer
call c_f_procpointer(f_add, f_ptr)
res = f_ptr(10.0d0, 20.0d0)
```
