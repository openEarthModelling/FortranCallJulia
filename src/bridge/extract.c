#include "bridge_internal.h"
#include <stdio.h>
#include <string.h>

// --- Extraction (Julia object -> Fortran memory) ---
//
// fcj_to_fortran / fcj_get_element / fcj_get_property.
//
// GC hazards honored here:
//  - a C static is NOT a GC root: cached function bindings are routed
//    through fcj_retain before the statics can reach them (dispatch.c
//    pattern); the cached ComplexF64 datatype is an immortal Base-bound
//    singleton, safe as a plain static (types.c pattern);
//  - every handle returned to the caller goes through fcj_retain.
//
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
//
// Kept self-contained: per-file statics, lazy resolution on first use
// (safe: all bridge calls run on the init thread, see check_thread).
static jl_datatype_t* complex_f64_type = NULL;
static jl_function_t* FuncGetProperty = NULL; // Base.getproperty
static jl_function_t* FuncGetElement = NULL;  // Base.getindex (linear)

// Cached ComplexF64 type object (immortal; kept alive by its Base binding).
static jl_datatype_t* fcj_complex_f64_type(void) {
    if (!complex_f64_type) {
        jl_value_t* t = jl_eval_string("ComplexF64");
        if (check_julia_exception()) return NULL;
        if (t && jl_is_datatype(t)) complex_f64_type = (jl_datatype_t*)t;
    }
    return complex_f64_type;
}

// Resolve + retain a Base binding once, caching it in *slot. Returns the
// retained function, or NULL (with the last error set) on failure.
static jl_function_t* fcj_resolve_base_binding(jl_function_t** slot, const char* name, const char* api) {
    if (*slot) return *slot;
    jl_function_t* f = jl_get_function(jl_base_module, name);
    if (!f) {
        char err[128];
        snprintf(err, sizeof(err), "%s: Base.%s not found", api, name);
        set_error(err);
        return NULL;
    }
    void* rooted = fcj_retain((jl_value_t*)f); // a C static is not a GC root
    if (!rooted) return NULL;
    *slot = (jl_function_t*)rooted;
    return *slot;
}

// numel == product of dims (== Julia length(A) for any rank). Computed from
// the dims rather than jl_array_maxsize, which reports the backing Memory
// length and can overshoot for reshaped arrays.
static long long fcj_array_numel(jl_array_t* a) {
    int rank = jl_array_rank((jl_value_t*)a);
    long long n = 1;
    for (int d = 0; d < rank; d++) n *= (long long)jl_array_dim(a, d);
    return n;
}

// Shared checks: handle must be an any-rank Array{Float64}/Array{ComplexF64}.
// On success returns the array and sets *elem_size; NULL (error set) otherwise.
static jl_array_t* fcj_extract_check_array(void* handle, const char* api, size_t* elem_size) {
    jl_value_t* v = (jl_value_t*)handle;
    if (!jl_is_array(v)) {
        char err[128];
        snprintf(err, sizeof(err), "%s: handle is not an Array", api);
        set_error(err);
        return NULL;
    }
    // Any-rank element-type check by identity against immortal type objects
    // (per-rank jl_apply_array_type caches cannot cover "any rank"; for a
    // concrete Array, jl_typeof returns the Array{T,N} type object, so
    // jl_tparam0 yields exactly T).
    jl_value_t* elty = jl_tparam0((jl_datatype_t*)jl_typeof(v));
    if (elty == (jl_value_t*)jl_float64_type) {
        *elem_size = sizeof(double);
    } else {
        jl_datatype_t* cf = fcj_complex_f64_type();
        if (!cf || elty != (jl_value_t*)cf) {
            char err[160];
            snprintf(err, sizeof(err), "%s: handle is not Array{Float64} or Array{ComplexF64}", api);
            set_error(err);
            return NULL;
        }
        *elem_size = 2 * sizeof(double);
    }
    return (jl_array_t*)v;
}

