---
title: 自带动力学
sync: 2026-10-31
---

# 自带动力学

capstone 没有把化学动力学写死。Fortran 驱动经由 FjKinetics——
`examples/07_capstone/FjKinetics/` 下的一个小型 Julia 包，其 v0.2 把所有
机理收拢到一个接口背后——推进网格，于是流场求解器永远不需要知道自己烧的是
什么化学。接入你自己的动力学有两条路：

1. **直接用 ChemMechSim。** 一个加载 Cantera-YAML 反应机理的开源 Julia 包；
   capstone 的 GRI-Mech 3.0 基准在它上面原样运行。
2. **实现 `AbstractKineticsSolver`。** 两个方法、一份契约——你的机理落进同一
   条 Fortran 调用的背后。

## 契约：`AbstractKineticsSolver`

基类型及其含义，逐字摘自
`examples/07_capstone/FjKinetics/src/FjKinetics.jl`：

```julia
"""
    AbstractKineticsSolver

Common base of the chemistry solvers. The mechanism-agnostic contract is
[`step_chemistry!`](@ref)(solver, Y, T, rho, dt): `Y` is `ncell x nspec`
species MASS fractions in the solver's species order, `T` cell temperatures,
`rho` cell densities; all are advanced in place by `dt`.
"""
abstract type AbstractKineticsSolver end
```

一个求解器＝这个基类型加两个方法。下面四个定义同样逐字摘自该文件（两行
`nspecies` 与两个 `step_chemistry!` 签名位于文件的不同位置；函数体略去）：

```julia
nspecies(ks::KineticsSolver) = ks.nspec
nspecies(gs::GriSolver) = gs.nspec

function step_chemistry!(ks::KineticsSolver, Y::AbstractMatrix{<:Real},
                         T::AbstractVector{<:Real}, rho::AbstractVector{<:Real},
                         dt::Real)

function step_chemistry!(gs::GriSolver, Y::AbstractMatrix{<:Real},
                         T::AbstractVector{<:Real}, rho::AbstractVector{<:Real},
                         dt::Real)
```

从这些名字里读出契约：

| 参数 | 含义 |
|---|---|
| `Y` | `ncell x nspec` 的组分**质量分数**，按求解器的组分顺序排列，原地推进 |
| `T` | 网格温度，原地推进 |
| `rho` | 网格密度；即使机理用不到它，它也是契约的一部分——单步机理用不到，GRI-Mech 3.0 离不开 |
| `dt` | 每个网格推进多远 |
| `nspecies(solver)` | Fortran 侧每个网格要打包的 `nspec` 列 |

FjKinetics v0.2 在这个基类型下带两个求解器：`OneStepSolver`（
`KineticsSolver` 的别名——反应流 capstone 的单步 Arrhenius 机理）与
`GriSolver`（经 ChemMechSim 的完整机理）。

## 路线一：ChemMechSim 与 GRI-Mech 3.0 capstone

ChemMechSim.jl 是一个处理 Cantera-YAML 反应机理的开源 Julia 包；它自带
GRI-Mech 3.0（53 个组分、325 个反应），位于 ChemMechSim 包内的
`examples/mechanism/gri30.yaml`——该路径在包里，不在本仓库。
对数字之前先记一条版本事项：General 注册表目前收的是 v1.0.0，而仓库已到
v1.2.0；本站所有验证数字都是对着 **v1.2.0** 产出的——先确认你的环境解析到的
是哪一个。

安装只需一个脚本。`scripts/install_sciml_env.jl`——用桥所嵌入的同一个
Julia 1.12.x 运行——创建临时环境 `scripts/sysimage_env`，并把 FortranBridge、
FjKinetics 与你的 ChemMechSim checkout 一起 develop 进去
（`CHEMMECHSIM_PATH` 覆盖 checkout 的位置）。capstone 可执行文件启动时探测
的就是这个环境；`FJ_KINETICS_PROJECT` 可以改指别处。

然后构建示例，先生成 native 基线（`run_gri_native.jl`，用钉版本的 Julia
跑——它拒绝在版本 shim 下运行，因为漂移的基线会打挂验收门，还把账错算到桥
头上）。基准的桥这一侧，摘自 `examples/07_capstone/2_gri_ignition.f90`
——整个化学驱动放在一个 eval 里，于是 Julia 侧的 throw 表现为一个无效结果，
原因在 `get_last_error_message()` 里：

```fortran
    call julia_eval_string( &
        'function fj_gri_run() :: NamedTuple' // new_line('a') // &
        '    gs = FjKinetics.build_gri30_kinetics()' // new_line('a') // &
        '    return FjKinetics.run_gri_ignition(gs)' // new_line('a') // &
        'end')
    res = dummy%call('fj_gri_run')
    if (.not. res%is_valid()) &
        call fail('fj_gri_run failed: ' // get_last_error_message())
```

解出来的数组按批拷回——`ts`（2001 个点）、`T`（2001）以及展平进一个缓冲的
`4 x 2001` 摩尔分数矩阵 `X`：每个数组一次 `%to_fortran`，逐元素的桥流量为
零。`ts` 与 `X` 两段，逐字摘录：

