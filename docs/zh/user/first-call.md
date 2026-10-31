---
title: 第一次调用
sync: 2026-10-31
---

# 第一次调用

最短的完整程序——启动运行时、加载 Julia 文件、调用函数、拆箱结果、关闭——就是
`examples/01_basics/1_quickstart.f90`，构建产物为 `ex01_quickstart`。本页逐步
讲解。还没构建的话先看[安装](installation.md)。

## 完整程序

```fortran
program ex01_quickstart
    use julia_high_level
    implicit none

    type(JuliaValue) :: julia ! Helper object for method dispatch
    type(JuliaValue) :: res
    real(kind=8) :: sum_result

    ! 1. Initialize the Julia Runtime
    call julia_init()

    ! 2. Load your Julia Code
    call julia_include_exe_relative("examples_lib.jl")
    call julia_eval_string('using .ExamplesLib')

    ! 3. Call a simple function: greet(name)
    !    Equivalent to Julia: res = ExamplesLib.greet("Fortran User")
    res = julia%call("ExamplesLib.greet", "Fortran User")

    ! 4. Call a calculation function: add_numbers(x, y)
    !    Equivalent to Julia: res = ExamplesLib.add_numbers(10.5, 20.0)
    res = julia%call("ExamplesLib.add_numbers", 10.5d0, 20.0d0)

    ! Convert the result back to Fortran real (Unboxing)
    sum_result = res%as_real()
    print *, "Result of 10.5 + 20.0 = ", sum_result

    ! 5. Shutdown
    call julia_shutdown()

end program ex01_quickstart
```

（仓库源码还打印了横幅并检查 `ExamplesLib` 是否加载成功；此处裁掉，其余未改。）

## 第 1 步：初始化

`julia_init()` 包装 C 入口 `fcj_init`，在你的进程内启动嵌入式 Julia 运行时
——没有独立的 Julia 进程，没有管道。随之而来两条规则：

- **每进程一个运行时**，且**所有桥调用都留在初始化它的线程上**。请从将来负责
  调用的线程初始化（所有示例里都是主线程）。
- `julia_shutdown()` 之后不支持重新初始化；只初始化一次。

要控制启动——sysimage 路径、项目环境、线程数、信号处置——改用
`julia_init_ex`；见[交付形态](deployment-modes.md)。

## 第 2 步：加载你的 Julia 代码

`julia_include_exe_relative("examples_lib.jl")` 包含一个**相对可执行文件解析**
（而非相对当前工作目录）的 Julia 文件——构建时已把 `examples_lib.jl` 拷到二
进制旁边，因此示例从任何目录都能跑。随后 `julia_eval_string` 把模块带入作用
域。该文件定义的函数包括：

```julia
function greet(name::String)
    println("Julia says: Hello, $name!")
    return "Greeting received"
end

function add_numbers(x::Float64, y::Float64)
    return x + y
end
```

## 第 3、4 步：调用，再拆箱

`julia%call(name, args...)` 按名查函数并自动装箱参数：`real` 装 `Float64`、
integer 装 `Int`、string 装 `String`、logical 装 `Bool`、complex 装
`ComplexF64`。结果是 `JuliaValue` 句柄——扎根在桥的 C 侧根集里，你持有期间
Julia 垃圾回收器不会回收它。

`%as_real()` 拆箱为普通 Fortran `real`。同族还有 `%as_integer()`、
`%as_logical()`、`%as_complex()`、`%as_string()`。

## 第 5 步：关闭

`julia_shutdown()` 包装 `fcj_shutdown`，干净地拆除运行时。Fast Path 函数指针
在此之后失效（见[两套 SDK，两种速度](two-sdks.md)）。

## 出错的时候

失败不会静默。每次桥调用都做异常检查；失败的调用返回无效句柄，
`get_last_error_message()` 把 Julia 错误文本带回 Fortran。摘自
`examples/01_basics/1_hello_world.f90`：

```fortran
    res = dummy%call("non_existent_func", 123)

    if (.not. res%is_valid()) then
        err_msg = get_last_error_message()
        print *, "[Fortran] Caught expected error: ", err_msg
    endif
```

## 运行

```bash
./examples/ex01_quickstart
```

```text
--- Example 1: Quickstart (Standard Workflow) ---
Julia says: Hello, Fortran User!
Result of 10.5 + 20.0 =    30.500000000000000
```

首次运行要付 Julia 运行时启动加上它所触及代码的 JIT 编译。这个微型示例只需数
秒；对载满 SciML 的 capstone，同样的冷启动实测 17.3 s
（[交付形态](deployment-modes.md)展示了 sysimage 把它降到 1.90 s）。

## 接下来去哪

- [两套 SDK，两种速度](two-sdks.md)——你刚用过的这一层、它下面的一层，以及
  ~3.8 ns 的指针路径。
- [数组与回调](arrays-and-callbacks.md)——N 维零拷贝数组，以及被 Julia 调用
  的 Fortran 子程序。
