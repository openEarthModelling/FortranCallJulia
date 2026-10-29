#include "bridge_internal.h"
#include <string.h>

// --- Cached type objects / Base bindings (lazy init) ---
// These are immortal: jl_apply_array_type for a concrete element type returns
// a cache-owned instance that lives for the whole session, and the "tuple"
// binding in Base is immortal once fetched. Safe to hold as C statics without
// GC rooting; do NOT push them on the GC stack. Lazy init is safe because all
// bridge calls run on the init thread (see check_thread). Kept per-file on
// purpose (accessors.c keeps its own small statics).
//
// The old per-rank statics (arr_f64_1d/2d/3d) became this ndim-indexed table
// when the _1d/_2d/_3d entry points collapsed into the rank-generic
// fcj_wrap_array / fcj_copy_array. FCJ_MAX_NDIM is a soft cap: Julia supports
// Array{T,N} for any N, but ranks > 16 are exotic, and a fixed table keeps the
// cache a plain static array (no allocation, no invalidation bookkeeping).
#define FCJ_MAX_NDIM 16
static jl_value_t *arr_f64_by_nd[FCJ_MAX_NDIM]; // [ndim-1], zero-initialized
static jl_function_t *tuple_func = NULL;

// Resolve (or lazily create) the Array{Float64,ndim} type object. Returns
// NULL with the last error set when ndim is out of [1, FCJ_MAX_NDIM] or the
// type application threw.
static jl_value_t *array_type_for_ndim(long ndim, const char *who) {
    if (ndim < 1 || ndim > FCJ_MAX_NDIM) {
        char buf[160];
        snprintf(buf, sizeof(buf),
                 "%s: ndim %ld out of range [1, %d]", who, ndim, FCJ_MAX_NDIM);
        set_error(buf);
        return NULL;
    }
    if (!arr_f64_by_nd[ndim - 1])
        arr_f64_by_nd[ndim - 1] =
            jl_apply_array_type((jl_value_t*)jl_float64_type, (size_t)ndim);
    return arr_f64_by_nd[ndim - 1];
}

// Build the (d1, ..., dN) dims tuple for jl_ptr_to_array via Base.tuple.
// jl_call is the same public apply machinery jl_call2/jl_call3 sit on top of,
// so the generic path costs the same per call as the old per-rank entry
// points; the only per-call work added by N-D generality is ndim jl_box_long
// calls the caller used to spell out as arguments anyway. Every step that can
// fail or throw is checked immediately: passing a NULL or stale dims value
// into jl_ptr_to_array crashes inside Julia with no bridge-level diagnostic.
// check_julia_exception() runs BEFORE the NULL checks so the detailed
// exception text is not overwritten by the generic message.
//
// JL_GC_PUSHARGS assigns its argument, so `args` must be a pointer VARIABLE;
// the macro allocates and zeroes the frame slots itself.
static jl_value_t *make_dims_tuple(long ndim, const long *dims, const char *who) {
    jl_value_t **args;
    JL_GC_PUSHARGS(args, (int)ndim);

    if (!tuple_func) tuple_func = jl_get_function(jl_base_module, "tuple");
    if (tuple_func == NULL) {
        char buf[128];
        snprintf(buf, sizeof(buf), "%s: Base.tuple binding not found", who);
        set_error(buf);
        JL_GC_POP();
        return NULL;
    }
    for (long i = 0; i < ndim; i++) {
        args[i] = jl_box_long(dims[i]);
        if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    }

    jl_value_t *dims_tuple = jl_call(tuple_func, args, (uint32_t)ndim);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    if (dims_tuple == NULL) {
        char buf[160];
        snprintf(buf, sizeof(buf),
                 "%s: Base.tuple returned NULL without an exception", who);
        set_error(buf);
        JL_GC_POP();
        return NULL;
    }
    JL_GC_POP();
    return dims_tuple;
}

