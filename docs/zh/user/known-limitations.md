---
title: 已知限制
sync: 2026-10-31
---

# 已知限制

四条边界，如实道来。没有一条是藏在这里的新闻——线程规矩与数组类型早在
[数组与回调](arrays-and-callbacks.md)里就塑造了你遇到的那些模式——但本页把
诚实的清单收在一处：每条边界是什么、代价几何、今天管用的做法是什么。

| # | 限制 | 今天管用的做法 |
|---|---|---|
| 1 | 桥调用全部钉死在 init 线程 | 批量：一次调用、全部网格 |
| 2 | 数组通道只有 `Float64` / `ComplexF64` | 批量数据放 `real(c_double)`；标量不受限 |
| 3 | 以 Linux + gcc/gfortran 为中心 | 不做任何其他声明 |
| 4 | 没有 `ctest` 自动化 | 手工跑示例验收门 |

## 1. 所有桥调用都钉死在 init 线程上

每进程一个运行时，由调用线程上的 `fcj_init` / `fcj_init_ex` 初始化——此后
每一次 `fcj_*` 调用（wrap、取数、eval、回调调用）都必须留在同一条线程上。
直白的后果：**OpenMP 并行一头撞墙。** 一个循环体跨桥的
`!$omp parallel do`，等于从非 init 线程发起调用，这在桥支持的范围之外。
`fcj_shutdown` 之后也不支持重新初始化：每进程一个生命周期。

管用的做法是把并行方向反过来。把所有网格打进一个包装好的缓冲，只发一次
调用；循环由 Julia 来做，用你在 init 时要的线程数
（`julia_init_ex(nthreads=N)`）。这就是
`examples/05_hpc_parallel/1_multithreading.f90` 的全部设计——10 万个矩阵
一次包装、一次调用——也是 capstone 化学的做法：每个 Strang 半步一次批量
`step_chemistry!`（[自带动力学](bring-your-own-kinetics.md)）。不跨桥的
Fortran 侧线程区域则一切照旧。

## 2. 数组通道只承载 `Float64` 与 `ComplexF64`

零拷贝通道的元素类型恰好两种。wrap 只收连续的 `real(c_double)` 内存；
`%to_fortran` 只填 `real` 或 `complex` 缓冲。整型数组或 `Float32` 数组不能
wrap——中间没有转换层，因为这条通道的意义就是什么都不转换。

标量不受此限：每种标量类型都能装箱（[两套 SDK，两种速度](two-sdks.md)）。
所以应对之策不过是常规的 Fortran 卫生：批量数值数据放进
`real(c_double)` 的 target——通常本来就在——零碎的小东西按标量过桥。

## 3. 以 Linux + gcc/gfortran 为中心

桥在 Linux 上开发与验证，用 CMake 构建、gcc/gfortran 编译、说标准的
`bind(c)`。这里没有任何东西在 macOS 或 Windows 上、在非 GNU 编译器下、在钉
住的 1.12.x 线之外的 Julia 构建上测试过。标准的 `bind(c)` 与
`iso_c_binding` 意味着它在别处多半也能跑——但本站不为没有真跑过的东西做任何
声明。

## 4. 没有 `ctest` 自动化

验收门是真的，但是手工的。它们是会打印响亮 PASS 哨兵串
（`EX_CAPSTONE_GRI_IGNITION_PASS` 及其同侪）、失败时非零退出的示例可执行
文件——而 `ctest` 一个都不驱动。你改了桥，就自己跑门：构建示例、运行、盯住
哨兵串。门在查什么，见[验证](../intro/validation.md)；完整清单铺在开发者的
[验收门](../developer/acceptance-gates.md)一页。

## 接下来去哪

- [自带动力学](bring-your-own-kinetics.md)——安然活在第 1、2 条限制之内的
  批量化学模式。
- [验证](../intro/validation.md)——尽管有这些限制，什么被验证过了。
- [桥内部](../developer/bridge-internals.md)——这些边界从何而来。
