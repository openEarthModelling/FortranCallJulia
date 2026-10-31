---
title: 验收门
sync: 2026-10-31
---

# 验收门

桥复现原生计算时才是正确的。这个说法是被检查的，不是被声明的：一组示例
可执行文件把桥接结果与原生基准比对，打印响亮的 PASS 哨兵串、失败即非零
退出。没有 `ctest` 接线（[已知限制](../user/known-limitations.md)）——门
靠手工跑，本页就是跑门人的手册：每道门查什么、怎么跑，以及整套流程唯一
会无声骗你的方式（版本漂移的基准）。

门在物理上意味着什么，见[验证](../intro/validation.md)页；这里只讲机制与
维护纪律。

## 门清单

| 哨兵串 | 示例 | 检查 |
|---|---|---|
| `SOD_VALIDATION_PASS` | `07_capstone/1_reacting_flow.f90`（sod 模式） | Sod 管与精确 Riemann 解 |
| `DETONATION_VALIDATION_PASS` | `07_capstone/1_reacting_flow.f90`（detonation 模式） | CJ 爆震速度 vs 解析 Chapman--Jouguet 值 |
| `EX_CAPSTONE_GRI_IGNITION_PASS` | `07_capstone/2_gri_ignition.f90` | 对原生 Julia 跑的四个门控量（下文） |
| `DEMO_PASS` | `06_sciml/3_sciml_demo.f90` | SciML 回调 demo 端到端 |

爆震门是物理头条检查：nx = 2700 时算得的前沿速度为 **7.12391**，解析 CJ
速度 **7.12470**——偏差 **0.011%**，燃烧态距 CJ 在 0.025% 以内（u 0.025%、
p 0.023%、rho 0.018%）。（nx = 400 时同一道门以 +8.53% 响亮失败并说明
原因：欠解析是错误，不是通过。）

## 四量 GRI 门

`2_gri_ignition.f90` 门的不是一个数而是四个，容差相同——点火延迟
`t_ign`（**1.1075 ms**）、末端温度 `T_end`、以及两个专门钉死布局敏感的
`4 x 2001` 列主序矩阵提取的摩尔分数抽查值（t = 0 的 `CH4`、t_end 的
`CO2`）。判决块逐字摘自 `examples/07_capstone/2_gri_ignition.f90`：

```fortran
    rel = abs(t_ign_f - t_ign_nat) / t_ign_nat
    rel_t = abs(T(NSAMPLE) - t_end_nat) / t_end_nat
    rel_x1 = abs(x_at(1, 1) - x_ch4_nat) / x_ch4_nat
    rel_x2 = abs(x_at(3, NSAMPLE) - x_co2_nat) / x_co2_nat
    ...
    if (rel < REL_TOL .and. rel_t < REL_TOL .and. rel_x1 < REL_TOL &
        .and. rel_x2 < REL_TOL) then
        print *, 'EX_CAPSTONE_GRI_IGNITION_PASS'
```

其中 `REL_TOL = 1.0e-8_c_double`。在正确钉死的运行时下，四个偏差**恰好
为 0**，全轨迹叠合审计的最坏序列残差低于 1e-12（实测 ~8.3e-13，落在最陡
的 CO2 上升段）。两个 `X` 门是布局绊线：列主序展平一旦出错，`X(1,1)` 读
到的就是别的物种，门以数量级失败，而不是以边缘失败。

注意门控的是什么：收敛标量，不是逐点轨迹。同一刚性系统的两次独立求解，
即使在同一运行时下，过渡段的少数点也会差在末位；逐点设门必然 flake，
而这四个标量稳定。门又足够紧，以至于*错误的运行时*溜不进去——这就是下
一节。

## 跑门

构建时打开示例，然后**先**生成原生基准，再跑桥侧。配方出自
`examples/07_capstone/2_gri_ignition.f90` 的文件头（下面的 Julia 路径是占
位符——用你钉死的 1.12.7 二进制，不要用版本 shim）：

```text
    cd build/examples
    <pinned-julia-1.12.7>/bin/julia --project=../../scripts/sysimage_env \
        ../../examples/07_capstone/run_gri_native.jl
    ./ex_capstone_gri_ignition
```

基准脚本写 `gri_native.dat`（四个参考值）与完整原生轨迹
`output/gri_native_series.csv`；可执行文件读 `.dat`、经桥跑同一条
FjKinetics 调用路径、取回数组，然后打印四个相对偏差加哨兵串。其余门不
需要基准步骤——它们的参考是解析的或内建的。

过期基准会被响亮抓住：可执行文件拒绝格式与当前脚本不符的 `.dat`，并给
出"重新生成"提示。

## 陷阱：漂移的基准让门失败、还嫁祸给桥

验收比较只有在**两边跑同一个 Julia** 时才有意义。桥可执行文件内嵌构建钉
死的 `libjulia` 1.12.7；原生基准却由路径上的那个 `julia` 生成。在
`julia` 实为自动更新版本 shim 的机器上，这一对悄悄错开——而失败方式很
恶劣：门把桥的取数通道报成嫌疑人，因为被测的是桥这一侧。

这不是假设，是真事。一次用指向 1.13.2 的 shim 重新生成的基准，让四道门
中的两道报出非零余量（0 / 1.74e-9 / 0 / 6.75e-9，最坏 6.75e-9）——看着
像通过，实际已中毒——而过渡窗上逐点漂移达 **T rel 1.5e-5**、
**CH4 rel 0.54**。1e-8 的门被*基准错位*轻松跨越，调查
却先追了求解器非确定性与线程归约顺序。用钉死二进制重新生成基准，四个偏
差一夜之间全归零。完整故事见[教训](lessons.md)；工程残留是两道守卫。

运行时守卫，逐字摘自 `examples/07_capstone/run_gri_native.jl`（原错误串
写的是开发者本机安装路径；此处缩短为占位符）：

```julia
const BRIDGE_JULIA = v"1.12.7"   # the libjulia the bridge executable links
VERSION == BRIDGE_JULIA || error(
    "native baseline must be generated with the bridge-pinned Julia " *
    "$BRIDGE_JULIA (this is $(VERSION)) -- use the pinned 1.12.7 binary, " *
    "not the juliaup shim. A different runtime drifts at the ignition " *
    "transition and fails the 1e-8 gates while wrongly indicting the " *
    "bridge extraction.")
```

构建侧的孪生兄弟是 `CMakeLists.txt` 里的 `FJ_BUILD_SYSIMAGE` 守卫：配置期
拒绝一切 1.12.x 线以外的 Julia，并把话挑明（"不要用 juliaup shim"）。

## 维护纪律

1. **每次都用钉死二进制重新生成基准。** 守卫让任何别的选择都变得响亮。
2. **桥改动之后跑全部四道门**，不是只跑离你改动最近的那道。过去一次审查
   修复引入的回归，只有新加的 `X` 门当场抓住——仅有 t_ign 一道门时，双
   重间接的物种索引 bug 一直绿着。
3. **看余量，不只是看哨兵串。** 门会打印四个偏差；全零才是健康的稳态。
   任何持续停在 1e-9 的值都意味着基准又错位了——先找运行时，再碰桥。

## 接下来去哪

- [教训](lessons.md)——漂移事故全貌，以及本页默认成立的其余规则。
- [从零重建](rebuild.md)——重新生成门所依赖的 sysimage 与 AOT 产物。
- [验证](../intro/validation.md)——每道门背后的物理。
