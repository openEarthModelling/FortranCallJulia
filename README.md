# Fortran-Julia High-Performance Middleware

A robust cross-language middleware that lets Fortran programs call Julia
functions through a C bridge layer -- and Julia solvers call back into
Fortran. Built for high-performance scientific computing: a legacy Fortran
code base can act as the right-hand side of an OrdinaryDiffEq solver, and
results come back through zero-copy or batch-extraction APIs.

## Key Features

*   **Hybrid Architecture**
    *   **High-Level OOP:** `JuliaValue` objects in Fortran with automatic,
        GC-safe memory management (a C-side root set backs every handle).
    *   **Fast Path:** raw C function pointers for tight loops (measured
        ~3.8 ns/call vs ~815 ns for generic calls, 100k-iteration averages).
*   **Zero-Copy Arrays:** pass Fortran arrays to Julia without copying.
*   **Callbacks (Fortran -> Julia):** `julia_callback` wraps a `bind(c)`
    subroutine into a Julia callable, e.g. an ODE right-hand side consumed
    by OrdinaryDiffEq (`examples/05_sciml`).
*   **Batch Extraction (Julia -> Fortran):** `%to_fortran` copies a whole
    dense array in one call; `%element` and `%property` navigate result
    objects. Implemented on top of cached `Base.getindex` /
    `Base.getproperty` bindings, so it works with Julia 1.12's
    Memory-backed arrays (where `jl_arrayref` no longer exists).
*   **Startup Control:** `julia_init_ex` sets sysimage, project, thread
    count and signal disposition; failures return with
    `get_last_error_message()` instead of aborting the process.
*   **Sysimage Pipeline:** `-DFJ_BUILD_SYSIMAGE=ON` builds
    `libfj_sysimage.so` with SciMLBase + OrdinaryDiffEq precompiled in.
*   **Robustness:** every bridge call is exception-checked; a failed
    `julia_eval_string` prints the Julia error to stderr instead of
    silently degrading into wrong answers.

## Project Structure

```text
.
├── src/
│   ├── FortranBridge/    # Julia package (GCManager, FunctionRegistry,
│   │                     #   Accessors, Utilities, Callbacks)
│   ├── bridge/           # C bridge layer: core, memory, dispatch, arrays,
│   │                     #   accessors, callbacks, extract
│   ├── lib_support/      # Fortran helpers for the compiled-library demo
│   └── julia_sdk.f90     # Fortran SDK (julia_low_level + julia_high_level)
├── examples/             # Progressive tutorial suite
│   ├── 01_basics/ .. 04_performance/
│   ├── 05_hpc_parallel/  # Multithreading, MPI bootstrap
│   └── 05_sciml/         # Callbacks, batch data, end-to-end ODE demo
├── scripts/              # Sysimage pipeline (build_sysimage.jl,
│                         #   precompile.jl, install_sciml_env.jl)
└── CMakeLists.txt
```

## Prerequisites

*   **Julia 1.12.x**, self-contained install. The same binary must build any
    sysimage; a version shim such as juliaup's `julia` pointing at another
    minor version is rejected by the sysimage build guard.
*   **gfortran** (recommended; GNU-only flags are compiler-gated) or another
    Fortran compiler with its own equivalents.
*   **CMake >= 3.13**.

## Building

### Standard Build (Library + Examples)

1.  **Create a build directory:**
    ```bash
    mkdir build && cd build
    ```

2.  **Configure:**
    ```bash
    cmake -DBUILD_EXAMPLES=ON ..
    # optional: precompile the SciML stack into a sysimage
    # cmake -DFJ_BUILD_SYSIMAGE=ON ..
    ```

3.  **Compile and run:**
    ```bash
    make -j8
    ./examples/ex01_quickstart
    ```

    Examples resolve their data files (the FortranBridge package and
    examples_lib.jl) **next to the executable**, so they run from any
    working directory.

### Sysimage (AOT) Pipeline

`scripts/install_sciml_env.jl` creates the scratch environment
`scripts/sysimage_env` (SciMLBase + OrdinaryDiffEq). With
`-DFJ_BUILD_SYSIMAGE=ON`, CMake drives `scripts/build_sysimage.jl`
(`create_sysimage(:FortranBridge, precompile_execution_file=scripts/precompile.jl)`,
cpu_target=native) and produces `build/libfj_sysimage.so` (~929 MB). Load
it via `julia_init_ex(image_path=...)`.

### Separated Compilation (Install Library, Build Examples Standalone)

