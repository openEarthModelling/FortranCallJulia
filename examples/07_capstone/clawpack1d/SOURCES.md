# Vendored: Clawpack classic 1D kernel

Frozen copy of the 1D wave-propagation kernel from Clawpack classic, used as
the transport engine of the reacting-flow capstone example. Files are kept
**byte-identical to upstream** (no reformatting, no edits) so they stay
diff-able against their source; application-layer derivations (e.g. the
4-equation reacting Riemann solver) live next to the example, not here.

| File | Upstream path |
|---|---|
| `step1.f90` | https://github.com/clawpack/classic `src/1d/step1.f90` @ 5.14.0 |
| `limiter.f90` | https://github.com/clawpack/classic `src/1d/limiter.f90` @ 5.14.0 |
| `philim.f90` | https://github.com/clawpack/classic `src/1d/philim.f90` @ 5.14.0 |
| `bc1.f` | https://github.com/clawpack/classic `src/1d/bc1.f` @ 5.14.0 |
| `rp1_euler_with_efix.f90` | https://github.com/clawpack/riemann `src/rp1_euler_with_efix.f90` @ master (fetched 2026-10-26) |
| `LICENSE` | https://github.com/clawpack/classic `LICENSE` @ 5.14.0 (BSD 3-Clause, Clawpack Developers 1994-2018) |

Not vendored (deliberately):

- `claw1.f` / `claw1ez.f` — the classic time loop. Our Fortran driver owns the
  time loop; that is the point of the example (operator splitting around
  `step1`, with the source half-step crossing the bridge into Julia). This
  also matches classic's own design: `step1` never calls the source routine;
  splitting is done by the loop.
- `copyq1.f`, `inlinelimiter.f90` — unused by this application.

Notes for this build:

- Compiled as a static library with GNU Fortran `-fno-underscoring` to match
  the in-tree examples that link it (`bc1` is fixed-form, everything else is
  free-form).
- `rp1_euler_with_efix.f90` reads `gamma` from `common /cparam/`; the driver
  sets it. It solves the 3-equation (pure Euler) system and is used directly
  by the Sod validation mode. The reacting mode uses an app-layer derivation
  of it (passive species as a 4th wave family at contact speed) kept under
  `examples/07_capstone/`.
