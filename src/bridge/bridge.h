#ifndef FORT_JULIA_BRIDGE_H
#define FORT_JULIA_BRIDGE_H

#include <julia.h>

// Initialize Julia Runtime (historical entry point; thin wrapper over
// fj_init_ex with: no explicit project, Julia default threads, and
// handle_signals pinned to 1 -- Julia's signal handlers stay in place,
// matching the historical behavior). If fj_init_ex fails, the last error is
// printed to stderr and the process exits(1); fj_init has no return value
// to report through.
void fj_init(const char* image_path);

// Startup options for fj_init_ex.
//   sysimage_path  : Julia sysimage file to load (NULL = default sysimage).
//   project_path   : directory containing the FortranBridge package's
//                    Project.toml (NULL = probe chain, see fj_init_ex).
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
//                        defaults (historical fj_init behavior).
typedef struct fj_options {
    const char* sysimage_path;
    const char* project_path;
    int nthreads;
    int handle_signals;
} fj_options_t;

// Initialize the Julia runtime with explicit startup control.
// Returns 0 on success. On EVERY failure path -- Julia init failure, project
// activation failure, FortranBridge package load failure, missing registry
// symbols, invalid arguments -- it returns nonzero with fj_get_last_error()
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
int fj_init_ex(const fj_options_t* opts);

// Shutdown Julia Runtime. Must be called from the thread that initialized
// the runtime (the bridge's single-thread contract, like every bridge
// call): while the runtime is live, a call from any other thread is
// refused with fj_get_last_error() set instead of racing the shutdown
// state changes. Shutting down a never-initialized runtime is a benign
// no-op (it only runs Julia's atexit hook).
void fj_shutdown();

// --- Environment ---
// Absolute directory of the running executable (no trailing slash),
// resolved via /proc/self/exe. Written into buf (bufsize bytes including
// the terminator); returns buf, or NULL if the platform cannot resolve it
// or buf is too small. Use it to locate data files shipped next to the
// binary -- the Fortran SDK's julia_include_exe_relative is built on it.
char* fj_get_executable_dir(char* buf, size_t bufsize);

// --- Object Management (High-Level API) ---

// Retain a Julia object (prevent GC). Returns a raw pointer that can be stored in Fortran.
void* fj_retain(jl_value_t* val);

// Release a Julia object (allow GC).
void fj_release(void* ptr);


// --- Generic Call Interface (High-Level API) ---

jl_value_t* fj_call0(const char* func_name);
jl_value_t* fj_call1_float64(const char* func_name, double arg1);
jl_value_t* fj_call1_obj(const char* func_name, void* arg_obj);
jl_value_t* fj_call2_obj_double(const char* func_name, void* arg_obj, double arg2);
jl_value_t* fj_eval_string(const char* cmd);

// Call a Julia function with N arguments
jl_value_t* fj_call_general(const char* func_name, void** args, int32_t nargs);

// --- Function Handle API (cached name -> function resolution) ---

// Resolve a function by name using the internal function-name cache.
// Returns an opaque handle, or NULL (with the last error set) on failure.
// The handle stays valid only while the cache holds it (the cache entry is
// its GC root), i.e. until fj_clear_function_cache() is called.
void* fj_resolve_function(const char* func_name);

// Call a function handle obtained from fj_resolve_function.
// Handles nargs == 0 with a possibly NULL args pointer.
jl_value_t* fj_call_function(void* func_handle, void** args, int32_t nargs);

// Free the C-side function-name cache, releasing the GC root of each entry.
// Wired into fj_shutdown (called first, while the runtime can still honor
// fj_release); calling it manually remains valid at any time.
void fj_clear_function_cache(void);

// True when the handle refers to a Julia Function object (used by the SDK to
// route %call on function objects through the call_value path).
int fj_is_function(void* handle);

// Call with Keyword Arguments
jl_value_t* fj_call_kwargs(const char* func_name, void** args, int32_t nargs, 
                           const char** kw_keys, void** kw_vals, int32_t nkw);


// --- Fast Path (Low-Level API) ---
void* fj_get_function_pointer(const char* func_name, const char* ret_type, const char* arg_types);

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
// Returns an opaque handle -- already routed through the fj_retain root
// set, release with fj_release -- or NULL with fj_get_last_error() set on
// failure.
void* fj_create_callback(void* fnptr, void* ctx);

// --- Extraction (Julia object -> Fortran memory) ---

// Copy the elements of an Array{Float64} or Array{ComplexF64} (any rank,
// dense/contiguous) into dest, interpreted as double / double-complex of
// size n. Returns 0 on success; -1 with fj_get_last_error() set if handle
// is not such an array or n != length(handle).
int fj_to_fortran(void* handle, void* dest, long long n);

// 1-based linear array indexing. Returns a RETAINED handle for the boxed
// element (release with fj_release), or NULL with fj_get_last_error() set
// if handle is not an array or idx is out of bounds.
void* fj_get_element(void* handle, long long idx);

// getproperty(handle, name). Returns a RETAINED handle (release with
// fj_release), or NULL with fj_get_last_error() set on failure.
void* fj_get_property(void* handle, const char* name);

// --- Error Handling ---
const char* fj_get_last_error();

// Returns 1 if the runtime is initialized and ready, 0 otherwise
int fj_ready(void);

// --- Boxing (C primitive -> Julia Object) ---
void* fj_box_float64(double val);
void* fj_box_int32(int val);
void* fj_box_int64(long long val);
void* fj_box_bool(int val); // 0 or 1
void* fj_box_string(const char* val);
void* fj_box_complex(double re, double im);

// --- Unboxing (Julia Object -> C primitive) ---
double fj_unbox_float64(void* obj);
long long fj_unbox_int64(void* obj);
int fj_unbox_int32(void* obj);
int fj_unbox_bool(void* obj);
const char* fj_unbox_string(void* obj);
double fj_unbox_complex_real(void* obj);
double fj_unbox_complex_imag(void* obj);

// --- Arrays ---
void* fj_wrap_array_1d(void* data, long dim1);
void* fj_wrap_array_2d(void* data, long dim1, long dim2);
void* fj_wrap_array_3d(void* data, long dim1, long dim2, long dim3);

// --- Array Deep Copies (Alloc + Memcpy) ---
void* fj_copy_array_1d(void* data, long dim1);
void* fj_copy_array_2d(void* data, long dim1, long dim2);
void* fj_copy_array_3d(void* data, long dim1, long dim2, long dim3);

// --- Accessors (Field & Index) ---
void* fj_get_field(void* obj, const char* name);
void fj_set_field(void* obj, const char* name, void* val);
void* fj_get_index_i(void* obj, long long idx);
void fj_set_index_i(void* obj, long long idx, void* val);

// --- Extended Accessors ---
void* fj_get_index_ii(void* obj, long long i, long long j);
void fj_set_index_ii(void* obj, long long i, long long j, void* val);
void* fj_get_index_iii(void* obj, long long i, long long j, long long k);
void fj_set_index_iii(void* obj, long long i, long long j, long long k, void* val);
void* fj_get_index_s(void* obj, const char* key);
void fj_set_index_s(void* obj, const char* key, void* val);

// --- Introspection ---
long long fj_length(void* obj);
long long fj_ndims(void* obj);
long long fj_size(void* obj, int dim);
void* fj_make_unitrange(long long start, long long stop);

#endif // BRIDGE_H