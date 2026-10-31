---
title: 数组与回调
sync: 2026-10-31
---

# 数组与回调

标量已经[初次过桥](first-call.md)；真正的计算要搬数组，还需要双向的控制流。本页
补齐剩下的数据管道：数组免拷贝进 Julia、一次调用整块取回、以及一个 `bind(c)`
Fortran 子程序被 Julia 当作右端函数调用。这一切都架在
[两套 SDK，两种速度](two-sdks.md)的那两层之上。

## 数组进桥：零拷贝 wrap 还是深拷贝

两个 rank 泛型函数决定数组怎么过桥，区别只在内存所有权。二者都是单一的
assumed-rank 入口，extents 从 `size(arr, k)` 推导——不存在一个可能与数组不一致
的、由调用方提供的长度——并且都接受 1 到 16 维、连续的 `real(kind=8)` 数据。

| | `julia_wrap_array(arr)` | `julia_copy_array(arr)` |
|---|---|---|
| Julia 拿到什么 | 一个指向**你的**内存的 `Array{Float64,N}` 头 | 一个新分配的 `Array{Float64,N}`，数据 memcpy 进去 |
| 数据搬运 | 零：wrap 只建头部，不搬载荷 | 一次完整拷贝（结果取回还要再一次） |
| Julia 侧写入 | 立刻落在你的 Fortran 数组里 | 落在 Julia 的副本里 |
| 所有权 | 你的；Julia 永远不会释放这块内存 | Julia 的，由 GC 管理 |
| 什么时候用 | 原地核、大网格、热循环 | Julia 侧要持有该数组，或者你不想让两门语言共享内存 |

两者都选择响亮拒绝而不是瞎猜：rank 超过 16、任一维长度为零（零长数组上
`c_loc` 非法）、或实参不连续，都会得到一个无效的 `JuliaValue` 加一条打到
`error_unit` 的诊断。

wrap 的实际样子，摘自 `examples/01_basics/2_zero_copy_arrays.f90`：

```fortran
    ! 2. Box the Fortran Array into a Julia Object
    !    This creates a Julia Array header pointing to the EXISTING Fortran memory.
    !    NO DATA COPY happens here. Extents are derived from size() by the SDK.
    dummy = julia_wrap_array(simulation_grid)

    ! 3. Call Julia Function with the Array
    !    Julia sees a standard Matrix{Float64}.
    !    Any changes Julia makes are written directly to 'simulation_grid'.
    !    ExamplesLib.update_simulation_state!(grid, dt)
    res = julia%call("ExamplesLib.update_simulation_state!", dummy, 0.5d0)

    ! 4. Verify Changes in Fortran
    print *, "After Julia Update:"
    print *, "Grid(1,1) [Expected > 0]: ", simulation_grid(1,1)
    print *, "Grid(50,50):              ", simulation_grid(50,50)
```

`simulation_grid` 初始为零；调用之后它的元素不是零了。这就是零拷贝的证据——若
发生了拷贝，Fortran 数组读出来应该仍是 `0.0`。wrap 附带一条规矩：头部指向你的
内存，而所有权标志声明 Julia 不会释放它；因此，只要还有任何句柄可能够到这块
内存，让它活着、别挪动，就是你这边的责任。

N 维是字面意思：rank 并不封顶在 2 或 3。同一个 wrap 走裸 C ABI 的样子，摘自
`examples/01_basics/2_arrays.f90`：

```fortran
    ! --- 3. Hypermatrix (4D, zero-copy through the rank-generic API) ---
    ! The high-level SDK form is simply  vec_obj = julia_wrap_array(hyper)
    ! (extents derived from size()); here we exercise the raw C form and
    ! verify the wrap via introspection.
    hyper = 0.0d0
    raw_ptr = c_loc(hyper)
    dims(1:4) = [2_c_long, 3_c_long, 4_c_long, 5_c_long]
    wrapped_ptr = fcj_wrap_array(raw_ptr, 4_c_long, dims)
    mat_obj%ptr = fcj_retain(wrapped_ptr)
    print *, "  3. Rank-4 wrap: ndims=", mat_obj%ndims(), &
             " sizes=", (mat_obj%size_dim(k), k=1,4)
```

