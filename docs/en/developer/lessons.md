---
title: Lessons
sync: 2026-10-31
---

# Lessons

Every rule in this codebase was paid for. This page is the receipt drawer:
the incidents behind the guards, the pins, and the loud failure modes you
will meet while maintaining the bridge. Each entry follows the same shape
-- symptom, root cause, fix, and the rule left behind. The machines and
accounts involved stay anonymous on purpose; the mechanisms are what
transfer.

## 1. Pin the Julia runtime on both sides of any comparison

**Symptom.** The four GRI acceptance gates
([acceptance gates](acceptance-gates.md)) started reporting nonzero
margins around 1e-9 -- sometimes passing, sometimes not -- on runs where
neither the bridge nor the chemistry had changed. The visible suspect was
the bridge's array extraction.

**Root cause.** A version skew, not a bug. The bridge executable embeds
the build-pinned `libjulia` 1.12.7, but the native baseline had been
regenerated with a bare `julia` that was an auto-updating version shim,
silently pointing at 1.13.2 after an upstream release. The same stiff
solve, run by two different Julia versions, drifts at the ignition
transition -- measured pointwise up to **T rel 1.5e-5** and **CH4 rel
0.54** -- which crosses a 1e-8 gate effortlessly. The investigation first
chased solver nondeterminism and BLAS thread ordering; re-generating the
baseline with the pinned binary produced four exact zeros and closed the
case.

**Fix.** Two guards now refuse the skew loudly:
`run_gri_native.jl` errors unless `VERSION == v"1.12.7"`, and the
`FJ_BUILD_SYSIMAGE` CMake guard rejects any build Julia outside the 1.12.x
line, naming the version shim as the thing not to use.

**Rule.** Any A/B comparison -- baseline vs bridge, before vs after --
runs the same pinned binary on both sides. When a tight gate flakes,
audit the runtimes before the code.

## 2. Pin the SciML stack with `[compat]`

**Symptom.** Per-cell chemistry in the capstone suddenly cost ~700x more:
a frozen grid cell took 982 internal integrator steps instead of 1, a
burning cell ~54,000 instead of ~100, with ~3.5 MB allocated per cell. At
nx = 400 the chemistry phase ran 89 s where the tested stack needed
1.25 s.

**Root cause.** The scratch environment had drifted onto the
OrdinaryDiffEq 7.x line, because the kinetics package carried no
`[compat]` bounds. The 7.x step-size controller handles the per-cell
`reinit!` / `step!` pattern drastically worse -- a dependency resolved
"fine", performing badly.

**Fix.** The package's `[compat]` now pins the tested line -- Catalyst
~16.2, OrdinaryDiffEq ~6.111, SciMLBase ~2.155, StaticArrays ~1.9,
PrecompileTools ~1.3 -- the unused direct ModelingToolkit dependency was
dropped, and the environment assembly script documents why the pins are
load-bearing.

**Rule.** Pin everything your numerics depend on, and when throughput
degrades for no reason, print the resolved versions before profiling.
"Resolves" is not "works"; the resolver optimizes for compatibility, not
for your access pattern.

## 3. Never disable Julia's signal handling

**Symptom.** While wiring up startup options, setting
`jl_options.handle_signals = OFF` looked like a clean way to keep an
embedded runtime from stealing the host application's signal handlers.
The process then crashed at a GC safepoint -- in 14 of 15 runs.

**Root cause.** Embedded Julia's GC safepoint polling depends on Julia's
own SIGSEGV handler; turning signal handling off removes machinery the
runtime itself needs. The crash is reliable, not racy -- which at least
makes it easy to reproduce.

**Fix.** The bridge never writes `jl_options.handle_signals`. The need it
was meant to serve ("don't take over my signals") is met differently:
`handle_signals = 0` in `fcj_options_t` means *no takeover* -- after a
successful init the bridge resets `SIGINT` / `SIGTERM` to `SIG_DFL`,
leaving the GC-critical handlers intact.

**Rule.** Treat `jl_options` as read-only. If you need host-friendly
signal disposition, reset specific signals after init; never remove
Julia's own handlers from under it.

## 4. On the shared cluster: judge jobs by exit code, not stdout

**Symptom.** Batch jobs launched through Slurm's `srun` on the shared
cluster would intermittently print their entire stdout twice --
whole blocks duplicated verbatim, across independent runs, on otherwise
healthy jobs. Even a bare shell `echo` reproduced it; no environment
variable or node-specific setting explained it.

**Root cause.** A cluster I/O quirk in the launch layer, not in any
program being run. It is noise in the transport, and it cannot be fixed
from inside a job.

**Fix and rule.** Automated verdicts key on the **exit code** and the
test summary line, never on how the log reads; when a log is archived or
piped onward, de-duplicate repeated lines (`awk '!seen[$0]++'` is the
house idiom). Never parse a Slurm log for a sentinel you intend to act on
without allowing for duplication -- and never let a duplicated-looking
log convince you a job ran twice.

## 5. A "self-contained" AOT library that downloads 570 MB on first run

**Symptom.** A PackageCompiler-built library, advertised as
self-contained, spent its first initialization on a network fetch of
~570 MB (IntelOpenMP / oneTBB / MKL) on a machine with no package depot.

**Root cause.** A dependency in the SciML closure probes `MKL_jll` --
a *lazy* artifact -- at image load. PackageCompiler's default bundles
only non-lazy artifacts, so "everything you need" silently meant
"everything except the lazies".

**Fix.** Build with `include_lazy_artifacts = true`; the capstone's AOT
build script carries the comment explaining exactly this. Verified by
initializing under an empty `JULIA_DEPOT_PATH` and a fresh home directory:
zero network access.

**Rule.** "Self-contained" is a testable claim -- test it with an empty
depot on a network-isolated path, not by reading your own build script.

## 6. An AOT library owns its runtime: enter through its own front door

**Symptom.** Linking a compiled Julia library into a process that also
uses the bridge SDK worked -- until initialization segfaulted or
misbehaved in ways that pointed everywhere at once.

**Root cause.** The compiled library bundles its own `libjulia`, and the
process now has two opinions about where the runtime lives. Calling the
SDK's `julia_init()` drives a bare `jl_init()` that looks for a default
`sys.so` the bundled layout does not ship -- the sysimage is compiled
*into* the library, and only its exported `init_julia` knows how to load
it, with an explicit bindir.

**Fix.** In AOT mode, lifecycle goes through the library's exported
`init_julia` / `shutdown_julia` and nothing else. The interface
declarations live in `src/lib_support/julia_library_interface.f90`, and
the working examples (`examples/03_deployment/2_compiled_library/`,
`examples/07_capstone/3_aot_kinetics/`) show the pattern.

**Rule.** One process, one runtime owner. When a library ships its own
Julia, that library's entry points -- not the SDK's -- are the lifecycle.

## Where to go next

- [Acceptance gates](acceptance-gates.md) -- the guards these incidents
  left behind, and how to run them.
- [Rebuild from zero](rebuild.md) -- the three rebuild recipes, with the
  pins and flags from entries 1, 2, and 5 already in place.
- [Known limitations](../user/known-limitations.md) -- the honest edges
  that are design, not bugs.
