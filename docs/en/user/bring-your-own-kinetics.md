---
title: Bring your own kinetics
sync: 2026-10-31
---

# Bring your own kinetics

The capstone does not hardcode its chemistry. The Fortran driver advances
cells through FjKinetics, the small Julia package at
`examples/07_capstone/FjKinetics/`, whose v0.2 puts every mechanism behind
one interface -- so the flow solver never learns what chemistry it is
burning. Bringing your own kinetics comes in two tiers:

1. **Use ChemMechSim as-is.** An open-source Julia package that loads
   Cantera-YAML reaction mechanisms; the capstone's GRI-Mech 3.0 benchmark
   runs on it unchanged.
2. **Implement `AbstractKineticsSolver`.** Two methods, one contract -- your
   mechanism drops in behind the same Fortran call.

## The contract: `AbstractKineticsSolver`

The base type and its meaning, verbatim from
`examples/07_capstone/FjKinetics/src/FjKinetics.jl`:

```julia
"""
    AbstractKineticsSolver

Common base of the chemistry solvers. The mechanism-agnostic contract is
[`step_chemistry!`](@ref)(solver, Y, T, rho, dt): `Y` is `ncell x nspec`
species MASS fractions in the solver's species order, `T` cell temperatures,
`rho` cell densities; all are advanced in place by `dt`.
"""
abstract type AbstractKineticsSolver end
```

A solver is that base plus two methods. All four definitions below are
verbatim from the same file (the two `nspecies` lines and the two
`step_chemistry!` signatures sit at different points in it; bodies elided):

```julia
nspecies(ks::KineticsSolver) = ks.nspec
nspecies(gs::GriSolver) = gs.nspec

function step_chemistry!(ks::KineticsSolver, Y::AbstractMatrix{<:Real},
                         T::AbstractVector{<:Real}, rho::AbstractVector{<:Real},
                         dt::Real)

function step_chemistry!(gs::GriSolver, Y::AbstractMatrix{<:Real},
                         T::AbstractVector{<:Real}, rho::AbstractVector{<:Real},
                         dt::Real)
```

Read the contract off those names:

| Argument | Meaning |
|---|---|
| `Y` | `ncell x nspec` species **mass fractions** in the solver's species order, advanced in place |
| `T` | cell temperatures, advanced in place |
| `rho` | cell densities; part of the contract even when a mechanism ignores it -- the single-step one does, GRI-Mech 3.0 needs it |
| `dt` | how far every cell is advanced |
| `nspecies(solver)` | the `nspec` columns the Fortran side packs per cell |

FjKinetics v0.2 ships two solvers under the base: `OneStepSolver` (an alias
of `KineticsSolver` -- the single-step Arrhenius mechanism of the
reacting-flow capstone) and `GriSolver` (a full mechanism through
ChemMechSim).

## Tier 1: ChemMechSim and the GRI-Mech 3.0 capstone

ChemMechSim.jl is an open-source Julia package for Cantera-YAML reaction
mechanisms; it bundles GRI-Mech 3.0 itself (53 species, 325 reactions) at
`examples/mechanism/gri30.yaml`. One version note before you compare digits:
the General registry currently carries v1.0.0 while the repository is at
v1.2.0, and every validation number on this site was produced against
**v1.2.0** -- check which one your environment actually resolved.

Setup is one script. `scripts/install_sciml_env.jl` -- run with the same
Julia 1.12.x the bridge embeds -- creates the scratch environment
`scripts/sysimage_env` and develops FortranBridge, FjKinetics, and your
ChemMechSim checkout into it (`CHEMMECHSIM_PATH` overrides where the
checkout lives). The capstone executables probe for that environment at
startup; `FJ_KINETICS_PROJECT` redirects the probe.

Then build the examples and generate the native baseline first
(`run_gri_native.jl`, under the pinned Julia -- it refuses to run under a
version shim, because a drifting baseline fails the gates while wrongly
blaming the bridge). The bridge side of the benchmark, from
`examples/07_capstone/2_gri_ignition.f90` -- the whole chemistry driver kept
in one eval, so a Julia-side throw surfaces as an invalid result with the
reason in `get_last_error_message()`:

```fortran
    call julia_eval_string( &
        'function fj_gri_run() :: NamedTuple' // new_line('a') // &
        '    gs = FjKinetics.build_gri30_kinetics()' // new_line('a') // &
        '    return FjKinetics.run_gri_ignition(gs)' // new_line('a') // &
        'end')
    res = dummy%call('fj_gri_run')
    if (.not. res%is_valid()) &
        call fail('fj_gri_run failed: ' // get_last_error_message())
```

The solution's arrays come back in bulk copies -- `ts` (2001 points), `T`
(2001), and the `4 x 2001` mole-fraction matrix `X` flattened into one
buffer: one `%to_fortran` per array, zero per-element bridge traffic. The
`ts` and `X` legs, verbatim:

