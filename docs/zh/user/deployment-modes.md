---
title: 交付形态
sync: 2026-10-31
---

# 交付形态

一份 Fortran 源码，四种交付形态。桥调用在它们之间不变；变的是这些调用背后的
Julia 代码如何到达机器——从项目环境解释执行、预编译进嵌入式运行时加载的
sysimage、或是提前编译成一个普通的共享库——直到队尾的完全不用 Julia。第四种
形态，纯 Fortran 的 native，是前三种共同的度量基线。

## 谱系

以下数字量自 capstone 反应流示例（完整报告：
`examples/07_capstone/PERFORMANCE.md`）：

| 形态 | 启动 | 目标机需要什么 | 目标机上有 Julia 吗？ |
|---|---|---|---|
| JIT（嵌入式，项目环境） | init **17.3 s** | 你的二进制、钉版本的 Julia 安装、项目环境及其包仓库 | 有 |
| sysimage | init **1.90 s** | 你的二进制加 sysimage 文件，由同一个 Julia 构建 | 有 |
| AOT 库 | 库 init 0.58--1.97 s | 你的二进制加编译出的 `.so` | 没有 |
| native（纯 Fortran） | 无 | 你的二进制 | 没有 |

连成阶梯：JIT 冷启动到首个结果 **17.3 s**；sysimage 降到 **1.90 s**；AOT 版本
首次调用约 **12 μs**，逼近进程里根本没有 Julia 的 native 基线。（12 μs 是进
编译库的一次平凡调用；第一次*真正的*化学调用在任何形态下都是毫秒级的求解器
工作——定这个数的是工作量，不是形态。）

同一台机器上多次运行的启动区间：JIT 15.1--20.2 s（要加载约 92 个包缓存；高
端发生在机器繁忙时），sysimage 0.93--2.37 s（低端是热页缓存），AOT
0.58--1.97 s（库的冷到热页缓存）。

## 什么变，什么不变

**启动变；每次调用的开销不变。** 热态调用在每种形态下走的都是同一套 `fcj_*`
ABI，因此[两套 SDK，两种速度](two-sdks.md)里的数字到处成立：泛型约 815 ns，
Fast Path 约 3.8 ns。capstone 的化学总时长给出实证——同样的 5216 个 Strang
半步上 4.79 s（JIT）对 4.02 s（sysimage），而差值的方向在不同运行间翻转。
那是机器负载噪声（约 ±20%），不是形态效应。为启动延迟、为交付物选形态；别为
稳态速度选。

内存同样不变：sysimage 运行的峰值 RSS 与 JIT 运行相差不超过 ~30 MB。镜像
预编译的是代码，压缩不了你的问题本身需要的堆。

## 形态 1：JIT——开发者的默认

用 `julia_init()` 或 `julia_init_ex(project_path=...)` 初始化，让 Julia 在运行
时从仓库加载预编译的包缓存。没有额外的构建步骤，每个包都经自己的 `[compat]`
边界 resolve，一条顶层的 `julia_eval_string` 就能现场重定义代码。代价是
17.3 s 量级的启动，以及一台背得动整个包仓库的目标机。

省略 `project_path` 时，`julia_init_ex` 按序探测 FortranBridge 包：环境变量
`$JULIA_FJ_PROJECT`，然后装在可执行文件旁边的副本，然后 `$JULIA_PROJECT`。
探测失败则不初始化直接返回，原因在 `get_last_error_message()` 里。

## 形态 2：sysimage——构建时付账，两秒钟加载

`cmake -DFJ_BUILD_SYSIMAGE=ON` 驱动 `scripts/build_sysimage.jl`：PackageCompiler
的 `create_sysimage` 编译 `FortranBridge`、`SciMLBase`、`OrdinaryDiffEq` 与
`FjKinetics`，把一份预编译工作负载追进镜像。产物是一个大文件——本仓库载满
SciML 的镜像约一个 GB——由嵌入式运行时在 init 时加载。运行时不编译任何东西，
这是构造使然：代码已经在镜像里。

capstone 驱动用一个分支在前两种形态间切换，摘自
`examples/07_capstone/1_reacting_flow.f90`：

```fortran
            if (trim(jmode) == 'sysimage') then
                inquire(file=trim(image_path), exist=lex)
                if (.not. lex) then
                    write (error_unit, '(a)') 'FATAL: sysimage not found at ' // &
                        trim(image_path) // ' (set FJ_SCIML_SYSIMAGE)'
                    error stop 1
                end if
                print '(a,a,a,a)', 'detonation: julia mode=sysimage image=', trim(image_path), &
                    ' project=', trim(project_path)
                call julia_init_ex(image_path=trim(image_path), project_path=trim(project_path))
            else
                print '(a,a,a)', 'detonation: julia mode=jit project=', trim(project_path)
                call julia_init_ex(project_path=trim(project_path))
            end if
```

两条注意事项。镜像按 `cpu_target="native"` 烘焙——构建主机的指令集——所以它是
单主机产物。而且它钉死在确切的 Julia 构建上：构建镜像与嵌入运行时的必须是同
一个自含 1.12.7 二进制；指向另一个 minor 版本的 shim 会被 sysimage 构建守卫
拒掉（[安装](installation.md)）。

sysimage 形态下，镜像已经把预编译模块绑定在 `Main` 里，于是 JIT 路径需要的那
次运行时 `import` 根本不发生。capstone 统计的 init/setup 桥调用：sysimage
形态 13 次，JIT 形态 15 次，差的正是那次 import。

## 形态 3：AOT——Julia 变成一个普通共享库

