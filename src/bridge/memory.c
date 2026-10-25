#include "bridge_internal.h"
#include <stdlib.h>
#include <stdint.h>

// --- Object Management ---
//
// fj_retain/fj_release keep their bind(C) signatures but no longer round-trip
// through Julia (retain_obj/release_obj in GCManager.jl) on the hot path.
// Retained objects live in a Julia Vector{Any} reachable through the constant
// binding `Main.FJ_ROOTS` (created once at the end of a successful fj_init
// via fj_roots_init below); bookkeeping is a pure-C ptr -> slot hash map with
// per-pointer refcounts, mirroring GCManager's REF_COUNTS/PTR_CACHE logic.
// GCManager.jl stays untouched as the fallback path (and for precompilation).
//
// GC lifetime of the cached handles: a JL_GC_PUSH cannot span bridge calls,
// but no local root is needed. The vector stays alive because `const
// Main.FJ_ROOTS` is a module binding, i.e. a GC root holding the only
// reference to it, so the cached jl_array_t* stays valid for the runtime's
// lifetime and every written slot is scanned as part of that vector.
// `fj_nothing` is the `nothing` singleton kept alive by its Base binding.
// jl_array_grow_end fills newly exposed slots with jl_nothing, so the GC
// never scans uninitialized memory.
//
// Single-thread contract: all bridge calls happen on the init thread
// (check_thread in core.c enforces it), so these statics need no locking.

#define FJ_ROOTS_GROW 256
#define FJ_MAP_INITIAL_CAP 64 // power of two
// Occupied keys are real Julia heap pointers, never NULL; deleted entries are
// tombstoned so probe chains stay intact.
#define FJ_MAP_TOMBSTONE ((void*)1)

int fj_roots_init(void);
void fj_roots_teardown(void);

// Root vector (Main.FJ_ROOTS, a Vector{Any})
static jl_array_t* fj_roots = NULL;
static jl_value_t* fj_nothing = NULL; // cached `nothing`
static size_t fj_roots_len = 0; // logical length we manage (<= capacity)
static size_t fj_roots_cap = 0; // current jl_array_len(fj_roots)

// Free list of reusable slot indices (LIFO)
static size_t* fj_free_slots = NULL;
static size_t fj_free_count = 0;
static size_t fj_free_cap = 0;

// ptr -> slot map: open addressing, linear probing, power-of-two capacity,
// rehash at 70% load
typedef struct {
    void* key;    // the (void*)jl_value_t* handle Fortran stores
    size_t slot;  // index into fj_roots
    size_t count; // reference count (GCManager REF_COUNTS semantics)
} fj_map_entry_t;

static fj_map_entry_t* fj_map = NULL;
static size_t fj_map_cap = 0;  // power of two
static size_t fj_map_used = 0; // live entries
static size_t fj_map_fill = 0; // live entries + tombstones

// --- C-side root set internals ---

static void fj_roots_reset(void) {
    free(fj_map);
    fj_map = NULL;
    fj_map_cap = 0;
    fj_map_used = 0;
    fj_map_fill = 0;
    free(fj_free_slots);
    fj_free_slots = NULL;
    fj_free_count = 0;
    fj_free_cap = 0;
    fj_roots = NULL;
    fj_nothing = NULL;
    fj_roots_len = 0;
    fj_roots_cap = 0;
}

static size_t fj_map_hash(void* key) {
    // 64-bit pointer mix (murmur3 finalizer) to avalanche aligned pointers
    uintptr_t x = (uintptr_t)key;
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ULL;
    x ^= x >> 33;
    return (size_t)x;
}

static fj_map_entry_t* fj_map_find(void* key) {
    if (fj_map_cap == 0) return NULL;
    size_t mask = fj_map_cap - 1;
    size_t i = fj_map_hash(key) & mask;
    while (1) {
        void* k = fj_map[i].key;
        if (k == key) return &fj_map[i];
        if (k == NULL) return NULL; // end of probe chain
        i = (i + 1) & mask;
    }
}

// Raw insert; caller guarantees headroom (fresh tables hold no tombstones).
static void fj_map_insert_raw(void* key, size_t slot, size_t count) {
    size_t mask = fj_map_cap - 1;
    size_t i = fj_map_hash(key) & mask;
    while (fj_map[i].key != NULL) i = (i + 1) & mask;
    fj_map[i].key = key;
    fj_map[i].slot = slot;
    fj_map[i].count = count;
    fj_map_used++;
    fj_map_fill++;
}

