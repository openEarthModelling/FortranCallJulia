# scripts/precompile.jl

# Load the FortranBridge package from its project environment. Run with the
# package project active, e.g. julia --project=src/FortranBridge, or via
# scripts/build_sysimage.jl (which activates the project for the build).
using FortranBridge

# 1. Exercise Fast Path Registration
# This triggers compilation of the @cfunction wrapper.
# register_f2 takes the function itself plus its lookup name; the old script
# called it with (:julia_add, Float64, (Float64, Float64)) and never defined
# julia_add at all, so it could not have run as written.
julia_add(a, b) = a + b
c_ptr = register_f2(julia_add, "julia_add")

# 2. Exercise Object Management
# We use a mutable struct to be safe with pointer conversion if needed, 
# though String is usually okay for testing.
mutable struct TestType
    x::Int
end
obj = TestType(42)

# The GC manager keys on the raw pointer address (what C passes back), so
# retention takes the pointer together with the object it protects.
ptr = pointer_from_objref(obj)
retain_obj(ptr, obj)
release_obj(ptr)

# 3. Exercise Array Utils
print_array_info([1.0, 2.0, 3.0])

# 4. Exercise the math function
julia_add(10.0, 20.0)

println("Precompilation complete.")

# 5. SciML solve path and the Fortran callback dispatch path
# PrecompileTools workloads execute only while an image is being generated;
# PackageCompiler runs this file inside the incremental sysimage build, so
# everything compiled here is baked into libfj_sysimage.
using PrecompileTools

# Julia-native stand-in for the Fortran-backed RHS. fcj_create_callback installs
# the real function under the global name Main.FJ_CALLBACK at runtime (latest
# created wins), so precompiling the same-signature dispatch through that
# global is what the eval-ed solver code hits; the placeholder binding created
# below is re-bound away on the first fcj_create_callback call.
function precompile_rhs!(du, u, p, t)
    du[1] = u[2]
    du[2] = -u[1]
    return nothing
end

PrecompileTools.@setup_workload begin
    using OrdinaryDiffEq: ODEProblem, solve, Tsit5
    using SciMLBase: ReturnCode

    PrecompileTools.@compile_workload begin
        # (a) One real (small) ODE solve: harmonic oscillator via Tsit5
        #     (~20 adaptive steps). Compiles the OrdinaryDiffEq solve path
        #     that Fortran clients exercise at runtime.
        prob = ODEProblem(precompile_rhs!, [1.0, 0.0], (0.0, 2.0))
        sol = solve(prob, Tsit5(); save_everystep = false)
        sol.retcode == ReturnCode.Success ||
            error("precompile workload ODE solve failed: $(sol.retcode)")

        # (b) The Main.FJ_CALLBACK binding fcj_create_callback maintains:
        #     install a same-signature stand-in and invoke it once so the
        #     call-site shape (du, u, p, t) through the global is compiled.
        Core.eval(Main, :(FJ_CALLBACK = $precompile_rhs!))
        fcj_cb = getfield(Main, :FJ_CALLBACK)
        du = zeros(2)
        fcj_cb(du, [1.0, 0.0], nothing, 0.0)
        du[2] == -1.0 || error("precompile workload callback did not run")
    end
end

# 6. FjKinetics chemistry path of the capstone example. The Fortran driver
# evals exactly this shape once per Strang half-step: buffers wrapped from
# Fortran memory are ordinary Array{Float64} (unsafe_wrap), sliced by view
# into the active set. The package's own workload covers plain and view
# paths inside the package cache; this section additionally warms the
# runtime expression shape (kwarg build, global re-binding) against Main.
using FjKinetics

fcj_ks = FjKinetics.build_kinetics(A = 164180.0, Ea = 25.0, R_g = 1.0,
                                  q = 25.0, cv = 2.5)
FjKinetics.nspecies(fcj_ks) == 2 || error("precompile workload: bad mechanism")

# emulate the driver's persistent zero-copy buffers + active-set slicing
const FJ_YBUF = zeros(8, 2)
const FJ_TBUF = zeros(8)
const FJ_RHOBUF = zeros(8)
FJ_YBUF[:, 1] .= 1.0
FJ_TBUF .= 17.0
for n_active in (2, 8)
    FjKinetics.step_chemistry!(fcj_ks,
        view(FJ_YBUF, 1:n_active, :), view(FJ_TBUF, 1:n_active),
        view(FJ_RHOBUF, 1:n_active), 4.0e-4)
end

println("FjKinetics precompilation complete.")
