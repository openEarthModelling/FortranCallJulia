module FjKinetics

# Phase A chemistry of the reacting-flow capstone: a single-step irreversible
# Arrhenius reaction F -> P coupled to a constant-volume adiabatic energy
# equation, written directly in Catalyst. The per-cell ODE is
#
#     dF/dt = -k(T)*F,   dP/dt = +k(T)*F,   dT/dt = (q/cv)*k(T)*F,
#     k(T) = A * exp(-Ea / (R_g*T)),
#
# where F and P are the unburned/burned mass fractions (F + P = 1) and q is
# the heat release per unit mass (progress-variable form of the standard
# single-step detonation model). One ODEProblem is compiled once and reused
# for every cell and every Strang half-step via reinit! -- no remake, no
# re-specialization, hence no JIT after the first solve.
#
# v0.2 adds the mechanism-agnostic solver hierarchy: Phase A's solver is
# FROZEN (same struct, same fields, same step_chemistry! method) under the
# new AbstractKineticsSolver base, and GriSolver brings a full reaction
# mechanism (GRI-Mech 3.0 by default) through ChemMechSim -- one-shot
# simulate() per advance, see the GriSolver docstring for the Phase B
# follow-ups (per-cell reinit!/step! on the ChemMechSim integrator).

using Catalyst
# All symbolic-API names come through Catalyst's @reexport of
# ModelingToolkitBase. Importing them from the high-level ModelingToolkit
# package instead would grab MTK v11's deprecation shims, whose ODESystem
# does not interop with Catalyst 16 systems (convert fails).
using Catalyst: ode_model, unknowns, parameters, complete, getname
using Catalyst: ODEFunction
using OrdinaryDiffEq: Rodas5P, FBDF
using SciMLBase
using SciMLBase: ODEProblem, init, reinit!, step!
using StaticArrays: MVector
using PrecompileTools
# Full-mechanism solver (v0.2). ChemMechSim is a dev-path dependency (the
# registry carries only v1.0.0; the repo is at 1.2.0) -- see
# scripts/install_sciml_env.jl, which develops it into the shared env.
using ChemMechSim
using ChemMechSim: Mechanism

export KineticsSolver, OneStepSolver, AbstractKineticsSolver,
       build_kinetics, step_chemistry!, nspecies,
       GriSolver, build_gri30_kinetics, run_gri_ignition

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
    AbstractKineticsSolver

Common base of the chemistry solvers. The mechanism-agnostic contract is
[`step_chemistry!`](@ref)(solver, Y, T, rho, dt): `Y` is `ncell x nspec`
species MASS fractions in the solver's species order, `T` cell temperatures,
`rho` cell densities; all are advanced in place by `dt`.
"""
abstract type AbstractKineticsSolver end

"""
    KineticsSolver

A per-cell chemistry integrator bound to one compiled ODEProblem. Build it
once with [`build_kinetics`](@ref), then call
[`step_chemistry!`](@ref) on every Strang half-step. All cells share the
single integrator instance; `reinit!` with an `MVector` reuses the existing
type-specialized code, so after the first solve there is no compilation.

`OneStepSolver` is an alias for this type (the Phase A one-step mechanism).
"""
struct KineticsSolver{
    Prob<:ODEProblem, Integ<:SciMLBase.AbstractODEIntegrator, SolAlg} <: AbstractKineticsSolver
    prob::Prob
    integ::Integ
    alg::SolAlg
    nspec::Int
    idx_species::Vector{Int}   # u0 slot of each species, Y column order
    idx_T::Int                 # u0 slot of the temperature
    p::Vector{Float64}         # parameter vector in prob order
end

const OneStepSolver = KineticsSolver

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
# v0.2: full-mechanism solver (GRI-Mech 3.0 by default) through ChemMechSim.
# ChemMechSim's public API is one-shot: build u0 -> simulate(reactor, tspan)
# -> fresh solution. There is no exposed reinit!/step! on a persistent
# integrator (its systems have thousands of compiled methods; the
# per-cell increment API is a Phase B follow-up), so every advance below is
# an independent solve. Correct, but each call pays integrator setup -- for
# the ignition-delay demo (one solve) that is exactly right; for Strang
# coupling into the flow solver it is the known optimization target.
# ---------------------------------------------------------------------------

"""
    GriSolver <: AbstractKineticsSolver

A whole-mechanism chemistry solver backed by ChemMechSim (Cantera-YAML
mechanisms; GRI-Mech 3.0 by default). Build it with
[`build_gri30_kinetics`](@ref); advance cells with [`step_chemistry!`](@ref)
(mass-fraction <-> concentration conversion is handled internally via the
species molar masses) or run a one-shot homogeneous ignition with
[`run_gri_ignition`](@ref).

