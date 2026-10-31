# examples/07_capstone/run_gri_native.jl
#
# Native baseline for the bridge acceptance test (examples/07_capstone/
# gri_ignition.f90): the SAME FjKinetics call path as the Fortran example,
# run directly by julia -- no bridge, no Fortran. The ignition delay the
# example recomputes in Fortran from extracted arrays must reproduce this
# run to rel diff < 1e-8.
#
# Run from build/examples (that is also where the .dat is read by default):
#
#   cd build/examples
#   julia --project=../../scripts/sysimage_env \
#       ../../examples/07_capstone/run_gri_native.jl
#   ./ex_capstone_gri_ignition
#
# Output files:
#   gri_native.dat (FJ_GRI_NATIVE_OUT overrides) -- one line
#     "t_ign_seconds T_end_K X_CH4_t0 X_CO2_tend"
#   the two mole-fraction spot values anchor the 4x2001 X matrix extraction
#   (layout-sensitive: they pin species row 1 at grid point 1 and species row
#   3 at the last grid point, the hand-checked column-major indexing in the
#   Fortran example)
#   output/gri_native_series.csv (FJ_GRI_NATIVE_SERIES overrides) -- the full
#   native trajectory, same CSV convention as the Fortran drivers ('#'
#   metadata lines + column-name row); figures/plot_capstone.py overlays it
#   on the bridge run's gri_ignition.csv (fig: bridge vs native)
using FjKinetics

const OUT = get(ENV, "FJ_GRI_NATIVE_OUT", "gri_native.dat")
const SERIES_OUT = get(
    ENV, "FJ_GRI_NATIVE_SERIES",
    joinpath(@__DIR__, "output", "gri_native_series.csv"),
)

gs = build_gri30_kinetics()
println("native run: $(gs.nspec)-species mechanism from $(basename(gs.yaml_path))")
r = run_gri_ignition(gs)
open(OUT, "w") do io
    println(io, r.t_ign, " ", r.T_end, " ", r.X[1, 1], " ", r.X[3, end])
end
mkpath(dirname(abspath(SERIES_OUT)))
open(SERIES_OUT, "w") do io
    println(io, "# GRI-Mech 3.0 ignition (native Julia run): stoich CH4/air, ",
              "1500 K, 1 atm, constant volume")
    println(io, "# t_ign_s = ", r.t_ign, ", T_end_K = ", r.T_end)
    println(io, "t_s,T_K,X_CH4,X_O2,X_CO2,X_OH")
    for i in eachindex(r.ts)
        println(io, join((r.ts[i], r.T[i], r.X[1, i], r.X[2, i],
                          r.X[3, i], r.X[4, i]), ","))
    end
end
println("native: t_ign = $(round(r.t_ign * 1e3, digits=4)) ms, ",
        "T_end = $(round(r.T_end, digits=1)) K -> $OUT, $SERIES_OUT")
