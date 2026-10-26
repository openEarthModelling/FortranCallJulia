# Capstone performance report: Fortran ⇄ Julia reacting-flow example

All numbers from the 2026-10-26 runs on the development node (192-core
shared host, load ~119 during measurement; single core per run). Julia
1.12.7, FjKinetics on the compat-pinned stack (OrdinaryDiffEq 6.111.0,
see plan.md and the capstone commits). Identical compiled kernel
(`FjKinetics.step_chemistry!`, Rodas5P, abstol 1e-10 / reltol 1e-8) in
every mode.

## End-to-end detonation validation (HLW 2000 Ex.2, nx = 2700, t = 0.3)

The Fortran driver owns the time loop (2608 transport steps, 5216 Strang
chemistry half-steps, 25245 active cell-solves). Physics identical in
both modes: detonation speed 7.12391 vs s_CJ = 7.12470 (0.011%), burnt
state within 0.02% of CJ.

| mode              | julia init | first chem half-step | chemistry total | run total | peak RSS | bridge calls |
|-------------------|-----------:|---------------------:|----------------:|----------:|---------:|-------------:|
| jit (project env) |   15.1 s*  |        21.6 µs       |       4.10 s    |   7.00 s  |  1.15 GB | 5229 |
| sysimage          |    2.37 s  |        21.8 µs       |       4.87 s    |   7.89 s  |  1.18 GB | 5229 |

\* 20.2 s in an independent run under higher load; JIT init = loading
~92 package caches from disk. Bridge calls: 13 init/setup + 5215
chemistry (one `julia_eval` per half-step with a nonempty active set) +
1 shutdown. The first half-step is µs-scale in BOTH modes — nothing
compiles at runtime; that is the zero-JIT verification (commit 5).

## Chemistry kernel micro-benchmark (identical 64-cell hot/frozen mix)

`chem_bench_reference.jl` (pure Julia) and `2_aot_kinetics/` (standalone
compiled library) drive the same interleaved workload: odd cells at
T = 17 (full 10-decade burn, ~100 internal steps each), even cells at
T = 1.6 (frozen, one internal step), dt = 4e-4, state reset every call.

| mode                              | startup       | steady per cell-step |
|-----------------------------------|--------------:|---------------------:|
| pure Julia (package caches, JIT)  | 17.5 s load   |      309 µs          |
| embedded JIT / sysimage           | (see above)   |  same compiled kernel; per-half-step bridge eval adds only parse cost (µs), dwarfed by the ~200 µs/cell of solver work in the real run |
| AOT standalone library            | 1.76 s init   | 236 / 347 µs (two runs, load ~119) |

Per-cell-step costs are accuracy-driven (Rodas5P resolving F through 10
decades at reltol 1e-8): ~6 µs frozen, ~65 µs induction, ~430 µs burn
on an idle core (measured 2026-10-26, bench2); the 309 µs figure above
is the 50/50 mix on the loaded node.

## What each mode buys

- **JIT (embedded, project env)**: zero build steps, slowest startup
  (~15-20 s), needs the full depot on the target machine.
- **sysimage**: one 1.20 GB image; startup 2.4 s (6-8×); same heap
  footprint (peak RSS within 30 MB of JIT); no compilation risk at
  runtime by construction.
- **AOT library**: fastest startup (1.76 s library init — plain image
  load, no package caches, no env); no Julia installation, depot, or
  project on the target, kernel reached by C symbols (`kinetics_build`,
  `kinetics_step`, zero-copy `unsafe_wrap` of the Fortran buffers).
  One-time build cost: 50 min wall and ~33 GB peak compiler RSS for the
  non-incremental codegen of the whole dependency closure (this is
  build-machine memory, not deployment footprint); dist/ 2.5 GB with
  the lazy MKL artifacts bundled (1.8 GB before, see incident below). First step
  after init is 28 ms for 64 cells — no compilation at runtime.

## Version-pinning incident (why the pinned stack matters)

Measured 2026-10-26: with the same example resolved against
OrdinaryDiffEq 7.8.1 (the unpinned float), the per-cell
`reinit!`/`step!` pattern degrades ~700× — a frozen cell costs 982
internal steps instead of 1, a burning cell ~50 000 instead of ~100,
~3.5 MB allocated per cell — turning the nx=2700 chemistry budget into
hours. FjKinetics pins its tested line in `[compat]`; the sysimage and
AOT environments resolve through it. Details: plan.md, commit d2ba6ff.

## First-init artifact downloads (self-containedness)

The very first AOT run downloaded ~570 MB from the network at
`init_julia` (IntelOpenMP, oneTBB, MKL) before touching any chemistry:
LinearSolve, deep in the SciML closure, probes the `MKL_jll` lazy
artifact when the image loads, and PackageCompiler bundles only
non-lazy artifacts by default — so the "standalone" library silently
reached for the internet on any machine without a Julia depot. Fix:
`create_library(...; include_lazy_artifacts = true)` bakes the lazy
artifacts into dist/ (verified with an empty `JULIA_DEPOT_PATH` and
fresh `HOME`: no downloads, identical timings). The 283 s first-init
measurement is that download run; the 1.76 s init is with artifacts
resolved locally.