int fcj_to_fortran(void* handle, void* dest, long long n) {
    if (!fcj_ready()) { set_error("Julia runtime not initialized or already shut down"); return -1; }
    if (!check_thread()) return -1;
    if (!handle) { set_error("fcj_to_fortran: NULL handle"); return -1; }
    if (!dest) { set_error("fcj_to_fortran: NULL destination buffer"); return -1; }
    if (n < 0) { set_error("fcj_to_fortran: negative n"); return -1; }

    jl_value_t* v = (jl_value_t*)handle;
    JL_GC_PUSH1(&v);

    size_t elem_size = 0;
    jl_array_t* a = fcj_extract_check_array(handle, "fcj_to_fortran", &elem_size);
    if (!a) { JL_GC_POP(); return -1; }

    long long len = fcj_array_numel(a);
    if (n != len) {
        char err[192];
        snprintf(err, sizeof(err), "fcj_to_fortran: n (%lld) does not match array length (%lld)", n, len);
        set_error(err);
        JL_GC_POP();
        return -1;
    }

    // Dense/contiguous Float64/ComplexF64 arrays keep their elements raw at
    // jl_array_data_ (the same backing the accessors.c fast path indexes).
    memcpy(dest, jl_array_data_(a), (size_t)n * elem_size);
    JL_GC_POP();
    return 0;
}

void* fcj_get_element(void* handle, long long idx) {
    if (!fcj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    if (!handle) { set_error("fcj_get_element: NULL handle"); return NULL; }

    jl_value_t* v = (jl_value_t*)handle;
    jl_value_t* v_idx = NULL;
    jl_value_t* elem = NULL;
    JL_GC_PUSH3(&v, &v_idx, &elem);

    if (!jl_is_array(v)) { set_error("fcj_get_element: handle is not an Array"); JL_GC_POP(); return NULL; }
    long long len = fcj_array_numel((jl_array_t*)v);
    if (idx < 1 || idx > len) {
        char err[192];
        snprintf(err, sizeof(err), "fcj_get_element: index (%lld) out of bounds for array of length %lld", idx, len);
        set_error(err);
        JL_GC_POP();
        return NULL;
    }

    jl_function_t* getindex = fcj_resolve_base_binding(&FuncGetElement, "getindex", "fcj_get_element");
    if (!getindex) { JL_GC_POP(); return NULL; }

    v_idx = jl_box_int64(idx);
    elem = jl_call2(getindex, v, v_idx); // boxes numerics, like jl_arrayref did
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }

    void* out = fcj_retain(elem); // root before the result becomes reachable from C
    JL_GC_POP();
    return out;
}

void* fcj_get_property(void* handle, const char* name) {
    if (!fcj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    if (!handle) { set_error("fcj_get_property: NULL handle"); return NULL; }
    if (!name) { set_error("fcj_get_property: NULL name"); return NULL; }

    jl_function_t* getproperty = fcj_resolve_base_binding(&FuncGetProperty, "getproperty", "fcj_get_property");
    if (!getproperty) return NULL;

    jl_value_t* v = (jl_value_t*)handle;
    jl_value_t* v_name = NULL;
    jl_value_t* prop = NULL;
    JL_GC_PUSH3(&v, &v_name, &prop);

    v_name = (jl_value_t*)jl_symbol(name); // getproperty dispatches on Symbol
    prop = jl_call2(getproperty, v, v_name);
    if (check_julia_exception()) { JL_GC_POP(); return NULL; }

    void* out = fcj_retain(prop); // root before the result becomes reachable from C
    JL_GC_POP();
    return out;
}

// Invalidate the module caches. Called from fcj_shutdown: the pointers are
// only tombstoned (the objects die with the runtime at jl_atexit_hook(0));
// see the lifecycle note in bridge_internal.h.
void fcj_extract_clear_cache(void) {
    complex_f64_type = NULL;
    FuncGetProperty = NULL;
    FuncGetElement = NULL;
}
