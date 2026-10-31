---
title: Why Fortran and Julia?
sync: 2026-10-31
---

# Why Fortran and Julia?

Most scientific code is not greenfield. The situation this project was built
for: a mature Fortran hydrodynamics code that is trusted, fast, and expensive
to touch -- sitting next to a Julia solver ecosystem that keeps producing
tools Fortran has no equivalent of. FortranCallJulia's answer is to stop
choosing. Keep the hydrodynamics in Fortran, take the solver ecology from
Julia, couple both in one process.

## What stays in Fortran

- **The physics driver.** Decades-validated numerics with existing
  verification baselines. A rewrite would reset that trust for zero physical
  gain.
- **The main loop and I/O.** Time stepping, mesh management, checkpointing,
  HPC launcher integration -- the parts where the Fortran toolchain is
  already proven.
- **The deployment shape.** The final artifact is still one executable,
  compiled by gfortran, that a cluster scheduler can run unchanged. Julia
  is linked in, not shipped alongside.

## What comes from Julia

- **A live stiff-ODE ecosystem.** OrdinaryDiffEq solvers (FBDF, Rodas5P)
  integrate stiff chemistry without hand-rolled implicit integrators, and
  improvements arrive as package updates.
- **Reaction kinetics as code.** Catalyst builds the reaction network;
  GRI-Mech 3.0 -- 53 species, 325 reactions -- is consumed through
  `ChemMechSim.jl` (open source; the validation here used v1.2.0).
- **Composability without churn on the Fortran side.** A new solver, a new
  package version, a new model -- the Fortran code keeps calling the same
  `fcj_*` entry points.

## The coupling, in one sentence of numerics

The reacting-flow capstone couples an explicit Fortran Euler step (a Clawpack
kernel) with a stiff Julia chemistry step through **Strang splitting** -- half
a hydro step, then a full chemistry step, then half a hydro step -- which
keeps second-order accuracy in time while each world integrates with the
method that suits it.

## Why a C bridge in the middle

Julia's only stable embedding surface is its C API: `libjulia` and the `jl_*`
functions. The bridge in `src/bridge` is the single place that talks to that
API, so the rest of the system never does. Concentrating the C there buys
three things:

1. **GC safety.** Every object handed to Fortran is entered into a C-side
   root set (`fcj_map`) that outlives Julia's collector, then released
   explicitly.
2. **Error discipline.** Every call is exception-checked; failures return an
   error code and human-readable text via `get_last_error_message()`.
3. **A stable, narrow ABI.** Roughly 105 `fcj_*` symbols -- small enough to
   audit, stable enough that Fortran and Julia can evolve independently on
   either side.

## What it costs

The bridge is not free of constraints: bridge calls are pinned to the thread
that initialized Julia, the array channel supports `Float64` /
`ComplexF64` (scalars are all-type), and the supported platform is Linux with
gcc/gfortran. The full list is in
[Known limitations](../user/known-limitations.md); the design decisions
behind it continue in [Architecture](architecture.md).
