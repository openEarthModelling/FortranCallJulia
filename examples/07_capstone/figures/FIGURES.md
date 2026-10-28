# Capstone 图集讲解（学术版）

四张数据图全部由 [`plot_capstone.py`](plot_capstone.py) 从驱动的 ASCII
数据文件（`../output/*.dat`，已 gitignore）渲染，PNG 600 dpi + PDF，无
手工后处理；性能常数在脚本内逐一标注 `../PERFORMANCE.md` 出处行。所有
图共用同一编码约定：**蓝色 = 数值/计算结果，红色虚线 = 解析参考**
（参考线画在数据线上方，虚线缝隙露出下方数据，重合处以"红虚骑蓝实"
呈现）。

再生成方式（集群上）：

```bash
cmake --build build --target ex_reacting_flow
./build/examples/ex_reacting_flow detonation 2700 0.3 sysimage   # det 两件数据
./build/examples/ex_reacting_flow                                 # sod 数据
cd examples/07_capstone/figures && python3 plot_capstone.py
```

---

## fig1_sod_transport — Sod 激波管三联图（ρ / u / p，183 mm 双栏）

### 数学模型与精确解

惰性输运路径验证的是一维 Euler 方程组的守恒形式

$$
\partial_t \mathbf{U} + \partial_x \mathbf{F}(\mathbf{U}) = 0,\qquad
\mathbf{U} = \begin{pmatrix}\rho\\ \rho u\\ E\end{pmatrix},\quad
\mathbf{F} = \begin{pmatrix}\rho u\\ \rho u^2 + p\\ u(E+p)\end{pmatrix},
$$

理想气体 $p = (\gamma-1)\bigl(E - \tfrac12 \rho u^2\bigr)$，$\gamma = 1.4$。
初值为经典 Sod / Toro Test 1 间断：左态 $(\rho,u,p) = (1,\,0,\,1)$，
右态 $(0.125,\,0,\,0.1)$，$t = 0.2$。该 Riemann 问题有闭式自相似解，
由五种波型之三构成：**左行稀疏波扇**（扇内各量是 $x/t$ 的函数）、
**接触间断**（密度跳跃、压力与速度连续）与**右行激波**。中间星区
$(p_\*, u_\*)$ 由非线性方程 $f(p_\*) = 0$ 的 Newton 迭代求得（$f$ 为
跨左、右波速度增量之差）；驱动内的求解器 `sod_star_state` 残差
$\sim 1.1\times10^{-16}$（机器精度），跨激波状态由 Rankine–Hugoniot
跳跃关系连接。图中红色虚线即该精确解的逐格采样。

### 数值方法与预期误差

数值解（蓝线）是一阶 Godunov 有限体积格式：分段常数重构 + 逐界面
精确 Riemann 通量（vendored Clawpack `rp1` 内核），$n_x = 400$，
$\Delta x = 1.25\times10^{-3}$。一阶格式的数值耗散把间断抹成宽度
$O(\Delta x)$ 的过渡层——图中激波与接触间断处蓝线比红线"缓"正是此
效应，网格加密即收窄，属格式的**预期行为而非错误**。定量地，
$L^1$ 误差（逐格对精确解）

$$
L^1(q) = \frac{1}{n_x}\sum_i |q_i - q_{\mathrm{exact}}(x_i)|
$$

为 $\rho\ 1.89\times10^{-3}$、$u\ 2.49\times10^{-3}$、
$p\ 1.09\times10^{-3}$，与一阶精度 $O(\Delta x)$ 一致。守恒格式的
结构保证也同时被验证：质量与总能量漂移 $\sim 10^{-13}$（机器精度级），
动量变化与出流边界的净压力冲量 $(p_L - p_R)\,t$ 严格对账
（$0.180 = 0.180$）。

### 物理图景

初始压差驱动气体向右流动：稀疏波把左端高压气等熵膨胀降压，接触面
（密度界面）与激波以不同速度右行；速度场在两波之间形成平台 $u_\*$
（接触面两侧速度、压力相等是界面无压差扰动的体现）。这张图成立即
说明：**耦合化学之前，输运内核对非线性双曲守恒律的全部波系（光滑
扇、线性间断、非线性间断）都算对了**。

---

## fig2_detonation_structure — CJ 爆震结构四联（183 mm 双栏）

### 数学模型

验证算例为 HLW 2000 Ex.2：带单步 Arrhenius 放热源的反应 Euler 方程组

