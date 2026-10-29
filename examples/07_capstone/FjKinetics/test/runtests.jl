using Test
using FjKinetics
using FjKinetics: build_kinetics, step_chemistry!, nspecies
using OrdinaryDiffEq: Rodas5P
using StaticArrays

# Reference parameters: an aggressive but numerically tame single-step set.
const P_REF = (; A = 1.0e6, Ea = 1.0e4, R_g = 1.0, q = 20.0, cv = 2.5)

@testset "FjKinetics" begin

@testset "mechanism structure" begin
    ks = build_kinetics(; P_REF..., T_ref = 1500.0)
    @test nspecies(ks) == 2
    @test size(ks.prob.u0) == (3,)              # (F, P, T) per cell
    @test ks.prob.u0 isa MVector
    # batch interface contract: Y ncell x 2, T/rho ncell
    Y = [1.0 0.0; 1.0 0.0; 0.5 0.5]
    T = [1500.0, 900.0, 1200.0]
    step_chemistry!(ks, Y, T, [1.0, 1.0, 1.0], 1.0e-6)
    @test all(Y .>= 0.0) && all(Y .<= 1.0)
    @test all(T .> 0.0)
end

@testset "isothermal analytic solution (q=0)" begin
    # with no heat release, k(T) is constant and F decays exponentially
    ks = build_kinetics(; A = 2.5, Ea = 100.0, R_g = 1.0, q = 0.0, cv = 2.5,
                        alg = Rodas5P(), abstol = 1e-12, reltol = 1e-12)
    k = 2.5 * exp(-100.0 / 1200.0)
    for dt in (1.0e-3, 0.1, 3.0)
        Y = [1.0 0.0]
        T = [1200.0]
        step_chemistry!(ks, Y, T, [1.0], dt)
        @test Y[1, 1] ≈ exp(-k * dt) rtol = 1e-8
        @test Y[1, 2] ≈ 1 - exp(-k * dt) rtol = 1e-8
        @test T[1] ≈ 1200.0 atol = 1e-9
    end
end

@testset "energy bookkeeping and complete burn" begin
    ks = build_kinetics(; P_REF..., abstol = 1e-12, reltol = 1e-12)
    # hot cell burns out completely; T rise = (q/cv) * burned mass fraction
    Y = [0.3 0.7]
    T0 = 2000.0
    T = [T0]
    step_chemistry!(ks, Y, T, [1.0], 10.0)
    @test Y[1, 1] < 1e-10                       # burned out
    @test Y[1, 1] + Y[1, 2] ≈ 1.0 atol = 1e-9   # mass conservation
    @test T[1] ≈ T0 + (P_REF.q / P_REF.cv) * 0.3 rtol = 1e-6
    # cold cell with high activation energy stays frozen (induction)
    Y = [1.0 0.0]
    T = [300.0]
    step_chemistry!(ks, Y, T, [1.0], 10.0)
    @test Y[1, 1] > 0.999999
    @test T[1] < 300.0 + 1e-4
end

@testset "batch equals single-cell loop" begin
    ks = build_kinetics(; P_REF...)
    ncell = 7
    Yb = zeros(ncell, 2)
    Yb[:, 1] .= [0.1, 0.3, 0.7, 0.95, 0.5, 0.85, 0.2]
    Yb[:, 2] .= 1.0 .- Yb[:, 1]
    Tb = [500.0, 800.0, 1100.0, 1400.0, 1700.0, 2000.0, 2300.0]
    Y1 = copy(Yb); T1 = copy(Tb)
    Y2 = copy(Yb); T2 = copy(Tb)
    step_chemistry!(ks, Y1, T1, ones(ncell), 5.0e-4)
    for i in 1:ncell
        Yi = Y2[i:i, :]; Ti = T2[i:i]
        step_chemistry!(ks, Yi, Ti, [1.0], 5.0e-4)
        Y2[i, 1] = Yi[1, 1]; Y2[i, 2] = Yi[1, 2]; T2[i] = Ti[1]
    end
    @test Y1 ≈ Y2 rtol = 1e-12
    @test T1 ≈ T2 rtol = 1e-12
end

