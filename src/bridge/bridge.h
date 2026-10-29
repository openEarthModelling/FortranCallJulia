#ifndef FORT_JULIA_BRIDGE_H
#define FORT_JULIA_BRIDGE_H

#include <julia.h>

// Initialize Julia Runtime (historical entry point; thin wrapper over
// fcj_init_ex with: no explicit project, Julia default threads, and
// handle_signals pinned to 1 -- Julia's signal handlers stay in place,
// matching the historical behavior). If fcj_init_ex fails, the last error is
// printed to stderr and the process exits(1); fcj_init has no return value
// to report through.
void fcj_init(const char* image_path);

// Startup options for fcj_init_ex.
//   sysimage_path  : Julia sysimage file to load (NULL = default sysimage).
//   project_path   : directory containing the FortranBridge package's
//                    Project.toml (NULL = probe chain, see fcj_init_ex).
//   nthreads       : if > 0, the runtime is started with this many threads
//                    (JULIA_NUM_THREADS is set before init); 0 = Julia default.
//   handle_signals : signal-disposition control. jl_options.handle_signals
//                    is NEVER touched by the bridge (always left at its
//                    default ON: Julia needs its SIGSEGV handler for GC
//                    safepoint polling; turning it OFF crashes the embedded
//                    runtime). Instead:
//                    0 = "no takeover" (the DEFAULT): after a successful
//                        Julia init, SIGINT and SIGTERM are reset to SIG_DFL
//                        via signal(), so Julia no longer intercepts
//                        interactive termination (MPI-friendly);
//                        GC-critical handlers (SIGSEGV/SIGBUS/SIGFPE) stay
//                        intact.
//                    nonzero = leave everything at Julia's post-init
//                        defaults (historical fcj_init behavior).
typedef struct fcj_options {
    const char* sysimage_path;
    const char* project_path;
    int nthreads;
    int handle_signals;
} fcj_options_t;

// Initialize the Julia runtime with explicit startup control.
// Returns 0 on success. On EVERY failure path -- Julia init failure, project
// activation failure, FortranBridge package load failure, missing registry
// symbols, invalid arguments -- it returns nonzero with fcj_get_last_error()
// set; the process is never aborted.
// The options are consumed as follows:
//   - nthreads and handle_signals take effect only when this call performs
//     the Julia initialization itself (they are applied before jl_init /
//     jl_init_with_image_file).
//   - project_path (or its probe chain) is activated after init via
//     Base.set_active_project, then the FortranBridge package is loaded
//     with `using FortranBridge`.
// Probe order when project_path == NULL:
//   1. $JULIA_FJ_PROJECT (must contain Project.toml)
//   2. a directory named FortranBridge containing Project.toml next to the
//      running executable (resolved via /proc/self/exe)
//   3. $JULIA_PROJECT (must contain Project.toml)
// A NULL opts pointer is equivalent to the defaults {NULL, NULL, 0, 0}
// (no explicit project/sysimage, Julia default threads, no signal
// takeover -- safe only because of the post-init signal reset).
int fcj_init_ex(const fcj_options_t* opts);

// Shutdown Julia Runtime. Must be called from the thread that owns the
// runtime (the bridge's single-thread contract, like every bridge call):
// while the runtime is live or still initializing, a call from any other
// thread is refused with fcj_get_last_error() set instead of racing the
// shutdown state changes. Shutting down a runtime whose initialization was
// never attempted still runs, and leaves the lifecycle state at SHUTDOWN
// (a later fcj_init_ex is refused, as after any shutdown); Julia itself is
// untouched (its atexit hook no-ops when the runtime never initialized).
void fcj_shutdown();

// --- Environment ---
// Absolute directory of the running executable (no trailing slash),
// resolved via /proc/self/exe. Written into buf (bufsize bytes including
// the terminator); returns buf, or NULL if the platform cannot resolve it
// or buf is too small. Use it to locate data files shipped next to the
// binary -- the Fortran SDK's julia_include_exe_relative is built on it.
char* fcj_get_executable_dir(char* buf, size_t bufsize);

// --- Object Management (High-Level API) ---

// Retain a Julia object (prevent GC). Returns a raw pointer that can be stored in Fortran.
void* fcj_retain(jl_value_t* val);

// Release a Julia object (allow GC).
void fcj_release(void* ptr);


