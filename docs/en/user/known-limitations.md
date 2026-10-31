---
title: Known limitations
sync: 2026-10-31
---

# Known limitations

Four edges, stated plainly. None of them is news hidden here -- the thread
rule and the array types already shaped the patterns you met in
[Arrays and callbacks](arrays-and-callbacks.md) -- but this page is the
honest list in one place, each item with what it costs and the move that
works today.

| # | Limitation | The move that works today |
|---|---|---|
| 1 | Bridge calls pinned to the init thread | batch: one call, all cells |
| 2 | Array channel `Float64` / `ComplexF64` only | keep bulk data `real(c_double)`; scalars are unbounded |
| 3 | Linux + gcc/gfortran centric | nothing else is claimed |
| 4 | No `ctest` automation | run the example gates by hand |

## 1. All bridge calls are pinned to the init thread

One runtime per process, initialized by `fcj_init` / `fcj_init_ex` on the
calling thread -- and every subsequent `fcj_*` call (a wrap, an extraction,
an eval, a callback invocation) must stay on that same thread. The blunt
consequence: **OpenMP parallelism hits a wall.** A `!$omp parallel do` loop
whose body crosses the bridge is calling from a non-init thread, which is
outside everything the bridge supports. Re-initialization after
`fcj_shutdown` is not supported either: one lifecycle per process.

What works is inverting the parallelism. Pack every cell into one wrapped
buffer and make ONE call; Julia does the looping, on as many threads as you
asked for at init (`julia_init_ex(nthreads=N)`). That is the whole design of
`examples/05_hpc_parallel/1_multithreading.f90` -- 100,000 matrices wrapped
once, one call -- and of the capstone's chemistry, one batched
`step_chemistry!` per Strang half-step
([Bring your own kinetics](bring-your-own-kinetics.md)). Fortran-side
threads stay fine for any region that makes no bridge calls.

## 2. The array channel carries `Float64` and `ComplexF64` only

The zero-copy channel has exactly two element types. Wrapping takes
contiguous `real(c_double)` memory; `%to_fortran` fills a `real` or
`complex` buffer. An integer array or a `Float32` array does not wrap --
there is no conversion layer in between, because the point of the channel
is that nothing gets converted.

Scalars are not so bounded: every scalar type boxes
([Two SDKs, two speeds](two-sdks.md)). So the workaround is ordinary
Fortran hygiene: bulk numeric data lives in `real(c_double)` targets --
which it usually does anyway -- and everything small crosses as a scalar.

## 3. Linux + gcc/gfortran centric

The bridge is developed and validated on Linux, built with CMake, compiled
with gcc/gfortran, speaking standard `bind(c)`. Nothing here has been tested
on macOS or Windows, with non-GNU compilers, or against Julia builds outside
the pinned 1.12.x line. Standard `bind(c)` and `iso_c_binding` mean it may
well work elsewhere -- but nothing is claimed on this site that was not
actually run.

## 4. No `ctest` automation

The acceptance gates are real but manual. They are example executables that
print loud PASS sentinels (`EX_CAPSTONE_GRI_IGNITION_PASS` and siblings) and
exit nonzero on failure -- and `ctest` drives none of them. If you change
the bridge, you run the gates yourself: build the examples, run them, watch
for the sentinels. What the gates check is documented in
[Validation](../intro/validation.md); the full inventory is laid out in the
developer's [acceptance gates](../developer/acceptance-gates.md) page.

## Where to go next

- [Bring your own kinetics](bring-your-own-kinetics.md) -- the batched
  chemistry pattern that lives comfortably inside limits 1 and 2.
- [Validation](../intro/validation.md) -- what is verified despite these
  limits.
- [Bridge internals](../developer/bridge-internals.md) -- where the edges
  come from.
