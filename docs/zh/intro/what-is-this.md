---
title: FortranCallJulia 是什么？
sync: 2026-10-31
---

# FortranCallJulia 是什么？

FortranCallJulia 把 Julia 运行时嵌入 Fortran 应用程序——同一进程、同一可执行文件。Fortran 代码经由一层薄 C 桥（`fcj_*` C ABI，约 105 个符号）调用 Julia；Julia 再通过 `@cfunction` 蹦床回调 Fortran，于是一个 `bind(c)` Fortran 子程序可以直接充当 OrdinaryDiffEq 积分的右端项。

三个世界共同编入最终二进制：

| 世界 | 内容 |
|---|---|
| Fortran | 应用本体：驱动器、水力学、主循环。示例 01--07，由双层 SDK（`julia_high_level` / `julia_low_level`）封装。 |
| C 桥 | `src/bridge`——8 个 C 源文件编成 `fcj_middleware.a`。负责 GC 根集、参数装箱、数组、回调、错误检查。 |
| Julia | `libjulia` 1.12.7（钉死）、`FortranBridge.jl`、`FjKinetics.jl` v0.2、compat 钉死的 SciML 栈、`ChemMechSim.jl`。 |

## 能用它做什么

- **从 Fortran 调 Julia。** 求值表达式、带关键字参数调用函数、装箱任意类型的标量——全部通过 `bind(c)` 声明的 `fcj_*` 调用完成，构建树里不出现任何生成代码。
- **数组零拷贝传递。** N 维 Fortran 数组原地包装成 Julia 数组；结果零拷贝回流，或经批量取数接口返回（`%to_fortran` 一次调用拷回整个稠密数组）。
- **从 Julia 调 Fortran。** `julia_callback` 把 `bind(c)` 子程序包装成 Julia 可调用对象——例如被 OrdinaryDiffEq 消费的 ODE 右端项。
- **选择交付形态。** 同一份源码可按 JIT、sysimage 或 AOT 方式运行，见[交付形态](../user/deployment-modes.md)。
- **响亮地失败。** 每次桥调用都做异常检查；失败经 `get_last_error_message()` 报出，而不是悄悄退化成错误答案。

## 定义本项目的数字

- **开销。** Fast Path 调用（裸 C 函数指针，面向紧循环）约 **3.8 ns**，泛型调用路径约 **815 ns**（10 万次迭代平均）。
- **启动阶梯。** JIT 冷启动到首个结果 **17.3 s**；sysimage 降到 **1.90 s**；AOT 版本首次调用约 **12 μs**，逼近原生基线。
- **正确性。** CJ 爆速 **7.12391**，解析值 **7.12470**（偏差 0.011%）；桥接对原生在四道验收门上 **0 偏差**；GRI 点火延迟 **t_ign = 1.1075 ms**。出处与背景见[验证](validation.md)。

## 接下来去哪

- [为什么是 Fortran 与 Julia？](why-fortran-julia.md)——动机，以及两种语言的分工。
- [架构](architecture.md)——三个世界的细节，附交互式架构图。
- [验证](validation.md)——每个硬数字的来源。
- 准备动手构建？从[安装](../user/installation.md)开始。
