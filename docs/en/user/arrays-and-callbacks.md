---
title: Arrays and callbacks
sync: 2026-10-31
---

# Arrays and callbacks

Scalars crossed the bridge on [Your first call](first-call.md); real
computing moves arrays and needs control flow in both directions. This
page is the remaining data plumbing: arrays into Julia without copying,
arrays back out in one call, and a `bind(c)` Fortran subroutine driven
from Julia as a right-hand side. All of it sits on the two SDKs of
[Two SDKs, two speeds](two-sdks.md).

## Arrays in: zero-copy wrap or deep copy

Two rank-generic functions decide how an array crosses, and they differ
only in memory ownership. Both are single assumed-rank entry points that
read the extents from `size(arr, k)` -- there is no caller-supplied length
that could disagree with the array -- and both take any rank from 1 to 16
of contiguous `real(kind=8)` data.

| | `julia_wrap_array(arr)` | `julia_copy_array(arr)` |
|---|---|---|
| What Julia gets | an `Array{Float64,N}` header pointing at **your** memory | a fresh `Array{Float64,N}`, data memcpy'd in |
| Data motion | none: the wrap builds a header, not a payload | one full copy (and another if you copy results back) |
| Julia-side writes | land in your Fortran array, immediately | land in Julia's copy |
| Ownership | yours; Julia never frees the memory | Julia's, GC-managed |
| Reach for it when | in-place kernels, big grids, hot loops | the Julia side keeps the array, or you want the aliasing gone |

Both reject loudly instead of guessing: a rank above 16, any zero extent
(`c_loc` on a zero-sized array is illegal), or a non-contiguous actual
argument each yields an invalid `JuliaValue` plus a diagnostic on
`error_unit`.

The wrap in action, from `examples/01_basics/2_zero_copy_arrays.f90`:

```fortran
    ! 2. Box the Fortran Array into a Julia Object
    !    This creates a Julia Array header pointing to the EXISTING Fortran memory.
    !    NO DATA COPY happens here. Extents are derived from size() by the SDK.
    dummy = julia_wrap_array(simulation_grid)

    ! 3. Call Julia Function with the Array
    !    Julia sees a standard Matrix{Float64}.
    !    Any changes Julia makes are written directly to 'simulation_grid'.
    !    ExamplesLib.update_simulation_state!(grid, dt)
    res = julia%call("ExamplesLib.update_simulation_state!", dummy, 0.5d0)

    ! 4. Verify Changes in Fortran
    print *, "After Julia Update:"
    print *, "Grid(1,1) [Expected > 0]: ", simulation_grid(1,1)
    print *, "Grid(50,50):              ", simulation_grid(50,50)
```

`simulation_grid` started at zero; after the call its elements are not.
That is the proof of zero-copy -- had a copy happened, the Fortran array
would still read `0.0`. One rule comes with the wrap: the header points
at your memory and the ownership flag says Julia will not free it, so
keeping that memory alive and in place, for as long as any handle can
still reach it, is your side of the bargain.

N-dimensional means it: the rank is not capped at 2 or 3. The same wrap
through the raw C ABI, from `examples/01_basics/2_arrays.f90`:

```fortran
    ! --- 3. Hypermatrix (4D, zero-copy through the rank-generic API) ---
    ! The high-level SDK form is simply  vec_obj = julia_wrap_array(hyper)
    ! (extents derived from size()); here we exercise the raw C form and
    ! verify the wrap via introspection.
    hyper = 0.0d0
    raw_ptr = c_loc(hyper)
    dims(1:4) = [2_c_long, 3_c_long, 4_c_long, 5_c_long]
    wrapped_ptr = fcj_wrap_array(raw_ptr, 4_c_long, dims)
    mat_obj%ptr = fcj_retain(wrapped_ptr)
    print *, "  3. Rank-4 wrap: ndims=", mat_obj%ndims(), &
             " sizes=", (mat_obj%size_dim(k), k=1,4)
```

