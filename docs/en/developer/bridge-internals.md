---
title: Bridge internals
sync: 2026-10-31
---

# Bridge internals

Eight C files, four responsibility groups, one contract. The user-facing
pages describe the bridge from outside -- the `fcj_*` ABI, the two Fortran
SDK layers, the numbers. This page opens the box: what each file owns, how
the GC debt is paid, and where the Julia 1.12 C API forced workarounds. It
is written for maintainers changing `src/bridge/`; nothing here is needed
to *use* the bridge.

The [architecture page](../intro/architecture.md) gives the same system in
one screen; read that first if you are new.

## The eight files

| Group | Files | Owns |
|---|---|---|
| Core | `core.c`, `memory.c` | lifecycle (`fcj_init` / `fcj_init_ex` / `fcj_shutdown`), thread pinning, the GC root set |
| Dispatch & boxing | `dispatch.c`, `types.c` | `fcj_call*` / `fcj_call_kwargs`, the function-name cache, scalar boxing (`fcj_box_*`) |
| Array channel | `arrays.c`, `extract.c` | N-D zero-copy wraps, deep copies, batch extraction to Fortran |
| Callback access | `callbacks.c`, `accessors.c` | `@cfunction` trampolines, `get_field` / `get_property`, native `Float64` element access |

Two headers frame them. `bridge.h` is the public contract: 53 `fcj_`
functions plus `fcj_options_t` -- everything a Fortran `bind(c)` layer can
reach. `bridge_internal.h` is private: the native element accessors
(`fcj_get_real` and siblings), shared helpers, and the per-module
cache-clear hooks `fcj_shutdown` walks. The "~105 exported `fcj_*` symbols"
headline used across this site counts the whole `fcj_` namespace across
these sources; the binding layer `src/julia_binding.f90` declares 58 of
them (52 of the 53 public functions -- `fcj_ready` is never bound -- plus
the 6 internal element accessors), and the rest are
internal helpers that never cross the ABI.

## Core: lifecycle and the root set

`core.c` owns the state machine. `fcj_state` is `_Atomic`; every entry
point checks it through `fcj_ready()` before touching Julia. The thread
rule from [Known limitations](../user/known-limitations.md) is enforced,
not documented, in `check_thread()` (verbatim from `src/bridge/core.c`):

```c
int check_thread() {
    if (pthread_self() != main_thread_id) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Thread Error: Julia called from thread %p, runtime owned by thread %p",
                 (void*)pthread_self(), (void*)main_thread_id);
        set_error(msg);
        return 0; // Fail
    }
    return 1; // OK
}
```

Failure semantics split by entry point: `fcj_init` aborts the process on
failure (the original contract), while `fcj_init_ex` returns an error code
and leaves the reason in `fcj_get_last_error()` -- surfaced in Fortran as
`get_last_error_message()`. `fcj_shutdown` is one-way: the state machine
never returns to READY, and re-initialization after shutdown is rejected
loudly rather than attempted.

`memory.c` is the GC story, and its header comment states the design
better than a paraphrase would (from `src/bridge/memory.c`):

```c
// fcj_retain/fcj_release keep their bind(C) signatures but no longer round-trip
// through Julia (retain_obj/release_obj in GCManager.jl) on the hot path.
// Retained objects live in a Julia Vector{Any} reachable through the constant
// binding `Main.FJ_ROOTS` ... bookkeeping is a pure-C ptr -> slot hash map with
// per-pointer refcounts, mirroring GCManager's REF_COUNTS/PTR_CACHE logic.
```

The mechanics that matter to a maintainer:

- **A C static is not a GC root.** Any function or value cached in a
  `static` must be routed through `fcj_retain` (a module binding counts;
  a bare static does not). The one sanctioned exception is immortal
  singletons kept alive by their Base binding, such as the `ComplexF64`
  type object cached in `types.c`.
- **`fcj_map` is open-addressing with tombstones and refcounts** --
  deleted entries tombstone so probe chains stay intact, and a pointer
  retained twice occupies one slot with a count of two.
- **No locking anywhere in these statics.** The single-thread contract
  (`check_thread`) is the lock. Break the contract and you have a data
  race, not a bug report.

## Dispatch and boxing

`dispatch.c` turns names into calls. The function-name cache is a fixed
256-slot table hashed with FNV-1a; cache hits are routed through
`fcj_retain` so the cached `jl_function_t*` is rooted. Two invalidation
rules a maintainer must never undo:

1. The cache is cleared **first** in `fcj_shutdown` -- before anything
   else could still dereference it.
2. **Every `julia_eval_string` invalidates the name caches.** An eval can
   redefine `f` from a function to a closure, and a stale cache entry
   would call the captured old object forever. (The Fast Path registry
   keeps its captured-object semantics by design and documents it;
   see [Two SDKs, two speeds](../user/two-sdks.md).)

