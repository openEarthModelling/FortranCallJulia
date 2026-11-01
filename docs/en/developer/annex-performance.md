---
title: Performance annex
annex: true
---

This annex is published in English only.

Migrated from `examples/07_capstone/PERFORMANCE.md` (the 2026-10-26
capstone report). Every number, table, and conclusion below is
reproduced verbatim; only the prose identifying the measurement
machines has been genericized for the public site (machine references
read "a shared build host" / "the loaded host" here -- load figures
and core counts are part of the measurement record and are unchanged).

# Capstone performance report: Fortran ⇄ Julia reacting-flow example

All numbers from the 2026-10-26 runs on a shared build host (192-core,
load ~119 during measurement; single core per run). Julia
1.12.7, FjKinetics on the compat-pinned stack: the load-bearing pins
(OrdinaryDiffEq 6.111.0, Catalyst 16.2.1, PrecompileTools 1.3.4) are
identical in every validation environment; patch-level deps
differ slightly by artifact -- the JIT runs resolved through FjKinetics'
Manifest at measurement time (SciMLBase 2.155.1, StaticArrays 1.9.18),
while the
sysimage and AOT environments resolved SciMLBase 2.155.2 /
StaticArrays 1.9.24 (within [compat], which floors the minor lines, so
the 700x drift class cannot recur through resolution). Identical compiled kernel
(`FjKinetics.step_chemistry!`, Rodas5P, abstol 1e-10 / reltol 1e-8) in
every mode.

## End-to-end detonation validation (HLW 2000 Ex.2, nx = 2700, t = 0.3)

The Fortran driver owns the time loop (2608 transport steps, 5216 Strang
chemistry half-steps, 25245 active cell-solves). Physics identical in
both modes: detonation speed 7.12391 vs s_CJ = 7.12470 (0.011%), burnt
state within 0.025% of CJ (worst: u 0.025%, p 0.023%, rho 0.018%).

| mode              | julia init | first non-empty chem call | chemistry total | run total | peak RSS | bridge calls |
|-------------------|-----------:|--------------------------:|----------------:|----------:|---------:|-------------:|
| jit (project env) |   17.3 s   |          7.58 ms          |       4.79 s    |   7.72 s  |  1.15 GB | 5231 |
| sysimage          |    1.90 s  |          8.04 ms          |       4.02 s    |   7.04 s  |  1.18 GB | 5229 |

Final driver (post round-2 review fixes), 2026-10-26, back-to-back runs
from the repo root; the build/examples-cwd repeats gave jit 15.7 s /
7.11 ms / 4.43 s / 7.22 s and sysimage 0.96 s / 7.83 ms / 4.99 s /
7.95 s. Bridge calls = init/setup + 5215 chemistry (one `julia_eval`
per half-step with a nonempty active set) + 1 shutdown; init/setup is
15 in jit mode (binding probe + `import FjKinetics` + re-probe) vs 13
in sysimage mode (probe only — the image binds `Main.FjKinetics`
already, so no import runs). Peak RSS from the earlier same-day batch
(VmHWM poller); the fixes touch only setup and validation, not the
measured paths. Init ranges across all same-day runs: jit 15.1-20.2 s
(loading ~92 package caches; the high end under load), sysimage
0.93-2.37 s (the low end with a warm page cache).

**Zero-JIT verification (corrected after adversarial review).** An
earlier revision of this report timed "the first chemistry half-step"
at 21.6/21.8 µs and called that the zero-JIT proof. That was an empty
measurement: half-step 1 has an empty active set (unburnt cells sit
below t_cut, burnt driver cells below z_floor), so it makes no Julia
call at all and the timer covered only the 2700-cell packing loop. The
probe now clocks the first NON-EMPTY half-step — the post-transport
one, the first call that actually crosses the bridge. Result on the
final driver: 7.1-8.0 ms across all four runs (jit 7.58/7.11 ms,
sysimage 8.04/7.83 ms) — statistically indistinguishable, all ms-scale,
i.e. pure solver work over the handful of newly-shocked cells. A
runtime compile event would cost 100 ms-seconds; no run shows one. The
jit mode's ms-scale first call is a package-cache hit (FjKinetics'
PrecompileTools workload precompiled the exact view-based call
signature), the sysimage's is the same code baked in the image.
Per-active-cell-solve: jit 4.79/4.43 s per 25245 = 175-190 µs, sysimage
4.02/4.99 s per 25245 = 159-198 µs — the ranges overlap, and the
direction of the difference flips WITHIN this batch (repo-root runs:
sysimage 4.02 < jit 4.79; build-cwd runs: sysimage 4.99 > jit 4.43) and
again across earlier same-day batches (4.10 vs 4.87, then 4.60 vs 3.89)
— the jit-vs-sysimage chemistry-total gap is host-load noise (~±20%),
not a mode effect.

