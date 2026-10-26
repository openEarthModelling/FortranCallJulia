module KineticsAOT

# AOT (ahead-of-time compiled library) entry points for the capstone
# chemistry kernel: the same FjKinetics batched step the Fortran driver
# reaches through the bridge, exposed as Base.@ccallable C functions and
# baked into a standalone shared library by PackageCompiler create_library
# (MyLib precedent, examples/03_deployment/2_compiled_library).
#
# The comparison the perf report makes (examples/06_capstone, commit 7):
#   JIT      embedded runtime, package caches          (bridge eval path)
#   sysimage embedded runtime, image                   (bridge eval path)
#   AOT      standalone library, @ccallable entry      (this module)
#   Julia    native driver, no boundary at all         (reference)
# All four run the identical FjKinetics.step_chemistry! kernel.

using FjKinetics

const KS = Ref{FjKinetics.KineticsSolver}()

# Build the solver; returns nspecies (2) so callers can sanity-check the
# mechanism exactly like the bridge driver does.
Base.@ccallable function kinetics_build(a::Cdouble, ea::Cdouble, rg::Cdouble,
                                        q::Cdouble, cv::Cdouble)::Cint
    KS[] = FjKinetics.build_kinetics(A = a, Ea = ea, R_g = rg, q = q, cv = cv)
    return Int32(FjKinetics.nspecies(KS[]))
end

# One batched Strang half-step over n cells. y is the Fortran ybuf(n,2)
# in column-major order -- unsafe_wrap sees the same layout the bridge's
# zero-copy wrap produces, so this is the identical data path. n is a
# Cint on the wire; unsafe_wrap requires NTuple{N,Int} dims, so convert
# once up front.
Base.@ccallable function kinetics_step(y_ptr::Ptr{Cdouble}, t_ptr::Ptr{Cdouble},
                                       rho_ptr::Ptr{Cdouble}, n::Cint,
                                       dt::Cdouble)::Cint
    n >= 0 || return Int32(-1)
    nc = Int(n)
    y = unsafe_wrap(Matrix{Cdouble}, y_ptr, (nc, 2); own = false)
    t = unsafe_wrap(Vector{Cdouble}, t_ptr, nc; own = false)
    rho = unsafe_wrap(Vector{Cdouble}, rho_ptr, nc; own = false)
    FjKinetics.step_chemistry!(KS[], y, t, rho, dt)
    return Int32(0)
end

end # module KineticsAOT