// --- Generic Call Interface (High-Level API) ---

jl_value_t* fcj_call0(const char* func_name);
jl_value_t* fcj_call1_float64(const char* func_name, double arg1);
jl_value_t* fcj_call1_obj(const char* func_name, void* arg_obj);
jl_value_t* fcj_call2_obj_double(const char* func_name, void* arg_obj, double arg2);
// Evaluate Julia source. The redefinition-sensitive name caches are
// invalidated on every call (both outcome paths -- top-level expressions
// commit as they evaluate, so a throwing eval can still have rebound
// names), so name-based calls made after the eval observe the current
// definitions. See fcj_clear_function_cache for which rebinding paths this
// covers.
jl_value_t* fcj_eval_string(const char* cmd);

// Call a Julia function with N arguments
jl_value_t* fcj_call_general(const char* func_name, void** args, int32_t nargs);

// --- Function Handle API (cached name -> function resolution) ---

// Resolve a function by name using the internal function-name cache.
// Returns an OWNED handle (rooted via fcj_retain, independent of the name
// cache), or NULL (with the last error set) on failure. The handle stays
// valid across evals and cache invalidations; balance it with fcj_release.
// The Fortran SDK exposes this as julia_function; its finalizer releases.
void* fcj_resolve_function(const char* func_name);

// Call a function handle obtained from fcj_resolve_function.
// Handles nargs == 0 with a possibly NULL args pointer.
jl_value_t* fcj_call_function(void* func_handle, void** args, int32_t nargs);

// Drop the redefinition-sensitive name caches: the C-side function-name
// cache (freeing keys, releasing GC roots) and -- when the loaded
// FortranBridge provides clear_kw_cache! (a stale sysimage may not; then
// the kwargs cache keeps the previous behavior) -- the Julia-side kwargs
// cache. Wired into fcj_shutdown (called first, while the runtime can still honor
// fcj_release) and into fcj_eval_string (both outcome paths). Covers
// rebinding through eval and include-reached-through-eval, the paths the
// bridge intercepts; rebinding by other means (set_field/setproperty! on a
// module, calling include() or a reload() helper BY NAME) is not observed
// automatically -- call this after such operations. The Fortran SDK
// exposes it as julia_clear_function_cache.
void fcj_clear_function_cache(void);

// True when the handle refers to a Julia Function object (used by the SDK to
// route %call on function objects through the call_value path).
int fcj_is_function(void* handle);

// Call with Keyword Arguments
jl_value_t* fcj_call_kwargs(const char* func_name, void** args, int32_t nargs, 
                           const char** kw_keys, void** kw_vals, int32_t nkw);


// --- Fast Path (Low-Level API) ---
//
// register_f2_string: returns a raw @cfunction pointer for direct calls at
// native speed. The registry keeps the CFunction object alive (rooted in
// Main), so GC lifetime is safe; the CONTRACT has hard edges, and misuse
// crashes the process with no Julia-side diagnostic:
//   1. The trampoline captures the function OBJECT resolved at
//      registration, not a frozen method: an ordinary same-name method
//      redefinition IS observed through old pointers, but rebinding the
//      name to a new object (e.g. a closure) leaves old pointers calling
//      the captured object -- register after the final definition or
//      rebinding.
//   2. Re-registering a name invalidates earlier pointers for that name
//      (the previous CFunction becomes collectable, its code may be
//      freed) -- discard previously obtained pointers.
//   3. The called function must not throw: an exception unwinds through
//      the C trampoline frame -- undefined behavior, typically a segfault.
//      Handle errors inside Julia or return a sentinel value.
//   4. ret_type/arg_types must exactly match the method signature
//      (bitstypes only); nothing is validated at registration.
//   5. The pointer is invalid after fcj_shutdown (one runtime per process).
void* fcj_get_function_pointer(const char* func_name, const char* ret_type, const char* arg_types);

// --- Callback Bridge (Fortran RHS -> Julia callable) ---

