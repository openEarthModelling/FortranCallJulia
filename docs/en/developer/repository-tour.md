---
title: Repository tour
sync: 2026-10-31
---

# Repository tour

The map before the territory. This page walks the repository top-level down
to the files that matter, says what each piece is for, and points to the
page that covers it in depth. Read it once here; after that the site's
search should be enough.

## The top level

| Entry | What it is |
|---|---|
| `src/bridge/` | The C heart of the bridge: 8 files, ~105 exported `fcj_*` symbols ([bridge internals](bridge-internals.md)) |
| `src/FortranBridge/` | The Julia-side package: 5 submodules behind `FortranBridge.jl` |
| `src/julia_binding.f90` | `julia_low_level`: the `bind(c)` truth over the `fcj_*` C ABI |
| `src/julia_sdk.f90` | `julia_high_level`: `type(JuliaValue)`, boxing, converters, `%to_fortran` |
| `src/lib_support/` | Fortran support types and the AOT library interface declarations |
| `examples/` | 7 numbered example families, `01_basics` through `07_capstone`, plus `legacy/` |
| `scripts/` | Environment install, sysimage build, precompile workload, docs tooling |
| `docs/` | This bilingual MkDocs site (`en` default, `zh` mirror) |
| `tests/` | Site parity tests (`test_docs_parity.py`) -- the docs gates, not the physics gates |
| `CMakeLists.txt` | Build: the `fcj_middleware` static library, examples, `FJ_BUILD_SYSIMAGE` |
| `README.md` | Gateway to this documentation site: links into both locales, the headline numbers, and the local build recipe |
| `plan.md` | The running development log: every wave, incident, and decision, dated |
| `embedding.md` | Curated notes on embedding Julia from C, with third-party pointers |
| `requirements*.txt` | Python dependencies for the docs build (`-docs`) and dev tooling (`-dev`) |

## `src/`: the bridge in three languages

**`src/bridge/` -- C.** The embeddable core. Eight `.c` files in four
responsibility groups: core lifecycle (`core.c`, `memory.c`), dispatch and
boxing (`dispatch.c`, `types.c`), the array channel (`arrays.c`, `extract.c`),
and callback access (`callbacks.c`, `accessors.c`). Two headers define the
surface: `bridge.h` is the public contract (53 `fcj_` functions plus
`fcj_options_t`), `bridge_internal.h` the private one (native element
accessors, per-module cache-clear hooks). Everything a maintainer needs is
on [bridge internals](bridge-internals.md).

**`src/FortranBridge/` -- Julia.** The package the embedded runtime loads.
Five submodules under `src/FortranBridge/src/FortranBridge.jl`:

| Submodule | Role |
|---|---|
| `GCManager.jl` | The Julia-side root registry (`Main.FJ_ROOTS` fallback path, refcounts) |
| `FunctionRegistry.jl` | Name-to-function registry, `@cfunction` trampolines for the Fast Path |
| `Accessors.jl` | `getfield` / `getproperty` helpers behind `%element` and `%property` |
| `Callbacks.jl` | Fortran `bind(c)` subroutines wrapped into Julia callables |
| `Utilities.jl` | Small shared helpers |

**`src/julia_binding.f90` and `src/julia_sdk.f90` -- Fortran.** The two SDK
layers of [Two SDKs, two speeds](../user/two-sdks.md): the low-level
`bind(c)` declarations (58 symbols), and the high-level OOP layer built on
top. `src/lib_support/` holds `julia_types.f90` (support types) and
`julia_library_interface.f90` -- the `init_julia` / `shutdown_julia`
declarations the AOT examples link against
([deployment modes](../user/deployment-modes.md)).

## `examples/`: the numbered ladder

Each family is a step up in ambition; the numbering is also the recommended
reading order.

| Family | Contents | Demonstrates |
|---|---|---|
| `01_basics` | hello world, quickstart, arrays, zero-copy arrays, data structures | first calls, the array channel |
| `02_intermediate` | math operations, keyword arguments | `%call` variants, `fcj_call_kwargs` |
| `03_deployment` | init options, custom sysimage, `2_compiled_library/` | startup control, AOT |
| `04_performance` | JIT vs AOT, call overhead, memory transfer, access patterns, benchmark suite | where the ~815 ns / ~3.8 ns numbers come from |
| `05_hpc_parallel` | multithreading (100,000 wrapped matrices, one call), MPI bootstrap | batching inside the one-thread rule |
| `06_sciml` | callback, batch data, SciML demo | OrdinaryDiffEq across the bridge |
| `07_capstone` | reacting flow, GRI ignition, `3_aot_kinetics/`, `FjKinetics/`, `figures/`, `PERFORMANCE.md` | everything at once, plus the acceptance gates |

`examples/legacy/` keeps the eleven pre-package examples (`01_hello.f90` ...
`11_all_types.f90`) for archaeology; nothing links against them.
`examples/CMakeLists.txt` builds one executable per numbered source, copies
the Julia runtime and project next to the executables, and adds the `MyLib`
AOT demo when its `dist/` exists.

## `scripts/`: the maintenance tooling

| File | Role |
|---|---|
| `install_sciml_env.jl` | Creates `scripts/sysimage_env` and assembles the pinned SciML stack into it |
| `build_sysimage.jl` | PackageCompiler `create_sysimage` over FortranBridge + SciMLBase + OrdinaryDiffEq + FjKinetics |
| `precompile.jl` | The precompile workload traced into the sysimage |
| `docs_parity.py`, `docs_leak_patterns.txt` | The bilingual parity and leak gates this site is held to |

The pinned-environment story behind the first three is
[Rebuild from zero](rebuild.md); why the pins exist at all is
[Lessons](lessons.md).

## `docs/`, `tests/`, and the site gates

`docs/` holds `en/` (default locale) and `zh/` (mirror), plus the excluded
`superpowers/` working notes. `tests/test_docs_parity.py` drives
`scripts/docs_parity.py`: every page must exist in both locales with a
translated title, the `sync` stamps must agree, and no page may leak
machine-specific strings (local paths, hostnames) -- the same sanitization
rule the prose pages are written under.

## Where to go next

- [Bridge internals](bridge-internals.md) -- the eight C files, group by
  group, with the real code in front of you.
- [Acceptance gates](acceptance-gates.md) -- what "correct" means here, and
  how to re-prove it after a change.
- [Contributing](contributing.md) -- turning a tour into a pull request.