深拷贝是同一个调用形状、另一笔账。下面两段都跑在 3000 x 3000 的矩阵上（约
72 MB），摘自 `examples/04_performance/3_memory_transfer.f90`：

```fortran
    ! Step 1: Explicit Deep Copy to Julia
    wrapped_array = julia_copy_array(matrix)
    ! Step 2: Call function (returns new array)
    res = julia%call("perf_scale_matrix", wrapped_array, 2.0d0)
```

```fortran
    ! Step 1: Wrap (O(1))
    ! The rank-generic wrapper derives the extents from size()
    wrapped_array = julia_wrap_array(matrix)

    ! Step 2: Call In-Place Function
    ! We pass the wrapped array. No data moves.
    res = julia%call("perf_scale_matrix_bang", wrapped_array, 2.0d0)
```

## 数组出桥：先导航，再一次拷完

结果以句柄回来。两个访问器在结果对象里导航，一次调用把数据搬走：

- `%element(i)`——从 1 开始的线性索引，返回已 retain 的句柄。
- `%property(name)`（及其兄弟 `%get_field(name)`）——经 `Base.getproperty`
  的按名访问：结构体字段、`NamedTuple` 键、求解器的解对象。
- `%to_fortran(buf, n)`——**一次**调用把一个稠密数组拷进你的 Fortran 缓冲；
  `real` 与 `complex` 两个重载按缓冲类型解析。

摘自 `examples/06_sciml/2_batch_data.f90`（`fail` 是该示例自己的中止辅助例程）：

```fortran
    d = julia_eval(' (a = [7.0,8.0,9.0],) ')
    if (.not. d%is_valid()) &
        call fail('julia_eval NamedTuple failed')
    a = d%property("a")
    if (.not. a%is_valid()) &
        call fail('property("a") failed: ' // get_last_error_message())
    rc = a%to_fortran(rbuf, 3_c_int64_t)
    if (rc /= 0) &
        call fail('to_fortran on NamedTuple property failed: ' // get_last_error_message())
```

错误套路就是[初次调用](first-call.md)里的家规：检查句柄或返回码，
`get_last_error_message()` 带回 Julia 侧的文本。例如对两个元素的向量做越界的
`%element(5)`，会返回无效句柄并填好错误消息。

批量取数同时也是最便宜的过桥方式。逐元素访问每一跳都是一次桥跳；
`%to_fortran` 整个数组只跳一次。同一笔账还说：当一个循环放在哪边都行时，把它
放进 Julia、带着数组过一次桥——`examples/04_performance/4_access_patterns.f90`
在百万元素规模上量的正是这笔账。

## 回调：Fortran 当右端函数

数组搬数据；回调把控制权交给 Fortran。`julia_callback` 把一个 `bind(c)` 子程序
指针包成 Julia 可调用对象 `f(du, u, p, t)`——DifferentialEquations 一类求解器
期待的签名——于是求解器每一步都调进你的 Fortran。这个可调用对象通过 `ccall`
调你的子程序，创建时传入的上下文指针在每次调用时原样送达。

子程序签的是一份六参数契约。下面这个摘自 `examples/06_sciml/1_callback.f90`，
是无状态指数衰减 `du = -k*u`：

```fortran
    subroutine rhs(ctx, n, u, du, t, err) bind(c)
        type(c_ptr), value, intent(in) :: ctx        ! unused (stateless RHS)
        integer(kind=c_int64_t), value, intent(in) :: n
        type(c_ptr), value, intent(in) :: u, du
        real(kind=c_double), value, intent(in) :: t  ! unused (autonomous RHS)
        integer(kind=c_int), intent(out) :: err

        real(kind=c_double), pointer :: u_arr(:), du_arr(:)
        integer :: i

        err = 0_c_int
        if (n <= 0_c_int64_t) return
        call c_f_pointer(u, u_arr, [int(n)])
        call c_f_pointer(du, du_arr, [int(n)])
        do i = 1, int(n)
            du_arr(i) = -K_DECAY * u_arr(i)
        end do
    end subroutine rhs
```

这份契约有三个要点：