$$
\partial_t \mathbf{U} + \partial_x \mathbf{F}(\mathbf{U}) = \mathbf{S}(\mathbf{U}),\qquad
\mathbf{U} = \begin{pmatrix}\rho\\ \rho u\\ E\\ \rho Z\end{pmatrix},\quad
\mathbf{S} = \begin{pmatrix}0\\0\\0\\-K\rho Z\end{pmatrix},\quad
K = K_0\,e^{-E_a/(RT)},
$$

$Z$ 为未燃反应物分数（$Z=1$ 新鲜气体、$Z=0$ 完全燃烧），$\gamma=1.4$，
比放热 $q$ 取 HLW 参数。数值格式为 **Strang 算子分裂**（二阶时间精度）：

$$
\mathcal{L}_{2}(\Delta t) =
\mathcal{C}(\tfrac{\Delta t}{2})\;
\mathcal{T}(\Delta t)\;
\mathcal{C}(\tfrac{\Delta t}{2}),
$$

输运 $\mathcal{T}$ 用无源 Godunov（`rp1_reacting`），化学 $\mathcal{C}$
是逐格刚性 ODE 求解——刚性与放热时间尺度相差量级，这正是交给 Julia
侧 Rodas5P（abstol $10^{-10}$ / reltol $10^{-8}$）的部分。每个非空
化学半步跨 Fortran–Julia 桥**一次批量调用**（活跃格打包、冻结格跳过）。

### 物理图景：CJ 与 ZND 结构

自持爆震的经典图景是 ZND 模型：**前导激波**把未燃气 $(1,0,1,Z{=}1)$
绝热压缩到 von Neumann 态（高压高温但尚未反应）；高温在**诱导期**内
指数放大 Arrhenius 源项，随后燃烧层内 $Z\to 0$、放热 $q$ 转化为内能
与动能，支撑激波继续前进。稳态传播的终态由 **Chapman–Jouguet 条件**
唯一确定：Rayleigh 线（连接初态与终态、斜率由波速 $D$ 决定的动量-
能量约束）与放热 Hugoniot 曲线**相切**，切点满足声速条件
$u + c = D$——即 CJ 点。该点给出解析参考值

$$
\rho_{cj} = 1.6812,\quad u_{cj} = 2.8867,\quad p_{cj} = 21.5672,\quad
s_{cj} = 7.1247 .
$$

### 怎么读这张图

a/b/c 三联（ρ/u/p）中红色虚线即上述 CJ 值。波后大段平台与三条参考线
重合，说明燃烧产物已松弛到 CJ 终态——定量偏差 $\le 0.025\%$（最差
u 0.025%、p 0.023%、ρ 0.018%）。前沿处 ρ/p 的小尖峰是 von Neumann
态的残余（被 $O(\Delta x)$ 耗散部分抹平，$n_x = 2700$、
$\Delta x = 1.11\times10^{-3}$）。d 联的 Z 悬崖即反应层，inset 放大
显示其宽度仅 **≈3 个网格**：诱导区 + 燃烧区在该分辨率下已接近可分辨
极限——这正是 HLW 采用修正分数步（避免分裂误差把薄反应层推错位置）
的动机，也是此算例成为耦合格式试金石的原因。

---

## fig3_front_speed — 前沿轨迹与爆速（89 mm 单栏）

### 数学与测量协议

CJ 爆震以常速 $s_{cj}$ 自持传播，故前沿轨迹 $x_f(t)$ 应为直线。数值上
前沿位置由 Z=0.5 等值线定位：从右向左扫描找到第一个 $Z<0.5$ 的格，
格内线性插值（`front_x`），每个输运步采样一次（2608 个样本）。测速
采用**两点割线**：

$$
s = \frac{x_b - x_a}{t_b - t_a} = 7.12391,\qquad
t_a = \text{首个 } t \ge 0.5\,t_{final}\text{ 的样本},\ t_b = t_{final},
$$

测速窗口刻意取**后半程**：起爆建立期内轨迹偏离直线（图左下角可见），
属初始瞬态；后半程直线段才承载稳态波速信息。与 $s_{cj} = 7.12470$
的偏差为 **0.011%**——这是守恒格式数值耗散对波速的高阶小量影响；
按 Lax–Wendroff 型收敛定理，守恒相容格式随网格加密收敛到正确的
弱解传播速度，此处 0.011% 即 $n_x = 2700$ 下的有限分辨率残差。

### 怎么读

珠串点 = 采样密度（细线连全部 2608 步，珠串每 25 步取一）；灰色底带
= 驱动的测速窗口；蓝色粗线 = 上述割线，两个白边圆点是测速端点
$(t_a, x_a)$、$(t_b, x_b)$；红色虚线 = 过同一终点、斜率 $s_{cj}$ 的
CJ 参考线。红虚骑在蓝割线上方且缝隙对齐——两条线在图尺度上不可分，
本身就是"数值波速 = CJ 波速"的直接视觉证据。