static int fj_map_rehash(size_t new_cap) {
    fj_map_entry_t* old = fj_map;
    size_t old_cap = fj_map_cap;
    fj_map_entry_t* fresh = calloc(new_cap, sizeof(fj_map_entry_t));
    if (fresh == NULL) return -1;
    fj_map = fresh;
    fj_map_cap = new_cap;
    fj_map_used = 0;
    fj_map_fill = 0;
    for (size_t j = 0; j < old_cap; j++) {
        if (old[j].key != NULL && old[j].key != FJ_MAP_TOMBSTONE) {
            fj_map_insert_raw(old[j].key, old[j].slot, old[j].count);
        }
    }
    free(old);
    return 0;
}

// Insert a brand-new key with count 1 (fj_retain checks fj_map_find first,
// so duplicates never reach here). Returns 0, or -1 on out-of-memory
// (map left unchanged).
static int fj_map_put(void* key, size_t slot) {
    if ((fj_map_fill + 1) * 10 >= fj_map_cap * 7) {
        size_t new_cap = fj_map_cap ? fj_map_cap : FJ_MAP_INITIAL_CAP;
        while ((fj_map_used + 1) * 10 >= new_cap * 7) new_cap <<= 1;
        if (fj_map_rehash(new_cap) != 0) return -1;
    }
    size_t mask = fj_map_cap - 1;
    size_t i = fj_map_hash(key) & mask;
    size_t tomb = SIZE_MAX;
    while (1) {
        void* k = fj_map[i].key;
        if (k == key) return 0; // unreachable; keep the existing entry intact
        if (k == FJ_MAP_TOMBSTONE) {
            if (tomb == SIZE_MAX) tomb = i;
        } else if (k == NULL) {
            fj_map_entry_t* e = &fj_map[tomb != SIZE_MAX ? tomb : i];
            e->key = key;
            e->slot = slot;
            e->count = 1;
            fj_map_used++;
            if (tomb == SIZE_MAX) fj_map_fill++; // a reused tombstone already counts toward fill
            return 0;
        }
        i = (i + 1) & mask;
    }
}

static int fj_free_push(size_t slot) {
    if (fj_free_count == fj_free_cap) {
        size_t new_cap = fj_free_cap ? fj_free_cap * 2 : FJ_MAP_INITIAL_CAP;
        size_t* grown = realloc(fj_free_slots, new_cap * sizeof(size_t));
        if (grown == NULL) return -1;
        fj_free_slots = grown;
        fj_free_cap = new_cap;
    }
    fj_free_slots[fj_free_count++] = slot;
    return 0;
}

// Create Main.FJ_ROOTS once (idempotent guard, same pattern as the
// FortranBridge check in fj_init) and cache the handles. Returns 0 on
// success; on failure the caller falls back to retain_obj/release_obj and
// last_error_msg holds the reason.
int fj_roots_init(void) {
    fj_roots_reset();

    jl_eval_string("isdefined(Main, :FJ_ROOTS) || Main.eval(Meta.parse(\"const FJ_ROOTS = Vector{Any}()\"))");
    if (check_julia_exception()) return -1;

    jl_value_t* roots = jl_eval_string("FJ_ROOTS");
    if (check_julia_exception()) return -1;
    if (roots == NULL || !jl_is_array(roots)) {
        set_error("FJ_ROOTS setup failed: Main.FJ_ROOTS is not an Array");
        return -1;
    }

    jl_value_t* nothing_val = jl_eval_string("nothing");
    if (check_julia_exception()) return -1;
    if (nothing_val == NULL) {
        set_error("FJ_ROOTS setup failed: could not resolve 'nothing'");
        return -1;
    }

    fj_map_entry_t* fresh = calloc(FJ_MAP_INITIAL_CAP, sizeof(fj_map_entry_t));
    if (fresh == NULL) {
        set_error("FJ_ROOTS setup failed: out of memory for ptr->slot map");
        return -1;
    }
    fj_map = fresh;
    fj_map_cap = FJ_MAP_INITIAL_CAP;
    fj_map_used = 0;
    fj_map_fill = 0;

    // Both handles stay valid without a local GC root: the constant binding
    // Main.FJ_ROOTS is a GC root holding the only reference to the vector,
    // and `nothing` is kept alive by its Base binding.
    fj_roots = (jl_array_t*)roots;
    fj_nothing = nothing_val;
    fj_roots_cap = (size_t)jl_array_len(fj_roots);
    // A re-init may find a pre-existing FJ_ROOTS: never clobber old slots,
    // manage only what we append from here on (fresh array: both are 0).
    fj_roots_len = fj_roots_cap;
    return 0;
}