`fcj_call1_float64` through the N-argument family and `fcj_call_kwargs`
(the keyword-argument path) all funnel through the same
`jl_call`/exception-check tail. `types.c` boxes Fortran scalars into Julia
objects -- `fcj_box_float64`, `fcj_box_string`, and the rest -- plus the
cached `ComplexF64` datatype noted above.

## The array channel

`arrays.c` wraps Fortran memory as a Julia `Array` of any rank 1 through
`FCJ_MAX_NDIM`, zero-copy, via `jl_ptr_to_array`. The wrap path, verbatim
from `src/bridge/arrays.c` (the three guard helpers are the same shape,
elided for length):

```c
void* fcj_wrap_array(void* data, long ndim, const long* dims) {
    if (!fcj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_value_t *array_type = NULL;
    jl_value_t *dims_tuple = NULL;
    JL_GC_PUSH2(&array_type, &dims_tuple);

    array_type = array_type_for_ndim(ndim, "fcj_wrap_array");
    ...
    dims_tuple = make_dims_tuple(ndim, dims, "fcj_wrap_array");
    ...
    jl_array_t *arr = jl_ptr_to_array(array_type, data, dims_tuple, 0);

    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return (void*)arr;
}
```

Two disciplines visible in that excerpt, both load-bearing everywhere in
the bridge: local values are rooted with `JL_GC_PUSH2` for the duration of
a call, and any error path `set_error`s a reason before returning NULL.
The deep-copy sibling `fcj_copy_array` allocates a fresh Julia array and
memcpys in, with an overflow-checked extent product before the allocation.

`extract.c` is the return leg: `fcj_to_fortran` (one bulk copy into a
Fortran buffer, length-checked), `fcj_get_element`, `fcj_get_property`.
The bulk path is a single `memcpy` from `jl_array_data_` with an `n == len`
check -- which is why the extraction channel is bit-exact and why the
acceptance gates can put a 1e-8 door in front of it
([acceptance gates](acceptance-gates.md)).

## Callback access

`callbacks.c` runs the other direction: Fortran `bind(c)` subroutines
wrapped into Julia-callable objects through `@cfunction` trampolines, with
the calling context carried opaquely. This is the machinery behind the
OrdinaryDiffEq callback demos of `examples/06_sciml/1_callback.f90`. The
hard rule from the user pages holds at this level too: a trampoline frame
cannot host a Julia exception, so a throwing callee is undefined behavior
-- validate on the Fortran side, return sentinels.

`accessors.c` implements `%element` and `%property`, and here the Julia
1.12 C API forced the most instructive workarounds in the tree. The header
of `extract.c` records them (from `src/bridge/extract.c`):

```c
// 1.12.7 API notes (verified against include/julia/julia.h):
//  - jl_get_property does not exist; jl_get_field exists but only reads
//    plain struct fields (no getproperty overloads, no NamedTuples), so
//    the contract's fallback applies: Base.getproperty is cached once and
//    jl_call-ed, matching helper_getfield semantics in Accessors.jl;
//    getproperty dispatches on Symbol, so the name is interned with
//    jl_symbol (immortal, globally rooted) instead of boxed as a String;
//  - jl_arrayref does not exist either (removed with the Memory-backed
//    array rewrite), so element boxing goes through a cached
//    Base.getindex binding -- the same numeric boxing jl_arrayref used to
//    perform.
```

Read that as the general lesson: when a `jl_*` convenience is missing,
cache the equivalent Base function once (rooted through `fcj_retain`) and
`jl_call` it -- do not hand-roll struct offsets. `bridge_internal.h` adds
the native element accessors (`fcj_get_real` / `fcj_set_real` and 2- and
3-index forms): direct `Float64` reads and writes into wrapped memory, no
boxing, used by the hot per-cell paths.

## Signals and error transport

The bridge never writes `jl_options.handle_signals`: GC safepoint polling
depends on Julia's own signal handlers, and disabling them crashes at a
safepoint -- reliably, not occasionally ([Lessons](lessons.md)). The
`handle_signals=0` option offered by `fcj_options_t` means "no takeover":
after a successful init the bridge resets `SIGINT`/`SIGTERM` to `SIG_DFL`,
leaving the GC-critical handlers intact.

Errors travel one channel: the per-runtime last-error buffer, read through
`fcj_get_last_error()` and surfaced as `get_last_error_message()`. A
Julia-side exception is caught at the call boundary, formatted into that
buffer, and the call returns an invalid handle or NULL -- the process keeps
running.

## Where to go next

- [Acceptance gates](acceptance-gates.md) -- how you prove you did not
  break any of this.
- [Rebuild from zero](rebuild.md) -- the sysimage and AOT builds that wrap
  this core for deployment.
- [Lessons](lessons.md) -- the incidents that put these rules in writing.
