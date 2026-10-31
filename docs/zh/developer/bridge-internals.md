---
title: 桥内部
sync: 2026-10-31
---

# 桥内部

8 个 C 文件、4 个职责组、1 份契约。用户侧页面从外面描述桥——`fcj_*`
ABI、两层 Fortran SDK、那些数字。本页打开盒子：每个文件拥有什么、GC 的账
怎么还、Julia 1.12 的 C API 在哪里逼出了绕行方案。它是写给改
`src/bridge/` 的维护者的；要*使用*桥，不需要这里任何内容。

[架构页](../intro/architecture.md)用一屏讲同一个系统；如果你是初来，先读
它。

## 八个文件

| 组 | 文件 | 拥有 |
|---|---|---|
| 核心 | `core.c`、`memory.c` | 生命周期（`fcj_init` / `fcj_init_ex` / `fcj_shutdown`）、线程钉死、GC 根集 |
| 分发与装箱 | `dispatch.c`、`types.c` | `fcj_call*` / `fcj_call_kwargs`、函数名缓存、标量装箱（`fcj_box_*`） |
| 数组通道 | `arrays.c`、`extract.c` | N 维零拷贝包装、深拷贝、批量取数回 Fortran |
| 回调访问 | `callbacks.c`、`accessors.c` | `@cfunction` 蹦床、`get_field` / `get_property`、原生 `Float64` 元素访问 |

两个头文件给它们定框。`bridge.h` 是公共契约：53 个 `fcj_` 函数加
`fcj_options_t`——Fortran `bind(c)` 层能碰到的一切。`bridge_internal.h`
是私有的：原生元素访问器（`fcj_get_real` 及其同族）、共用助手、以及
`fcj_shutdown` 逐一走过的各模块清缓存钩子。全站沿用的"约 105 个导出
`fcj_*` 符号"这一口径数的是这些源码里整个 `fcj_` 命名空间；绑定层
`src/julia_binding.f90` 声明其中 58 个（53 个公共函数中的 52 个——
`fcj_ready` 从不被绑定——加 6 个内部元素访问器），其余是从不过 ABI 的内
部助手。

## 核心：生命周期与根集

`core.c` 拥有状态机。`fcj_state` 是 `_Atomic`；每个入口先经 `fcj_ready()`
检查它才碰 Julia。[已知限制](../user/known-limitations.md)里的线程规则在
`check_thread()` 里是被执行、不是被记录（逐字摘自 `src/bridge/core.c`）：

```c
int check_thread() {
    if (pthread_self() != main_thread_id) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Thread Error: Julia called from thread %p, runtime owned by thread %p",
                 (void*)pthread_self(), (void*)main_thread_id);
        set_error(msg);
        return 0; // Fail
    }
    return 1; // OK
}
```

失败语义按入口分家：`fcj_init` 失败即终止进程（原始契约），而
`fcj_init_ex` 返回错误码、原因留在 `fcj_get_last_error()`——Fortran 侧以
`get_last_error_message()` 读到。`fcj_shutdown` 是单向的：状态机永不回到
READY，shutdown 之后重新初始化会被响亮拒绝，而不是被尝试。

`memory.c` 是 GC 的故事，它的头注释比任何转述都说得清楚（摘自
`src/bridge/memory.c`）：

```c
// fcj_retain/fcj_release keep their bind(C) signatures but no longer round-trip
// through Julia (retain_obj/release_obj in GCManager.jl) on the hot path.
// Retained objects live in a Julia Vector{Any} reachable through the constant
// binding `Main.FJ_ROOTS` ... bookkeeping is a pure-C ptr -> slot hash map with
// per-pointer refcounts, mirroring GCManager's REF_COUNTS/PTR_CACHE logic.
```

维护者要记住的机制：

- **C static 不是 GC 根。** 任何缓存进 `static` 的函数或值必须走
  `fcj_retain`（模块绑定算数；裸 static 不算）。唯一被允许的例外是被
  Base 绑定保活的不朽单例，例如 `types.c` 缓存的 `ComplexF64` 类型对象。
- **`fcj_map` 是开放寻址加墓碑与引用计数**——被删条目打墓碑使探测链保
  持完整；同一指针 retain 两次占一个槽、计数为二。
- **这些 static 一处锁都没有。** 单线程契约（`check_thread`）就是锁。
  破坏契约你得到的是数据竞争，不是一个 bug 报告。

## 分发与装箱

`dispatch.c` 把名字变成调用。函数名缓存是 256 槽定长表、FNV-1a 哈希；
缓存命中经 `fcj_retain` 路由，缓存住的 `jl_function_t*` 才有根。维护者
永远不能撤销的两条失效规则：

1. 该缓存在 `fcj_shutdown` 中**最先**被清——趁还没有任何东西能再解引用
   它。
2. **每次 `julia_eval_string` 都使名字缓存失效。** 一次 eval 可以把 `f`
   从函数重定义成闭包，过期缓存项会永远调用捕获的旧对象。（Fast Path 注
   册表刻意保留其捕获对象语义并写明了；见
   [两套 SDK，两种速度](../user/two-sdks.md)。）

