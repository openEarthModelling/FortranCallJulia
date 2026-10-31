---
title: Deployment modes
sync: 2026-10-31
---

# Deployment modes

One Fortran source, four delivery forms. The bridge calls do not change
between them; what changes is how the Julia code behind those calls
reaches the machine -- interpreted from a project environment, precompiled
into a sysimage the embedded runtime loads, or compiled ahead of time into
a plain shared library -- and, at the end of the line, not using Julia at
all. That fourth form, native pure Fortran, is the baseline the other
three are measured against.

## The spectrum

Measured on the capstone reacting-flow example (full report:
`examples/07_capstone/PERFORMANCE.md`):

| Mode | Startup | What the target machine needs | Julia on the target? |
|---|---|---|---|
| JIT (embedded, project env) | **17.3 s** init | your binary, a pinned Julia install, the project env and its package depot | yes |
| Sysimage | **1.90 s** init | your binary plus the sysimage file, built by the same Julia | yes |
| AOT library | 0.58--1.97 s library init | your binary plus the compiled `.so` | no |
| Native (pure Fortran) | none | your binary | no |

As a ladder: **17.3 s** from cold start to first result in JIT, **1.90 s**
with a sysimage, and the AOT build answers its first call in about
**12 μs**, approaching the native baseline of having no Julia in the
process at all. (The 12 μs is a trivial call into the compiled library;
a first *real* chemistry call costs milliseconds of solver work in every
mode, because the work sets that number, not the mode.)

Startup ranges across runs on one machine: JIT 15.1--20.2 s (it loads
about 92 package caches; the high end is a busy machine), sysimage
0.93--2.37 s (the low end with a warm page cache), AOT 0.58--1.97 s
(cold-to-warm page cache on the library).

## What changes and what does not

**Startup changes; per-call cost does not.** A warm call crosses the same
`fcj_*` ABI in every mode, so the numbers from
[Two SDKs, two speeds](two-sdks.md) hold everywhere: ~815 ns generic,
~3.8 ns on the Fast Path. The capstone's chemistry totals show it
empirically -- 4.79 s (JIT) against 4.02 s (sysimage) over the same 5216
Strang half-steps, a gap that flips sign between runs. It is machine-load
noise (about ±20%), not a mode effect. Pick a mode for startup latency
and for what ships; do not pick it for steady-state speed.

Memory does not change either: the sysimage run's peak RSS lands within
~30 MB of the JIT run. The image precompiles code; it does not shrink the
heap your problem needs.

## Mode 1: JIT -- the developer default

Initialize with `julia_init()` or `julia_init_ex(project_path=...)` and
let Julia load precompiled package caches from a depot at runtime. No
extra build steps, every package resolves through its `[compat]` bounds,
and a top-level `julia_eval_string` can redefine code live. The price is
the 17.3 s-class startup, and a target machine that carries the whole
depot.

When `project_path` is omitted, `julia_init_ex` probes for the
FortranBridge package: the `$JULIA_FJ_PROJECT` environment variable, then
the copy installed next to the executable, then `$JULIA_PROJECT`. A
failed probe returns without initializing, the reason in
`get_last_error_message()`.

## Mode 2: sysimage -- pay at build time, load in two seconds

`cmake -DFJ_BUILD_SYSIMAGE=ON` drives `scripts/build_sysimage.jl`:
PackageCompiler's `create_sysimage` over `FortranBridge`, `SciMLBase`,
`OrdinaryDiffEq`, and `FjKinetics`, tracing a precompile workload into
the image. The result is a large file -- about a gigabyte for this
repository's SciML-laden image -- that the embedded runtime loads at
init. Nothing compiles at runtime, by construction: the code is already
in the image.

The capstone driver switches between the first two modes with one branch,
from `examples/07_capstone/1_reacting_flow.f90`:

```fortran
            if (trim(jmode) == 'sysimage') then
                inquire(file=trim(image_path), exist=lex)
                if (.not. lex) then
                    write (error_unit, '(a)') 'FATAL: sysimage not found at ' // &
                        trim(image_path) // ' (set FJ_SCIML_SYSIMAGE)'
                    error stop 1
                end if
                print '(a,a,a,a)', 'detonation: julia mode=sysimage image=', trim(image_path), &
                    ' project=', trim(project_path)
                call julia_init_ex(image_path=trim(image_path), project_path=trim(project_path))
            else
                print '(a,a,a)', 'detonation: julia mode=jit project=', trim(project_path)
                call julia_init_ex(project_path=trim(project_path))
            end if
```

Two caveats. The image is baked for `cpu_target="native"` -- the build
host's instruction set -- so it is a single-host artifact. And it is
pinned to the exact Julia build: the same self-contained 1.12.7 binary
must build the image and embed the runtime; a version shim pointing at
another minor version is rejected by the sysimage build guard
([Installation](installation.md)).

In sysimage mode the image already binds the precompiled modules in
`Main`, so the runtime `import` the JIT path needs simply does not run.
The capstone counts 13 init/setup bridge calls in sysimage mode against
15 in JIT, and the difference is that missing import sequence: the
`import FjKinetics` eval plus the re-probe that follows it.

## Mode 3: AOT -- Julia as an ordinary shared library

