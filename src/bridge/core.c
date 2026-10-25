#include <julia.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/stat.h>
#include "bridge_internal.h"

// C-side GC root set for fj_retain/fj_release (implemented in memory.c)
extern int fj_roots_init(void);
extern void fj_roots_teardown(void);

// Define this only once in the executable/main library
JULIA_DEFINE_FAST_TLS

// Global reference to the FortranBridge module in Julia
jl_module_t* FortranBridgeMod = NULL;
jl_function_t* FuncRetain = NULL;
jl_function_t* FuncRelease = NULL;
jl_function_t* FuncRegister = NULL;
jl_function_t* FuncRegisterStr = NULL;
jl_function_t* FuncGetField = NULL;
jl_function_t* FuncSetField = NULL;
jl_function_t* FuncGetIndex = NULL;
jl_function_t* FuncSetIndex = NULL;
jl_function_t* FuncCallKwargs = NULL;

jl_function_t* FuncGetIndex2D = NULL;
jl_function_t* FuncSetIndex2D = NULL;
jl_function_t* FuncGetIndex3D = NULL;
jl_function_t* FuncSetIndex3D = NULL;
jl_function_t* FuncGetIndexString = NULL;
jl_function_t* FuncSetIndexString = NULL;
jl_function_t* FuncLength = NULL;
jl_function_t* FuncNdims = NULL;
jl_function_t* FuncSize = NULL;
jl_function_t* FuncMakeUnitRange = NULL;

static pthread_t main_thread_id;
static char last_error_msg[2048] = "No error";

// Lifecycle state machine
enum { FJ_UNINIT = 0, FJ_READY = 1, FJ_SHUTDOWN = 2 };
static int fj_state = 0;

// --- Helper Functions ---

void set_error(const char* msg) {
    snprintf(last_error_msg, sizeof(last_error_msg), "%s", msg);
}

const char* fj_get_last_error() {
    return last_error_msg;
}

int fj_ready(void) {
    return fj_state == FJ_READY;
}

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

#ifndef JULIA_BINDIR
#define JULIA_BINDIR NULL
#endif

int check_julia_exception() {
    jl_value_t *ex = jl_exception_occurred();
    if (ex) {
        JL_GC_PUSH1(&ex);
        jl_exception_clear(); // Clear immediately so one exception does not poison later calls

        jl_function_t *sprint = jl_get_function(jl_base_module, "sprint");
        jl_function_t *showerror = jl_get_function(jl_base_module, "showerror");

        if (sprint && showerror) {
            jl_value_t *err_str_val = jl_call2(sprint, showerror, ex);
            if (jl_exception_occurred()) {
                // Formatting itself raised a new exception; clear it too
                jl_exception_clear();
                set_error("Julia Exception Occurred (sprint failed)");
            } else if (err_str_val && jl_is_string(err_str_val)) {
                set_error(jl_string_ptr(err_str_val));
            } else {
                set_error("Julia Exception Occurred (sprint failed)");
            }
        } else {
            fprintf(stderr, "Julia Exception: %s\n", jl_typeof_str(ex));
            set_error("Julia Exception Occurred (sprint/showerror not found)");
        }
        JL_GC_POP();
        return 1; // Exception occurred
    }
    return 0; // No exception
}

// --- Project resolution (fj_init_ex) ---

// Returns 1 if dir exists and contains a Project.toml file.
static int fj_is_project_dir(const char* dir) {
    char buf[4096];
    struct stat st;
    if (dir == NULL || dir[0] == '\0') return 0;
    snprintf(buf, sizeof(buf), "%s/Project.toml", dir);
    return stat(buf, &st) == 0 && S_ISREG(st.st_mode);
}

// Resolve the FortranBridge project directory (must contain Project.toml).
// Probe order when no explicit path is given:
//   1. $JULIA_FJ_PROJECT
//   2. a directory named FortranBridge next to the running executable
//      (resolved via /proc/self/exe)
//   3. $JULIA_PROJECT
// Returns a pointer to a static buffer (valid until the next call), or NULL
// if no candidate validates.
static const char* fj_resolve_project(const char* explicit_path) {
    static char exe_dir_buf[4096];
    static char candidate[4096];
    const char* env;

    if (explicit_path != NULL && explicit_path[0] != '\0') {
        return fj_is_project_dir(explicit_path) ? explicit_path : NULL;
    }

    env = getenv("JULIA_FJ_PROJECT");
    if (fj_is_project_dir(env)) return env;

    ssize_t n = readlink("/proc/self/exe", exe_dir_buf, sizeof(exe_dir_buf) - 1);
    if (n > 0) {
        char* slash;
        exe_dir_buf[n] = '\0';
        slash = strrchr(exe_dir_buf, '/');
        if (slash != NULL) {
            slash[1] = '\0'; /* truncate to directory, keep trailing '/' */
            snprintf(candidate, sizeof(candidate), "%sFortranBridge", exe_dir_buf);
            if (fj_is_project_dir(candidate)) return candidate;
        }
    }

    env = getenv("JULIA_PROJECT");
    if (fj_is_project_dir(env)) return env;

    return NULL;
}

