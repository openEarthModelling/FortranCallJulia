module FjKinetics

# Phase A chemistry of the reacting-flow capstone: a single-step irreversible
# Arrhenius reaction F -> P coupled to a constant-volume adiabatic energy
# equation, written directly in Catalyst (ChemMechSim enters only in Phase B,
# with GRI-Mech 3.0). The per-cell ODE is
#
#     dF/dt = -k(T)*F,   dP/dt = +k(T)*F,   dT/dt = (q/cv)*k(T)*F,
#     k(T) = A * exp(-Ea / (R_g*T)),
#
# where F and P are the unburned/burned mass fractions (F + P = 1) and q is
# the heat release per unit mass (progress-variable form of the standard
# single-step detonation model). One ODEProblem is compiled once and reused
# for every cell and every Strang half-step via reinit! -- no remake, no
# re-specialization, hence no JIT after the first solve.

using Catalyst
# All symbolic-API names come through Catalyst's @reexport of
# ModelingToolkitBase. Importing them from the high-level ModelingToolkit
# package instead would grab MTK v11's deprecation shims, whose ODESystem
# does not interop with Catalyst 16 systems (convert fails).
using Catalyst: ode_model, unknowns, parameters, complete, getname
using Catalyst: ODEFunction
using OrdinaryDiffEq: Rodas5P
using SciMLBase
using SciMLBase: ODEProblem, init, reinit!, step!
using StaticArrays: MVector
using PrecompileTools

export KineticsSolver, build_kinetics, step_chemistry!, nspecies

# ---------------------------------------------------------------------------
# Model construction
# ---------------------------------------------------------------------------

# eval_expression=true + eval_module=FjKinetics make MTK evaluate the
# generated RHS/Jacobian code into THIS module as ordinary compiled methods.
# The default (RuntimeGeneratedFunction) is invisible to PackageCompiler, so
# a sysimage would silently fall back to JIT at runtime; this route is what
# lets the compiled code be captured (zero-JIT verification comes with the
# sysimage commit).
#
# Everything expensive is built ONCE at module load, as `const`s:
# - during package precompilation these top-level statements finish before
#   the PrecompileTools workload runs, so the workload sees their methods in
#   its world (eval'ing inside the workload instead would be a world-age
#   error: the freshly eval'ed closure could not be called there);
# - in a PackageCompiler sysimage the const VALUES are baked into the image,
#   so `build_kinetics` at runtime does no symbolic work and no eval at all.
function _build_system()
    rn = @reaction_network FjReactor begin
        @species F(t) P(t)
        @variables T(t)
        @parameters A Ea R_g q cv
        A * exp(-Ea / (R_g * T)), F --> P
        @equations D(T) ~ (q / cv) * A * exp(-Ea / (R_g * T)) * F
    end
    # ode_model (not the deprecated convert(ODESystem, rn) path): Catalyst 16
    # builds a unified ModelingToolkitBase.System in ODE mode
    osys = ode_model(rn; combinatoric_ratelaws = false)
    return complete(osys)
end

const _SYS = _build_system()
const _SYMS = [getname(s) for s in unknowns(_SYS)]
const _IDX_F = findfirst(==(Symbol("F")), _SYMS)
const _IDX_P = findfirst(==(Symbol("P")), _SYMS)
const _IDX_T = findfirst(==(Symbol("T")), _SYMS)
if _IDX_F === nothing || _IDX_P === nothing || _IDX_T === nothing
    error("unexpected unknown set after completion: $_SYMS")
end
const _PSYMS = [getname(v) for v in parameters(_SYS)]
# generated RHS + analytic Jacobian, evaluated into this module; the plain
# SciMLBase ODEProblem below keeps the MVector u0 static (ODEProblem(sys,..)
# instead would canonicalize it into a heap Vector)
const _F = ODEFunction{true}(_SYS; jac = true,
                             eval_expression = true, eval_module = FjKinetics)

"""
    KineticsSolver

A per-cell chemistry integrator bound to one compiled ODEProblem. Build it
once with [`build_kinetics`](@ref), then call
[`step_chemistry!`](@ref) on every Strang half-step. All cells share the
single integrator instance; `reinit!` with an `MVector` reuses the existing
type-specialized code, so after the first solve there is no compilation.
"""
struct KineticsSolver{
    Prob<:ODEProblem, Integ<:SciMLBase.AbstractODEIntegrator, SolAlg}
    prob::Prob
    integ::Integ
    alg::SolAlg
    nspec::Int
    idx_species::Vector{Int}   # u0 slot of each species, Y column order
    idx_T::Int                 # u0 slot of the temperature
    p::Vector{Float64}         # parameter vector in prob order
end

nspecies(ks::KineticsSolver) = ks.nspec

