---
title: Validation
sync: 2026-10-31
---

# Validation

Every headline number on this site comes from an acceptance gate that was
actually run, not from design intent. Three gates anchor the project. Each
one compares the bridge against an independent baseline, and each one only
counts when both sides run the **same pinned Julia 1.12.7** -- a comparison
across Julia versions measures version drift, not the bridge.

## Gate 1: CJ detonation speed

The reacting-flow capstone (`reacting_flow`) simulates a Chapman--Jouguet
detonation: a Fortran Euler driver with a vendored Clawpack kernel, coupled
to Catalyst chemistry through Strang splitting.

| Quantity | Value |
|---|---|
| Simulated CJ speed | 7.12391 |
| Analytic CJ speed | 7.12470 |
| Deviation | **0.011%** |

The simulated wave speed agreeing with the analytic CJ value to four digits
means the operator splitting, the bridge crossings inside it, and the Julia
chemistry integrator all conserve the physics to within discretization error.

## Gate 2: bridge vs native, four gates, zero deviation

The GRI ignition case (`gri_ignition`) is run twice: once through the bridge
and once as a native Julia baseline. Four acceptance gates compare the
outputs.

| Setting | Result |
|---|---|
| Julia version, both sides | 1.12.7 (pinned) |
| Gates compared | 4 |
| Deviations found | **0** |
| Residuals | < 1e-12 |

Residuals below 1e-12 are at the level where floating-point non-associativity
ends and exact agreement begins: the bridge changes nothing about the
arithmetic.

!!! note "Why the pin is part of the metric"
    An earlier comparison run once failed for a reason that had nothing to
    do with the bridge: a version shim silently resolved to a different
    Julia minor version than the one the bridge embeds, and the baseline
    drifted. Since then, both sides of every comparison are pinned to the
    same 1.12.7 binary.

## Gate 3: GRI ignition delay

The same machinery computes the ignition delay of a homogeneous GRI-Mech 3.0
mixture (53 species, 325 reactions):

- **t_ign = 1.1075 ms**, taken as `argmax |dT/dt|` -- the time of maximum
  heat-release rate, the standard sharp definition that does not depend on a
  threshold convention.

A physically meaningful ignition delay from a 325-reaction network is an
end-to-end check: mechanism parsing (`ChemMechSim.jl`, open source; this
validation used v1.2.0), network construction (Catalyst), stiff integration
(OrdinaryDiffEq), and the data path back into Fortran arrays.

## Summary

| Metric | Value | Gate |
|---|---|---|
| CJ detonation speed | 7.12391 vs 7.12470, 0.011% off | `reacting_flow`, Clawpack1d + Strang splitting |
| Bridge vs native | 4 gates, 0 deviations, residuals < 1e-12 | `gri_ignition`, both sides on 1.12.7 |
| GRI ignition delay | t_ign = 1.1075 ms (argmax abs(dT/dt)) | `gri_ignition`, GRI-Mech 3.0 via ChemMechSim.jl v1.2.0 |

Reproduction steps, timing methodology, and the deployment-mode ladder
(JIT 17.3 s -> sysimage 1.90 s -> AOT first call ~12 μs) are covered in the
[User Guide](../user/deployment-modes.md) and the developer annexes.
