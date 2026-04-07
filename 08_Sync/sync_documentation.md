# 时变信道下的同步技术文档

> **文档版本**：v1.0 · **适用标准**：5G NR / LTE / V2X / LEO 卫星通信  
> **关键词**：帧同步、符号同步、位同步、多普勒、时变信道、OFDM、OTFS

---

## 目录

1. [基本概念与系统模型](#1-基本概念与系统模型)
2. [帧同步（Frame Synchronization）](#2-帧同步frame-synchronization)
3. [符号同步（Symbol Synchronization）](#3-符号同步symbol-synchronization)
4. [位同步（Bit Synchronization）](#4-位同步bit-synchronization)
5. [三层同步的联合设计](#5-三层同步的联合设计)
6. [应用场景与参数选取指南](#6-应用场景与参数选取指南)

---

## 1. 基本概念与系统模型

### 1.1 时变信道模型

时变信道（Time-Varying Channel）的数学模型为：

$$y(t) = \int h(\tau, t) \cdot x(t - \tau) \, d\tau + n(t)$$

其中 $h(\tau, t)$ 为时延-时间二维冲激响应，$\tau$ 为多径时延，$t$ 为时变量。

### 1.2 核心信道参数

| 参数 | 定义 | 典型值范围 | 意义 |
|------|------|-----------|------|
| 多普勒频移 $f_d$ | $f_d = v/\lambda = v \cdot f_c / c$ | 1 Hz ~ 数十kHz | 运动引起的频率偏移 |
| 相干时间 $T_c$ | $T_c \approx 1 / (2\pi f_d)$ | μs ~ ms 级 | 信道保持稳定的时间 |
| 多径时延扩展 $\tau_{rms}$ | 各径时延均方根值 | 10 ns ~ 数μs | 引起 ISI 的根本原因 |
| 相干带宽 $B_c$ | $B_c \approx 1 / \tau_{rms}$ | kHz ~ MHz | 信道响应基本不变的带宽 |
| 归一化多普勒 $\nu$ | $\nu = f_d \cdot T_s$ | 0.0001 ~ 0.5 | 判断时变严重程度 |

### 1.3 归一化多普勒 $\nu$ 的判断准则

| $\nu$ 范围 | 信道状态 | 同步策略 |
|---|---|---|
| $\nu < 0.001$ | 准静态信道 | 传统方法有效 |
| $0.001 \sim 0.01$ | 慢时变 | 导频插值跟踪 |
| $0.01 \sim 0.1$ | 中速时变 | BEM 建模 + EKF |
| $\nu > 0.1$ | 快时变 | OTFS / 联合 ML 估计 |

### 1.4 三层同步层次结构

```
接收信号 r(t)
    │
    ▼
┌─────────────────────────────┐
│       帧同步（粗粒度）        │  ← 确定帧边界 k₀
│  相关检测 / Schmidl-Cox      │
└─────────────┬───────────────┘
              │ k₀ + 粗 CFO 估计
              ▼
┌─────────────────────────────┐
│      符号同步（中粒度）       │  ← 确定采样时刻 τ̂
│  TED 环路 / BEM / OTFS      │
└─────────────┬───────────────┘
              │ τ̂ + 精细频偏
              ▼
┌─────────────────────────────┐
│      位同步（精细粒度）       │  ← 实时相位跟踪
│  PLL / Kalman / PT-RS       │
└─────────────┬───────────────┘
              │
              ▼
        均衡 → 解调 → 译码
```

---

## 2. 帧同步（Frame Synchronization）

### 2.1 任务定义

帧同步是最粗粒度的时间对齐，目标是在连续比特流中**定位帧的起始边界** $k_0$，为后续同步层提供时间参考。

**主要任务：**
- 定位帧起始位置 $k_0$
- 识别前导码 / 同步字（SFD）
- 粗略估计信道时延
- 提供给符号同步的时间基准

### 2.2 时变信道的挑战

| 挑战 | 原因 | 影响 |
|------|------|------|
| 相关峰展宽 | 多普勒扩散使前导码失真 | 峰值模糊，难以定位 |
| 峰值位置漂移 | 速度变化改变时延 | 帧边界估计偏移 |
| 固定阈值失效 | SNR 随时变波动 | 检测率下降 |
| 多路径干扰 | 多径使相关函数出现旁瓣 | 虚警率上升 |

### 2.3 核心算法

#### 2.3.1 滑动相关检测（基础方法）

$$R(k) = \left| \sum_{n=0}^{N-1} r(n+k) \cdot s^*(n) \right|^2$$

帧边界估计：$\hat{k}_0 = \arg\max_k R(k)$

**时变改进**——二维时延-多普勒搜索：

$$\hat{k}_0 = \arg\max_k \max_{f \in [-f_{d,\max}, f_{d,\max}]} \left| \sum_{n=0}^{N-1} r(n+k) s^*(n) e^{-j2\pi f n T_s} \right|^2$$

#### 2.3.2 Schmidl-Cox 自相关法（OFDM 专用）

利用 OFDM 循环前缀（CP）的周期性：

$$M(d) = \frac{\left|\sum_{m=0}^{L-1} r^*(d+m) r(d+m+N)\right|^2}{\left(\sum_{m=0}^{L-1} |r(d+m+N)|^2\right)^2}$$

粗 CFO 估计：

$$\hat{\varepsilon} = \frac{1}{2\pi} \angle \sum_{m=0}^{L-1} r^*(m) r(m+N)$$

#### 2.3.3 Kalman 帧跟踪

建立帧偏移状态方程，适用于平稳运动场景：

$$k_{0}[n+1] = k_{0}[n] + \Delta k[n] + w[n]$$
$$y[n] = k_{0}[n] + v[n]$$

### 2.4 算法对比

| 算法 | 时变鲁棒性 | 计算复杂度 | 适用场景 |
|------|-----------|-----------|---------|
| 滑动相关 | 弱 | $O(N^2)$ | 低速 (<30 km/h) |
| Schmidl-Cox | 中 | $O(N)$ | 中速 OFDM (<120 km/h) |
| 联合 CFO 补偿相关 | 强 | $O(N \cdot M)$ | 高速/卫星 (>300 km/h) |
| Kalman 帧跟踪 | 强 | $O(N)$ | 平稳运动场景 |

---

## 3. 符号同步（Symbol Synchronization）

### 3.1 任务定义

符号同步的目标是**确定每个符号的最优采样时刻 $\hat{\tau}$**，同时完成精确的载波频率偏移（CFO）估计与补偿。

**主要任务：**
- 确定最优采样时刻 $\hat{\tau}$（消除 ISI）
- 精确估计并补偿 CFO $\Delta\hat{f}$
- 抑制子载波间干扰（ICI）
- OFDM：整数 + 小数定时偏移分离

### 3.2 OFDM 中的 ICI 问题

当多普勒频移 $f_d$ 不可忽视时，OFDM 子载波正交性被破坏：

$$Y_k = H_k X_k + \underbrace{\sum_{l \neq k} C_{k-l} X_l}_{\text{ICI 项}} + N_k$$

ICI 系数为：

$$C_{k-l} = \frac{1}{N} \sum_{n=0}^{N-1} h(n) e^{j2\pi(l-k+\nu)n/N}$$

其中归一化多普勒 $\nu = f_d T_s$，ICI 功率正比于 $\nu^2$。

### 3.3 定时恢复环路（TED Loop）

标准定时恢复结构：

```
r(t) → [匹配滤波 MF/RRC] → [可控采样器 NCO] → y[n]
                                  ↑                    │
                               [VCO/NCO] ← [PI 环路滤波] ← [TED 误差检测]
```

#### 常用 TED 算法

**Gardner 算法**（推荐，无需判决，时变鲁棒性强）：

$$e[n] = y\left[n - \tfrac{1}{2}\right] \left(y[n] - y[n-1]\right)$$

**Mueller-Müller 算法**（需要判决反馈）：

$$e[n] = y[n-1]\hat{a}[n] - y[n]\hat{a}[n-1]$$

**联合 ML 估计**（最优，计算复杂度高）：

$$\hat{\tau} = \arg\max_\tau \, p(\mathbf{r} | \tau, \mathbf{h})$$

#### TED 算法对比

| 算法 | 时变适应性 | 是否需要判决 | 计算复杂度 | 推荐场景 |
|------|-----------|------------|-----------|---------|
| Gardner | 强 | 否 | 低 | 时变通用首选 |
| Mueller-Müller | 中 | 是 | 低 | 高 SNR 静态场景 |
| CP 自相关 | 强 | 否 | 低 | OFDM 专用 |
| 联合 ML | 最强 | 否 | 高 | 高可靠性场景 |

### 3.4 OFDM 符号同步的三子任务

| 子任务 | 方法 | 估计量 |
|--------|------|--------|
| 整数倍定时偏移 | CP 边界相关检测 | $\Delta k \in \mathbb{Z}$ |
| 小数倍采样偏移 | 细调 NCO 相位 | $\epsilon \in (-0.5, 0.5)$ |
| 残余 CFO 补偿 | 频域相位校正 | $\Delta\hat{f}$ |

### 3.5 高速时变场景的进阶方案

#### 基扩展模型（BEM）

将时变信道在一段时间内展开为基函数线性组合：

$$h(\tau, t) = \sum_{q=0}^{Q-1} c_q(\tau) \cdot b_q(t)$$

- **CE-BEM**：$b_q(t) = e^{j2\pi q \Delta f t}$（复指数基，对应多普勒）
- **P-BEM**：$b_q(t) = t^q$（多项式基）
- **DCT-BEM**：离散余弦基

#### OTFS 调制（时延-多普勒域）

$$x_{DD}[\ell, k] \xrightarrow{\text{ISFFT}} x_{TF}[n,m] \xrightarrow{\text{Heisenberg变换}} s(t)$$

OTFS 将每个时延-多普勒格点上的信道系数近似为常数，从根本上解决快时变问题。

---

## 4. 位同步（Bit Synchronization）

### 4.1 任务定义

位同步（时钟恢复 + 相位跟踪）的目标是**从接收信号中恢复发端时钟相位**，并实时补偿时变信道引起的相位旋转，维持相干解调条件。

**主要任务：**
- 恢复符号级时钟相位
- 实时跟踪相位漂移 $\theta(t)$
- 补偿残余频率偏差
- 维持相干解调的相位基准

### 4.2 时变信道中的相位漂移

时变信道相位不再为常数：

$$\theta(t) = \theta_0 + 2\pi \int_0^t \Delta f(\tau) \, d\tau$$

其中 $\Delta f(t) = \frac{v(t)}{c} \cdot f_c$ 随速度持续变化，要求接收端具备**快速跟踪能力**。

### 4.3 锁相环（PLL）位同步

#### 基本 PLL 递推方程

**相位误差检测：**

$$e_\phi[n] = \text{Im}\left\{y[n] \cdot \hat{a}^*[n] \cdot e^{-j\hat{\phi}[n]}\right\}$$

**相位估计更新（二阶 PI 滤波器）：**

$$\hat{\phi}[n+1] = \hat{\phi}[n] + \alpha_1 e_\phi[n] + \alpha_2 \sum_{k=0}^{n} e_\phi[k]$$

#### PLL 参数设计（时变场景）

| 参数 | 静态信道 | 慢时变 | 快时变 |
|------|---------|--------|--------|
| 环路带宽 $B_L$ | ~0.001 $f_s$ | ~0.01 $f_s$ | ~0.05 $f_s$ |
| 滤波器阶数 | 1阶 | 2阶 PI | 3阶 PID |
| 跟踪误差 | 极小 | 小 | 中等（需权衡噪声） |

> **设计权衡**：环路带宽越宽 → 跟踪快速相位变化能力越强，但噪声容限越差。需根据 $f_d T_s$ 选取最优 $B_L$。

### 4.4 三种位同步结构

#### 方案一：闭环 PLL 跟踪

```
r(t) → 匹配滤波 → 采样 → 相位检测(PD) → PI滤波器 → VCO
                    ↑__________________________________|
```

适用：慢时变场景，连续相位跟踪。

#### 方案二：判决反馈相位跟踪（DFPT）

$$\hat{\phi}[n] = \hat{\phi}[n-1] + \mu \cdot \text{Im}\left\{y[n] \cdot \hat{a}^*[n]\right\}$$

适用：中速时变，误码率较低时可靠性高。

#### 方案三：Kalman 滤波器联合跟踪

状态向量：$\mathbf{x} = [\phi, \Delta f, \Delta(\Delta f)]^T$

状态方程：

$$\mathbf{x}[n+1] = \mathbf{A} \mathbf{x}[n] + \mathbf{w}[n], \quad \mathbf{A} = \begin{bmatrix} 1 & T_s & T_s^2/2 \\ 0 & 1 & T_s \\ 0 & 0 & 1 \end{bmatrix}$$

观测方程：

$$z[n] = \mathbf{C} \mathbf{x}[n] + v[n], \quad \mathbf{C} = [1, 0, 0]$$

适用：高速时变，能联合跟踪相位、频偏和频偏斜率。

#### 三种方案对比

| 方案 | 时变跟踪能力 | 实现复杂度 | 对误码的敏感性 | 推荐场景 |
|------|-----------|-----------|--------------|---------|
| 闭环 PLL（2阶） | 中 | 低 | 低 | LTE/慢时变 |
| 判决反馈 | 中强 | 低 | 高 | 高 SNR 中速 |
| Kalman 联合跟踪 | 强 | 中 | 低 | 5G/高速/V2X |

### 4.5 5G NR PT-RS 导频辅助相位跟踪

**PT-RS（Phase Tracking Reference Signal）** 是 5G NR Release 15 引入的专用相位跟踪导频：

#### 相位估计

$$\hat{\theta}[k] = \angle \left( y_p[k] \cdot p^*[k] \right)$$

其中 $p[k]$ 为已知导频序列，$y_p[k]$ 为导频位置接收值。

#### 插值补偿

在非导频位置用线性插值估计相位：

$$\hat{\theta}[n] = \hat{\theta}[k_1] + \frac{n - k_1}{k_2 - k_1}\left(\hat{\theta}[k_2] - \hat{\theta}[k_1]\right), \quad k_1 \leq n \leq k_2$$

#### PT-RS 密度自适应规则

| 速度（km/h） | 建议 PT-RS 时域间隔 | 目的 |
|-------------|-------------------|------|
| < 30 | 每 4 个 OFDM 符号 | 降低开销 |
| 30 ~ 120 | 每 2 个 OFDM 符号 | 平衡精度与开销 |
| > 120 | 每个 OFDM 符号 | 精确跟踪快速相位变化 |

---

## 5. 三层同步的联合设计

### 5.1 层间依赖关系

```
帧同步误差 Δk₀  →  造成符号定时偏差  →  加重相位跟踪负担
符号定时误差 Δτ  →  引入 ISI / ICI    →  使位同步相位基准混乱
位同步相位误差   →  影响判决反馈 TED   →  加剧符号同步精度
```

**关键约束：**
- 帧同步精度需优于 $T_{CP}/4$（CP 长度的四分之一）
- 符号定时偏差需小于 $T_s / 10$
- 相位跟踪残差需小于 $\pi / (2M)$（$M$ 为调制阶数）

### 5.2 联合迭代同步架构

在高可靠性系统（如 5G NR 高速场景）中，三层同步与信道估计进行**交替迭代**：

```
第 1 轮（粗同步）
帧同步 → 符号同步（粗）→ 位同步（粗）→ 信道估计（初始）
                                              │
                                              ↓（反馈精化）
第 2 轮（精同步）
符号同步（精）→ 位同步（精）→ 信道估计（更新）→ 均衡解调
```

### 5.3 三层同步完整对比

| 维度 | 帧同步 | 符号同步 | 位同步 |
|------|--------|---------|--------|
| **目标** | 帧边界 $k_0$ | 采样时刻 $\hat{\tau}$ + CFO | 相位/时钟跟踪 |
| **精度** | 帧级 (ms) | 符号级 (μs) | 亚符号级 (ns) |
| **时变主要影响** | 相关峰展宽/偏移 | ISI + ICI | 相位旋转 + 频偏漂移 |
| **核心算法** | 滑动相关/Schmidl-Cox | Gardner TED / ML | PLL / Kalman / PT-RS |
| **更新频率** | 每帧一次 | 每符号 1–4次 | 每符号 / 每导频 |
| **高速场景策略** | 联合 CFO 补偿相关 | BEM + OTFS | 宽带宽 PLL / EKF |
| **5G NR 对应** | PSS/SSS 检测 | DMRS 辅助定时 | PT-RS 相位跟踪 |

---

## 6. 应用场景与参数选取指南

### 6.1 场景分类

| 场景 | 典型速度 | 多普勒 $f_d$ | 归一化 $\nu$ (@15kHz SCS) | 推荐同步策略 |
|------|---------|------------|--------------------------|------------|
| 低速行人 | ~5 km/h | ~9 Hz | ~0.0006 | 稀疏导频 + 线性插值 |
| 车载 V2X | ~120 km/h | ~222 Hz | ~0.015 | 密集导频 + EKF 跟踪 |
| 高铁 HSR | ~350 km/h | ~648 Hz | ~0.043 | BEM + OTFS 帧结构 |
| 水声通信 | ~10 节 | 大时延扩展 | — | 稀疏信道估计 + 迭代均衡 |
| LEO 卫星 | ~7.5 km/s | 数十 kHz | >1 | 多普勒预补偿 + 专用帧 |

### 6.2 同步方案选择流程

```
判断 ν = f_d · T_s
       │
  ν < 0.001 ──→ 标准 PLL + 稀疏导频（低开销）
       │
  0.001 ~ 0.01 → Gardner TED + 2阶 PLL + 导频辅助
       │
  0.01 ~ 0.1 ──→ BEM 信道模型 + EKF + 密集 PT-RS
       │
  ν > 0.1 ─────→ OTFS 调制 OR 联合 ML 估计 + 宽带宽 Kalman
```

### 6.3 5G NR 同步信号结构（参考）

```
一个时隙（14个OFDM符号）中的参考信号分布：

符号 0  1  2  3  4  5  6  7  8  9  10  11  12  13
     D  D  DM D  D  PT D  D  DM  D   D  PT   D   D
         ↑              ↑        ↑           ↑
        DMRS           PT-RS   DMRS        PT-RS

DMRS：信道估计 + 粗定时        D = 数据符号
PT-RS：精细相位跟踪            频率轴上稀疏插入（每4个子载波一个PT-RS）
```

---

## 参考文献

1. Schmidl, T. M., & Cox, D. C. (1997). *Robust frequency and timing synchronization for OFDM*. IEEE Transactions on Communications.
2. Gardner, F. M. (1986). *A BPSK/QPSK timing-error detector for sampled receivers*. IEEE Transactions on Communications.
3. Bajwa, W. U., et al. (2010). *Compressed channel sensing: A new approach to estimating sparse multipath channels*. Proceedings of the IEEE.
4. Raviteja, P., et al. (2018). *Interference cancellation and iterative detection for orthogonal time frequency space modulation*. IEEE Transactions on Wireless Communications.
5. 3GPP TS 38.211 (2023). *NR; Physical channels and modulation*. Release 17.