Here the direction flips: instead of Fortran embedding Julia,
PackageCompiler's `create_library` compiles a Julia package and its whole
dependency closure into `dist/`, exposing your functions as C symbols.
Fortran links the result like any C library, and the target needs no
Julia install, no depot, no project. Startup is a plain image load
(0.58--1.97 s, cold-to-warm cache), and a first call into the library
answers in ~12 μs. Nothing JITs, ever.

The bridge is not involved in this mode, and that has a sharp edge: the
SDK's `julia_init()` must not be used. The interface note from
`examples/04_performance/1_jit_vs_aot.f90`:

```fortran
        ! Lifecycle of the runtime embedded in libmylib.so. The SDK's
        ! julia_init() must NOT be used in this mode: linking libmylib.so
        ! makes its bundled libjulia satisfy libjulia.so.1 for the whole
        ! process, and a bare jl_init() would then look for a default
        ! sys.so that the bundled layout does not ship (the sysimage is
        ! compiled INTO libmylib.so and only init_julia() knows how to
        ! load it, with an explicit bindir).
        subroutine init_julia(argc, argv) bind(c, name="init_julia")
            use iso_c_binding
            integer(c_int), value :: argc
            type(c_ptr), value :: argv
        end subroutine

        subroutine shutdown_julia(retcode) bind(c, name="shutdown_julia")
            use iso_c_binding
            integer(c_int), value :: retcode
        end subroutine
```

The same first call, both worlds (same source, two builds):

```fortran
#ifdef COMPILED_MODE
    res = my_add_float(10.0d0, 20.0d0)
#else
    res_obj = julia%call("perf_add_one", 10.0d0)
    res = res_obj%as_real()
#endif
```

Error handling changes shape too: no Julia exception can cross a C ABI.
The compiled library returns integer codes instead -- the capstone's AOT
chemistry kernel uses 0 for success, -1 for a bad `n`, -2 for a solver
that was never built, -3 for a solver that threw -- and its buffers are
wrapped zero-copy, exactly like the bridge's `fcj_wrap_array`.

Two costs to know before choosing it. The build is heavy: the
non-incremental codegen of the whole closure took about 50 min wall and
~33 GB peak compiler RSS for the capstone kernel, and `dist/` ships about
2.5 GB. And the API surface freezes: you call fixed C symbols, not names
resolved at runtime.

One sentence of PackageCompiler hygiene: build with
`include_lazy_artifacts=true`, or the "self-contained" library will
silently download lazy artifacts (MKL among them) from the network the
first time it loads on a machine without a depot.

Working examples: `examples/03_deployment/2_compiled_library/` (the small
demo) and `examples/07_capstone/3_aot_kinetics/` (the production-shaped
one).

## Mode 4: native -- the yardstick

Pure Fortran, nothing embedded. It belongs in the table because it is the
reference: every bridge mode is validated against a native run of the
same physics -- four acceptance gates, zero deviations, residuals below
1e-12 ([Validation](../intro/validation.md)). When a workload buys
nothing from Julia, native is not a fallback; it is the answer.

## Startup control: `julia_init_ex`

All three embedded modes start through the same SDK call, which wraps the
C entry point `fcj_init_ex` (as `julia_shutdown` wraps `fcj_shutdown`).
Its optional arguments are the deployment knobs: `image_path` (the
sysimage), `project_path` (the environment), `nthreads` (Julia threads),
`handle_signals` (disposition). From
`examples/03_deployment/ex_init_options.f90`:

```fortran
    ! 1. Initialize the Julia runtime with explicit startup options:
    !    - project_path: omitted on purpose -- the exe-adjacent probe finds
    !      the FortranBridge package copied next to this executable by the
    !      build, and an explicit RELATIVE path would be validated against
    !      the CWD (breaking runs from any other directory)
    !    - nthreads = 2
    !    - handle_signals = 0 ("no takeover": SIGINT/SIGTERM are reset to
    !      SIG_DFL after init; GC-critical handlers stay intact -- bridge.h)
    call julia_init_ex(nthreads=2, handle_signals=0)
```

Failure semantics are deliberate: a bad option (a path too long to fit,
an environment that does not exist) returns without initializing and
`get_last_error_message()` carries the reason -- the process does not
abort. On signals: the bridge never touches `jl_options.handle_signals`,
because GC safepoint polling depends on Julia's own handlers; the `0`
above means "no takeover", resetting `SIGINT`/`SIGTERM` to their defaults
after init. The legacy `julia_init` / `julia_init_with_image` keep their
historical signal behavior.

## Choosing

1. **Develop in JIT.** Nothing to build, live redefinition, the whole
   stack resolvable through `[compat]`. The 17.3 s-class startup is a
   development tax, paid on a machine that can afford it.
2. **Cut startup with a sysimage when the same binary runs repeatedly on
   a known host.** 1.90 s to first result, identical heap footprint, no
   runtime compilation by construction. Budget the image size, and
   remember it is host-pinned and Julia-version-pinned.
3. **Go AOT when the target has no Julia, or when first-call latency is
   the product.** Nothing to install, ~12 μs first call, integer error
   codes instead of exceptions -- and a heavy one-time build you schedule
   in advance, not stumble into.
4. **Stay native where Julia buys nothing.** The baseline is also a
   mode.

## Where to go next

- [Bring your own kinetics](bring-your-own-kinetics.md) -- the delivery
  modes wrapped around a real chemistry package.
- [Validation](../intro/validation.md) -- the correctness gates that no
  mode is allowed to break.
- [Performance annex](../developer/annex-performance.md) -- the full
  capstone performance report behind every number on this page.
