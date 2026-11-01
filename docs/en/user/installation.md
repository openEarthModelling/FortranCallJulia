---
title: Installation
sync: 2026-11-01
---

# Installation

FortranCallJulia builds on Linux with gfortran, gcc, and CMake, embedding a
pinned Julia 1.12.7 runtime in-process. The C bridge, the two-tier Fortran
SDK, and the Julia-side runtime package (`FortranBridge.jl`) all come from
this repository -- there is nothing else to download. Two entries in the
matrix below are load-bearing pins; the sections after the table explain
why they are not negotiable.

## Version matrix

| Component | Version | Notes |
|---|---|---|
| OS | Linux | The only platform exercised by the acceptance suite. |
| Compilers | gfortran + gcc | GNU-specific flags (`-fno-underscoring`) are compiler-gated in CMake. |
| CMake | 3.13 or newer | Drives the bridge, the SDK, and the examples. |
| Julia | **1.12.7, pinned** | The embedded `libjulia`; see the next section. |
| Catalyst | `~16.2` (major 16) | Compat-pinned via `FjKinetics.jl`'s `[compat]`. |
| OrdinaryDiffEq | `~6.111` (major 6) | Compat-pinned; the 7.x line is a measured ~700x regression. |
| SciMLBase | `~2.155` (major 2) | Compat-pinned alongside the two above. |
| ChemMechSim.jl | **v1.2.0** | Open source; the version every validation number here was produced with. |

Only the first four rows are needed to build and run the basics examples.
The SciML pins and ChemMechSim matter once you build the sysimage or the
chemistry capstone (`examples/07_capstone`).

## Julia 1.12.7, pinned on purpose

The bridge embeds `libjulia` 1.12.7, and every acceptance baseline must run
exactly that version -- the same runtime, or the comparison is meaningless.
The pin is not cosmetic. During this project's development a `juliaup` shim
silently drifted to a newer minor release, the comparison baselines
followed the shim, and the version mismatch masqueraded as a bridge
regression: a defect hunt aimed at code that was never broken. Since then
the version is pinned and actively checked -- the sysimage build refuses to
run under anything but Julia 1.12.x.

Install a self-contained Julia 1.12.7 and make sure `julia` on `PATH`
resolves to it:

```bash
julia --version        # must report: julia version 1.12.7
```

With juliaup, pin the default explicitly, because the shim's default can
change under you:

```bash
juliaup add 1.12.7
juliaup default 1.12.7
julia --version
```

A plain tarball install works equally well. Whichever route you take: the
same binary must later build any sysimage you load
([Deployment modes](deployment-modes.md)).

## The SciML stack, compat-pinned

`examples/07_capstone/FjKinetics/Project.toml` pins the solve stack through
`[compat]`: Catalyst `~16.2`, OrdinaryDiffEq `~6.111`, SciMLBase `~2.155`
-- the major-16 / major-6 / major-2 lines. Resolve through those pins and
do not force an upgrade past them. The reason is measured, not aesthetic:
with the stack left unpinned, a resolve once drifted onto the
OrdinaryDiffEq 7.x line, whose step-size controller degraded the
per-grid-cell `reinit!`/`step!` pattern by roughly 700x (a frozen cell
costing hundreds of internal steps instead of one). The pins live in the
package, so a normal resolve respects them; you only break them by
force-upgrading.

The one-time environment setup is scripted. `scripts/install_sciml_env.jl`
creates the scratch environment `scripts/sysimage_env`, develops the
in-repo packages into it (`FortranBridge.jl`, `FjKinetics.jl` v0.2, plus
ChemMechSim -- next section), adds the SciML stack, and then wires
`FjKinetics`' own package environment. Run it with the same pinned Julia:

```bash
julia scripts/install_sciml_env.jl
```

## ChemMechSim.jl

ChemMechSim.jl supplies mechanism input -- GRI-Mech 3.0 with 53 species and
325 reactions -- and is open source, installable as a normal Julia package:

```julia
import Pkg
Pkg.add("ChemMechSim")
Pkg.status("ChemMechSim")
```

**Every validation number in these docs was produced with v1.2.0.** The
General registry can lag behind the repository (it has carried v1.0.0 while
the repository was already at v1.2.0), so if `Pkg.status` reports something
older, install the tagged v1.2.0 from a checkout of the repository instead:

```julia
Pkg.develop(path="<your ChemMechSim.jl checkout>")   # at tag v1.2.0
```

`scripts/install_sciml_env.jl` expects such a checkout and develops it into
both environments it sets up; if yours is not in the default location,
point `CHEMMECHSIM_PATH` at it before running the script. Whichever way you
installed it, confirm the version inside `scripts/sysimage_env` before
comparing your results against the validation numbers.

## Build

From a checkout of this repository:

```bash
mkdir build && cd build
cmake -DBUILD_EXAMPLES=ON ..
make -j8
./examples/ex01_quickstart
```

At configure time CMake finds `julia` on `PATH` -- failing immediately with
a clear message if it is missing -- and asks `julia-config.jl` for the C
and linker flags that match your Julia build. The build produces
`libfcj_middleware.a` (eight C bridge sources plus the two Fortran SDK
sources) and links it statically into each example executable; the
`FortranBridge` runtime directory and `examples_lib.jl` are copied next to
the executables, so examples run from any working directory.

For the optional sysimage build, which cuts the SciML cold start from
17.3 s to 1.90 s:

```bash
julia scripts/install_sciml_env.jl    # once; see the SciML section above
cmake -DFJ_BUILD_SYSIMAGE=ON ..
make fcj_sysimage                     # minutes; downloads on first run
```

## Consuming from another CMake project

The library exports one namespaced CMake target, `fcj::fcj_middleware`,
through two tiers. Both need the same pinned Julia 1.12.x at configure
time -- the package re-runs Julia discovery on your machine (Julia on
`PATH`, or `-DJULIA_EXECUTABLE=...`) and rejects a different minor,
because the bridge embeds libjulia 1.12.7.

**`find_package`** -- install once, then consume the install tree:

```cmake
find_package(FortranCallJulia 0.1 REQUIRED)
target_link_libraries(your_app PRIVATE fcj::fcj_middleware)
```

Configure with `-DCMAKE_PREFIX_PATH=/path/to/installed/prefix`. One
caveat: the installed Fortran modules under `include/` were compiled by
the builder's gfortran -- consume them with the same gfortran version, or
use FetchContent to compile everything with your own.

**`FetchContent`** -- no install step; compile the bridge inside your
tree and pin a tag:

```cmake
include(FetchContent)
FetchContent_Declare(fcj
    GIT_REPOSITORY https://github.com/openEarthModelling/FortranCallJulia.git
    GIT_TAG        v0.1.0)
FetchContent_MakeAvailable(fcj)
target_link_libraries(your_app PRIVATE fcj::fcj_middleware)
```

At runtime the bridge locates the `FortranBridge` Julia package via
`JULIA_FJ_PROJECT` or a directory next to the executable. With
`find_package` the Config sets `FortranCallJulia_FortranBridge_DIR` to
the installed copy; with FetchContent it is `<fcj-source>/src/FortranBridge`.
Both tiers are exercised in CI by `tests/cmake_consumer`.

## Where to go next

- [Your first call](first-call.md) -- the minimal program, walked through.
- [Two SDKs, two speeds](two-sdks.md) -- choosing between the two layers.