"""
    build_kinetics(; A, Ea, R_g, q, cv, abstol=1e-10, reltol=1e-8,
                   alg=Rodas5P(), T_ref=1000.0) -> KineticsSolver

Assemble a solver for the Phase A single-step mechanism with the given
parameters. The generated RHS/Jacobian is built once at package load; this
only packages the numeric parameters, so it is cheap and JIT-free:

- `A`:      Arrhenius prefactor (units of 1/time, progress-variable form)
- `Ea`:     activation energy (in the k(T) = A*exp(-Ea/(R_g*T)) convention;
            the HLW 2000 example uses E+ = 25 with R_g = 1)
- `R_g`:    universal gas constant in matching units
- `q`:      heat release per unit mass
- `cv`:     constant-volume specific heat

The returned solver advances the vector (F, P, T) per cell. Default initial
state is fully unburned at `T_ref`; `step_chemistry!` overwrites it with the
actual cell state anyway.
"""
function build_kinetics(; A::Real, Ea::Real, R_g::Real, q::Real, cv::Real,
                        abstol::Real = 1e-10, reltol::Real = 1e-8,
                        alg = Rodas5P(), T_ref::Real = 1000.0)
    # parameter vector in the order the compiled function expects
    pmap = Dict(:A => A, :Ea => Ea, :R_g => R_g, :q => q, :cv => cv)
    p = Float64[pmap[s] for s in _PSYMS]

    u0 = MVector{3,Float64}(undef)
    u0[_IDX_F] = 1.0
    u0[_IDX_P] = 0.0
    u0[_IDX_T] = Float64(T_ref)
    prob = ODEProblem(_F, u0, (0.0, 1.0), p)

    integ = init(prob, alg; abstol = abstol, reltol = reltol,
                 save_everystep = false, save_start = false)
    return KineticsSolver(prob, integ, alg, 2, [_IDX_F, _IDX_P], _IDX_T, p)
end

"""
    step_chemistry!(ks, Y, T, rho, dt) -> ks

Advance every cell's chemistry by `dt` in place. `Y` is `ncell x nspec`
(species mass fractions, column order [F, P] for Phase A), `T` the cell
temperatures, `rho` the cell densities. `rho` is unused by the Phase A
progress-variable mechanism but part of the mechanism-agnostic interface
(GRI-Mech 3.0 in Phase B needs density); it must still be passed with
`ncell` elements.

Per cell this reinitializes the shared integrator with an `MVector` and
takes exactly one `step!` to `dt` -- zero allocations after the first call.
"""
function step_chemistry!(ks::KineticsSolver, Y::AbstractMatrix{<:Real},
                         T::AbstractVector{<:Real}, rho::AbstractVector{<:Real},
                         dt::Real)
    ncell = length(T)
    size(Y, 1) == ncell && size(Y, 2) == ks.nspec && length(rho) == ncell ||
        error("step_chemistry!: Y must be $(ncell)x$(ks.nspec), rho $(ncell)")
    dt > 0 || error("step_chemistry!: dt must be positive, got $dt")
    integ = ks.integ
    u0 = MVector{3,Float64}(undef)
    for i in 1:ncell
        u0[ks.idx_species[1]] = Float64(Y[i, 1])
        u0[ks.idx_species[2]] = Float64(Y[i, 2])
        u0[ks.idx_T] = Float64(T[i])
        reinit!(integ, u0, t0 = 0.0, tf = dt)
        step!(integ, dt, true)
        Y[i, 1] = integ.u[ks.idx_species[1]]
        Y[i, 2] = integ.u[ks.idx_species[2]]
        T[i] = integ.u[ks.idx_T]
    end
    return ks
end

# ---------------------------------------------------------------------------
# Precompilation workload: build the mechanism and run one batch step so the
# entire path (DSL -> ode_model -> complete -> ODEProblem -> init -> reinit! ->
# step!) is compiled into the package image. PackageCompiler sysimages then
# capture it; without a sysimage the package's own precompile cache already
# warms most of it.
# ---------------------------------------------------------------------------

PrecompileTools.@setup_workload begin
    PrecompileTools.@compile_workload begin
        ks = build_kinetics(; A = 1.0e6, Ea = 1.0e4, R_g = 1.0, q = 20.0,
                            cv = 2.5, T_ref = 1500.0)
        # plain Arrays: the bridge zero-copy path wraps Fortran memory into
        # Matrix/Vector, so this is the type specialization used at runtime
        Y = zeros(4, 2)
        Y[:, 1] .= 1.0
        T = fill(1500.0, 4)
        rho = fill(1.0, 4)
        step_chemistry!(ks, Y, T, rho, 1.0e-6)
    end
end

end # module