```fortran
    v = res%property('ts')
    if (.not. v%is_valid()) call fail('property ts: ' // get_last_error_message())
    rc = v%to_fortran(ts, int(NSAMPLE, kind=c_int64_t))
    if (rc /= 0) call fail('to_fortran ts: ' // get_last_error_message())

    ! Matrix{Float64} 4x2001, bulk-copied into the flat buffer
    v = res%property('X')
    if (.not. v%is_valid()) call fail('property X: ' // get_last_error_message())
    rc = v%to_fortran(Xflat, int(NSP_OUT * NSAMPLE, kind=c_int64_t))
    if (rc /= 0) call fail('to_fortran X: ' // get_last_error_message())
```

（夹在中间的 `T` 段形状完全相同。）判决权随后在 Fortran 手里——点火判据直接
在取回的数组上计算，与验证脚本用的是同一条：

```fortran
    do k = 1, NSAMPLE - 1
        dtdt(k) = abs((T(k + 1) - T(k)) / (ts(k + 1) - ts(k)))
    end do
    imax = maxloc(dtdt, 1)          ! first occurrence, like Julia's argmax
    t_ign_f = ts(imax + 1)
```

验收是对着 native 运行过四道门——Fortran 算出的 `t_ign`、取回的 `T_end`、
外加两个钉死列主序矩阵布局的 `X` 抽查值——每个的相对差都在 1e-8 以内
（[验证](../intro/validation.md)）。跑出来的头条数字：化学计量比 CH4/空气、
1500 K、1 atm、定容绝热，延迟取在 `argmax |dT/dt|` 处，**t_ign = 1.1075 ms**。

**先钉住环境，再怪别的。** FjKinetics 的 `[compat]` 钉死了求解栈——
Catalyst ~16.2、OrdinaryDiffEq ~6.111、SciMLBase ~2.155——因为一个未钉住的
环境曾经漂到 OrdinaryDiffEq 7.x 线上，其步长控制器把每网格的
`reinit!`/`step!` 模式拖慢约 **700 倍**（一个冻结网格要跑 982 步内部步而不是
1 步）。如果逐网格化学突然变得极慢，先查解析结果；桥是惯常的嫌疑人，也通常
是无辜的。

## 路线二：实现接口

你的机理＝一个子类型加那两个方法。让它即插即用的规矩：

1. **逐字镜像参数形状**（`Y::AbstractMatrix{<:Real}`、
   `T`/`rho::AbstractVector{<:Real}`、`dt::Real`）：capstone 传入的是包装好的
   Fortran 内存及其 `view`，dispatch 落在你的具体类型上。
2. **像内建求解器一样大声校验。** `KineticsSolver` 方法里的守卫对，逐字摘录：

```julia
    size(Y, 1) == ncell && size(Y, 2) == ks.nspec && length(rho) == ncell ||
        error("step_chemistry!: Y must be $(ncell)x$(ks.nspec), rho $(ncell)")
    dt > 0 || error("step_chemistry!: dt must be positive, got $dt")
```

3. **原地推进；返回物理上可容许的状态。** 返回质量分数就保持
   `Y >= 0` 且 `sum(Y) == 1`——`GriSolver` 在闭合求和前会把容差水平的负浓度
   （痕量组分在 `abstol` 处的下冲）钳到零，因为喂给可压缩流求解器一个微观上
   为负的质量分数是真实的危险。
4. **这条路上允许 throw。** 桥接住异常，原因经 `get_last_error_message()`
   浮现在 Fortran 调用点。[两套 SDK，两种速度](two-sdks.md)里的裸函数指针
   路径是唯一的例外：被调函数体不许 throw。
5. **`rho` 是契约的一部分**，哪怕你的机理用不到它；Fortran 总会打包它。

Fortran 侧则完全不用改。capstone 把常驻的网格缓冲一次包装好，此后每个 Strang
半步对活跃网格就是一次批量调用——摘自
`examples/07_capstone/1_reacting_flow.f90`（其上的打包循环略去）：

```fortran
            write (dts, '(es24.16)') dt_half
            write (expr, '(a,i0,a,i0,a,i0,a)') &
                'FjKinetics.step_chemistry!(FJ_KS, view(FJ_Y,1:', n_act, &
                ',:), view(FJ_T,1:', n_act, '), view(FJ_RHO,1:', n_act, &
                '), ' // trim(dts) // ')'
            v_res = julia_eval(trim(expr))
```

换掉 `FJ_KS` 绑定的求解器，同一行代码推进 2 个组分或 53 个：机理完全活在
`view` 的 Julia 一侧。

## 接下来去哪

- [交付形态](deployment-modes.md)——同一套化学的四种交付形态；彼此之间变的
  只有启动。
- [验证](../intro/validation.md)——t_ign = 1.1075 ms 从哪来、背后的验收门。
- [已知限制](known-limitations.md)——这套模式运行其中的边界：单线程、
  `Float64` 数组，以及各自的应对。