- **`u` 与 `du` 是直接指进 Julia 数组的裸指针**——上面的零拷贝通道反着走。你
  读 `u`、写 `du`，原地、各 `n` 个元素；每一步什么都不需要编组。
- **`err` 是错误通道。** 返回非零，Julia 侧就 throw；桥接住异常，在 Fortran 调
  用点经 `get_last_error_message()` 浮出水面。任何 Fortran 失败都不会无声
  通过。
- **`ctx` 是你的**——创建时传入的任意 `type(c_ptr)`，每次调用原样奉还（这个
  无状态 RHS 不用它）。

接线只要三步，同一示例：

```fortran
    ! 2. Wrap the bind(c) RHS into a Julia callable (already retained)
    fn = c_funloc(rhs)
    cb = julia_callback(fn, c_null_ptr)
    if (.not. cb%is_valid()) then
        write (error_unit, '(A)') 'FATAL: julia_callback failed: ' // get_last_error_message()
        stop 1
    end if

    ! 3. Box f's arguments: du (Float64 vector workspace, zero-copy),
    !    u = [1.0], p = 0.0, t = 0.0 (p is ignored by the bridge closure)
    du_f(1) = 0.0_c_double
    u_f(1) = 1.0_c_double
    du_boxed = julia_wrap_array(du_f)
    u_boxed = julia_wrap_array(u_f)
    p_boxed = julia_box_real(0.0_c_double)
    t_boxed = julia_box_real(0.0_c_double)
    if (.not. du_boxed%is_valid() .or. .not. u_boxed%is_valid()) then
        write (error_unit, '(A)') 'FATAL: boxing du/u failed'
        stop 1
    end if

    ! 4. Invoke the Julia callable f(du, u, p, t); it ccalls back into
    !    rhs, which writes du in place.
    res = cb%call_value(du_boxed, u_boxed, p_boxed, t_boxed)
```

`call_value` 之后，`du_f(1)` 已经是 `-K_DECAY * 1.0`：RHS 直接写进了被 wrap 成
`du` 的那个 Fortran 数组。桥还会把这个可调用对象绑定到 `Main.FJ_CALLBACK`，
于是用 `julia_eval_string` 拼出来的求解器代码能按名字找到它。端到端版本——
Tsit5 积分谐振子、对解析解校验到约 1e-9——是
`examples/06_sciml/3_sciml_demo.f90`。

两个方向都靠蹦床。这一侧把你的 `bind(c)` 地址装箱成不透明指针、在 Julia 里闭
包化。另一个方向上，`get_function_pointer` 让桥生成一个扎根在 `Main` 的
`@cfunction` 蹦床，把一个 Julia 函数的裸 C 指针交给 Fortran，每次调用约
3.8 ns；那条路径与它的硬边界属于[两套 SDK，两种速度](two-sdks.md)。

## 两条通道共守的规矩

1. **一个线程。** 每次桥调用——wrap、取数、回调调用——都发生在初始化运行时的
   那个线程上。回调也不例外：求解器在调用它的线程上执行，而在这座桥里那永远
   是 init 线程。
2. **数组元素类型只有 `Float64` 与 `ComplexF64`。** wrap 只收连续的
   `real(c_double)`；`%to_fortran` 只填 `real` 或 `complex` 缓冲。标量不受此
   限——每种标量类型都能装箱。这是已知限制，记录在
   [已知限制](known-limitations.md)。
3. **预算单位是过桥次数，不是调用次数。** 泛型调用约 815 ns、Fast Path 调用约
   3.8 ns（10 万次迭代平均）；相对真实求解器工作都是噪声。但一个逐元素循环若
   百万次跨桥，就百万次付这跳的钱。把循环挪进某一侧，别把元素来回搬。

## 接下来去哪

- [交付形态](deployment-modes.md)——同一份程序按 JIT、sysimage 或 AOT 库交付：
  变的是启动，不是你刚学会掂量的每次调用开销。
- [自带动力学](bring-your-own-kinetics.md)——这些通道在 capstone 尺度上的
  应用，背后是一个真实的化学动力学包。
- [已知限制](known-limitations.md)——线程钉死、数组类型、平台支持，一份诚实的
  清单。
