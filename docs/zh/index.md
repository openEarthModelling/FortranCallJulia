---
title: 在 Fortran 中嵌入 Julia 运行时
sync: 2026-10-31
---

![FortranCallJulia 徽标](../assets/logo.png)

把 Julia 运行时嵌入 Fortran 应用程序：Fortran 经 C 桥（`fcj_*` C ABI）调用
Julia，Julia 求解器再回调 Fortran——同一进程、零拷贝数组、每次调用都做异常检查。

从入门四页开始：

- [FortranCallJulia 是什么？](intro/what-is-this.md)——30 秒导览
- [为什么是 Fortran 与 Julia？](intro/why-fortran-julia.md)——动机与分工
- [架构](intro/architecture.md)——三个世界，附交互式架构图
- [验证](intro/validation.md)——三项硬指标及其出处

准备动手构建？继续前往[安装](user/installation.md)。

!!! note "双语站点"
    本文档以 English 与简体中文双语发布。使用顶栏的语言选择器切换。
