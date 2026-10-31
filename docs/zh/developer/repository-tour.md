---
title: 仓库导览
sync: 2026-10-31
---

# 仓库导览

先给你地图，再看地形。本页从仓库顶层走到真正要紧的文件，说明每块东西是
干什么的，并指向深入讲它的页面。这里读一遍即可；之后用站内搜索就够了。

## 顶层一览

| 条目 | 是什么 |
|---|---|
| `src/bridge/` | 桥的 C 心脏：8 个文件、约 100 个导出的 `fcj_*` 符号（[桥内部](bridge-internals.md)） |
| `src/FortranBridge/` | Julia 侧包：`FortranBridge.jl` 之下的 5 个子模块 |
| `src/julia_binding.f90` | `julia_low_level`：覆盖 `fcj_*` C ABI 的 `bind(c)` 真相本体 |
| `src/julia_sdk.f90` | `julia_high_level`：`type(JuliaValue)`、装箱、转换器、`%to_fortran` |
| `src/lib_support/` | Fortran 支撑类型与 AOT 库接口声明 |
| `examples/` | 7 个编号示例族，`01_basics` 到 `07_capstone`，另有 `legacy/` |
| `scripts/` | 环境装配、sysimage 构建、预编译负载、文档工具 |
| `docs/` | 本双语 MkDocs 站点（`en` 默认，`zh` 镜像） |
| `tests/` | 站点双语对拍测试（`test_docs_parity.py`）——文档门，不是物理门 |
| `CMakeLists.txt` | 构建：`fcj_middleware` 静态库、示例、`FJ_BUILD_SYSIMAGE` |
| `README.md` | 项目概览、构建配方、Fast Path 契约 |
| `plan.md` | 滚动开发日志：每一波、每次事故与决策，带日期 |
| `embedding.md` | 从 C 嵌入 Julia 的精选笔记，附第三方指引 |
| `requirements*.txt` | 文档构建（`-docs`）与开发工具（`-dev`）的 Python 依赖 |

## `src/`：三种语言写成的桥

**`src/bridge/`——C。** 可嵌入核心。8 个 `.c` 文件分四个职责组：核心生命
周期（`core.c`、`memory.c`）、分发与装箱（`dispatch.c`、`types.c`）、数组
通道（`arrays.c`、`extract.c`）、回调访问（`callbacks.c`、`accessors.c`）。
两个头文件划定界面：`bridge.h` 是公共契约（53 个 `fcj_` 函数加
`fcj_options_t`），`bridge_internal.h` 是私有的（原生元素访问器、各模块清
缓存钩子）。维护者需要的一切都在[桥内部](bridge-internals.md)。

**`src/FortranBridge/`——Julia。** 嵌入运行时加载的包。`src/FortranBridge/
src/FortranBridge.jl` 之下有五个子模块：

| 子模块 | 职责 |
|---|---|
| `GCManager.jl` | Julia 侧根注册表（`Main.FJ_ROOTS` 回退路径、引用计数） |
| `FunctionRegistry.jl` | 名字到函数的注册表、Fast Path 的 `@cfunction` 蹦床 |
| `Accessors.jl` | `%element` 与 `%property` 背后的 `getfield` / `getproperty` 助手 |
| `Callbacks.jl` | 把 Fortran `bind(c)` 子程序包装成 Julia 可调用对象 |
| `Utilities.jl` | 共用小工具 |

**`src/julia_binding.f90` 与 `src/julia_sdk.f90`——Fortran。** 即
[两套 SDK，两种速度](../user/two-sdks.md)的两层：低层 `bind(c)` 声明（58
个符号），与建在其上的高层 OOP 层。`src/lib_support/` 放 `julia_types.f90`
（支撑类型）和 `julia_library_interface.f90`——AOT 示例链接的
`init_julia` / `shutdown_julia` 声明（[交付形态](../user/deployment-modes.md)）。

## `examples/`：编号阶梯

每个家族都比上一个更进一步；编号同时就是推荐阅读顺序。

| 家族 | 内容 | 演示什么 |
|---|---|---|
| `01_basics` | hello world、quickstart、数组、零拷贝数组、数据结构 | 第一次调用、数组通道 |
| `02_intermediate` | 数学运算、关键字参数 | `%call` 变体、`fcj_call_kwargs` |
| `03_deployment` | init 选项、自定义 sysimage、`2_compiled_library/` | 启动控制、AOT |
| `04_performance` | JIT vs AOT、调用开销、内存搬运、访问模式、基准套件 | ~815 ns / ~3.8 ns 数字的出处 |
| `05_hpc_parallel` | 多线程（10 万个包装矩阵、一次调用）、MPI 引导 | 单线程规则内的批量化 |
| `06_sciml` | 回调、批量取数、SciML demo | 跨桥的 OrdinaryDiffEq |
| `07_capstone` | 反应流、GRI 点火、`3_aot_kinetics/`、`FjKinetics/`、`figures/`、`PERFORMANCE.md` | 一切合体，外加验收门 |

`examples/legacy/` 保留包化之前的十个示例（`01_hello.f90` ...
`10_external_script.f90`）供考古；没有任何东西链接它们。
`examples/CMakeLists.txt` 为每个编号源文件构建一个可执行文件，把 Julia 运
行时和项目拷到可执行文件旁，并在 `dist/` 存在时加入 `MyLib` AOT 演示。

## `scripts/`：维护工具

| 文件 | 角色 |
|---|---|
| `install_sciml_env.jl` | 创建 `scripts/sysimage_env` 并把钉死的 SciML 栈装配进去 |
| `build_sysimage.jl` | PackageCompiler `create_sysimage`，覆盖 FortranBridge + SciMLBase + OrdinaryDiffEq + FjKinetics |
| `precompile.jl` | 被追踪进 sysimage 的预编译负载 |
| `docs_parity.py`、`docs_leak_patterns.txt` | 本站要过的双语对拍与泄漏门 |

前三个脚本背后的钉死环境故事见[从零重建](rebuild.md)；钉死为什么存在，见
[教训](lessons.md)。

## `docs/`、`tests/` 与站点门

`docs/` 放 `en/`（默认语言）与 `zh/`（镜像），外加被排除在站点外的
`superpowers/` 工作笔记。`tests/test_docs_parity.py` 驱动
`scripts/docs_parity.py`：每个页面必须在两个语言下都存在、标题已翻译、
`sync` 戳一致，且任何页面都不得泄漏机器特征串（本机路径、主机名）——也
正是散文页写作时遵守的同一条脱敏规则。

## 接下来去哪

- [桥内部](bridge-internals.md)——8 个 C 文件，一组一组，真代码摆在眼前。
- [验收门](acceptance-gates.md)——在这里"正确"意味着什么，改动之后如何
  重新证明。
- [贡献指南](contributing.md)——把一次导览变成一个 pull request。