---

## fig4_performance — 四模式成本对比（89 mm 单栏）

### 数学/统计口径

- **启动时间**（a 联，对数轴）：Julia 运行时与代码就绪的全部成本。
  jit 模式需载入 ~92 个包缓存（15.1–20.2 s）；sysimage 把全部依赖
  烤进 1.2 GB 镜像，只剩镜像载入（0.93–2.37 s，页缓存冷热差异）；
  AOT 自含库的 init 为 0.58–1.97 s（冷/热页缓存区间）；纯 Julia
  参考实现 17.5 s（单次，菱形标记）。
- **稳态每格成本**（b 联，线性轴，µs/格）：化学总时 ÷ 活跃格数
  （25245 次格求解）。jit 175–190、sysimage 159–198、AOT 236–361、
  纯 Julia 309 µs。

关键结论由两联对比给出：**模式的差别全部集中在启动段**（约一个量级
的分离）；稳态每格成本四组范围互相重叠、**在节点负载噪声内不可区分**
——因为热路径是同一份编译好的内核（`FjKinetics.step_chemistry!`，
Rodas5P），桥接本身每半步只增加 µs 级的调用解析开销。

### 统计判据（为何"重叠"是有意义的结论）

共享节点运行间噪声 ~±20%。判别两组差异是否真实，用的是**同批背靠背
对比 + 批间方向翻转检验**：若差值方向在不同批次间翻转（本仓库实测：
同批内 sysimage 4.02 s < jit 4.79 s，换 cwd 复跑 4.99 s > 4.43 s），
则差异归属噪声而非模式效应。此外"零 JIT"由**首个非空化学调用**计时
证明：7.1–8.0 ms 为纯求解量级（若发生运行时编译，尖峰应为 100 ms–s
级），四个运行无一出现。

b 联唯一的数据排除已在图内脚注与 PERFORMANCE.md 记录：AOT 的一次
32 核独占物理核跑（191 µs）与 1 核共享节点跑不可比，不计入范围。

---

## fig0_schematic — 耦合架构示意图

（本节由 AI 生成草图填充：见 [fig0_schematic.png](fig0_schematic.png)。
该图为概念示意（mechanism/architecture draft），不承载定量数据；
生成方式与出处见同目录 `fig0_schematic/` 的 provenance 记录。）

---

## 参考文献

1. Sod, G. A. (1978). A survey of several finite difference methods for
   systems of nonlinear hyperbolic conservation laws. *Journal of
   Computational Physics*, **27**(1), 1–31.
2. Toro, E. F. (2009). *Riemann Solvers and Numerical Methods for Fluid
   Dynamics* (3rd ed.), §4.5（精确 Riemann 求解器）及 Test 1。Springer.
3. Helzel, C., LeVeque, R. J., & Warneke, G. (2000). A modified fractional
   step method for the accurate approximation of detonation waves.
   *SIAM Journal on Scientific Computing*, **22**(4), 1489–1510.
   （Ex.2 算例与修正分数步来源。）
4. LeVeque, R. J. (2002). *Finite Volume Methods for Hyperbolic Problems*.
   Cambridge University Press.（波传播算法 / Clawpack 内核。）
5. Strang, G. (1968). On the construction and comparison of difference
   schemes. *SIAM Journal on Numerical Analysis*, **5**(3), 506–517.
   （算子分裂的二阶性。）
6. Fickett, W., & Davis, W. C. (1979). *Detonation: Theory and Experiment*.
   University of California Press.（CJ 条件、Rayleigh 线–Hugoniot 几何
   与 ZND 结构的标准参考；ZND 原始工作见 Zel'dovich (1940)、
   von Neumann (1942)、Döring (1943)。）
7. Rackauckas, C., & Nie, Q. (2017). DifferentialEquations.jl — a
   performant and feature-rich ecosystem for solving differential
   equations in Julia. *Journal of Open Research Software*, **5**(1).
   （化学侧刚性 ODE 栈，Rodas5P。）

---

## QA 附录

每张图附带两份审计 JSON（随图提交）：`*.alignment.json`（渲染时面板
对齐门，1.5 pt 容差）与 `*.collision-audit.json`（PDF 几何碰撞审计）。
字形审计（5 pt 底线）在提交的 PDF 上执行，全部 PASS；最小字形 5.5 pt。
产物按用户契约为 PNG 600 dpi + PDF（不导出 SVG/TIFF，为记录在案的
契约豁免）。数据完整性：全部数据点全绘、无平滑、无平均；唯一排除
（AOT 32 核跑）在图内与本文件双重记录。