## Chemistry kernel micro-benchmark (identical 64-cell hot/frozen mix)

`chem_bench_reference.jl` (pure Julia) and `3_aot_kinetics/` (standalone
compiled library) drive the same interleaved workload: odd cells at
T = 17 (full 10-decade burn, ~100 internal steps each), even cells at
T = 1.6 (frozen, one internal step), dt = 4e-4, state reset every call.

| mode                              | startup                  | steady per cell-step |
|-----------------------------------|-------------------------:|---------------------:|
| pure Julia (package caches, JIT)  | 17.5 s load              |      309 µs          |
| embedded jit / sysimage (from the detonation run above) | (see above) | 190 / 159 µs (batch ranges 175-190 / 159-198 µs) |
| AOT standalone library            | 0.58-1.97 s init**       | 236 / 347 / 319 / 240 / 240 / 191 / 353 / 361 µs (eight runs, three builds) |

Per-cell-step costs are accuracy-driven (Rodas5P resolving F through 10
decades at reltol 1e-8): ~6 µs frozen, ~65 µs induction, ~430 µs burn
on an idle core (measured 2026-10-26, bench2); the mixed-workload
figures above are on the loaded host (~±20% run-to-run). The
per-half-step bridge eval adds only parse cost (µs), dwarfed by the
~180 µs/cell of solver work in the real run.

\*\* AOT init spans 0.58-1.97 s across runs: cold page cache on the
1.5 GB library vs warm; the cold-machine bound is the high end. The
eight steady numbers span three library builds (original; round-1
guarded @ccallables; round-2 clearable-solver + __init__) and two
allocation shapes: 191 µs was measured inside a 32-core allocation
(dedicated physical cores); 353/361 µs come from 1-core allocations on
the loaded host, where a hyperthread sibling of the lone core is busy
(the 2x gap tracks the sibling, not the build). The per-build triplets
agree within the host-load band — the guards never touch the hot path.

## What each mode buys

- **JIT (embedded, project env)**: zero build steps, slowest startup
  (~15-20 s), needs the full depot on the target machine.
- **sysimage**: one 1.20 GB image; startup 2.4 s (6-8×); same heap
  footprint (peak RSS within 30 MB of JIT); no compilation risk at
  runtime by construction.
- **AOT library**: fastest startup (0.58-1.97 s library init, cold- to
  warm-cache — plain image load, no package caches, no env); no Julia
  installation, depot, or project on the target, kernel reached by C
  symbols (`kinetics_build`, `kinetics_step`, zero-copy `unsafe_wrap` of
  the Fortran buffers; error-code contract — no Julia exception can
  cross the C ABI, and a fresh library load starts WITHOUT a solver: a
  module __init__ clears the build-time solver at image load, so
  `kinetics_step` before `kinetics_build` returns -2 instead of
  silently computing with baked-in parameters). One-time build cost:
  50 min wall and ~33 GB peak compiler RSS for the non-incremental
  codegen of the whole dependency closure (this is build-machine
  memory, not deployment footprint); dist/ 2.5 GB with the lazy MKL
  artifacts bundled (1.8 GB before, see incident below). Build +
  guards + first batched 64-cell step after init is 14-25 ms, and the
  first timed step (post-warm-up) 14-19 ms ≈ steady — no compilation
  at runtime; the error codes (-2 before build, -1 bad n, 0 success)
  are exercised by built-in guards on every bench run, including in
  the empty-depot proof environment.

## Version-pinning incident (why the pinned stack matters)

Measured 2026-10-26: with the same example resolved against
OrdinaryDiffEq 7.8.1 (the unpinned float), the per-cell
`reinit!`/`step!` pattern degrades ~700× — a frozen cell costs 982
internal steps instead of 1, a burning cell ~50 000 instead of ~100,
~3.5 MB allocated per cell — turning the nx=2700 chemistry budget into
hours. FjKinetics pins its tested line in `[compat]`; the sysimage and
AOT environments resolve through it.

## First-init artifact downloads (self-containedness)

The very first AOT run downloaded ~570 MB from the network at
`init_julia` (IntelOpenMP, oneTBB, MKL) before touching any chemistry:
LinearSolve, deep in the SciML closure, probes the `MKL_jll` lazy
artifact when the image loads, and PackageCompiler bundles only
non-lazy artifacts by default — so the "standalone" library silently
reached for the internet on any machine without a Julia depot. Fix:
`create_library(...; include_lazy_artifacts = true)` bakes the lazy
artifacts into dist/ (verified with an empty `JULIA_DEPOT_PATH` and
fresh `HOME`: no downloads, bench green — re-proven on every guarded
rebuild, most recently the final round-2 artifact). The 283 s first-init
measurement is that download run; 0.58-1.97 s is init with the artifacts
resolved locally.
