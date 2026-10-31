---
title: 延伸阅读
sync: 2026-10-31
---

# 延伸阅读

本站讲这座桥。下面的链接是维护者真会想在第二个标签页里开着的上游资源
——我们嵌入的机制的官方手册、我们用来构建的打包工具、验证问题背后的领
域参考。每条都注明它支撑本站哪一页。（其中部分文档在主检出里留有本地镜像
供离线使用；但该镜像不入库、也不随站点发布，所以这里的每个链接都指向活的
上游。）

## 从 C 嵌入 Julia

- [Embedding Julia——Julia 手册](https://docs.julialang.org/en/v1/manual/embedding/) --
  `jl_init`、GC 根（`JL_GC_PUSH`）、`jl_call`、`julia-config.jl` 嵌入流程
  的权威参考。[桥内部](bridge-internals.md)的一切都建在这一页加
  `julia.h` 头文件之上。
- [Julia 官方文档](https://docs.julialang.org/en/v1/) -- Julia 侧包依赖的
  语言语义从这里查起。
- [juliaup](https://github.com/JuliaLang/juliaup) -- 其自动更新 shim 促成
  了[教训](lessons.md)中钉死纪律的版本管理器。把任何构建指向一个实为
  shim 的 `julia` 之前，先读它的 channel 文档。

## PackageCompiler：sysimage 与 AOT 库

- [PackageCompiler.jl 文档](https://julialang.github.io/PackageCompiler.jl/stable/) --
  [从零重建](rebuild.md)两条配方背后的手册。
- [Sysimages](https://julialang.github.io/PackageCompiler.jl/stable/sysimages.html) --
  `create_sysimage` 追踪什么、烤进什么；镜像为何钉死在一个 Julia 构建与
  一个 `cpu_target` 上。
- [Building libraries](https://julialang.github.io/PackageCompiler.jl/stable/libs.html) --
  `create_library`、`Base.@ccallable`，以及 AOT 示例遵循的 `init_julia`
  契约。
- [PackageCompiler.jl 仓库](https://github.com/JuliaLang/PackageCompiler.jl) --
  issue 与发行说明；`include_lazy_artifacts` 行为的追踪处。

## 化学背后的 SciML 栈

- [DifferentialEquations.jl 文档](https://docs.sciml.ai/DiffEqDocs/stable/) --
  求解器套件；每格 `reinit!` / `step!` 模式的性能退化就是
  [教训](lessons.md)条目 2。
- [Catalyst.jl 文档](https://docs.sciml.ai/Catalyst/stable/) -- 钉死栈里的
  反应网络建模层。
- [OrdinaryDiffEq.jl](https://github.com/SciML/OrdinaryDiffEq.jl) 与
  [SciMLBase.jl](https://github.com/SciML/SciMLBase.jl) -- `[compat]` 钉死
  载重的求解器与问题接口包。
- [SciML](https://sciml.ai/) -- 生态总览站。

## 验证问题的领域参考

- [GRI-Mech 3.0](http://www.me.berkeley.edu/gri_mech/) -- 天然气燃烧的
  53 物种、325 反应机理，[验收门](acceptance-gates.md)点火延迟基准的来
  源。
- [Cantera](https://cantera.org/) -- ChemMechSim 加载的 YAML 机理格式；
  交叉核对机理数据的参考工具链。
- [Clawpack](https://www.clawpack.org/) -- 守恒律 / 有限体积方法；反应流
  capstone 所借鉴的波传播求解器的学术源头。

## 仓库相邻的工具

- [Preferences.jl](https://juliapackaging.github.io/Preferences.jl/stable/) --
  Julia 包如何按环境持久化设置；凡构建行为随环境不同，就会用到。
- [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) -- Julia 标
  准文档生成器；与本 MkDocs 站对照惯例的参照点。

## 接下来去哪

没有下游了——你已经到书架跟前。回到[开发者指南](repository-tour.md)，
或看本站自己的[验证故事](../intro/validation.md)。
