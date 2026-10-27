/* kinetics.h -- C entry points of the compiled KineticsAOT chemistry
 * library (examples/06_capstone/2_aot_kinetics; built by build_lib.jl
 * with PackageCompiler create_library). Runtime lifecycle (init_julia /
 * shutdown_julia) comes from the julia.h that create_library ships in
 * the same dist/include directory.
 *
 * Error codes -- no Julia exception ever crosses the C ABI:
 *   kinetics_build:  nspecies (2) on success, -1 on failure
 *   kinetics_step:    0 on success, -1 bad n, -2 solver not built,
 *                     -3 the solver threw
 * A fresh library load starts WITHOUT a solver (an __init__ hook clears
 * the slot the build-time workload filled, so -2 is reachable): call
 * kinetics_build before any kinetics_step.
 *
 * Layout: y is n x 2 column-major (Fortran ybuf(n,2)); the library
 * wraps it zero-copy, exactly like the bridge's fj_wrap_array_2d.
 */
#ifndef KINETICS_H
#define KINETICS_H

#ifdef __cplusplus
extern "C" {
#endif

int kinetics_build(double a, double ea, double rg, double q, double cv);

int kinetics_step(double *y, double *t, double *rho, int n, double dt);

#ifdef __cplusplus
}
#endif

#endif /* KINETICS_H */
