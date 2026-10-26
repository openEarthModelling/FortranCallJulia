# scripts/build_sysimage.jl
#
# Builds libfj_sysimage via PackageCompiler. Normally invoked by the CMake
# custom target `fj_sysimage` (root CMakeLists.txt with -DFJ_BUILD_SYSIMAGE=ON):
#
#   julia --project=scripts/sysimage_env scripts/build_sysimage.jl <output-path>
#
# ARGS[1] (required): output path of the sysimage. CMake passes
#   <build-dir>/libfj_sysimage<ext> (extension per platform).
#
# Prerequisite: the scratch environment scripts/sysimage_env must exist and be
# instantiated. One-time setup (run with the same Julia that embeds the image):
#
#   /path/to/julia-1.12.x scripts/install_sciml_env.jl

import Pkg

if isempty(ARGS)
    error("usage: julia --project=scripts/sysimage_env scripts/build_sysimage.jl <output-sysimage-path>")
end
output_path = abspath(ARGS[1])

project_root    = normpath(joinpath(@__DIR__, ".."))
package_path    = joinpath(project_root, "src", "FortranBridge")
precompile_path = joinpath(project_root, "scripts", "precompile.jl")
sysimage_env    = joinpath(project_root, "scripts", "sysimage_env")

isfile(joinpath(sysimage_env, "Project.toml")) || error(
    "sysimage env not found at $(sysimage_env); " *
    "run scripts/install_sciml_env.jl once before building")

# Build from the scratch env (FortranBridge is dev'd there as a path dep).
# Idempotent: a no-op when the env is already instantiated.
Pkg.activate(sysimage_env; io = devnull)
Pkg.instantiate()
using PackageCompiler

println("--- Building sysimage ---")
println("  project:         $sysimage_env")
println("  FortranBridge:   $package_path")
println("  precompile file: $precompile_path")
println("  output:          $output_path")

# Per the PackageCompiler docs, create_sysimage takes the packages as the
# first argument and resolves them against the `project` environment;
# FortranBridge is found through its path dependency in that env. Everything
# compiled by precompile_execution_file is traced into the image. FjKinetics
# rides along for the capstone chemistry (its own PrecompileTools workload --
# plain-array AND view-based step_chemistry! paths -- is baked in through its
# package cache, so the per-half-step call the Fortran driver evals never
# compiles at runtime).
create_sysimage(
    ["FortranBridge", "SciMLBase", "OrdinaryDiffEq", "FjKinetics"],
    project = sysimage_env,
    sysimage_path = output_path,
    precompile_execution_file = precompile_path,
    cpu_target = "native", # single-host embedding: bake the build host's ISA
)

println("--- Sysimage built at: $output_path ---")