1.  **Build and install the library:**
    ```bash
    cmake -DCMAKE_INSTALL_PREFIX=../install_dist .. && make install
    ```
    The FortranBridge package installs to `share/FortranCallJulia/FortranBridge/`.

2.  **Build the examples against the installed SDK:**
    ```bash
    cd examples && cmake -DCMAKE_PREFIX_PATH=../../install_dist .. && make
    ```

## Usage Example

### 1. Initialize with explicit control & load code

```fortran
use julia_high_level

! project probe order: $JULIA_FJ_PROJECT -> FortranBridge/ next to the
! executable -> $JULIA_PROJECT; on failure check get_last_error_message()
call julia_init_ex(nthreads=2)

! include a Julia file shipped next to the binary (CWD-independent)
call julia_include_exe_relative("my_code.jl")
```

### 2. High-level OOP call

```fortran
type(JuliaValue) :: res
res = julia%call("sqrt", 2.0d0)
print *, res%as_real()
```

`%call` on an object that IS a function (e.g. a callback handle) ignores
the name argument and calls the object itself -- a true method call
(`fj_is_function` routes it through the call_value path).

### 3. Fast path (function pointers)

```fortran
type(c_funptr) :: c_ptr
procedure(proto), pointer :: f_ptr
c_ptr = get_function_pointer("julia_add", "Float64", "(Float64, Float64)")
call c_f_procpointer(c_ptr, f_ptr)
res = f_ptr(10.0d0, 20.0d0)            ! zero dispatch overhead
```

See `examples/04_performance/2_call_overhead.f90` for the registered
function pattern.

The pointer is kept alive by the registry (the source function and the
`@cfunction` result are rooted in `Main`), so GC lifetime is safe. The
contract has hard edges -- misuse crashes the process with no Julia-side
diagnostic:

1. The trampoline captures the function object at registration: same-name
   method redefinition is observed through old pointers, but rebinding the
   name to a new object (e.g. a closure) leaves old pointers calling the
   captured object. Register after the final definition or rebinding.
2. Re-registering a name invalidates earlier pointers for that name (the
   old `@cfunction` object becomes collectable); discard them.
3. The called function must not throw: an exception unwinds through the C
   trampoline frame (undefined behavior, typically a segfault). Handle
   errors inside Julia or return a sentinel value.
4. `ret_type`/`arg_types` must match the method signature exactly
   (bitstypes only); nothing is validated at registration.

### 4. Fortran callback as an ODE right-hand side

```fortran
! subroutine rhs(ctx, n, u, du, t, err) bind(c)  -- u/du are zero-copy
fn = c_funloc(rhs)
cb = julia_callback(fn, c_null_ptr)    ! Julia callable, also Main.FJ_CALLBACK
...
res = cb%call_value(du_boxed, u_boxed, p_boxed, t_boxed)
```

The full end-to-end demo (harmonic oscillator through Tsit5, analytic
comparison at ~1e-9 error) is `examples/05_sciml/3_sciml_demo.f90`.

### 5. Batch extraction

```fortran
v_u = sol%property("u")                ! Vector{Vector{Float64}}
v_last = v_u%element(n_u)              ! final saved state
rc = v_last%to_fortran(fbuf, 2_c_int64_t)   ! one copy, no per-element calls
```

## Compiled-Library Demo

`examples/03_deployment/2_compiled_library/` shows the opposite direction:
Julia compiled into a shared library consumed by plain Fortran.
`build_lib.jl` (PackageCompiler `create_library`) builds
`dist/lib/libmylib.so`; `run.sh` builds and runs the `demo_app`. The build
is pinned to the same self-contained 1.12.7 Julia; `dist/` output is not
tracked in git.

## Known Limitations

*   One runtime per process, initialized on the calling thread; all bridge
    calls must stay on that thread. Re-initialization after
    `julia_shutdown` is not supported.
*   Name caches are invalidated automatically after every
    `julia_eval_string` (on both success and failure -- a throwing eval can
    still have rebound names), so name-based calls observe top-level
    redefinitions made through eval. Rebinding by other means --
    `set_field`/`setproperty!` on a module, calling `include()` or a reload
    helper by name, Julia-side evals -- is not observed automatically; call
    `julia_clear_function_cache()` after such operations (it drops the name
    cache and, in current FortranBridge builds, the kwargs cache).
*   The `get_function_pointer` fast path trades safety for speed; its
    contract (final definition, no throwing, exact signatures) is spelled
    out under "Fast path (function pointers)".
*   Signal disposition: the bridge never touches `jl_options.handle_signals`
    (GC safepoint polling depends on Julia's SIGSEGV handler). "No takeover"
    resets SIGINT/SIGTERM to their defaults after init.
