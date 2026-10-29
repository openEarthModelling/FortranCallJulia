# examples/08_gri_ignition/run_native.jl
#
# Native baseline for the bridge acceptance test (examples/08_gri_ignition/
# gri_ignition.f90): the SAME FjKinetics call path as the Fortran example,
# run directly by julia -- no bridge, no Fortran. The ignition delay the
# example recomputes in Fortran from extracted arrays must reproduce this
# run to rel diff < 1e-8.
#
# Run from build/examples (that is also where the .dat is read by default):
#
#   cd build/examples
#   julia --project=../../scripts/sysimage_env \
#       ../../examples/08_gri_ignition/run_native.jl
#   ./ex_gri_ignition
#
# Output file (FJ_GRI_NATIVE_OUT overrides): one line
#   "t_ign_seconds T_end_K X_CH4_t0 X_CO2_tend"
# the two mole-fraction spot values anchor the 4x2001 X matrix extraction
# (layout-sensitive: they pin species row 1 at grid point 1 and species row 3
# at the last grid point, the hand-checked column-major indexing in the
# Fortran example)
using FjKinetics

const OUT = get(ENV, "FJ_GRI_NATIVE_OUT", "gri_native.dat")

gs = build_gri30_kinetics()
println("native run: $(gs.nspec)-species mechanism from $(basename(gs.yaml_path))")
r = run_gri_ignition(gs)
open(OUT, "w") do io
    println(io, r.t_ign, " ", r.T_end, " ", r.X[1, 1], " ", r.X[3, end])
end
println("native: t_ign = $(round(r.t_ign * 1e3, digits=4)) ms, ",
        "T_end = $(round(r.T_end, digits=1)) K -> $OUT")