void fj_roots_teardown(void) {
    fj_roots_reset();
}

// --- Object Management ---

void* fj_retain(jl_value_t* val) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    if (val == NULL) return NULL;

    // Fast path: root the object in Main.FJ_ROOTS, no Julia round trip.
    if (fj_roots != NULL) {
        fj_map_entry_t* e = fj_map_find(val);
        if (e != NULL) {
            e->count++; // duplicate retain: GCManager REF_COUNTS semantics
            return (void*)val;
        }

        JL_GC_PUSH1(&val); // keep val rooted across the possible GC in jl_array_grow_end

        size_t slot;
        if (fj_free_count > 0) {
            slot = fj_free_slots[--fj_free_count]; // reuse a freed slot
        } else {
            if (fj_roots_len >= fj_roots_cap) {
                jl_array_grow_end(fj_roots, FJ_ROOTS_GROW);
                if (check_julia_exception()) {
                    fj_roots = NULL; // grow failed: fall back to retain_obj/release_obj
                    JL_GC_POP();
                    return NULL;
                }
                fj_roots_cap = (size_t)jl_array_len(fj_roots);
            }
            slot = fj_roots_len++;
        }

        jl_array_ptr_set(fj_roots, slot, val); // val is now rooted by FJ_ROOTS

        if (fj_map_put(val, slot) != 0) {
            // Out of memory for the bookkeeping: undo the root and fail.
            jl_array_ptr_set(fj_roots, slot, fj_nothing);
            if (slot == fj_roots_len - 1) {
                fj_roots_len--;
            } else if (fj_free_push(slot) != 0) {
                // Slot is untracked but holds jl_nothing: harmless leak of one slot.
            }
            JL_GC_POP();
            set_error("fj_retain: out of memory for ptr->slot map");
            return NULL;
        }

        JL_GC_POP();
        return (void*)val;
    }

    // Fallback path (FJ_ROOTS setup failed): call FortranBridge.retain_obj(ptr, obj)
    // We pass the raw pointer address as the first argument (boxed as Ptr{Cvoid})
    // and the object itself as the second argument.

    jl_value_t *v_ptr = NULL;
    JL_GC_PUSH2(&val, &v_ptr); // Ensure val is rooted, and v_ptr

    v_ptr = jl_box_voidpointer(val);

    jl_call2(FuncRetain, v_ptr, val);

    if (check_julia_exception()) {
        JL_GC_POP();
        return NULL;
    }
    JL_GC_POP();

    return (void*)val;
}

void fj_release(void* ptr) {
    if (!fj_ready()) { set_error("Julia runtime not initialized or already shut down"); return; }
    if (!check_thread()) return;
    if (ptr == NULL) return;

    // Fast path: drop the slot in Main.FJ_ROOTS, no Julia round trip.
    if (fj_roots != NULL) {
        fj_map_entry_t* e = fj_map_find(ptr);
        if (e == NULL) {
            set_error("fj_release: pointer was not retained (double release?)");
            return;
        }
        if (e->count > 1) {
            e->count--; // still retained elsewhere: GCManager REF_COUNTS semantics
            return;
        }
        size_t slot = e->slot;
        e->key = FJ_MAP_TOMBSTONE; // remove the map entry
        fj_map_used--;
        jl_array_ptr_set(fj_roots, slot, fj_nothing);
        if (fj_free_push(slot) != 0) {
            // Slot is untracked but holds jl_nothing: harmless leak of one slot.
        }
        return;
    }

    // Fallback path (FJ_ROOTS setup failed): call FortranBridge.release_obj(ptr).
    jl_value_t* box_ptr = jl_box_voidpointer(ptr);
    JL_GC_PUSH1(&box_ptr);
    jl_call1(FuncRelease, box_ptr);
    check_julia_exception();
    JL_GC_POP();
}

// Invalidate the module caches. Called from fj_shutdown: the pointer is
// only tombstoned (the object dies with the runtime at jl_atexit_hook(0));
// see the lifecycle note in bridge_internal.h.
void fj_memory_clear_cache(void) {
    fj_nothing = NULL;
}
