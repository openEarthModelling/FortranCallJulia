# Fortran-Julia High-Performance Middleware

## Project Overview

This project aims to develop a robust cross-language middleware that allows Fortran programs to efficiently call Julia functions through a C bridge layer. It is designed to support high-performance scientific computing needs.

**Key Goals:**
*   **High Performance:** Support JIT/AOT dual modes and high-performance function pointer calls.
*   **Efficiency:** Zero-copy array passing between Fortran and Julia.
*   **Robustness:** Comprehensive exception capturing and handling.
*   **Usability:** idiomatic Fortran SDK.

## Architecture

The project is structured into three main layers:

1.  **Julia Layer (`middleware.jl`):**
    *   Acts as the registration center.
    *   Manages function pointers and prevents Garbage Collection (GC) of active objects using `IdDict`.
    *   Provides tools for array processing and C-compatible function generation.

2.  **C Bridge Layer (`bridge.c`):**
    *   Manages the Julia runtime lifecycle (initialization/finalization).
    *   Handles data exchange and type bridging.
    *   Implements exception handling mechanisms.
    *   Provides zero-copy array encapsulation using `jl_ptr_to_array`.

3.  **Fortran SDK (`julia_sdk.f90`):**
    *   Provides a user-friendly API using `iso_c_binding`.
    *   Encapsulates the complexity of the C bridge.
    *   Offers object-oriented wrappers (e.g., `julia_env`).

## Development Plan & Status

The project is currently in the **Planning/Initial Implementation** phase.

*   [ ] **Stage 1: Julia Registration Center** (`middleware.jl`) - Function management and GC prevention.
*   [ ] **Stage 2: C Bridge Core** (`bridge.c`) - Runtime management, AOT support, exception handling.
*   [ ] **Stage 3: Fortran SDK** (`julia_sdk.f90`) - API encapsulation and `iso_c_binding`.
*   [ ] **Stage 4: Build System** - Makefile and AOT compilation scripts.
*   [ ] **Stage 5: Future Optimizations** - Thread safety, memory monitoring.

## Building and Running

*Note: Build scripts are planned for Stage 4.*

**Anticipated Build Process:**
The project will likely use a `Makefile` to compile the C bridge and Fortran SDK, dynamically linking against the Julia runtime.

**Key Commands (Future):**
*   Compile: `make` (will use `julia-config.jl` to fetch flags).
*   Run Tests: Likely involves running a Fortran executable that loads the Julia shared library.

## Conventions

*   **Fortran:** Modern Fortran standards using `iso_c_binding` for interoperability.
*   **C:** Adhere to Julia's embedding API guidelines (e.g., `JULIA_DEFINE_FAST_TLS`).
*   **Julia:** Ensure functions are registered and pointers are protected from GC.
*   **Memory Management:** Strict attention to GC roots and ownership transfer (zero-copy).