```fortran
    v = res%property('ts')
    if (.not. v%is_valid()) call fail('property ts: ' // get_last_error_message())
    rc = v%to_fortran(ts, int(NSAMPLE, kind=c_int64_t))
    if (rc /= 0) call fail('to_fortran ts: ' // get_last_error_message())

    ! Matrix{Float64} 4x2001, bulk-copied into the flat buffer
    v = res%property('X')
    if (.not. v%is_valid()) call fail('property X: ' // get_last_error_message())
    rc = v%to_fortran(Xflat, int(NSP_OUT * NSAMPLE, kind=c_int64_t))
    if (rc /= 0) call fail('to_fortran X: ' // get_last_error_message())
```

(The `T` leg between them is the same shape again.) Fortran then owns the
verdict -- the ignition criterion is computed on the extracted arrays, the
same one the validation script uses:

```fortran
    do k = 1, NSAMPLE - 1
        dtdt(k) = abs((T(k + 1) - T(k)) / (ts(k + 1) - ts(k)))
    end do
    imax = maxloc(dtdt, 1)          ! first occurrence, like Julia's argmax
    t_ign_f = ts(imax + 1)
```

Acceptance is four gates against the native run -- the Fortran-computed
`t_ign`, the extracted `T_end`, and two `X` spot values that pin the
column-major matrix layout -- each within a relative 1e-8
([Validation](../intro/validation.md)). The headline that comes out:
**t_ign = 1.1075 ms** for stoichiometric CH4/air at 1500 K and 1 atm,
constant-volume adiabatic, the delay taken at `argmax |dT/dt|`.

**Pin your environment before blaming anything.** FjKinetics' `[compat]`
pins the solve stack -- Catalyst ~16.2, OrdinaryDiffEq ~6.111, SciMLBase
~2.155 -- because an unpinned environment once drifted onto the
OrdinaryDiffEq 7.x line, whose step-size controller degraded the per-cell
`reinit!`/`step!` pattern by about **700x per grid cell** (a frozen cell
cost 982 internal steps instead of 1). If per-cell chemistry suddenly
crawls, check the resolve first; the bridge is the usual suspect and
usually innocent.

## Tier 2: implement the interface

Your mechanism becomes a subtype plus the two methods. The rules that keep
it drop-in:

1. **Mirror the argument shapes exactly** (`Y::AbstractMatrix{<:Real}`,
   `T`/`rho::AbstractVector{<:Real}`, `dt::Real`): the capstone passes
   wrapped Fortran memory and `view`s of it, and dispatch lands on your
   concrete type.
2. **Validate loudly, like the built-ins.** The guard pair from the
   `KineticsSolver` method, verbatim:

```julia
    size(Y, 1) == ncell && size(Y, 2) == ks.nspec && length(rho) == ncell ||
        error("step_chemistry!: Y must be $(ncell)x$(ks.nspec), rho $(ncell)")
    dt > 0 || error("step_chemistry!: dt must be positive, got $dt")
```

3. **Advance in place; return an admissible state.** If you return mass
   fractions, keep `Y >= 0` and `sum(Y) == 1` -- `GriSolver` clamps
   tolerance-level negative concentrations (trace species undershooting at
   `abstol`) before closing the sum, because a microscopically negative mass
   fraction fed back into a compressible flow solver is a real hazard.
4. **Throwing is allowed on this path.** The bridge catches the exception
   and the reason surfaces at the Fortran call site through
   `get_last_error_message()`. The raw function-pointer route of
   [Two SDKs, two speeds](two-sdks.md) is the one path where the called
   body must not throw.
5. **`rho` is part of the contract** even if your mechanism ignores it;
   Fortran always packs it.

The Fortran side never changes. The capstone wraps its persistent cell
buffers once, and every Strang half-step is ONE batched call over the active
cells -- from `examples/07_capstone/1_reacting_flow.f90` (the packing loop
above it is elided):

```fortran
            write (dts, '(es24.16)') dt_half
            write (expr, '(a,i0,a,i0,a,i0,a)') &
                'FjKinetics.step_chemistry!(FJ_KS, view(FJ_Y,1:', n_act, &
                ',:), view(FJ_T,1:', n_act, '), view(FJ_RHO,1:', n_act, &
                '), ' // trim(dts) // ')'
            v_res = julia_eval(trim(expr))
```

Swap what `FJ_KS` is bound to and that same line advances 2 species or 53:
the mechanism lives entirely on the Julia side of the `view`.

## Where to go next

- [Deployment modes](deployment-modes.md) -- the same chemistry in four
  delivery forms; only startup changes between them.
- [Validation](../intro/validation.md) -- where t_ign = 1.1075 ms comes
  from, and the gates behind it.
- [Known limitations](known-limitations.md) -- the edges this pattern runs
  inside: one thread, `Float64` arrays, and what to do about each.
