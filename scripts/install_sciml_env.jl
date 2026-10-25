# scripts/install_sciml_env.jl
#
# One-time setup for the sysimage build (root CMakeLists with
# -DFJ_BUILD_SYSIMAGE=ON): creates and instantiates the scratch environment
# scripts/sysimage_env that the `fj_sysimage` CMake target and
# scripts/build_sysimage.jl build from.
#
# Run with the same Julia that embeds the sysimage (must be 1.12.x):
#
#   /path/to/julia-1.12.x scripts/install_sciml_env.jl

import Pkg

const PROJECT_ROOT      = normpath(joinpath(@__DIR__, ".."))
const FORTRANBRIDGE_PATH = joinpath(PROJECT_ROOT, "src", "FortranBridge")
const SYSIMAGE_ENV      = joinpath(@__DIR__, "sysimage_env")

isfile(joinpath(FORTRANBRIDGE_PATH, "Project.toml")) ||
    error("FortranBridge package not found at $(FORTRANBRIDGE_PATH)")

mkpath(SYSIMAGE_ENV)
Pkg.activate(SYSIMAGE_ENV; io = stdout)

# FortranBridge is an in-repo package: track it by path, not by registry.
Pkg.develop(path = FORTRANBRIDGE_PATH)

# SciML solve stack baked into the sysimage; PrecompileTools for the
# precompile workload; PackageCompiler because build_sysimage.jl runs with
# this env active (--project=scripts/sysimage_env) and does
# `using PackageCompiler`.
Pkg.add(["SciMLBase", "OrdinaryDiffEq", "PrecompileTools", "PackageCompiler"])

Pkg.instantiate()
Pkg.precompile()
Pkg.status()
println("sysimage env ready at $(SYSIMAGE_ENV)")
