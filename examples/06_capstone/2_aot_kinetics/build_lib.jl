using PackageCompiler
using Pkg

# AOT build for the capstone chemistry kernel (MyLib precedent,
# examples/03_deployment/2_compiled_library): a standalone shared library
# embedding FjKinetics and its Catalyst/MTK stack, exposing the batched
# chemistry step as Base.@ccallable C functions.
println("Building KineticsAOT library...")
println("Source: KineticsAOT/")
println("Target: dist/")

# 1. Environment: locate relative to THIS script, not the process CWD
#    (the MyLib lesson: activating a relative name resolves against CWD).
cd(@__DIR__)
Pkg.activate("KineticsAOT")
Pkg.instantiate()

# 2. Compile. incremental=false + filter_stdlibs = fully self-contained
#    library (deployment artifact; the perf report compares its startup
#    and per-call cost against the JIT and sysimage bridge modes).
create_library("KineticsAOT", "dist";
    lib_name = "libkinetics",
    force = true,
    header_files = ["KineticsAOT/src/KineticsAOT.jl"],
    incremental = false,
    filter_stdlibs = true,
    # LinearSolve (SciML closure) probes MKL_jll, a lazy artifact, at
    # image load -- without bundling it the library downloads ~570 MB
    # from the network on first init, breaking self-containedness.
    include_lazy_artifacts = true,
    precompile_execution_file = ["aot_precompile.jl"],
)

println("Build complete.")
