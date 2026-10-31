---
title: 安装
sync: 2026-10-31
---

# 安装

FortranCallJulia 在 Linux 上用 gfortran、gcc 与 CMake 构建，在进程内嵌入钉死的
Julia 1.12.7 运行时。C 桥、双层 Fortran SDK、Julia 侧运行时包
（`FortranBridge.jl`）全部来自本仓库——没有别的东西需要下载。下表中有两项是
承重钉死；表格之后的几节解释它们为什么不可协商。

## 版本矩阵

| 组件 | 版本 | 说明 |
|---|---|---|
| 操作系统 | Linux | 验收套件跑过的唯一平台。 |
| 编译器 | gfortran + gcc | GNU 专属旗标（`-fno-underscoring`）在 CMake 中按编译器门控。 |
| CMake | 3.13 及以上 | 驱动桥、SDK 与示例的构建。 |
| Julia | **1.12.7，钉死** | 被嵌入的 `libjulia`；见下一节。 |
| Catalyst | `~16.2`（主版本 16） | 经 `FjKinetics.jl` 的 `[compat]` 钉死。 |
| OrdinaryDiffEq | `~6.111`（主版本 6） | 钉死；7.x 线是实测约 700 倍的回归。 |
| SciMLBase | `~2.155`（主版本 2） | 与上两条一同钉死。 |
| ChemMechSim.jl | **v1.2.0** | 开源；本文档所有验证数字所用版本。 |

只有前四行是构建并运行 basics 示例所必需的。SciML 钉死与 ChemMechSim 在你
构建 sysimage 或化学 capstone（`examples/07_capstone`）时才登场。

## Julia 1.12.7，为什么钉死

桥在进程内嵌入 `libjulia` 1.12.7，而每一道验收基线都必须跑完全相同的版本——
运行时不同，比对就没有意义。这个钉死不是装饰性的。本项目开发期间，一个
`juliaup` shim 悄悄漂移到了更新的次版本，比对基线跟着 shim 走，版本失配伪装
成了一次桥接回归：一场针对从未坏过的代码的排障。自那以后版本被钉死并被主动
检查——sysimage 构建在非 Julia 1.12.x 下直接拒绝运行。

安装一个自含的 Julia 1.12.7，并确认 `PATH` 上的 `julia` 解析到它：

```bash
julia --version        # 必须报告：julia version 1.12.7
```

用 juliaup 的话，显式钉住默认版本——shim 的默认值可能在你不知情时改变：

```bash
juliaup add 1.12.7
juliaup default 1.12.7
julia --version
```

直接用 tarball 安装同样可以。无论走哪条路：之后构建任何要加载的 sysimage 都
必须用同一个二进制（见[交付形态](deployment-modes.md)）。

## SciML 栈，compat 钉死

`examples/07_capstone/FjKinetics/Project.toml` 通过 `[compat]` 钉住求解栈：
Catalyst `~16.2`、OrdinaryDiffEq `~6.111`、SciMLBase `~2.155`——即主版本
16 / 6 / 2 三条线。让 resolve 走这些钉死，不要强行升级越过它们。理由是实测
的，不是审美：在栈未钉死时，一次 resolve 曾漂到 OrdinaryDiffEq 7.x 线，其步
长控制器让每网格单元的 `reinit!`/`step!` 模式退化约 700 倍（一个冻结单元花
几百步内部步进，而不是一步）。钉死写在包里，正常的 resolve 会遵守；只有强行
升级才会破坏它。

一次性环境搭建有脚本。`scripts/install_sciml_env.jl` 创建 scratch 环境
`scripts/sysimage_env`，把仓库内包 dev 进去（`FortranBridge.jl`、
`FjKinetics.jl` v0.2，加上 ChemMechSim——见下一节），添加 SciML 栈，然后再
接好 `FjKinetics` 自己的包环境。用同一个钉死的 Julia 运行它：

```bash
julia scripts/install_sciml_env.jl
```

## ChemMechSim.jl

ChemMechSim.jl 提供机理输入——GRI-Mech 3.0，53 物种、325 反应——已开源，
可当普通 Julia 包安装：

```julia
import Pkg
Pkg.add("ChemMechSim")
Pkg.status("ChemMechSim")
```

**本文档所有验证数字均以 v1.2.0 产生。** General registry 可能滞后于仓库
（仓库已到 v1.2.0 时，registry 还停留在 v1.0.0）。若 `Pkg.status` 报告的版本
更旧，请改从仓库 checkout 安装打了 tag 的 v1.2.0：

```julia
Pkg.develop(path="<你的 ChemMechSim.jl checkout>")   # 位于 tag v1.2.0
```

`scripts/install_sciml_env.jl` 期待这样一个 checkout，并把它 dev 进它搭建的
两个环境；若你的 checkout 不在默认位置，运行脚本前把 `CHEMMECHSIM_PATH` 指
向它。无论哪种装法，在把自己的结果与验证数字对照之前，先在
`scripts/sysimage_env` 里确认版本。

## 构建

在本仓库的 checkout 中：

```bash
mkdir build && cd build
cmake -DBUILD_EXAMPLES=ON ..
make -j8
./examples/ex01_quickstart
```

configure 阶段 CMake 在 `PATH` 上找 `julia`——找不到会立刻给出明确的报错
——并向 `julia-config.jl` 询问与你的 Julia 构建匹配的 C 旗标与链接旗标。构建
产出 `libfcj_middleware.a`（8 个 C 桥源文件加 2 个 Fortran SDK 源文件），
静态链入每个示例可执行文件；`FortranBridge` 运行时目录与 `examples_lib.jl`
被拷贝到可执行文件旁边，因此示例从任何工作目录都能运行。

可选的 sysimage 构建把 SciML 冷启动从 17.3 s 降到 1.90 s：

```bash
julia scripts/install_sciml_env.jl    # 一次性；见上文 SciML 一节
cmake -DFJ_BUILD_SYSIMAGE=ON ..
make fcj_sysimage                     # 数分钟；首次运行有下载
```

## 接下来去哪

- [第一次调用](first-call.md)——最小程序逐行讲解。
- [两套 SDK，两种速度](two-sdks.md)——在两层之间如何选择。
