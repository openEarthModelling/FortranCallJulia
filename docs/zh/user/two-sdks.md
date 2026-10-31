---
title: 两套 SDK，两种速度
sync: 2026-10-31
---

# 两套 SDK，两种速度

Fortran 经两个模块到达桥，它们是分层关系，不是竞争对手。`julia_low_level`
（`src/julia_binding.f90`）是 `bind(c)` 的真相本体：一个声明 `fcj_*` C ABI 的
interface 块，约 105 个符号，其上什么都没有。`julia_high_level`
（`src/julia_sdk.f90`）建在它上面：带 GC 安全生命周期的 `JuliaValue` 句柄、自动
装箱、转换器、批量取数（`%to_fortran`）。两者可以在一个程序里混用——高层
`use` 了低层，而且它的 `get_function_pointer` 助手正是下文指针路径的推荐入口。

## 定位

| | `julia_high_level` | `julia_low_level` |
|---|---|---|
| 源码 | `src/julia_sdk.f90` | `src/julia_binding.f90` |
| 形态 | OOP：带类型绑定过程的 `type(JuliaValue)` | `fcj_*` C ABI 的 `bind(c)` 声明（约 105 个符号） |
| 参数 | 自动装箱（`real` 装 `Float64`、string 装 `String`……） | 你自己装箱或传 `c_ptr` |
| 生命周期 | GC 安全：赋值即 retain，终结器恰好 release 一次 | 手动 `fcj_retain` / `fcj_release` |
| 结果 | `%as_real()` 一族、`%element` / `%property`、`%to_fortran` 批量拷贝 | 裸 `type(c_ptr)`，你自己拆箱 |
| 错误 | 无效句柄 + `get_last_error_message()` | 返回码 + `get_last_error_message()` |
| 适用 | 应用胶水、探索、一切非逐次迭代的调用 | 直达 C ABI、未被封装的符号、极薄分层 |

## 同一个调用，两种写法

高层，摘自 `examples/01_basics/1_quickstart.f90`：

```fortran
    res = julia%call("ExamplesLib.add_numbers", 10.5d0, 20.0d0)
    sum_result = res%as_real()
```

低层，你在 `src/julia_binding.f90` 里看到的声明：

```fortran
    function fcj_call1_float64(func_name, arg1) bind(c, name="fcj_call1_float64") result(res)
        import :: c_char, c_double, c_ptr
        character(kind=c_char), dimension(*), intent(in) :: func_name
        real(kind=c_double), value :: arg1
        type(c_ptr) :: res
    end function fcj_call1_float64
```

返回的 `c_ptr` 不会替你扎根：要让对象在后续桥调用间存活，你必须
`fcj_retain`，用完后恰好 `fcj_release` 一次。这本账正是 `JuliaValue` 免费替你
管的部分——所以默认推荐高层。

## 数字

| 路径 | 每次调用 | 买到什么 |
|---|---|---|
| Fast Path：裸 C 函数指针 | **~3.8 ns** | 无名字查找、无装箱、无异常检查 |
| 泛型类型化调用 | **~815 ns** | 任意函数、任意参数、完整错误检查 |

两个数字都是 10 万次迭代的平均，由
`examples/04_performance/2_call_overhead.f90` 产出。把它们读作"通用性的价格"：
泛型路径每次都要解析名字、装箱每个实参、拆箱结果、并在每一跳检查 Julia 异常。
面对任何真实负载——一次 `inv()`、一个 ODE 步——800 ns 是噪声；面对水力学循环
里的每网格单元调用，就不是了。

## Fast Path

当同一个 bitstype 签名的函数要在紧循环里反复调用时，降级为一次性注册的裸函数
指针。摘自 `examples/04_performance/2_call_overhead.f90`（计时代码略）：

```fortran
    abstract interface
        function func_add_one(val) bind(c)
            import :: c_double
            real(c_double), value :: val
            real(c_double) :: func_add_one
        end function func_add_one
    end interface

    procedure(func_add_one), pointer :: c_func => null()

    raw_ptr = get_function_pointer("perf_add_one", "Float64", "Float64")
    call c_f_procpointer(raw_ptr, c_func)

    do i = 1, N
        y = c_func(x)            ! ~3.8 ns：一次普通 C 调用，仅此而已
    end do
```

注册表把底层 `@cfunction` 扎根在 `Main` 里，GC 生命周期是安全的——但契约有硬
边界，误用会让进程崩溃且没有 Julia 侧诊断：

1. **在最终定义之后注册。** 蹦床在注册时捕获函数对象；之后重绑定该名字（例如
   换成闭包）后，旧指针调用的仍是捕获到的那个对象。
2. **重注册同名会使先前指针失效**；丢弃旧指针。
3. **被调函数不得抛异常。** 异常穿过 C 蹦床帧展开属未定义行为，通常是段错误；
   在 Julia 内部处理错误，或返回哨兵值。
4. **类型必须精确匹配**——`ret_type` / `arg_types` 只接受 bitstype；注册时
   什么都不校验。
5. **指针随运行时终结**：`julia_shutdown()` 之后失效。

## 何时用谁

1. **默认用 `julia_high_level`。** 正确性与 GC 安全优先；相对任何值得跨桥的计
   算，~815 ns 的泛型路径都可忽略。应用胶水、结果导航、一次性调用：留在这一
   层。
2. **需要 C ABI 本身时降到 `julia_low_level`**——SDK 没有封装的 `fcj_*` 符
   号、桥之上的极薄分层、或 OOP 层不合身的场合。retain/release 的簿记由你接
   手；记错就是泄漏或悬垂。
3. **紧循环里两者都不用——走 Fast Path**（或干脆把调用提出循环）。签名是
   bitstype 固定、函数体不会抛异常时，`get_function_pointer` 加
   `c_f_procpointer` 能把每次调用压到 ~3.8 ns。capstone 里每网格单元的化学
   步就是这么省下来的。

## 接下来去哪

- [数组与回调](arrays-and-callbacks.md)——两个世界之间的另外两座桥：零拷贝
  数组与 `@cfunction` 回调。
- [交付形态](deployment-modes.md)——JIT、sysimage、AOT：什么变（启动），什么
  不变（每次调用的开销）。
