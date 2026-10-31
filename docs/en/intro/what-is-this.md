---
title: What is FortranCallJulia?
sync: 2026-10-31
---

# What is FortranCallJulia?

FortranCallJulia embeds the Julia runtime inside a Fortran application -- one
process, one executable. Fortran code calls Julia through a thin C bridge (the
`fcj_*` C ABI, about 105 symbols), and Julia calls back into Fortran through
`@cfunction` trampolines, so a `bind(c)` Fortran subroutine can serve as the
right-hand side of an OrdinaryDiffEq integration.

Three worlds are compiled into the final binary:

| World | Contents |
|---|---|
| Fortran | The application itself: driver, hydrodynamics, main loop. Examples 01--07, wrapped by the two-tier SDK (`julia_high_level` / `julia_low_level`). |
| C bridge | `src/bridge` -- eight C source files built into `fcj_middleware.a`. Owns GC roots, argument boxing, arrays, callbacks, error checking. |
| Julia | `libjulia` 1.12.7 (pinned), `FortranBridge.jl`, `FjKinetics.jl` v0.2, a compat-pinned SciML stack, and `ChemMechSim.jl`. |

## What you can do with it

- **Call Julia from Fortran.** Evaluate expressions, call functions with
  keyword arguments, box scalars of any type -- all through `fcj_*` calls
  declared `bind(c)`, no generated source in your build tree.
- **Pass arrays without copying.** N-dimensional Fortran arrays are wrapped
  in place as Julia arrays; results flow back zero-copy or through
  batch extraction (`%to_fortran` copies a whole dense array in one call).
- **Call Fortran from Julia.** `julia_callback` wraps a `bind(c)` subroutine
  into a Julia callable -- for example an ODE right-hand side consumed by
  OrdinaryDiffEq.
- **Pick a delivery mode.** The same source runs JIT-compiled, against a
  sysimage, or AOT-compiled -- see [Deployment modes](../user/deployment-modes.md).
- **Fail loudly.** Every bridge call is exception-checked; a failure surfaces
  through `get_last_error_message()` instead of silently degrading into wrong
  answers.

## The numbers that define it

- **Overhead.** A Fast Path call -- a raw C function pointer, for tight
  loops -- costs about **3.8 ns**, against roughly **815 ns** for a generic
  typed call (100k-iteration averages).
- **Startup ladder.** JIT **17.3 s** from cold start to first result;
  a sysimage cuts that to **1.90 s**; the AOT build answers its first call
  in about **12 μs**, approaching the native baseline.
- **Correctness.** CJ detonation speed **7.12391** vs the analytic
  **7.12470** (0.011% deviation); bridge vs native shows **0 deviation**
  across four acceptance gates; GRI ignition delay **t_ign = 1.1075 ms**.
  Details and context in [Validation](validation.md).

## Where to go next

- [Why Fortran and Julia?](why-fortran-julia.md) -- the motivation and the
  split of labor between the two languages.
- [Architecture](architecture.md) -- the three worlds in detail, with an
  interactive diagram.
- [Validation](validation.md) -- where each hard number comes from.
- Ready to build? Start with [Installation](../user/installation.md).