// Reject non-positive dimensions up front: a zero or negative extent would
// otherwise surface as a Julia-side throw (empty array) or a bogus memcpy
// size, far from the caller's mistake.
static int check_dims_positive(long ndim, const long *dims, const char *who) {
    for (long i = 0; i < ndim; i++) {
        if (dims[i] <= 0) {
            char buf[160];
            snprintf(buf, sizeof(buf),
                     "%s: dimension %ld is %ld, must be positive",
                     who, i + 1, dims[i]);
            set_error(buf);
            return 0;
        }
    }
    return 1;
}

// --- Array Wrapper (Zero-Copy, any rank 1..FCJ_MAX_NDIM) ---

void* fcj_wrap_array(void* data, long ndim, const long* dims) {
    if (!fcj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_value_t *array_type = NULL;
    jl_value_t *dims_tuple = NULL;
    JL_GC_PUSH2(&array_type, &dims_tuple);

    array_type = array_type_for_ndim(ndim, "fcj_wrap_array");
    if (array_type == NULL) { JL_GC_POP(); return NULL; }
    if (!check_dims_positive(ndim, dims, "fcj_wrap_array")) { JL_GC_POP(); return NULL; }
    dims_tuple = make_dims_tuple(ndim, dims, "fcj_wrap_array");
    if (dims_tuple == NULL) { JL_GC_POP(); return NULL; }

    jl_array_t *arr = jl_ptr_to_array(array_type, data, dims_tuple, 0);

    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return (void*)arr;
}

// --- Array Deep Copy (Alloc + Memcpy, any rank 1..FCJ_MAX_NDIM) ---
//
// Allocates with jl_alloc_array_nd -- the public N-D constructor the old
// jl_alloc_array_{1,2,3}d specializations parallel, taking plain C extents so
// no dims tuple is needed on this path -- then copies the full extent. The
// element-count product is overflow-checked against SIZE_MAX / sizeof(double)
// BEFORE any allocation or memcpy: with caller-supplied extents, a product
// that wraps the address space would otherwise allocate a small array and
// memcpy gigabytes past its end.
void* fcj_copy_array(void* data, long ndim, const long* dims) {
    if (!fcj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;

    // Range-check ndim BEFORE any loop writes dims_sz[0..ndim-1]: a caller
    // passing ndim > FCJ_MAX_NDIM would otherwise smash the stack array.
    jl_value_t *array_type = NULL;
    JL_GC_PUSH1(&array_type);
    array_type = array_type_for_ndim(ndim, "fcj_copy_array");
    if (array_type == NULL) { JL_GC_POP(); return NULL; }

    unsigned long long total = 1;
    size_t dims_sz[FCJ_MAX_NDIM];
    for (long i = 0; i < ndim; i++) {
        if (dims[i] <= 0) {
            char buf[160];
            snprintf(buf, sizeof(buf),
                     "fcj_copy_array: dimension %ld is %ld, must be positive",
                     i + 1, dims[i]);
            set_error(buf);
            JL_GC_POP();
            return NULL;
        }
        if ((unsigned long long)dims[i] >
            (unsigned long long)-1 / sizeof(double) / total) {
            char buf[160];
            snprintf(buf, sizeof(buf),
                     "fcj_copy_array: extent product overflows (%ld at dim %ld)",
                     dims[i], i + 1);
            set_error(buf);
            JL_GC_POP();
            return NULL;
        }
        total *= (unsigned long long)dims[i];
        dims_sz[i] = (size_t)dims[i];
    }

    jl_array_t *arr = jl_alloc_array_nd(array_type, dims_sz, (size_t)ndim);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }

    double* raw_data = (double*)jl_array_data(arr, double);
    memcpy(raw_data, data, (size_t)total * sizeof(double));

    JL_GC_POP();
    return (void*)arr;
}

// Invalidate the module caches. Called from fcj_shutdown: the pointers are
// only tombstoned (the objects die with the runtime at jl_atexit_hook(0));
// see the lifecycle note in bridge_internal.h.
void fcj_arrays_clear_cache(void) {
    for (int i = 0; i < FCJ_MAX_NDIM; i++)
        arr_f64_by_nd[i] = NULL;
    tuple_func = NULL;
}
