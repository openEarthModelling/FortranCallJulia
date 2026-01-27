using PackageCompiler
using Pkg

println("Building MyLib library...")
println("Source: MyLib/")
println("Target: dist/")

# 1. 准备环境
Pkg.activate("MyLib")
Pkg.instantiate()

# 2. 编译
cd(@__DIR__)

create_library("MyLib", "dist";
    lib_name="libmylib",
    force=true,
    header_files=["MyLib/src/MyLib.jl"], 
    incremental=false,
    filter_stdlibs=true
)

println("Build complete.")