Species order for the `Y` argument is `mech.species` order (the mechanism
file's species order). The underlying state is species CONCENTRATIONS in
mol/m^3 plus temperature (ChemMechSim's `state_basis = :concentration`).
"""
struct GriSolver <: AbstractKineticsSolver
    mech::Mechanism
    reactor::BatchReactor
    sys::Any                  # lowered MTK system (from extract_system)
    nspec::Int
    var_T::Any                # symbolic T unknown (index into unknowns order)
    idx_species::Vector{Int}  # sol.u slot of each species, Y column order
    idx_T::Int                # sol.u slot of the temperature
    W::Vector{Float64}        # molar mass (kg/mol) per species
    alg::Any
    abstol::Float64
    reltol::Float64
    yaml_path::String
end

nspecies(gs::GriSolver) = gs.nspec

"""
    build_gri30_kinetics(; yaml_path=nothing, mode=:adiabatic_constV,
                         solver=FBDF(), reltol=1e-8, abstol=1e-12) -> GriSolver

Load a mechanism (default: the GRI-Mech 3.0 YAML bundled with ChemMechSim at
`examples/mechanism/gri30.yaml`) and package it as a solver. `mode` and the
solver controls are ChemMechSim `BatchReactor`/`simulate` options; the
defaults mirror ChemMechSim's own GRI30 ignition-delay validation
(FBDF, reltol 1e-8, abstol 1e-12).

Every species must appear as a dynamic unknown of the lowered system (true
for `:adiabatic_constV` concentration-state reactors) and carry a molar
mass -- both are needed for the mass-fraction <-> concentration conversion
in `step_chemistry!`.
"""
function build_gri30_kinetics(; yaml_path::Union{AbstractString,Nothing} = nothing,
                              mode::Symbol = :adiabatic_constV,
                              solver = FBDF(), reltol::Real = 1e-8,
                              abstol::Real = 1e-12)
    path = yaml_path === nothing ?
        joinpath(pkgdir(ChemMechSim), "examples", "mechanism", "gri30.yaml") :
        String(yaml_path)
    isfile(path) || error("build_gri30_kinetics: mechanism file not found: $path")
    mech = load_mechanism(path)
    reactor = BatchReactor(mech; mode = mode)
    sys = extract_system(reactor)
    syms = [getname(s) for s in unknowns(sys)]
    idx_T = findfirst(==(Symbol("T")), syms)
    idx_T === nothing &&
        error("build_gri30_kinetics: lowered system has no T unknown (mode=$mode)")
    # untyped first: Int[...] would convert `nothing` -> MethodError before
    # the descriptive missing-species diagnostic below can fire
    idx_species_raw = [findfirst(==(Symbol(sp.name)), syms) for sp in mech.species]
    missing = [sp.name for (sp, i) in zip(mech.species, idx_species_raw) if i === nothing]
    isempty(missing) || error("build_gri30_kinetics: species not dynamic unknowns " *
                              "of the lowered system (mode=$mode): $missing")
    idx_species = Int.(idx_species_raw)
    W = Float64[sp.molecular_weight for sp in mech.species]
    all(w -> w > 0 && !isnan(w), W) || error("build_gri30_kinetics: mechanism has " *
        "species with unspecified/invalid molar mass (needed for Y <-> c conversion)")
    return GriSolver(mech, reactor, sys, length(mech.species),
                     unknowns(sys)[idx_T], idx_species, idx_T, W,
                     solver, Float64(abstol), Float64(reltol), path)
end

"""
    step_chemistry!(gs::GriSolver, Y, T, rho, dt) -> gs

Advance every cell's chemistry by `dt` in place, one independent
ChemMechSim `simulate` per cell (one-shot API: correct but each call pays
integrator setup -- see the GriSolver docstring). `Y` holds species MASS
fractions in `mech.species` column order; they are converted to
concentrations with the cell density (`c = rho * Y / W`) and back with the
END-state total density (`Y = c * W / sum(c .* W)`), so mass conservation
closes the loop even where the integrator's mass balance drifts at
tolerance level. Tolerance-level negative concentrations (trace species
undershooting at `abstol`) are clamped to zero before the closure, so the
returned state is physically admissible: `Y >= 0` and `sum(Y) == 1` exactly.
"""
function step_chemistry!(gs::GriSolver, Y::AbstractMatrix{<:Real},
                         T::AbstractVector{<:Real}, rho::AbstractVector{<:Real},
                         dt::Real)
    ncell = length(T)
    size(Y, 1) == ncell && size(Y, 2) == gs.nspec && length(rho) == ncell ||
        error("step_chemistry!: Y must be $(ncell)x$(gs.nspec), rho $(ncell)")
    dt > 0 || error("step_chemistry!: dt must be positive, got $dt")
    for i in 1:ncell
        u0 = Dict{String,Float64}(sp.name => Float64(rho[i]) * Float64(Y[i, j]) / gs.W[j]
                                  for (j, sp) in enumerate(gs.mech.species))
        u0["T"] = Float64(T[i])
        sol = simulate(gs.reactor, (0.0, Float64(dt)); u0 = u0, solver = gs.alg,
                       reltol = gs.reltol, abstol = gs.abstol)
        sol.retcode == SciMLBase.ReturnCode.Success ||
            error("step_chemistry!: GRI solve failed in cell $i (retcode $(sol.retcode))")
        ue = sol.u[end]
        T[i] = ue[gs.idx_T]
        # clamp tolerance-level negative concentrations (trace intermediates
        # undershoot at abstol, measured ~-8e-17 for C2H2 here) BEFORE the
        # closure, so the returned state is physically admissible --
        # Y >= 0 and sum(Y) == 1 exactly; a microscopically negative mass
        # fraction fed back into a compressible flow solver is a real hazard
        rho_end = sum(max(ue[gs.idx_species[j]], 0.0) * gs.W[j]
                      for j in 1:gs.nspec)
        for j in 1:gs.nspec
            Y[i, j] = max(ue[gs.idx_species[j]], 0.0) * gs.W[j] / rho_end
        end
    end
    return gs
end

"""
    run_gri_ignition(gs; T0=1500.0, P0=101325.0,
                     X0=Dict("CH4"=>1/10.52, "O2"=>2/10.52, "N2"=>7.52/10.52),
                     tspan=(0.0, 5.0e-3), nsample=2001,
                     species_out=("CH4","O2","CO2","OH")) -> NamedTuple

One-shot homogeneous ignition-delay run, mirroring ChemMechSim's
`examples/validation/gri30_ignition.jl` (stoichiometric CH4/air,
constant-volume adiabatic): initial state is `X0` mole fractions diluted to
concentrations at (`T0`, `P0`), integrated over `tspan` with the solver
controls stored in `gs`.

Returns `(ts, T, X, t_ign, T_end)`:
- `ts::Vector{Float64}`  the nsample-point time grid on tspan
- `T::Vector{Float64}`   temperature on that grid
- `X::Matrix{Float64}`   `length(species_out) x nsample` MOLE fractions of
  the requested species (X[k, :] for species_out[k]); tolerance-level
  negative interpolants clamped to zero, same admissibility contract as
  `step_chemistry!`
- `t_ign::Float64`       ignition delay by max |dT/dt| on the grid,
  reported AT the grid point after the steepest segment
  (`ts[argmax(abs.(diff(T) ./ diff(ts))) + 1]`, the validation script's
  criterion)
- `T_end::Float64`       final temperature
"""
function run_gri_ignition(gs::GriSolver;
                          T0::Real = 1500.0, P0::Real = 101325.0,
                          X0::Dict{String,<:Real} =
                              Dict("CH4" => 1.0 / 10.52, "O2" => 2.0 / 10.52,
                                   "N2" => 7.52 / 10.52),
                          tspan::Tuple{Real,Real} = (0.0, 5.0e-3),
                          nsample::Int = 2001,
                          species_out::Tuple{Vararg{String}} = ("CH4", "O2", "CO2", "OH"))
    nsample >= 2 || error("run_gri_ignition: nsample must be >= 2, got $nsample")
    R = 8.314
    c_tot = Float64(P0) / (R * Float64(T0))
    u0 = Dict{String,Float64}(sp.name => get(X0, sp.name, 0.0) * c_tot
                              for sp in gs.mech.species)
    u0["T"] = Float64(T0)
    sol = simulate(gs.reactor, (Float64(tspan[1]), Float64(tspan[2])); u0 = u0,
                   solver = gs.alg, reltol = gs.reltol, abstol = gs.abstol)
    sol.retcode == SciMLBase.ReturnCode.Success ||
        error("run_gri_ignition: solve failed (retcode $(sol.retcode))")

    ts = collect(range(Float64(tspan[1]), Float64(tspan[2]); length = nsample))
    A = sol(ts)                        # ns x nsample state matrix on the grid
    T = vec(Float64.(A[gs.idx_T, :]))
    # same admissibility clamp as step_chemistry!: dense interpolation can
    # undershoot to tolerance-level negatives on trace species, and reported
    # mole fractions must stay >= 0
    Cs = max.(Float64.(A[gs.idx_species, :]), 0.0)
    totals = vec(sum(Cs; dims = 1))
    X = Matrix{Float64}(undef, length(species_out), nsample)
    for (k, name) in enumerate(species_out)
        j = findfirst(==(name), (sp.name for sp in gs.mech.species))
        j === nothing && error("run_gri_ignition: species $name not in mechanism")
        X[k, :] .= Cs[j, :] ./ totals   # Cs row j already IS species j
    end
    # ignition criterion: grid point AFTER the steepest |dT/dt| segment
    t_ign = ts[argmax(abs.(diff(T) ./ diff(ts))) + 1]
    return (ts = ts, T = T, X = X, t_ign = t_ign, T_end = T[end])
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
        # view-based active-set call path used by the capstone example:
        # wrapped full-domain buffers are sliced in Julia
        step_chemistry!(ks, view(Y, 1:2, :), view(T, 1:2), view(rho, 1:2), 1.0e-6)
    end
end

end # module