// Wrap a Fortran bind(c) RHS subroutine pointer into a Julia callable
// f(du, u, p, t):
//   fnptr : pointer to the Fortran RHS
//             subroutine rhs(ctx, n, u, du, t, err) bind(c)
//           with ctx = type(c_ptr), value; n = integer(kind=c_int64_t),
//           value; u and du = type(c_ptr), value (raw Float64 element
//           pointers into Julia heap memory, zero-copy, n elements each);
//           t = real(kind=c_double), value; err = integer(kind=c_int),
//           intent(out). err /= 0 makes the Julia side throw.
//   ctx   : opaque user context passed through to every RHS invocation
//           (may be NULL).
// The callable ignores p. As a side effect the SAME closure object that the
// returned handle points at is bound to Main.FJ_CALLBACK (latest created
// wins), so eval-ed solver code can reach it by name.
// Returns an opaque handle -- already routed through the fcj_retain root
// set, release with fcj_release -- or NULL with fcj_get_last_error() set on
// failure.
void* fcj_create_callback(void* fnptr, void* ctx);

// --- Extraction (Julia object -> Fortran memory) ---

// Copy the elements of an Array{Float64} or Array{ComplexF64} (any rank,
// dense/contiguous) into dest, interpreted as double / double-complex of
// size n. Returns 0 on success; -1 with fcj_get_last_error() set if handle
// is not such an array or n != length(handle).
int fcj_to_fortran(void* handle, void* dest, long long n);

// 1-based linear array indexing. Returns a RETAINED handle for the boxed
// element (release with fcj_release), or NULL with fcj_get_last_error() set
// if handle is not an array or idx is out of bounds.
void* fcj_get_element(void* handle, long long idx);

// getproperty(handle, name). Returns a RETAINED handle (release with
// fcj_release), or NULL with fcj_get_last_error() set on failure.
void* fcj_get_property(void* handle, const char* name);

// --- Error Handling ---
const char* fcj_get_last_error();

// Returns 1 if the runtime is initialized and ready, 0 otherwise
int fcj_ready(void);

// --- Boxing (C primitive -> Julia Object) ---
void* fcj_box_float64(double val);
void* fcj_box_int32(int val);
void* fcj_box_int64(long long val);
void* fcj_box_bool(int val); // 0 or 1
void* fcj_box_string(const char* val);
void* fcj_box_complex(double re, double im);

// --- Unboxing (Julia Object -> C primitive) ---
double fcj_unbox_float64(void* obj);
long long fcj_unbox_int64(void* obj);
int fcj_unbox_int32(void* obj);
int fcj_unbox_bool(void* obj);
const char* fcj_unbox_string(void* obj);
double fcj_unbox_complex_real(void* obj);
double fcj_unbox_complex_imag(void* obj);

// --- Arrays (rank-generic: any rank 1..16) ---
// Wrap Fortran-owned contiguous Float64 memory as a zero-copy Julia
// Array{Float64,ndim} (column-major on both sides, dims in Fortran order).
// data points at the first element; dims holds ndim extents in Fortran
// dimension order. No copy is made: the Julia array aliases caller memory,
// which must outlive every use of the wrapper and must not be reallocated.
// Returns a raw (unrooted) handle for the bridge root set (fcj_retain), or
// NULL with fcj_get_last_error() set on failure.
void* fcj_wrap_array(void* data, long ndim, const long* dims);

// Deep-copy variant: allocates a fresh GC-managed Array{Float64,ndim} with
// the given extents and memcpy's total elements from data. The extent
// product is overflow-checked before allocation. Same error contract as
// fcj_wrap_array.
void* fcj_copy_array(void* data, long ndim, const long* dims);

// --- Accessors (Field & Index) ---
void* fcj_get_field(void* obj, const char* name);
void fcj_set_field(void* obj, const char* name, void* val);
void* fcj_get_index_i(void* obj, long long idx);
void fcj_set_index_i(void* obj, long long idx, void* val);

// --- Extended Accessors ---
void* fcj_get_index_ii(void* obj, long long i, long long j);
void fcj_set_index_ii(void* obj, long long i, long long j, void* val);
void* fcj_get_index_iii(void* obj, long long i, long long j, long long k);
void fcj_set_index_iii(void* obj, long long i, long long j, long long k, void* val);
void* fcj_get_index_s(void* obj, const char* key);
void fcj_set_index_s(void* obj, const char* key, void* val);

// --- Introspection ---
long long fcj_length(void* obj);
long long fcj_ndims(void* obj);
long long fcj_size(void* obj, int dim);
void* fcj_make_unitrange(long long start, long long stop);

#endif // BRIDGE_H