@testset "integrator reuse carries no state between cells" begin
    ks = build_kinetics(; P_REF...)
    hot = ([0.9 0.1], [2200.0])
    cold = ([1.0 0.0], [350.0])
    Yh1 = [hot[1][1] hot[1][2]]; Th1 = [hot[2][1]]
    Yc  = [cold[1][1] cold[1][2]]; Tc  = [cold[2][1]]
    step_chemistry!(ks, Yh1, Th1, [1.0], 1.0e-3)   # hot burns -> T rises a lot
    step_chemistry!(ks, Yc,  Tc,  [1.0], 1.0e-3)   # cold: nearly frozen
    Yh2 = [hot[1][1] hot[1][2]]; Th2 = [hot[2][1]]
    step_chemistry!(ks, Yh2, Th2, [1.0], 1.0e-3)   # same hot cell again
    @test Yh2 ≈ Yh1 rtol = 1e-10                   # unaffected by the cold cell
    @test Th2 ≈ Th1 rtol = 1e-10
    @test Yc[1] > 0.99
end

@testset "monotonicity" begin
    ks = build_kinetics(; P_REF...)
    ncell = 50
    Y = zeros(ncell, 2)
    Y[:, 1] .= range(1.0, 0.01; length = ncell)
    Y[:, 2] .= 1.0 .- Y[:, 1]
    T = collect(range(500.0, 2500.0; length = ncell))
    Y0 = copy(Y); T0 = copy(T)
    step_chemistry!(ks, Y, T, ones(ncell), 0.2)
    @test all(Y[:, 1] .<= Y0[:, 1] .+ 1e-12)   # fuel never increases
    @test all(Y[:, 2] .>= Y0[:, 2] .- 1e-12)   # product never decreases
    @test all(T .>= T0 .- 1e-9)                # exothermic: T never drops
    @test all(Y[:, 1] .+ Y[:, 2] .≈ 1.0)
end

# ------------------------------------------------------------------ v0.2 (GRI)
@testset "gri30 solver (v0.2)" begin
    @test KineticsSolver <: AbstractKineticsSolver
    @test OneStepSolver === KineticsSolver

    gs = build_gri30_kinetics()
    @test gs isa GriSolver
    @test gs isa AbstractKineticsSolver
    @test nspecies(gs) == 53                    # GRI-Mech 3.0
    @test all(>(0), gs.W)

    # one-shot ignition: stoichiometric CH4/air at 1500 K / 1 atm
    # (ChemMechSim's own validation setup; coarse grid keeps the test quick)
    r = run_gri_ignition(gs; nsample = 201)
    @test length(r.ts) == 201 && size(r.X) == (4, 201)
    @test r.t_ign ≈ 1.1075e-3 rtol = 3e-2       # coarse grid shifts by < 1 step
    @test 2000.0 < r.T_end < 3200.0
    @test r.X[1, end] < 1e-6                    # CH4 consumed
    @test r.X[3, end] > 1e-3                    # CO2 produced
    @test all(>=(0.0), r.X)

    # per-cell mass-fraction step: conservation + heat release
    names = [s.name for s in gs.mech.species]
    iCH4 = findfirst(==("CH4"), names)
    iO2  = findfirst(==("O2"), names)
    iN2  = findfirst(==("N2"), names)
    W = [s.molecular_weight for s in gs.mech.species]
    X = zeros(nspecies(gs))
    X[iCH4] = 1.0 / 10.52; X[iO2] = 2.0 / 10.52; X[iN2] = 7.52 / 10.52
    Ymass = reshape(X .* W ./ sum(X .* W), 1, :)
    rho = 101325.0 * sum(X .* W) / (8.314 * 1500.0)
    Tcell = [1500.0]
    step_chemistry!(gs, Ymass, Tcell, [rho], 1.5e-3)   # past ignition
    @test sum(Ymass) ≈ 1.0 rtol = 1e-9
    @test all(>=(0.0), Ymass)
    @test Tcell[1] > 2000.0                     # ignited
    @test Ymass[1, iCH4] < 1e-4                 # burned
    @test Ymass[1, iN2] > 0.7                   # diluent survives

    # documented argument-validation errors -- each fires before any ODE
    # solve, so these stay cheap
    @test_throws ErrorException build_gri30_kinetics(yaml_path = "/nonexistent/fj_kinetics.yaml")
    @test_throws ErrorException step_chemistry!(gs, zeros(1, 52), [1500.0], [1.0], 1.0e-6)
    @test_throws ErrorException step_chemistry!(gs, zeros(1, nspecies(gs)), [1500.0], [1.0], -1.0)
    @test_throws ErrorException run_gri_ignition(gs; nsample = 1)
end

end # top-level testset
