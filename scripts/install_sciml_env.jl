# scripts/install_sciml_env.jl
#
# One-time setup for the sysimage build (root CMakeLists with
# -DFJ_BUILD_SYSIMAGE=ON): creates and instantiates the scratch environment
# scripts/sysimage_env that the `fcj_sysimage` CMake target and
# scripts/build_sysimage.jl build from. As the second step it wires up the
# FjKinetics package's own environment (its Manifest is deliberately NOT
# tracked: dev-path entries point outside the repo), which Pkg.test() and
# example 08 need after a fresh clone.
#
# Run with the same Julia that embeds the sysimage (must be 1.12.x):
#
#   /path/to/julia-1.12.x scripts/install_sciml_env.jl

import Pkg

const PROJECT_ROOT      = normpath(joinpath(@__DIR__, ".."))
const FORTRANBRIDGE_PATH = joinpath(PROJECT_ROOT, "src", "FortranBridge")
const SYSIMAGE_ENV      = joinpath(@__DIR__, "sysimage_env")

# FjKinetics (capstone chemistry package) lives under the example dir
# (examples/07_capstone/FjKinetics) but this framework-level script still
# points at it: the sysimage embeds the capstone chemistry workload as part
# of the deployment recipe, so the scratch env dev's it alongside
# FortranBridge (the embedded runtime activates exactly one project).
const FJKINETICS_PATH = joinpath(PROJECT_ROOT, "examples", "07_capstone", "FjKinetics")

# ChemMechSim (full reaction mechanisms: GRI-Mech 3.0 via Cantera-YAML) is a
# FjKinetics v0.2 dependency tracked by dev path ONLY: the General registry
# carries v1.0.0 while the working repo is at v1.2.0. Default is the user's
# checkout; override with CHEMMECHSIM_PATH when relocating.
const CHEMMECHSIM_PATH = get(ENV, "CHEMMECHSIM_PATH",
                             joinpath(homedir(), "Project", "20260529_ChemSim",
                                      "ChemMechSim.jl"))

isfile(joinpath(FORTRANBRIDGE_PATH, "Project.toml")) ||
    error("FortranBridge package not found at $(FORTRANBRIDGE_PATH)")
isfile(joinpath(CHEMMECHSIM_PATH, "Project.toml")) ||
    error("ChemMechSim package not found at $(CHEMMECHSIM_PATH) " *
          "(set CHEMMECHSIM_PATH to your checkout)")

mkpath(SYSIMAGE_ENV)
Pkg.activate(SYSIMAGE_ENV; io = stdout)

# In-repo packages are tracked by path, not by registry: FortranBridge
# (bridge runtime) and FjKinetics (chemistry, pulls in the Catalyst/MTK
# stack for the sysimage). FjKinetics's [compat] pins the solve stack
# (OrdinaryDiffEq ~6.111): the 7.x line's step-size controller degrades the
# per-cell reinit!/step! pattern ~700x (a frozen cell costs 982 internal
# steps instead of 1), which is why this env must resolve through it.
# ChemMechSim's own [compat] pins the same Catalyst 16 / ODE 6 / SciMLBase 2
# lines, so the joint resolve is conflict-free.
Pkg.develop(path = FORTRANBRIDGE_PATH)
Pkg.develop(path = FJKINETICS_PATH)
Pkg.develop(path = CHEMMECHSIM_PATH)

# SciML solve stack baked into the sysimage; PrecompileTools for the
# precompile workload; PackageCompiler because build_sysimage.jl runs with
# this env active (--project=scripts/sysimage_env) and does
# `using PackageCompiler`.
Pkg.add(["SciMLBase", "OrdinaryDiffEq", "PrecompileTools", "PackageCompiler"])

Pkg.instantiate()
Pkg.precompile()
Pkg.status()
println("sysimage env ready at $(SYSIMAGE_ENV)")

# ---------------------------------------------------------------------------
# FjKinetics package env (examples/07_capstone/FjKinetics). Its Manifest is
# untracked on purpose (the ChemMechSim entry is a dev path outside this
# repo; a committed copy would break instantiate on any other machine).
# The [compat] pins in its Project.toml still govern the resolve; this step
# only wires the out-of-repo dev dependency so Pkg.test() and example 08
# work from a fresh clone.
# ---------------------------------------------------------------------------
Pkg.activate(FJKINETICS_PATH; io = stdout)
Pkg.develop(path = CHEMMECHSIM_PATH)
Pkg.instantiate()
Pkg.status()
println("FjKinetics env ready at $(FJKINETICS_PATH)")
