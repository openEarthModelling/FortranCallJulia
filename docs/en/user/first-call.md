---
title: Your first call
sync: 2026-10-31
---

# Your first call

The shortest complete program -- start the runtime, load a Julia file, call
a function, unbox the result, shut down -- is
`examples/01_basics/1_quickstart.f90`, built as `ex01_quickstart`. This page
walks it step by step. Build it first if you have not:
[Installation](installation.md).

## The whole program

```fortran
program ex01_quickstart
    use julia_high_level
    implicit none

    type(JuliaValue) :: julia ! Helper object for method dispatch
    type(JuliaValue) :: res
    real(kind=8) :: sum_result

    ! 1. Initialize the Julia Runtime
    call julia_init()

    ! 2. Load your Julia Code
    call julia_include_exe_relative("examples_lib.jl")
    call julia_eval_string('using .ExamplesLib')

    ! 3. Call a simple function: greet(name)
    !    Equivalent to Julia: res = ExamplesLib.greet("Fortran User")
    res = julia%call("ExamplesLib.greet", "Fortran User")

    ! 4. Call a calculation function: add_numbers(x, y)
    !    Equivalent to Julia: res = ExamplesLib.add_numbers(10.5, 20.0)
    res = julia%call("ExamplesLib.add_numbers", 10.5d0, 20.0d0)

    ! Convert the result back to Fortran real (Unboxing)
    sum_result = res%as_real()
    print *, "Result of 10.5 + 20.0 = ", sum_result

    ! 5. Shutdown
    call julia_shutdown()

end program ex01_quickstart
```

(The repository source also prints a banner and checks that `ExamplesLib`
loaded; trimmed here, unchanged otherwise.)

## Step 1: initialize

`julia_init()` wraps the C entry point `fcj_init` and starts the embedded
Julia runtime inside your process -- no separate Julia process, no pipe.
Two rules come with it:

- **One runtime per process**, and **all bridge calls stay on the thread
  that initialized it**. Initialize from the thread that will do the
  calling (the main thread in every example).
- Re-initialization after `julia_shutdown()` is not supported; init once.

For startup control -- sysimage path, project environment, thread count,
signal disposition -- use `julia_init_ex` instead; see
[Deployment modes](deployment-modes.md).

## Step 2: load your Julia code

`julia_include_exe_relative("examples_lib.jl")` includes a Julia file
**resolved relative to the executable**, not the current working directory
-- the build copied `examples_lib.jl` next to the binary, so the example
runs from anywhere. `julia_eval_string` then brings the module into scope.
The loaded file defines, among others:

```julia
function greet(name::String)
    println("Julia says: Hello, $name!")
    return "Greeting received"
end

function add_numbers(x::Float64, y::Float64)
    return x + y
end
```

## Steps 3 and 4: call, then unbox

`julia%call(name, args...)` looks the function up by name and boxes the
arguments automatically: `real` to `Float64`, integer to `Int`, string to
`String`, logical to `Bool`, complex to `ComplexF64`. The result is a
`JuliaValue` handle -- rooted in the bridge's C-side root set, so the Julia
garbage collector cannot reclaim it while you hold it.

`%as_real()` unboxes into a plain Fortran `real`. Its siblings:
`%as_integer()`, `%as_logical()`, `%as_complex()`, `%as_string()`.

## Step 5: shut down

`julia_shutdown()` wraps `fcj_shutdown` and tears the runtime down cleanly.
Fast Path function pointers are invalid after it (see
[Two SDKs, two speeds](two-sdks.md)).

## When something fails

Failures are not silent. Every bridge call is exception-checked; a failed
call returns an invalid handle, and `get_last_error_message()` carries the
Julia error text back to Fortran. From
`examples/01_basics/1_hello_world.f90`:

```fortran
    res = dummy%call("non_existent_func", 123)

    if (.not. res%is_valid()) then
        err_msg = get_last_error_message()
        print *, "[Fortran] Caught expected error: ", err_msg
    endif
```

## Run it

```bash
./examples/ex01_quickstart
```

```text
--- Example 1: Quickstart (Standard Workflow) ---
Julia says: Hello, Fortran User!
Result of 10.5 + 20.0 =    30.500000000000000
```

The first run pays Julia runtime startup plus JIT compilation of everything
it touches. For this trivial example that is seconds; for the SciML-laden
capstone the same cold start measures 17.3 s
([Deployment modes](deployment-modes.md) shows the sysimage cutting it to
1.90 s).

## Where to go next

- [Two SDKs, two speeds](two-sdks.md) -- the layer you just used, the one
  under it, and the ~3.8 ns pointer path.
- [Arrays and callbacks](arrays-and-callbacks.md) -- zero-copy N-D arrays
  and Fortran subroutines called from Julia.
