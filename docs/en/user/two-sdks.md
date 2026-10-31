---
title: Two SDKs, two speeds
sync: 2026-10-31
---

# Two SDKs, two speeds

Fortran reaches the bridge through two modules, and they are layers, not
rivals. `julia_low_level` (`src/julia_binding.f90`) is the `bind(c)` truth:
an interface block declaring the `fcj_*` C ABI, roughly 105 symbols, nothing
on top. `julia_high_level` (`src/julia_sdk.f90`) builds on it: `JuliaValue`
handles with GC-safe lifetimes, automatic boxing, converters, and batch
extraction (`%to_fortran`). You can mix them in one program -- the high
level `use`s the low level, and its `get_function_pointer` helper is the
recommended way into the pointer path further down.

## Positioning

| | `julia_high_level` | `julia_low_level` |
|---|---|---|
| Source | `src/julia_sdk.f90` | `src/julia_binding.f90` |
| Shape | OOP: `type(JuliaValue)` with type-bound procedures | `bind(c)` declarations of the `fcj_*` C ABI (~105 symbols) |
| Arguments | auto-boxing (`real` to `Float64`, string to `String`, ...) | you box or pass `c_ptr` yourself |
| Lifetime | GC-safe: assignment retains, finalizers release exactly once | manual `fcj_retain` / `fcj_release` |
| Results | `%as_real()` and siblings, `%element` / `%property`, `%to_fortran` batch copy | raw `type(c_ptr)`, you unbox |
| Errors | invalid handle + `get_last_error_message()` | return codes + `get_last_error_message()` |
| Best for | application glue, exploration, anything not per-iteration | direct ABI access, unwrapped symbols, minimal layering |

## The same call, both ways

High level, from `examples/01_basics/1_quickstart.f90`:

```fortran
    res = julia%call("ExamplesLib.add_numbers", 10.5d0, 20.0d0)
    sum_result = res%as_real()
```

Low level, the declaration your compiler sees in `src/julia_binding.f90`:

```fortran
    function fcj_call1_float64(func_name, arg1) bind(c, name="fcj_call1_float64") result(res)
        import :: c_char, c_double, c_ptr
        character(kind=c_char), dimension(*), intent(in) :: func_name
        real(kind=c_double), value :: arg1
        type(c_ptr) :: res
    end function fcj_call1_float64
```

The `c_ptr` result is not rooted for you: to keep the object alive across
further bridge calls you must `fcj_retain` it and `fcj_release` it exactly
once when done. That bookkeeping is precisely what `JuliaValue` gives you
for free -- which is why the high level is the default recommendation.

## The numbers

| Path | Per call | What it buys |
|---|---|---|
| Fast Path: raw C function pointer | **~3.8 ns** | no name lookup, no boxing, no exception check |
| Generic typed call | **~815 ns** | any function, any arguments, full error checking |

Both figures are 100k-iteration averages, produced by
`examples/04_performance/2_call_overhead.f90`. Read them as the price of
generality: the generic path resolves the name, boxes every argument,
unboxes the result, and checks for a Julia exception on each hop. Against
any real workload -- an `inv()`, an ODE step -- 800 ns is noise. Against a
per-grid-cell call inside a hydrodynamics loop, it is not.

## The Fast Path

When the same bitstype-signature function is called in a tight loop, drop
to a raw function pointer registered once. From
`examples/04_performance/2_call_overhead.f90` (timing scaffolding elided):

```fortran
    abstract interface
        function func_add_one(val) bind(c)
            import :: c_double
            real(c_double), value :: val
            real(c_double) :: func_add_one
        end function func_add_one
    end interface

    procedure(func_add_one), pointer :: c_func => null()

    raw_ptr = get_function_pointer("perf_add_one", "Float64", "Float64")
    call c_f_procpointer(raw_ptr, c_func)

    do i = 1, N
        y = c_func(x)            ! ~3.8 ns: a plain C call, nothing else
    end do
```

The registry roots the underlying `@cfunction` in `Main`, so GC lifetime is
safe -- but the contract has hard edges, and misuse crashes the process
with no Julia-side diagnostic:

1. **Register after the final definition.** The trampoline captures the
   function object at registration; rebinding the name later (for example
   to a closure) leaves old pointers calling the captured object.
2. **Re-registering a name invalidates earlier pointers** for that name;
   discard them.
3. **The called function must not throw.** An exception unwinding through
   the C trampoline frame is undefined behavior, typically a segfault;
   handle errors inside Julia or return a sentinel.
4. **Types must match exactly** -- `ret_type` / `arg_types` bitstypes only;
   nothing is validated at registration.
5. **Pointers die with the runtime**: invalid after `julia_shutdown()`.

## Which one, when

1. **Default to `julia_high_level`.** Correctness and GC safety first; the
   ~815 ns generic path is negligible next to any computation worth
   crossing the bridge for. Application glue, result navigation, one-off
   calls: stay here.
2. **Drop to `julia_low_level` when you need the C ABI itself** -- an
   `fcj_*` symbol the SDK does not wrap, minimal layering over the bridge,
   or a context where the OOP layer does not fit. You take over
   retain/release bookkeeping; mistakes leak or dangle.
3. **In a tight loop, use neither -- use the Fast Path** (or hoist the call
   out of the loop entirely). If the signature is bitstype-fixed and the
   body cannot throw, `get_function_pointer` plus `c_f_procpointer` gets
   you to ~3.8 ns per call. This is how per-grid-cell chemistry stays
   cheap in the capstone.

## Where to go next

- [Arrays and callbacks](arrays-and-callbacks.md) -- the other two bridges
  between the worlds: zero-copy arrays and `@cfunction` callbacks.
- [Deployment modes](deployment-modes.md) -- JIT, sysimage, AOT: what
  changes (startup) and what does not (per-call cost).
