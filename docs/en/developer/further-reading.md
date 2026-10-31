---
title: Further reading
sync: 2026-10-31
---

# Further reading

This site documents this bridge. The links below are the upstream
resources a maintainer will actually want open in a second tab --
official manuals for the machinery we embed, the packaging tools we build
with, and the domain references behind the validation problems. Each
entry says which page of ours it backs. (A local mirror of some of these
documents travels with the repository for offline work; it is excluded
from this site, so every link here goes to the live upstream source.)

## Embedding Julia from C

- [Embedding Julia -- the Julia manual](https://docs.julialang.org/en/v1/manual/embedding/) --
  the canonical reference for `jl_init`, GC roots (`JL_GC_PUSH`),
  `jl_call`, and the `julia-config.jl` embed flow. Everything in
  [bridge internals](bridge-internals.md) is built on this page plus the
  `julia.h` header.
- [The Julia documentation](https://docs.julialang.org/en/v1/) -- start
  here for the language semantics the Julia-side package relies on.
- [juliaup](https://github.com/JuliaLang/juliaup) -- the version manager
  whose auto-updating shims motivated the pinning discipline of
  [Lessons](lessons.md). Read its channel documentation before pointing
  any build at a `julia` that is really a shim.

## PackageCompiler: sysimages and AOT libraries

- [PackageCompiler.jl documentation](https://julialang.github.io/PackageCompiler.jl/stable/) --
  the manual behind both rebuild recipes of
  [rebuild from zero](rebuild.md).
- [Sysimages](https://julialang.github.io/PackageCompiler.jl/stable/sysimages.html) --
  what `create_sysimage` traces and bakes; why an image is pinned to one
  Julia build and one `cpu_target`.
- [Building libraries](https://julialang.github.io/PackageCompiler.jl/stable/libs.html) --
  `create_library`, `Base.@ccallable`, and the `init_julia` contract the
  AOT examples follow.
- [PackageCompiler.jl repository](https://github.com/JuliaLang/PackageCompiler.jl) --
  issues and release notes; where the `include_lazy_artifacts` behavior
  is tracked.

## The SciML stack behind the chemistry

- [DifferentialEquations.jl documentation](https://docs.sciml.ai/DiffEqDocs/stable/) --
  the solver suite; the per-cell `reinit!` / `step!` pattern whose
  performance regression is [Lessons](lessons.md) entry 2.
- [Catalyst.jl documentation](https://docs.sciml.ai/Catalyst/stable/) --
  the reaction-network modeling layer in the pinned stack.
- [OrdinaryDiffEq.jl](https://github.com/SciML/OrdinaryDiffEq.jl) and
  [SciMLBase.jl](https://github.com/SciML/SciMLBase.jl) -- the solver and
  problem-interface packages whose `[compat]` pins are load-bearing.
- [SciML](https://sciml.ai/) -- the ecosystem's overview site.

## Domain references for the validation problems

- [GRI-Mech 3.0](http://www.me.berkeley.edu/gri_mech/) -- the 53-species,
  325-reaction natural-gas combustion mechanism behind the ignition-delay
  benchmark of [acceptance gates](acceptance-gates.md).
- [Cantera](https://cantera.org/) -- the YAML mechanism format
  ChemMechSim loads; the reference toolchain for cross-checking
  mechanism data.
- [Clawpack](https://www.clawpack.org/) -- conservation-law /
  finite-volume methods; the intellectual home of the wave-propagation
  solver the reacting-flow capstone builds on.

## Tooling adjacent to this repository

- [Preferences.jl](https://juliapackaging.github.io/Preferences.jl/stable/) --
  how Julia packages persist per-environment settings; relevant whenever
  build behavior differs between environments.
- [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) -- the
  standard Julia documentation generator; the reference point for
  comparing conventions with this MkDocs site.

## Where to go next

Nothing downstream -- you have reached the reference shelf. Back to
[the developer guide](repository-tour.md), or to the site's own
[validation story](../intro/validation.md).