方向在这里翻转：不是 Fortran 嵌入 Julia，而是 PackageCompiler 的
`create_library` 把一个 Julia 包连同它全部依赖闭包编译进 `dist/`，把你的函数
暴露成 C 符号。Fortran 像链任何 C 库一样链它；目标机不需要 Julia 安装、仓库、
项目环境。启动就是一次普通的镜像加载（0.58--1.97 s，冷到热缓存），进库的第一
次调用约 12 μs 应答。永远没有 JIT。

这一形态不经过桥，且有一条锋利的边界：SDK 的 `julia_init()` 不许用。接口注释
摘自 `examples/04_performance/1_jit_vs_aot.f90`：

```fortran
        ! Lifecycle of the runtime embedded in libmylib.so. The SDK's
        ! julia_init() must NOT be used in this mode: linking libmylib.so
        ! makes its bundled libjulia satisfy libjulia.so.1 for the whole
        ! process, and a bare jl_init() would then look for a default
        ! sys.so that the bundled layout does not ship (the sysimage is
        ! compiled INTO libmylib.so and only init_julia() knows how to
        ! load it, with an explicit bindir).
        subroutine init_julia(argc, argv) bind(c, name="init_julia")
            use iso_c_binding
            integer(c_int), value :: argc
            type(c_ptr), value :: argv
        end subroutine

        subroutine shutdown_julia(retcode) bind(c, name="shutdown_julia")
            use iso_c_binding
            integer(c_int), value :: retcode
        end subroutine
```

同一个首次调用，两个世界（同一份源码，两次构建）：

```fortran
#ifdef COMPILED_MODE
    res = my_add_float(10.0d0, 20.0d0)
#else
    res_obj = julia%call("perf_add_one", 10.0d0)
    res = res_obj%as_real()
#endif
```

错误处理的形状也变了：任何 Julia 异常都过不了 C ABI。编译库改回整数错误码——
capstone 的 AOT 化学核用 0 表示成功、-1 表示 `n` 非法、-2 表示求解器尚未建
立、-3 表示求解器抛了——而它的缓冲同样是零拷贝 wrap，与桥的 `fcj_wrap_array`
如出一辙。

选它之前要知道两笔成本。构建很重：对 capstone 核，整个闭包的非增量 codegen
花了约 50 分钟墙钟、编译器峰值 RSS 约 33 GB，`dist/` 交付约 2.5 GB。而且 API
面就此冻结：你调用的是固定的 C 符号，不是运行时按名解析。

一句 PackageCompiler 卫生：用 `include_lazy_artifacts=true` 构建，否则这个
“自含”库在没有仓库的机器上首次加载时会静默从网络下载惰性 artifact（其中就有
MKL）。

可运行的例子：`examples/03_deployment/2_compiled_library/`（小演示）与
`examples/07_capstone/3_aot_kinetics/`（生产形态的那个）。

## 形态 4：native——丈量的尺

纯 Fortran，什么都不嵌入。它在这张表里，因为它是参照物：每种桥形态都要对同一
物理的 native 运行验证——四道验收门、零偏差、残差低于 1e-12
（[验证](../intro/validation.md)）。当一个工作负载从 Julia 什么都买不到时，
native 不是退路；它就是答案。

## 启动控制：`julia_init_ex`

三种嵌入式形态都从同一个 SDK 调用起步，它包装 C 入口 `fcj_init_ex`（正如
`julia_shutdown` 包装 `fcj_shutdown`）。它的可选参数就是交付旋钮：
`image_path`（sysimage）、`project_path`（环境）、`nthreads`（Julia 线程
数）、`handle_signals`（信号处置）。摘自
`examples/03_deployment/ex_init_options.f90`：

```fortran
    ! 1. Initialize the Julia runtime with explicit startup options:
    !    - project_path: omitted on purpose -- the exe-adjacent probe finds
    !      the FortranBridge package copied next to this executable by the
    !      build, and an explicit RELATIVE path would be validated against
    !      the CWD (breaking runs from any other directory)
    !    - nthreads = 2
    !    - handle_signals = 0 ("no takeover": SIGINT/SIGTERM are reset to
    !      SIG_DFL after init; GC-critical handlers stay intact -- bridge.h)
    call julia_init_ex(nthreads=2, handle_signals=0)
```

失败语义是有意设计的：坏选项（塞不下的路径、不存在的环境）不初始化直接返回，
`get_last_error_message()` 带着原因——进程不会中止。信号方面：桥从不碰
`jl_options.handle_signals`，因为 GC safepoint 轮询依赖 Julia 自己的处理器；
上面的 `0` 意为“不接管”：init 后把 `SIGINT`/`SIGTERM` 重置回默认。旧的
`julia_init` / `julia_init_with_image` 保持其历史信号行为。

## 选型

1. **开发用 JIT。** 无需构建、可现场重定义、整个栈都经 `[compat]` resolve。
   17.3 s 量级的启动是开发税，交在一台付得起的机器上。
2. **同一份二进制要在已知主机上反复跑时，用 sysimage 砍启动。** 1.90 s 到首
   个结果、堆足迹相同、构造上没有运行时编译。把镜像尺寸算进预算，并记住它钉
   主机、钉 Julia 版本。
3. **目标机上没有 Julia，或首次调用延迟就是产品时，上 AOT。** 无需安装、首次
   调用约 12 μs、整数错误码替代异常——外加一场你提前排期、而不是撞上的重型
   一次性构建。
4. **Julia 什么都买不到的地方，留在 native。** 基线也是一种形态。

## 接下来去哪

- [自带动力学](bring-your-own-kinetics.md)——交付形态套在一个真实化学动力学
  包上的样子。
- [验证](../intro/validation.md)——任何形态都不许打破的正确性门。
- [性能附件](../developer/annex-performance.md)——本页每个数字背后的完整
  capstone 性能报告。