The deep copy is the same call shape with different economics. Both
fragments below run on a 3000 x 3000 matrix (about 72 MB), from
`examples/04_performance/3_memory_transfer.f90`:

```fortran
    ! Step 1: Explicit Deep Copy to Julia
    wrapped_array = julia_copy_array(matrix)
    ! Step 2: Call function (returns new array)
    res = julia%call("perf_scale_matrix", wrapped_array, 2.0d0)
```

```fortran
    ! Step 1: Wrap (O(1))
    ! The rank-generic wrapper derives the extents from size()
    wrapped_array = julia_wrap_array(matrix)

    ! Step 2: Call In-Place Function
    ! We pass the wrapped array. No data moves.
    res = julia%call("perf_scale_matrix_bang", wrapped_array, 2.0d0)
```

## Arrays out: navigate, then copy once

Results come back as handles. Two accessors navigate a result object, and
one call moves the data:

- `%element(i)` -- 1-based linear indexing, returns a retained handle.
- `%property(name)` (and its sibling `%get_field(name)`) -- named access
  through `Base.getproperty`: struct fields, `NamedTuple` keys, solver
  solution objects.
- `%to_fortran(buf, n)` -- copies a dense array into your Fortran buffer
  in **one** call; the `real` and `complex` overloads resolve by the
  buffer type.

From `examples/06_sciml/2_batch_data.f90` (`fail` is that example's local
abort helper):

```fortran
    d = julia_eval(' (a = [7.0,8.0,9.0],) ')
    if (.not. d%is_valid()) &
        call fail('julia_eval NamedTuple failed')
    a = d%property("a")
    if (.not. a%is_valid()) &
        call fail('property("a") failed: ' // get_last_error_message())
    rc = a%to_fortran(rbuf, 3_c_int64_t)
    if (rc /= 0) &
        call fail('to_fortran on NamedTuple property failed: ' // get_last_error_message())
```

The error idiom is the house style from [Your first call](first-call.md):
check the handle or the return code, and `get_last_error_message()`
carries the Julia-side text. An out-of-bounds `%element(5)` on a
two-element vector, for instance, returns an invalid handle and populates
the message.

Batch extraction is also the cheap way across. Every per-element access
is a bridge hop; `%to_fortran` is one hop for the whole array. The same
arithmetic says: when a loop could run on either side, run it in Julia
and cross once with an array --
`examples/04_performance/4_access_patterns.f90` measures exactly that
trade at a million elements.

## Callbacks: Fortran as a right-hand side

Arrays move data; callbacks hand control to Fortran. `julia_callback`
wraps a `bind(c)` subroutine pointer into a Julia callable
`f(du, u, p, t)` -- the signature DifferentialEquations-style solvers
expect -- so the solver calls into your Fortran on every step. The
callable `ccall`s your subroutine, and a context pointer you supply at
creation reaches it untouched on every invocation.

The subroutine signs a six-argument contract. This one, from
`examples/06_sciml/1_callback.f90`, is a stateless exponential decay
`du = -k*u`:

```fortran
    subroutine rhs(ctx, n, u, du, t, err) bind(c)
        type(c_ptr), value, intent(in) :: ctx        ! unused (stateless RHS)
        integer(kind=c_int64_t), value, intent(in) :: n
        type(c_ptr), value, intent(in) :: u, du
        real(kind=c_double), value, intent(in) :: t  ! unused (autonomous RHS)
        integer(kind=c_int), intent(out) :: err

        real(kind=c_double), pointer :: u_arr(:), du_arr(:)
        integer :: i

        err = 0_c_int
        if (n <= 0_c_int64_t) return
        call c_f_pointer(u, u_arr, [int(n)])
        call c_f_pointer(du, du_arr, [int(n)])
        do i = 1, int(n)
            du_arr(i) = -K_DECAY * u_arr(i)
        end do
    end subroutine rhs
```

Three properties of that contract:

