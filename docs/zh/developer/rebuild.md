---
title: 从零重建
sync: 2026-10-31
---

# 从零重建

仓库里有三样东西是*构建产物*而不是源码：SciML sysimage、AOT 化学库、
capstone 图集。三样都能在全新克隆上从零重生成——本页就是各自的配方，含
让重建保持老实的守卫与开关。路径一律相对仓库根；凡提到 Julia 二进制，用
钉死的 1.12.7 安装，不要用版本 shim（[教训](lessons.md)条目 1）。

前两步的共同前置是钉死的草稿环境 `scripts/sysimage_env`。
`scripts/install_sciml_env.jl` 装配它（把 FortranBridge 与动力学包 dev 进
去、经 `[compat]` 钉死解析）；用桥所内嵌的同一个 1.12.x Julia 跑它。

## 第一步：SciML sysimage

sysimage 是把 17.3 s 的 JIT 启动换成 1.90 s 加载的东西
（[交付形态](../user/deployment-modes.md)）。Julia 侧包的形状一变就要重
建它。两个入口、一个结果：

```text
    cmake -B build -DFJ_BUILD_SYSIMAGE=ON ...
    cmake --build build --target fcj_sysimage
```

配置步会跑版本守卫：`FJ_BUILD_SYSIMAGE` 只接受 1.12.x 的构建 Julia，否则
配置失败并给出明确信息——sysimage 被钉死在制作它的那个 Julia 构建与构建
主机的指令集上（`cpu_target = "native"`），所以它按设计就是单机产物。

烤进去什么由 `scripts/build_sysimage.jl` 决定。核心调用逐字如下：

```julia
create_sysimage(
    ["FortranBridge", "SciMLBase", "OrdinaryDiffEq", "FjKinetics"],
    project = sysimage_env,
    sysimage_path = output_path,
    precompile_execution_file = precompile_path,
    cpu_target = "native", # single-host embedding: bake the build host's ISA
)
```

`precompile_execution_file`（`scripts/precompile.jl`，加各包自带的
PrecompileTools 负载）追踪到的一切都进镜像——刻意包含 plain 数组与
`view` 两条 `step_chemistry!` 路径，使 Fortran 驱动每半步 eval 的那次调用
在运行时永不编译。预期一个大文件（这套 SciML 负载的镜像约 1 GB）与以几十
分钟计的构建。

## 第二步：AOT 化学库

生产形态的 AOT 构建住在 `examples/07_capstone/3_aot_kinetics/`：一个小
Julia 包（`KineticsAOT`）暴露 `Base.@ccallable` 内核，由 PackageCompiler
的 `create_library` 编译进一个自带运行时的 `dist/`。在该目录下用钉死
Julia 跑 `build_lib.jl`；其核心调用逐字如下（注释保留——它是用一次事故
换来的警告）：

```julia
create_library("KineticsAOT", "dist";
    lib_name = "libkinetics",
    force = true,
    header_files = ["kinetics.h"],
    incremental = false,
    filter_stdlibs = true,
    # LinearSolve (SciML closure) probes MKL_jll, a lazy artifact, at
    # image load -- without bundling it the library downloads ~570 MB
    # from the network on first init, breaking self-containedness.
    include_lazy_artifacts = true,
    precompile_execution_file = ["aot_precompile.jl"],
)
```

为它留预算：整个闭包的非增量代码生成以小时和几十 GB 编译器峰值内存计，
`dist/` 约 2.5 GB。自含性用老实的办法验证——在空 `JULIA_DEPOT_PATH` 与全
新 home 目录下初始化，确认零网络访问（[教训](lessons.md)条目 5）。并记
住同页的生命周期规则：消费方走库导出的 `init_julia`，绝不走 SDK 的
`julia_init`。

`examples/03_deployment/2_compiled_library/` 里的小兄弟（MyLib）以教程规
模演示同一模式；`dist/` 一旦存在，CMake 构建自动加它的 `MyLib` 目标。

## 第三步：capstone 图集

`examples/07_capstone/figures/` 下的图全部由一个脚本从五份 CSV 渲染；没
有任何图是手改的。流水线：

1. **生成数据。** 跑两个 capstone 可执行文件
   （`ex_capstone_reacting_flow`、`ex_capstone_gri_ignition`）与原生基准
   （`run_gri_native.jl`，钉死二进制——叠合桥与原生的那张图继承基准的运
   行时）。它们把 `output/*.csv` 写在示例旁。
2. **渲染。** 在 `examples/07_capstone/figures/` 下：

```text
    python3 plot_capstone.py
```

脚本的 `main()` 从 `../output/*.csv` 渲染整套图（fig1 到 fig8），画前断
言每份文件的列契约，PNG 与 PDF 双输出。缺 CSV 或 CSV 过期会响亮失败，而
不是画出空轴。每张图讲什么、被哪些 QA 规则约束，记录在
`examples/07_capstone/figures/FIGURES.md`。

## 改动之后的重建顺序

一句顺序上的实话：源码改动只向前传播。桥或 Fortran 改动需要普通重建加
验收门；Julia 侧包改动额外需要第一步（AOT 路径要紧的话再加第二步）；影
响数据的改动需要先重跑示例，第三步才画得出新东西。跳步不会响亮失败——
只会无声地画出错误运行的图。

## 接下来去哪

- [交付形态](../user/deployment-modes.md)——每样产物在运行时买到什么。
- [验收门](acceptance-gates.md)——这些重建之后该跑什么。
- [性能附件](annex-performance.md)——sysimage 与 AOT 构建赖以验证的那些
  测量。
