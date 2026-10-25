using PackageCompiler
using Pkg

println("Building MyLib library...")
println("Source: MyLib/")
println("Target: dist/")

# 1. 准备环境（先定位脚本目录再 activate：旧写法把相对名 "MyLib" 解析到
#    进程 CWD，只有恰好站在本目录运行才能成功）
cd(@__DIR__)
Pkg.activate("MyLib")
Pkg.instantiate()

# 2. 编译

create_library("MyLib", "dist";
    lib_name="libmylib",
    force=true,
    header_files=["MyLib/src/MyLib.jl"], 
    incremental=false,
    filter_stdlibs=true
)

println("Build complete.")