- **`u` and `du` are raw pointers into Julia's arrays** -- the zero-copy
  channel above, in reverse. You read `u` and write `du` in place, `n`
  elements each; nothing is marshalled per step.
- **`err` is the error path.** Return nonzero and the Julia side throws;
  the bridge catches the exception and it surfaces at the Fortran call
  site through `get_last_error_message()`. No Fortran failure crosses
  silently.
- **`ctx` is yours** -- any `type(c_ptr)` you passed at creation, handed
  back on every call (ignored by this stateless RHS).

Wiring it up, same example:

```fortran
    ! 2. Wrap the bind(c) RHS into a Julia callable (already retained)
    fn = c_funloc(rhs)
    cb = julia_callback(fn, c_null_ptr)
    if (.not. cb%is_valid()) then
        write (error_unit, '(A)') 'FATAL: julia_callback failed: ' // get_last_error_message()
        stop 1
    end if

    ! 3. Box f's arguments: du (Float64 vector workspace, zero-copy),
    !    u = [1.0], p = 0.0, t = 0.0 (p is ignored by the bridge closure)
    du_f(1) = 0.0_c_double
    u_f(1) = 1.0_c_double
    du_boxed = julia_wrap_array(du_f)
    u_boxed = julia_wrap_array(u_f)
    p_boxed = julia_box_real(0.0_c_double)
    t_boxed = julia_box_real(0.0_c_double)
    if (.not. du_boxed%is_valid() .or. .not. u_boxed%is_valid()) then
        write (error_unit, '(A)') 'FATAL: boxing du/u failed'
        stop 1
    end if

    ! 4. Invoke the Julia callable f(du, u, p, t); it ccalls back into
    !    rhs, which writes du in place.
    res = cb%call_value(du_boxed, u_boxed, p_boxed, t_boxed)
```

After `call_value`, `du_f(1)` already holds `-K_DECAY * 1.0`: the RHS
wrote straight into the Fortran array that was wrapped as `du`. The
bridge also binds the callable to `Main.FJ_CALLBACK`, so solver code
assembled with `julia_eval_string` can reach it by name. The end-to-end
version -- a harmonic oscillator integrated with Tsit5, checked to about
1e-9 against the analytic solution -- is
`examples/06_sciml/3_sciml_demo.f90`.

Both directions ride trampolines. This one boxes your `bind(c)` address
as an opaque pointer and closes over it in Julia. In the other direction,
`get_function_pointer` has the bridge generate an `@cfunction` trampoline
rooted in `Main`, handing Fortran a raw C pointer to a Julia function at
~3.8 ns per call; that path and its hard edges belong to
[Two SDKs, two speeds](two-sdks.md).

## The rules both channels share

1. **One thread.** Every bridge call -- a wrap, an extraction, a callback
   invocation -- runs on the thread that initialized the runtime. A
   callback is no exception: the solver executes on the thread that
   called it, which in this bridge is always the init thread.
2. **Array element types are `Float64` and `ComplexF64`, only.** Wraps
   take contiguous `real(c_double)`; `%to_fortran` fills a `real` or
   `complex` buffer. Scalars are not so bounded -- every scalar type
   boxes. This is a known limit, tracked in
   [Known limitations](known-limitations.md).
3. **Crossings are the budget, not calls.** A generic call costs ~815 ns
   and a Fast Path call ~3.8 ns (100k-iteration averages); either is
   noise next to real solver work. But a per-element loop that crosses
   the bridge a million times pays the hop a million times. Move the
   loop into one side; do not move the elements across.

## Where to go next

- [Deployment modes](deployment-modes.md) -- the same program delivered
  as JIT, sysimage, or AOT library: what changes is startup, not the
  per-call cost you just learned to reason about.
- [Bring your own kinetics](bring-your-own-kinetics.md) -- these channels
  at capstone scale, with a real chemistry package behind them.
- [Known limitations](known-limitations.md) -- thread pinning, array
  types, platform support, in one honest list.