`fcj_call1_float64` 一族到 N 参版本、再到关键字参数路径 `fcj_call_kwargs`，
全部汇入同一条 `jl_call` 加异常检查的尾巴。`types.c` 把 Fortran 标量装
箱成 Julia 对象——`fcj_box_float64`、`fcj_box_string` 等——外加上述缓存
的 `ComplexF64` 数据类型。

## 数组通道

`arrays.c` 经 `jl_ptr_to_array` 把 Fortran 内存包装成 1 到 `FCJ_MAX_NDIM`
任意秩的 Julia `Array`，零拷贝。包装路径逐字摘自 `src/bridge/arrays.c`
（三个守卫助手同形，为篇幅略去）：

```c
void* fcj_wrap_array(void* data, long ndim, const long* dims) {
    if (!fcj_ready()) { set_error("Julia runtime not initialized or already shut down"); return NULL; }
    if (!check_thread()) return NULL;
    jl_value_t *array_type = NULL;
    jl_value_t *dims_tuple = NULL;
    JL_GC_PUSH2(&array_type, &dims_tuple);

    array_type = array_type_for_ndim(ndim, "fcj_wrap_array");
    ...
    dims_tuple = make_dims_tuple(ndim, dims, "fcj_wrap_array");
    ...
    jl_array_t *arr = jl_ptr_to_array(array_type, data, dims_tuple, 0);

    if (check_julia_exception()) { JL_GC_POP(); return NULL; }
    JL_GC_POP();
    return (void*)arr;
}
```

这段代码里看得见两条纪律，全桥处处负载：局部值在调用期间用
`JL_GC_PUSH2` 扎根；任何错误路径都先 `set_error` 原因再返回 NULL。深拷贝
兄弟 `fcj_copy_array` 分配全新 Julia 数组并 memcpy 进去，分配前做溢出检
查的规模乘积。

`extract.c` 是回程：`fcj_to_fortran`（一次批量拷进 Fortran 缓冲、长度校
验）、`fcj_get_element`、`fcj_get_property`。批量路径是从
`jl_array_data_` 出发、带 `n == len` 检查的单次 `memcpy`——正因如此取数
通道是位级精确的，验收门才敢把 1e-8 的门摆在它面前
（[验收门](acceptance-gates.md)）。

## 回调访问

`callbacks.c` 跑另一个方向：Fortran `bind(c)` 子程序经 `@cfunction` 蹦床
包装成 Julia 可调用对象，调用上下文不透明地携带。这是
`examples/06_sciml/1_callback.f90` 那些 OrdinaryDiffEq 回调演示背后的机
器。用户页的硬规则在这一层同样成立：蹦床帧容不下 Julia 异常，会抛错的被
调方属未定义行为——在 Fortran 侧校验、返回哨兵值。

`accessors.c` 实现 `%element` 与 `%property`，而 Julia 1.12 的 C API 在
这里逼出了全树最有教益的绕行。`extract.c` 的头注释记录在案（摘自
`src/bridge/extract.c`）：

```c
// 1.12.7 API notes (verified against include/julia/julia.h):
//  - jl_get_property does not exist; jl_get_field exists but only reads
//    plain struct fields (no getproperty overloads, no NamedTuples), so
//    the contract's fallback applies: Base.getproperty is cached once and
//    jl_call-ed, matching helper_getfield semantics in Accessors.jl;
//    getproperty dispatches on Symbol, so the name is interned with
//    jl_symbol (immortal, globally rooted) instead of boxed as a String;
//  - jl_arrayref does not exist either (removed with the Memory-backed
//    array rewrite), so element boxing goes through a cached
//    Base.getindex binding -- the same numeric boxing jl_arrayref used to
//    perform.
```

把它读成通用教训：当某个 `jl_*` 便捷函数缺席时，把等价的 Base 函数缓存
一次（经 `fcj_retain` 扎根）再 `jl_call` 它——不要手搓结构体偏移。
`bridge_internal.h` 补上原生元素访问器（`fcj_get_real` / `fcj_set_real`
及 2 维、3 维形态）：对包装内存的直接 `Float64` 读写，不装箱，供热路径
逐格使用。

## 信号与错误传输

桥永不写 `jl_options.handle_signals`：嵌入式 Julia 的 GC safepoint 轮询依
赖 Julia 自己的信号处理器，关掉它就会在 safepoint 崩溃——是必崩，不是偶
发（[教训](lessons.md)）。`fcj_options_t` 提供的 `handle_signals = 0` 含
义是*不接管*：init 成功后桥把 `SIGINT` / `SIGTERM` 重置为 `SIG_DFL`，
GC 关键的处理器原封不动。

错误走一条通道：每个运行时一个 last-error 缓冲，经 `fcj_get_last_error()`
读出、以 `get_last_error_message()` 露面。Julia 侧异常在调用边界被接住、
格式化进该缓冲，调用返回无效句柄或 NULL——进程继续跑。

## 接下来去哪

- [验收门](acceptance-gates.md)——你怎么证明自己没把这些弄坏。
- [从零重建](rebuild.md)——把这个核心包成交付形态的 sysimage 与 AOT 构建。
- [教训](lessons.md)——把这些规则写下来的那几次事故。