// Make project_dir the active project environment so that
// `using FortranBridge` resolves to the package it contains.
// Returns 0 on success, -1 (with the last error set) on failure.
static int fj_activate_project(const char* project_dir) {
    jl_value_t* dir_str = jl_cstr_to_string(project_dir);
    jl_function_t* set_active_project;
    JL_GC_PUSH1(&dir_str);
    set_active_project = jl_get_function(jl_base_module, "set_active_project");
    if (set_active_project == NULL) {
        JL_GC_POP();
        set_error("Base.set_active_project not found in this Julia build");
        return -1;
    }
    jl_call1(set_active_project, dir_str);
    JL_GC_POP();
    return check_julia_exception() ? -1 : 0;
}

int fj_init_ex(const fj_options_t* opts) {
    static const fj_options_t defaults = { NULL, NULL, 0, 1 };

    if (opts == NULL) opts = &defaults;

    if (fj_state == FJ_READY) return 0; // Already initialized by us
    if (fj_state == FJ_SHUTDOWN) {
        set_error("fj_init_ex: runtime was already shut down; re-initialization is not supported");
        return -1;
    }

    if (opts->project_path != NULL && opts->project_path[0] != '\0' &&
        !fj_is_project_dir(opts->project_path)) {
        set_error("fj_init_ex: project_path is set but contains no Project.toml");
        return -1;
    }

    if (main_thread_id == 0) main_thread_id = pthread_self();

    if (!jl_is_initialized()) {
        // Startup control must happen before jl_init*:
        //  - threads: Julia reads JULIA_NUM_THREADS from the environment at
        //    init time (verified against the embedded 1.12.7 runtime)
        //  - signal handling: Julia installs its handlers during init based
        //    on jl_options.handle_signals; setting it to OFF before init
        //    leaves signal disposition with the embedding process, which MPI
        //    runtimes require. (There is no JULIA_HANDLE_SIGNALS env var, so
        //    jl_options is the only reliable mechanism.)
        if (opts->nthreads > 0) {
            char nthreads_buf[32];
            snprintf(nthreads_buf, sizeof(nthreads_buf), "%d", opts->nthreads);
            setenv("JULIA_NUM_THREADS", nthreads_buf, 1);
        }
        jl_options.handle_signals = (opts->handle_signals != 0)
                                        ? JL_OPTIONS_HANDLE_SIGNALS_ON
                                        : JL_OPTIONS_HANDLE_SIGNALS_OFF;

        if (opts->sysimage_path != NULL) {
            jl_init_with_image_file(JULIA_BINDIR, opts->sysimage_path);
        } else {
            jl_init();
        }
    }

    if (check_julia_exception()) {
        fprintf(stderr, "Error: Julia runtime initialization failed.\nLast Error: %s\n", fj_get_last_error());
        exit(1);
    }

    jl_value_t* mod_check = jl_eval_string("isdefined(Main, :FortranBridge)");
    int is_loaded = (mod_check && jl_unbox_bool(mod_check));

    if (!is_loaded) {
        // Activate the project environment, then load the package.
        const char* project_dir = fj_resolve_project(opts->project_path);
        if (project_dir != NULL && fj_activate_project(project_dir) != 0) {
            fprintf(stderr, "Error: Could not activate FortranBridge project (%s).\nLast Error: %s\n",
                    project_dir, fj_get_last_error());
            exit(1);
        }
        jl_eval_string("using FortranBridge");
    } else {
        // Module already present (e.g. baked into a custom sysimage)
        jl_eval_string("using Main.FortranBridge");
    }

    if (check_julia_exception()) {
        fprintf(stderr, "Error: Julia initialization failed (Loading FortranBridge).\nLast Error: %s\n", fj_get_last_error());
        exit(1);
    }

    jl_value_t* mod_val = jl_eval_string("FortranBridge");
    if (check_julia_exception()) {
        fprintf(stderr, "Error: Julia initialization failed (Getting FortranBridge module).\nLast Error: %s\n", fj_get_last_error());
        exit(1);
    }
    
    if (mod_val && jl_is_module(mod_val)) {
        FortranBridgeMod = (jl_module_t*)mod_val;
        FuncRetain = jl_get_function(FortranBridgeMod, "retain_obj");
        FuncRelease = jl_get_function(FortranBridgeMod, "release_obj");
        FuncRegister = jl_get_function(FortranBridgeMod, "register_f2");
        FuncRegisterStr = jl_get_function(FortranBridgeMod, "register_f2_string");
        FuncGetField = jl_get_function(FortranBridgeMod, "helper_getfield");
        FuncSetField = jl_get_function(FortranBridgeMod, "helper_setfield");
        FuncGetIndex = jl_get_function(FortranBridgeMod, "helper_getindex");
        FuncSetIndex = jl_get_function(FortranBridgeMod, "helper_setindex");
        FuncCallKwargs = jl_get_function(FortranBridgeMod, "helper_call_kwargs");
        
        FuncGetIndex2D = jl_get_function(FortranBridgeMod, "helper_getindex_2d");
        FuncSetIndex2D = jl_get_function(FortranBridgeMod, "helper_setindex_2d");
        FuncGetIndex3D = jl_get_function(FortranBridgeMod, "helper_getindex_3d");
        FuncSetIndex3D = jl_get_function(FortranBridgeMod, "helper_setindex_3d");
        FuncGetIndexString = jl_get_function(FortranBridgeMod, "helper_getindex_string");
        FuncSetIndexString = jl_get_function(FortranBridgeMod, "helper_setindex_string");
        FuncLength = jl_get_function(FortranBridgeMod, "helper_length");
        FuncNdims = jl_get_function(FortranBridgeMod, "helper_ndims");
        FuncSize = jl_get_function(FortranBridgeMod, "helper_size");
        FuncMakeUnitRange = jl_get_function(FortranBridgeMod, "helper_make_unitrange");
        
        if (!FuncRetain || !FuncRelease || !FuncRegister || !FuncRegisterStr ||
            !FuncGetField || !FuncSetField || !FuncGetIndex || !FuncSetIndex || !FuncCallKwargs ||
            !FuncGetIndex2D || !FuncSetIndex2D || !FuncGetIndex3D || !FuncSetIndex3D || 
            !FuncGetIndexString || !FuncSetIndexString ||
            !FuncLength || !FuncNdims || !FuncSize || !FuncMakeUnitRange) {
             fprintf(stderr, "Error: One or more FortranBridge functions could not be loaded.\n");
             exit(1);
        }
    } else {
        fprintf(stderr, "Error: Could not load FortranBridge module.\n");
        exit(1);
    }

    // C-side GC root set for fast fj_retain/fj_release (memory.c). Failure is
    // non-fatal: those calls then use the retain_obj/release_obj fallback path.
    if (fj_roots_init() != 0) {
        fprintf(stderr, "Warning: C-side root set unavailable, falling back to retain_obj/release_obj: %s\n", fj_get_last_error());
    }

    fj_state = FJ_READY;
    return 0;
}

