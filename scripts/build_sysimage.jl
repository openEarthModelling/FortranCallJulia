# scripts/build_sysimage.jl
using PackageCompiler

# Define paths
project_root = joinpath(@__DIR__, "..")
package_path = joinpath(project_root, "src", "FortranBridge")
precompile_path = joinpath(project_root, "scripts", "precompile.jl")
build_dir = joinpath(project_root, "build")

# Ensure build directory exists
if !isdir(build_dir)
    mkdir(build_dir)
end

# Define output path (extension could be detected, but forcing .so for Linux/this project)
lib_name = "libfj_sysimage.so"
output_path = joinpath(build_dir, lib_name)

println("--- Starting Sysimage Build ---")
println("Package:         $package_path")
println("Precompile run:  $precompile_path")
println("Output location: $output_path")

# Create the sysimage from the FortranBridge package (src/FortranBridge).
create_sysimage(
    :FortranBridge,
    project = package_path,
    sysimage_path = output_path,
    precompile_execution_file = precompile_path,
    cpu_target = PackageCompiler.default_app_cpu_target() # Ensure portability if needed
)

println("--- Build Complete ---")
println("Sysimage created at: $output_path")
