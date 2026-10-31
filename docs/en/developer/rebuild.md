---
title: Rebuild from zero
sync: 2026-10-31
---

# Rebuild from zero

Three artifacts in this repository are *built products* rather than
source: the SciML sysimage, the AOT chemistry library, and the capstone
figure set. All three can be regenerated from scratch on a fresh clone --
this page is the recipe for each, with the guards and flags that keep the
rebuild honest. Paths are shown relative to the repository root; wherever
a Julia binary is named, use the pinned 1.12.7 install, not a version
shim ([Lessons](lessons.md), entry 1).

The common prerequisite for the first two is the pinned scratch
environment `scripts/sysimage_env`. `scripts/install_sciml_env.jl`
assembles it (developing FortranBridge and the kinetics packages into it,
resolving through the `[compat]` pins); run it with the same 1.12.x Julia
the bridge embeds.

## Step 1: the SciML sysimage

The sysimage is what turns a 17.3 s JIT startup into a 1.90 s load
([deployment modes](../user/deployment-modes.md)). Rebuild it whenever
the Julia-side packages change shape. Two entry points, one result:

```text
    cmake -B build -DFJ_BUILD_SYSIMAGE=ON ...
    cmake --build build --target fcj_sysimage
```

The configure step runs the version guard: `FJ_BUILD_SYSIMAGE` accepts
only a 1.12.x build Julia and fails configuration with an explicit
message otherwise -- a sysimage is pinned to the exact Julia build that
made it and to the build host's instruction set
(`cpu_target = "native"`), so it is a single-host artifact by design.

What gets baked in is decided by `scripts/build_sysimage.jl`. The core
call, verbatim:

```julia
create_sysimage(
    ["FortranBridge", "SciMLBase", "OrdinaryDiffEq", "FjKinetics"],
    project = sysimage_env,
    sysimage_path = output_path,
    precompile_execution_file = precompile_path,
    cpu_target = "native", # single-host embedding: bake the build host's ISA
)
```

Everything traced by `precompile_execution_file` (`scripts/precompile.jl`,
plus each package's own PrecompileTools workload) lands in the image --
deliberately including both the plain-array and the `view`-based
`step_chemistry!` paths, so the per-half-step call the Fortran driver
evals never compiles at runtime. Expect a large file (about a gigabyte
for this SciML-laden image) and a build measured in many minutes.

## Step 2: the AOT chemistry library

The production-shaped AOT build lives in
`examples/07_capstone/3_aot_kinetics/`: a small Julia package
(`KineticsAOT`) exposing `Base.@ccallable` kernels, compiled by
PackageCompiler's `create_library` into a `dist/` that ships its own
runtime. From that directory, run `build_lib.jl` with the pinned Julia;
the call at its heart, verbatim (comment kept -- it is the warning that
cost an incident to learn):

```julia
create_library("KineticsAOT", "dist";
    lib_name = "libkinetics",
    force = true,
    header_files = ["kinetics.h"],
    incremental = false,
    filter_stdlibs = true,
    # LinearSolve (SciML closure) probes MKL_jll, a lazy artifact, at
    # image load -- without bundling it the library downloads ~570 MB
    # from the network on first init, breaking self-containedness.
    include_lazy_artifacts = true,
    precompile_execution_file = ["aot_precompile.jl"],
)
```

Budget for it: the non-incremental codegen of the whole closure takes on
the order of an hour and tens of GB of peak compiler memory, and `dist/`
is ~2.5 GB. Verify self-containedness the honest way -- initialize under
an empty `JULIA_DEPOT_PATH` and a fresh home directory and confirm zero
network access ([Lessons](lessons.md), entry 5). And remember the
lifecycle rule from the same page: consumers enter through the library's
exported `init_julia`, never the SDK's `julia_init`.

The small sibling in `examples/03_deployment/2_compiled_library/`
(MyLib) demonstrates the identical pattern at tutorial scale; the CMake
build adds its `MyLib` target automatically once `dist/` exists.

## Step 3: the capstone figure set

The figures under `examples/07_capstone/figures/` are rendered by one
script from five CSV files; no figure is hand-edited. The pipeline:

1. **Generate the data.** Run both capstone executables
   (`ex_capstone_reacting_flow`, `ex_capstone_gri_ignition`) and the
   native baseline (`run_gri_native.jl`, pinned binary -- the figure
   that overlays bridge vs native inherits the baseline's runtime).
   They write `output/*.csv` next to the examples.
2. **Render.** From `examples/07_capstone/figures/`:

```text
    python3 plot_capstone.py
```

The script's `main()` renders the full set (fig1 through fig8) from
`../output/*.csv`, asserts each file's column contract before drawing,
and writes both PNG and PDF. A missing or stale CSV fails loudly rather
than rendering an empty axis. What each figure shows, and the QA rules
they are held to, are documented in `examples/07_capstone/figures/FIGURES.md`.

## Rebuild order after a change

A practical note on sequencing: source changes propagate forward only.
Bridge or Fortran changes need a plain rebuild plus the acceptance gates;
Julia-side package changes additionally need step 1 (and step 2 if the
AOT path matters to you); data-affecting changes need the examples rerun
before step 3 can show anything new. Skipping a step does not fail loudly
-- it silently renders figures of the wrong run.

## Where to go next

- [Deployment modes](../user/deployment-modes.md) -- what each artifact
  buys at runtime.
- [Acceptance gates](acceptance-gates.md) -- what to run after any of
  these rebuilds.
- [Performance annex](annex-performance.md) -- the measurements the
  sysimage and AOT builds were validated with.
