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

# Solver slot: a 0/1-element vector, not a Ref -- a Ref cannot be
# un-assigned, and the precompile workload leaves a solver behind when
# the image closes. __init__ runs at every image load (including the
# deployed library's init_julia) and empties the slot, so a fresh
# process starts WITHOUT a solver and kinetics_step honors its -2
# contract until kinetics_build runs; without this, a caller who
# forgot kinetics_step's build call would silently compute with the
# baked-in HLW parameters.
const KS = FjKinetics.KineticsSolver[]

function __init__()
    empty!(KS)
end

# Build the solver; returns nspecies (2) so callers can sanity-check the
# mechanism exactly like the bridge driver does.
# Error-code contract on both entries (review finding): a Julia exception
# must never escape a @ccallable function -- crossing the C ABI is
# undefined behavior. kinetics_build: nspecies (2) on success, -1 on
# failure. kinetics_step: 0 on success, -1 bad n, -2 solver not built
# yet, -3 the solver threw.
Base.@ccallable function kinetics_build(a::Cdouble, ea::Cdouble, rg::Cdouble,
                                        q::Cdouble, cv::Cdouble)::Cint
    try
        ks = FjKinetics.build_kinetics(A = a, Ea = ea, R_g = rg, q = q, cv = cv)
        empty!(KS)                  # replace atomically: never leave a stale
        push!(KS, ks)               # solver behind on a successful rebuild
        return Int32(FjKinetics.nspecies(ks))
    catch
        return Int32(-1)
    end
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
    isempty(KS) && return Int32(-2)
    try
        nc = Int(n)                # unsafe_wrap needs NTuple{N,Int}
        y = unsafe_wrap(Matrix{Cdouble}, y_ptr, (nc, 2); own = false)
        t = unsafe_wrap(Vector{Cdouble}, t_ptr, nc; own = false)
        rho = unsafe_wrap(Vector{Cdouble}, rho_ptr, nc; own = false)
        FjKinetics.step_chemistry!(KS[1], y, t, rho, dt)
        return Int32(0)
    catch
        return Int32(-3)
    end
end

end # module KineticsAOT