void fj_init(const char* image_path) {
    fj_options_t opts;
    opts.sysimage_path = image_path;
    opts.project_path = NULL;
    opts.nthreads = 0;
    opts.handle_signals = 1;
    fj_init_ex(&opts);
}

void fj_shutdown() {
    fj_state = FJ_SHUTDOWN;

    // Invalidate cached handles so post-shutdown calls hit the fj_ready guard
    FortranBridgeMod = NULL;
    FuncRetain = NULL;
    FuncRelease = NULL;
    FuncRegister = NULL;
    FuncRegisterStr = NULL;
    FuncGetField = NULL;
    FuncSetField = NULL;
    FuncGetIndex = NULL;
    FuncSetIndex = NULL;
    FuncCallKwargs = NULL;

    FuncGetIndex2D = NULL;
    FuncSetIndex2D = NULL;
    FuncGetIndex3D = NULL;
    FuncSetIndex3D = NULL;
    FuncGetIndexString = NULL;
    FuncSetIndexString = NULL;
    FuncLength = NULL;
    FuncNdims = NULL;
    FuncSize = NULL;
    FuncMakeUnitRange = NULL;

    // Drop the C-side root-set bookkeeping (Main.FJ_ROOTS dies with the runtime)
    fj_roots_teardown();

    jl_atexit_hook(0);
}
