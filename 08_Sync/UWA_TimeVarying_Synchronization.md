# 水声通信时变信道同步方法

> **文档定位**：本文档系统梳理时变水声信道下的同步失效机理与解决方案，涵盖帧同步、符号定时、载波同步三层体系，以及 HFM 定时偏置的消除方法，可直接作为 MATLAB 代码编写依据。

---

## 目录

1. [问题背景：为什么时变信道让同步失效](#1-问题背景为什么时变信道让同步失效)
2. [同步失效的三重机制](#2-同步失效的三重机制)
3. [同步体系总览](#3-同步体系总览)
4. [第一层：帧同步——同步序列的选择](#4-第一层帧同步同步序列的选择)
   - 4.1 LFM 信号及其缺陷
   - 4.2 HFM 信号的多普勒不变性
   - 4.3 HFM 定时偏置问题与消偏方案
   - 4.4 m 序列模糊度函数法
   - 4.5 三种方法性能对比
5. [第二层：符号定时同步——处理帧内漂移](#5-第二层符号定时同步处理帧内漂移)
   - 5.1 时变定时漂移的累积模型
   - 5.2 逐符号重采样（OFDM）
   - 5.3 SC-FDE 分块定时跟踪
   - 5.4 CP 自适应定时（加速度修正）
6. [第三层：载波同步——频率与相位跟踪](#6-第三层载波同步频率与相位跟踪)
   - 6.1 残余 CFO 与相位漂移模型
   - 6.2 决策导向锁相环（DD-PLL）
   - 6.3 导频辅助逐符号相位跟踪
7. [双 HFM 定时偏置的完整解决方案](#7-双-hfm-定时偏置的完整解决方案)
   - 7.1 偏置机理推导
   - 7.2 正负 HFM 组合消偏（核心方法）
   - 7.3 速度谱扫描法
   - 7.4 闭合公式直接修正
   - 7.5 多 HFM 相关求和法
8. [各体制专用同步流程](#8-各体制专用同步流程)
   - 8.1 OFDM 系统
   - 8.2 SC-FDE 系统
   - 8.3 OTFS 系统
9. [MATLAB 实现规范](#9-matlab-实现规范)
   - 9.1 函数接口汇总
   - 9.2 双 HFM 帧同步（含消偏）
   - 9.3 逐符号多普勒跟踪
   - 9.4 DD-PLL 载波同步
10. [参数设计指南](#10-参数设计指南)
11. [性能评估指标](#11-性能评估指标)

---

## 1. 问题背景：为什么时变信道让同步失效

水声信道的"时变性"区别于无线电信道，其根本原因在于**声速极低**（$c \approx 1500$ m/s），任何相对运动都会产生显著的宽带多普勒效应：

$$\alpha = v/c$$

典型数值对比：

| 场景 | 相对速度 $v$ | 多普勒因子 $\alpha$ | 100 符号后累积定时误差 |
|------|------------|-------------------|----------------------|
| 无线电（$c=3\times10^8$ m/s，$v=100$ m/s） | 100 m/s | $3.3\times10^{-7}$ | 忽略不计 |
| 水声（$c=1500$ m/s，$v=1$ m/s） | 1 m/s | $6.7\times10^{-4}$ | 0.067 个符号 |
| 水声（$c=1500$ m/s，$v=15.4$ m/s，即 30 kn） | 15.4 m/s | $1.03\times10^{-2}$ | **1.03 个符号** |

30 节的收发相对运动速度，仅传输 100 个符号后，同步误差已累积约 1 个符号宽度，导致后续所有符号的解调失败。

---

## 2. 同步失效的三重机制

### 2.1 机制一：宽带多普勒时间伸缩（最根本）

水声多普勒不是简单的频偏，而是整个时间轴的"橡皮拉伸"：

$$r(t) = \sum_{p=1}^{P} a_p \cdot s\!\left(\frac{t - \tau_p}{1+\alpha}\right) + n(t)$$

固定帧长的相关器假设信号长度不变，实际长度变为 $(1+\alpha)T$，导致：

- 互相关峰值偏移（LFM 信号严重，HFM 信号出现定时偏置）
- 越到帧尾，累积定时误差越大
- CP 长度与多径时延的匹配关系被破坏

### 2.2 机制二：时变多普勒（加速度效应）

实际场景中速度往往不恒定，多普勒因子随时间变化：

$$\alpha(t) = \alpha_0 + \dot{\alpha} \cdot t$$

这导致：

- 假设"帧内多普勒恒定"的 CP 自相关法失效
- 帧头估计的 $\hat{\alpha}$ 在帧尾已过时，补偿不准
- 速度方向突变时，相邻两帧的多普勒可能差异巨大

### 2.3 机制三：多径与多普勒的联合模糊

多径使互相关输出出现多个峰值：

$$|R(\tau)|^2 = \left|\sum_{p=1}^{P} a_p \cdot e^{-j2\pi f_c \tau_p} \cdot R_s\!\left(\tau - \tau_p - \Delta\tau_{Doppler}\right)\right|^2$$

多径分量的叠加使主峰展宽、旁瓣抬高，导致：

- 难以区分"最早到达的直达波"与"最强的多径分量"
- 多普勒估计精度下降（多路径各自带来不同偏置）
- 低信噪比下伪峰干扰同步决策

---

## 3. 同步体系总览

时变信道下的同步需要三层协同工作：

```
接收信号 r[n]
    │
    ▼ ─────────────────────────────────────────────────────
【第一层】帧同步（粗定时 + 多普勒粗估计）
    目标：找到帧起始位置 τ̂，获得多普勒粗估计 α̂_coarse
    工具：双 HFM / m 序列 / LFM（各有适用场景）
    输出：τ̂（帧头位置），α̂_coarse（精度 ~10⁻³）
    │
    ▼ ─────────────────────────────────────────────────────
【第二层】符号定时同步（细定时 + 帧内漂移跟踪）
    目标：处理帧内定时随时间漂移，逐符号/逐块精确对齐
    工具：逐符号重采样 / CP 自适应定时 / 分块定时修正
    输出：每个符号/块的精确采样起点
    │
    ▼ ─────────────────────────────────────────────────────
【第三层】载波同步（频率 + 相位跟踪）
    目标：估计并持续跟踪残余 CFO 和相位噪声
    工具：DD-PLL / 导频辅助逐符号相位跟踪
    输出：每个符号的相位补偿量
    │
    ▼ ─────────────────────────────────────────────────────
        均衡 → 解调 → 译码
```

---

## 4. 第一层：帧同步——同步序列的选择

### 4.1 LFM 信号及其缺陷

线性调频信号（LFM）的瞬时频率线性变化：

$$s_{LFM}(t) = A \cdot \exp\!\left(j2\pi\!\left(f_0 t + \frac{k}{2}t^2\right)\right), \quad k = B/T$$

**多普勒耦合问题**：LFM 的模糊函数在时延-多普勒平面上是斜线型，即多普勒偏移会被"误读"为时延偏移：

$$\Delta\tau_{LFM} = -\frac{f_d}{k} = -\frac{\alpha f_c}{B/T} = -\frac{\alpha f_c T}{B}$$

后果：速度 $v = 1$ m/s（$\alpha \approx 6.7 \times 10^{-4}$），载频 12 kHz，带宽 4 kHz，时长 0.1 s 时，定时误差 $\Delta\tau \approx 0.2$ ms，相当于在 48 kHz 采样率下漂移约 10 个采样点，严重破坏帧同步精度。

### 4.2 HFM 信号的多普勒不变性

双曲调频信号（HFM）的瞬时频率呈双曲变化：

$$f_{HFM}(t) = \frac{f_0}{1 - t/T_0}, \quad T_0 = \frac{f_0 T}{f_0 - f_1}$$

时域表达式：

$$s_{HFM}(t) = A \cdot \exp\!\left(-j2\pi f_0 T_0 \ln\!\left(1 - \frac{t}{T_0}\right)\right)$$

**多普勒不变性原理**：时间伸缩 $s(t/(1+\alpha))$ 等价于 HFM 在时间轴上的平移——即相关峰**不展宽、不衰减**，只产生位置偏移（定时偏置）。这与 LFM 的"峰值展宽衰减"本质不同，HFM 的相关处理增益在高速运动下得以保留。

**参数设计约束**：

- 起始频率 $f_0$、终止频率 $f_1$：决定带宽 $B = |f_1 - f_0|$ 和中心频率 $\bar{f} = (f_0 + f_1)/2$
- 信号时长 $T$：$T$ 越长，多普勒估计越精确，但定时偏置越大
- 推荐时间带宽积：$TB \geq 100$（保证足够相关增益）

### 4.3 HFM 定时偏置问题与消偏方案

**偏置机理**：

HFM 匹配滤波输出峰值位置相对真实时延产生系统性偏移：

- 正扫频 HFM+（$f_0 < f_1$）：

$$\Delta\tau_{+} \approx -\alpha \cdot \frac{T \bar{f}}{B}$$

- 负扫频 HFM−（$f_0 > f_1$）：

$$\Delta\tau_{-} \approx +\alpha \cdot \frac{T \bar{f}}{B}$$

偏置量的物理意义：速度越大、信号越长、相对带宽（$B/\bar{f}$）越小，偏置越大。偏置灵敏度定义为：

$$S_{bias} = \frac{T\bar{f}}{B}$$

典型参数下（$T=0.05$ s，$\bar{f}=12$ kHz，$B=8$ kHz）：$S_{bias} = 0.075$ s，即速度 1 m/s（$\alpha \approx 6.7 \times 10^{-4}$）产生约 50 µs（2.4 个样点@48 kHz）的定时偏置。

**核心消偏方法：正负 HFM 组合**

同时或串联发送 HFM+ 和 HFM−，利用偏置方向相反的特性：

$$\hat{\tau}_{真实} = \frac{\hat{\tau}_+ + \hat{\tau}_-}{2} \quad \Leftarrow \text{偏置对消}$$

$$\hat{\alpha} = \frac{(\hat{\tau}_- - \hat{\tau}_+)}{2 S_{bias}} = \frac{(\hat{\tau}_- - \hat{\tau}_+) B}{2T\bar{f}} \quad \Leftarrow \text{利用偏置差估计多普勒}$$

两种实现形式对比：

| 形式 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| 串联（时序叠加） | HFM+（T秒）然后 HFM−（T秒） | 无互干扰，峰值清晰 | 总时长 2T |
| 并联（时域叠加） | HFM+ + HFM− 同时发送 | 节省一半时长 | 需两路并行匹配滤波器分离 |

**精度分析**：

当偏置差 $\hat{\tau}_- - \hat{\tau}_+$ 的测量精度为 $\sigma_\tau$（由 SNR 和采样率决定），多普勒估计精度为：

$$\sigma_\alpha = \frac{\sigma_\tau \cdot B}{2T\bar{f}} = \frac{\sigma_\tau}{2S_{bias}}$$

插值精化（在相关峰附近用抛物线插值）可使 $\sigma_\tau$ 降低至亚采样点精度（约 $0.1/f_s$ 量级）。

### 4.4 m 序列模糊度函数法

m 序列（最大长度线性反馈移位寄存器序列）具有近似理想的自相关特性：

$$R_{m}(\tau) \approx \delta(\tau), \quad |\tau| > T_c$$

其中 $T_c = 1/f_{chip}$ 为码片时长。通过计算 m 序列的宽带模糊函数：

$$\chi(s, \tau) = \left|\int r(t) \cdot m^*\!\left(s(t - \tau)\right)\,dt\right|^2$$

二维搜索找到最大值点 $(s^*, \tau^*)$ 即得到多普勒伸缩因子和帧时延的联合估计。

**精度优势**：m 序列的模糊函数在时延-多普勒平面上呈"图钉形"（主峰尖锐、旁瓣均匀低），理论精度最高，但需要二维搜索，计算量大。

**两步搜索加速**：

1. 粗搜索：步长 $\Delta\alpha_{coarse} = 10^{-3}$，步长 $\Delta\tau_{coarse} = 1/f_s$
2. 细搜索：在粗估计附近，步长 $\Delta\alpha_{fine} = 10^{-5}$，步长 $\Delta\tau_{fine} = 0.1/f_s$（通过插值实现亚采样精度）

### 4.5 三种方法性能对比

| 指标 | LFM | 双 HFM（串联/叠加） | m 序列模糊度函数 |
|------|-----|--------------------|----------------|
| 多普勒估计精度 | 差（受时延-多普勒耦合影响） | 高 | 最高 |
| 定时偏置 | 严重（随速度线性增大） | 消偏后近零 | 无（二维联合估计） |
| 多径鲁棒性 | 中 | 强 | 强 |
| 计算复杂度 | 低（一维相关） | 低（两路并行相关） | 高（二维搜索） |
| 时长开销 | $T$ | $T$（叠加）或 $2T$（串联） | $T_{m}$（511 码片等） |
| 适用场景 | 静止/极低速 | 移动通信推荐（通用） | 精度要求极高、离线处理 |

---

## 5. 第二层：符号定时同步——处理帧内漂移

### 5.1 时变定时漂移的累积模型

帧头同步后，若多普勒因子为 $\hat{\alpha}$，则帧内第 $n$ 个符号的理想采样时刻相对标称时刻的漂移为：

$$\delta_n = \hat{\alpha} \cdot n \cdot T_s$$

其中 $T_s$ 为符号周期。若速度还在变化（加速度 $\dot{\alpha}$），则：

$$\delta_n = \alpha_0 T_s n + \frac{1}{2}\dot{\alpha} T_s^2 n^2$$

**关键约束**：当 $\delta_n$ 超过符号间隔的某个分数（对于 OFDM 通常为 CP 长度的 1/4，对于 SC 通常为 1/2 符号宽度），解调性能急剧恶化。

### 5.2 逐符号重采样（OFDM）

对第 $m$ 个 OFDM 符号，利用其内部导频子载波估计当前的实时多普勒因子 $\hat{\alpha}_m$：

$$\hat{\alpha}_m = \hat{\alpha}_{m-1} + (\hat{\alpha}_{m-1} - \hat{\alpha}_{m-2}) \quad \text{（线性外推预测）}$$

然后对该符号进行精细重采样，采样时刻：

$$t'_k = \frac{k}{1 + \hat{\alpha}_m}, \quad k = 0, 1, \ldots, N_{fft}-1$$

逐符号插值（三次样条或 Farrow 滤波器）后再做 FFT 解调。

**关键点**：帧内时变重采样因子需逐样点插值（而非整符号使用一个常数因子），否则符号边界处会出现不连续性，导致 ICI。

### 5.3 SC-FDE 分块定时跟踪

SC-FDE 将数据分为 $N_{blk}$ 块，每块长度为 $K$ 个样点。经过帧头粗估计 $\hat{\alpha}$ 后，每块的起始偏移量：

$$n_{start}^{(b)} = n_{frame\_start} + b \cdot (K + N_{cp}) + \underbrace{\text{round}(\hat{\alpha} \cdot b \cdot K)}_{\text{累积漂移修正}}$$

若在帧中间插入已知训练块（每 $K_b$ 块一次），则利用训练块的相关峰位置误差 $e_b$ 反馈修正：

$$n_{start}^{(b+1)} \leftarrow n_{start}^{(b+1)} + e_b$$

**更新公式**（比例积分环路）：

$$e_b = \hat{n}_{peak}^{(b)} - n_{expected}^{(b)}$$

$$\Delta\hat{\alpha}_b = K_p \cdot e_b + K_i \sum_{i=0}^{b} e_i$$

$$\hat{\alpha}_{update} = \hat{\alpha} + \Delta\hat{\alpha}_b$$

### 5.4 CP 自适应定时（加速度修正）

加速度使 CP 相关出现如下现象：

- 加速（$\dot{\alpha} > 0$）：CP 与符号尾部的匹配程度随符号序号递减，相关峰逐渐平坦
- 减速（$\dot{\alpha} < 0$）：相反

**三重定时估计法**（互相验证提升鲁棒性）：

1. **重心法**（粗估计）：在预期 CP 窗口内，以相关能量为权重求重心位置
2. **一阶期望法**：计算相关能量序列的一阶统计矩
3. **CP-副本自相关法**：接收 CP 与其期望副本做互相关，峰值位置即为符号定时

三种方法独立估计后取中位数或加权平均作为最终定时。

**加速度参数估计**：利用相邻若干符号的定时误差序列 $\{e_m\}$ 拟合线性趋势，得到加速度估计：

$$\hat{\dot{\alpha}} = \frac{\sum_m m \cdot e_m - \bar{m}\sum_m e_m}{\sum_m m^2 - N \bar{m}^2} \cdot \frac{1}{T_s}$$

用 $\hat{\dot{\alpha}}$ 对未来符号的定时预测做二阶修正，显著改善高机动场景下的同步性能。

---

## 6. 第三层：载波同步——频率与相位跟踪

### 6.1 残余 CFO 与相位漂移模型

重采样后，信号中残留的均匀频率偏差（残余 CFO）表现为时域相位随时间线性旋转：

$$r_{comp}[n] = r_{ideal}[n] \cdot e^{j2\pi\epsilon n / N} \cdot e^{j\phi_0}$$

其中 $\epsilon$ 为归一化残余 CFO，$\phi_0$ 为初始相位。在水声时变信道中，相位漂移速率也是时变的：

$$\phi(t) = \phi_0 + 2\pi\epsilon t + \pi\dot{\epsilon}t^2 + \text{相位噪声}$$

**相干时间约束**：接收机相位跟踪的更新速率必须快于信道相位的变化速率。水声信道相干时间：

$$T_{coh} \approx \frac{1}{2f_{Doppler\_spread}} = \frac{c}{2v \cdot f_c / c} = \frac{c^2}{2v f_c}$$

例如：$v = 1$ m/s，$f_c = 12$ kHz，$T_{coh} \approx 0.094$ s，即相位跟踪必须在约每 0.1 秒内更新一次。

### 6.2 决策导向锁相环（DD-PLL）

适用于 SC-TDE 和 SC-FDE 系统，逐符号更新相位：

**相位误差检测**：

$$e[n] = \text{Im}\!\left(\tilde{x}[n] \cdot \hat{x}^*[n]\right)$$

其中 $\tilde{x}[n]$ 为均衡后的复数符号，$\hat{x}[n]$ 为对应的判决符号（QPSK 时取星座点）。

**环路滤波（二阶 PLL）**：

$$\phi_{acc}[n+1] = \phi_{acc}[n] + K_i \cdot e[n]$$

$$\phi_{corr}[n] = K_p \cdot e[n] + \phi_{acc}[n]$$

**补偿**：

$$r_{pll}[n] = r_{comp}[n] \cdot e^{-j\phi_{corr}[n]}$$

**环路带宽设计原则**：

$$B_L = \frac{K_p}{2} f_s \quad \text{（近似，二阶环）}$$

- $B_L$ 太大：噪声进入环路，相位估计抖动大
- $B_L$ 太小：无法跟踪快速相位变化

推荐设计：$B_L \approx 0.005 \sim 0.02$ Hz（取决于平台速度和信道时变速率）。

**噪声带宽与跟踪带宽的折中**：

$$\sigma_\phi^2 \approx \frac{B_L N_0}{E_s}$$

其中 $N_0/E_s$ 为符号噪声功率比。典型要求 $\sigma_\phi < 5°$，由此反算允许的最小 SNR。

### 6.3 导频辅助逐符号相位跟踪（OFDM）

每个 OFDM 符号内保留连续导频（Continual Pilots），利用其估计整个符号的平均相位旋转：

$$\hat{\phi}_m = \frac{1}{N_p} \sum_{p=1}^{N_p} \angle\!\left(\frac{Y_m[k_p]}{X[k_p] \cdot \hat{H}[k_p]}\right)$$

**时变信道的修正**：时变信道下，信道响应 $\hat{H}[k_p]$ 自身也在变化，需要用前后符号的信道估计值做线性插值：

$$\hat{H}_m[k] = \frac{1}{2}\!\left(\hat{H}_{m-1}[k] + \hat{H}_{m+1}[k]\right)$$

**相位去卷绕**（Phase Unwrapping）：逐符号相位变化量 $\Delta\phi_m = \hat{\phi}_m - \hat{\phi}_{m-1}$ 需保持连续性，若相邻符号相位跳变超过 $\pi$，则执行去卷绕：

$$\hat{\phi}_m = \hat{\phi}_{m-1} + \text{angle\_wrap}(\Delta\phi_m)$$

其中 $\text{angle\_wrap}(x) = \mod(x + \pi, 2\pi) - \pi$。

---

## 7. 双 HFM 定时偏置的完整解决方案

### 7.1 偏置机理推导

HFM 信号匹配滤波输出为接收信号与本地参考信号的互相关。存在多普勒因子 $\alpha$ 时，接收信号的瞬时频率从 $f_0$ 变为 $f_0/(1+\alpha)$（近似），导致相关峰位置出现偏移。

推导过程（窄带近似）：

HFM+ 信号的瞬时周期为 $T(t) = 1/f(t)$，多普勒伸缩后瞬时周期变为 $(1+\alpha)T(t)$。匹配滤波输出峰值出现在累积周期相等的时刻，即积分方程：

$$\int_0^{T_{eff}} f_0^{-1}\!\left(1 - \frac{t}{T_0}\right)^{-1} dt' = T$$

解此方程得到偏置量（宽带精确表达式）：

$$\Delta\tau_{\pm} = \mp \frac{T_0}{(1+\alpha)} \left[\left(\frac{f_0}{f_0 \mp \alpha f_0}\right)^{?} - 1\right] \approx \mp \alpha \cdot \frac{T\bar{f}}{B}$$

在 $|\alpha| \ll 1$ 的水声场景下，窄带近似表达式有足够精度：

$$\boxed{\Delta\tau_{\pm} = \mp \alpha \cdot \frac{T\bar{f}}{B} = \mp \alpha \cdot S_{bias}}$$

### 7.2 正负 HFM 组合消偏（核心方法）

**算法流程**：

```
Step 1: 接收信号 r[n] 分别通过 HFM+ 和 HFM- 匹配滤波器
        corr_pos[n] = |xcorr(r, hfm_pos)|²
        corr_neg[n] = |xcorr(r, hfm_neg)|²

Step 2: 分别找到两路相关峰位置（含插值精化）
        τ̂_pos = peak_location(corr_pos)  [带亚采样插值]
        τ̂_neg = peak_location(corr_neg)  [带亚采样插值]

Step 3: 联合估计无偏时延和多普勒因子
        τ̂_true = (τ̂_pos + τ̂_neg) / 2       ← 偏置对消
        α̂      = (τ̂_neg - τ̂_pos) / (2·S_bias)  ← 多普勒估计

Step 4: 验证一致性（可选）
        |τ̂_pos - τ̂_neg| > threshold ? 警告：偏置修正可能失效（多径干扰）
```

**插值精化（亚采样精度）**：

在粗峰值位置 $n_{peak}$ 附近，利用相邻三点做抛物线插值：

$$\delta_n = \frac{corr[n_{peak}+1] - corr[n_{peak}-1]}{2\left(2\,corr[n_{peak}] - corr[n_{peak}+1] - corr[n_{peak}-1]\right)}$$

$$\hat{\tau}_{precise} = (n_{peak} + \delta_n) / f_s$$

此方法可将定时精度从 $1/f_s$ 提升至约 $0.05/f_s$（在高 SNR 下）。

### 7.3 速度谱扫描法

**构造速度谱**：对候选多普勒因子集合 $\{\alpha_k\}$，将接收信号时间轴按 $\alpha_k$ 伸缩后与本地 HFM 模板做相关，考察 HFM+ 和 HFM− 两路相关峰的对齐程度：

$$V(\alpha_k) = \frac{1}{\left|\hat{\tau}_+(\alpha_k) - \hat{\tau}_-(\alpha_k)\right| + \epsilon}$$

当 $\alpha_k = \alpha_{真实}$ 时，两路峰值对齐（偏置被正好补偿），$V(\alpha_k)$ 达到最大值。

**速度谱扫描步骤**：

1. 建立候选多普勒集合 $\alpha_k \in [\alpha_{min}, \alpha_{max}]$，步长 $\Delta\alpha$
2. 对每个 $\alpha_k$，将接收信号按 $(1+\alpha_k)$ 重采样后分别与 HFM+、HFM− 做互相关
3. 计算两路峰值位置差，构建速度谱 $V(\alpha_k)$
4. 取谱峰对应的 $\alpha_k$ 作为多普勒估计
5. 谱峰插值精化：在谱峰附近用抛物线插值进一步提升精度

**相比 CAF 的优势**：速度谱扫描仅需一维搜索，计算量比二维 CAF 低约 $N_\tau$ 倍（其中 $N_\tau$ 为时延搜索点数）。

**多径影响分析**：

多径使速度谱出现多个峰（真实速度峰 + 多径造成的伪峰），可通过以下方法抑制：

- 使用多帧信号的速度谱取均值（真实峰稳定，多径伪峰随帧变化）
- 设置速度谱主峰与次峰的能量比阈值（主峰能量显著高于旁瓣）

### 7.4 闭合公式直接修正

适用于已知多普勒因子 $\hat{\alpha}$（来自双 HFM 的多普勒估计结果），对单路 HFM 峰值位置直接修正：

$$\hat{\tau}_{true} = \hat{\tau}_{HFM+} - \Delta\tau_{+}(\hat{\alpha}) = \hat{\tau}_{HFM+} + \hat{\alpha} \cdot S_{bias}$$

$$\hat{\tau}_{true} = \hat{\tau}_{HFM-} - \Delta\tau_{-}(\hat{\alpha}) = \hat{\tau}_{HFM-} - \hat{\alpha} \cdot S_{bias}$$

两式应给出一致结果，若两者差值较大，说明多普勒估计误差较大或存在多径干扰。

### 7.5 多 HFM 相关求和法（MHFM）

使用 $K$ 对参数各异的 HFM 对（每对由 HFM+ 和 HFM− 构成），对 $K$ 对消偏结果求平均：

$$\hat{\tau}_{true} = \frac{1}{K}\sum_{i=1}^{K} \frac{\hat{\tau}_{+,i} + \hat{\tau}_{-,i}}{2}$$

$$\hat{\alpha} = \frac{1}{K}\sum_{i=1}^{K} \frac{(\hat{\tau}_{-,i} - \hat{\tau}_{+,i})}{2 S_{bias,i}}$$

统计增益约 $\sqrt{K}$ 倍（假设各对 HFM 的估计误差独立）。但需确保各对 HFM 的频率范围互不重叠或有足够区分度，以避免相互污染。

---

## 8. 各体制专用同步流程

### 8.1 OFDM 系统同步流程

```
OFDM 接收信号 r[n]
    │
    ▼
【帧同步】双 HFM 匹配滤波
    → 帧起始 τ̂，多普勒粗估计 α̂_coarse
    │
    ▼
【宽带补偿】重采样：r_comp[n] = Resample(r[n], α̂_coarse)
    │
    ▼
【符号级处理】对每个 OFDM 符号（m = 1, 2, ...）：
    │  (a) 提取含 CP 的符号段
    │  (b) CP 自相关 → 更新 α̂_m（加速度修正）
    │  (c) 逐符号精细重采样（三次样条/Farrow）
    │  (d) 去 CP → FFT
    │
    ▼
【残余 CFO 估计】利用连续导频：
    ε̂ = angle(mean(Y_m[pilots] / (X[pilots] × Ĥ[pilots]))) / (2π)
    │
    ▼
【相位补偿】r_phase[n] = r_comp[n] × exp(-j2πε̂n/N)
    │
    ▼
【信道估计+均衡】LS 估计 → FDE 均衡
    │
    ▼
【逐符号相位跟踪】导频辅助更新 φ̂_m → 时变相位补偿
```

**OFDM 同步的关键参数约束**：

- CP 长度需满足：$N_{cp} \geq \tau_{max} f_s + \alpha_{max} N_{fft}$（后项为漂移余量）
- 逐符号多普勒更新间隔 $\leq T_{coh}$，即要求每符号持续时间 $\leq T_{coh}$
- 连续导频密度：至少每 8 个子载波一个，用于相位跟踪

### 8.2 SC-FDE 系统同步流程

```
SC-FDE 接收信号 r[n]
    │
    ▼
【帧同步】双 HFM 前导码 + 后导码
    前导码位置 → τ̂_pre（帧起始）
    后导码位置 → τ̂_post（帧结束）
    │  α̂ = (τ̂_post - τ̂_pre - T_frame_nominal) / T_frame_nominal
    │  τ̂_true = (τ̂_pre + δτ_bias_correction)  ← 消偏修正
    │
    ▼
【宽带补偿】重采样至标准采样率
    r_comp[n] = Resample(r[n], α̂)
    │
    ▼
【帧内分块处理】（b = 1, 2, ..., N_blocks）
    │  (a) 计算第 b 块起始：n_start(b) = τ̂ + b×(K+N_cp) + round(α̂×b×K)
    │  (b) 去 CP，取块数据
    │  (c) K 点 FFT
    │  (d) MMSE 频域均衡（使用前导码估计的信道 H_est）
    │  (e) K 点 IFFT → 时域符号
    │  (f) 每 K_b 块更新一次定时估计（训练块反馈）
    │
    ▼
【Turbo 迭代均衡】（可选，3~6次）
    SISO-MMSE 均衡器 ⇌ BCJR 解码器
```

**SC-FDE 特有注意事项**：

- 前导码和后导码使用**相同的** HFM 对序列，间距即为帧标称时长 $T_{frame}$
- 多普勒估计精度：$\sigma_\alpha \approx \sigma_\tau / S_{bias}$，增大帧长可提升精度
- 分块定时修正的更新频率须高于速度变化率：$\Delta t_{update} < v / (a_{max} T_c)$

### 8.3 OTFS 系统同步流程

OTFS 在时延-多普勒域天然描述信道，同步需求有所不同：

```
OTFS 接收信号 r[n]
    │
    ▼
【粗帧同步】整帧 CP 互相关
    → 整帧起始位置 τ̂_frame（精度要求较低，半帧 CP 内即可）
    │  注：OTFS 的整帧 CP 仅需整帧起点定位，无需精确到符号级
    │
    ▼
【粗多普勒估计】（可选，用于严重失步情形）
    利用前导码（单个已知 OFDM 符号）的 CP 相关估计粗 α̂
    │
    ▼
【Wigner 变换 + SFFT】
    r_no_cp[n] = r[τ̂_frame + N_cp_total : ...]
    Y_TF[n,m] = FFT（每个时间块）
    Y_DD[k,l] = SFFT（Y_TF）
    │
    ▼
【DD 域信道估计】嵌入导频自动提供多普勒路径参数 {α_i, τ_i, h_i}
    多普勒路径参数即为信道响应，无需独立多普勒补偿模块
    │
    ▼
【MP 均衡器】消息传递迭代（10~30 次）
    同时完成 ISI、ICI、IDI 的联合消除
    │
    ▼
【分数多普勒修正】（若存在）
    窗函数方法 或 虚拟格点插值
```

**OTFS 同步的关键差异**：

- 不需要逐符号多普勒跟踪（DD 域天然处理时变）
- 整帧 CP 的长度须满足：$N_{cp,total} \geq (\tau_{max} + v_{max}/c \cdot N \cdot T_{sym}) \cdot f_s$
- 分数多普勒（格点间泄漏）是主要的同步残差来源

---

## 9. MATLAB 实现规范

### 9.1 函数接口汇总

**同步模块函数清单**：

| 函数名 | 输入 | 输出 | 功能说明 |
|--------|------|------|---------|
| `gen_hfm.m` | `f0, f1, T, fs` | `hfm [1×N]` | 生成单路 HFM 信号 |
| `sync_dual_hfm.m` | `r, hfm_pos, hfm_neg, fs, P` | `tau_est, alpha_est, qual` | 双 HFM 帧同步（含消偏） |
| `hfm_bias_correct.m` | `tau_raw, alpha, T, f_bar, B` | `tau_corrected` | 单路 HFM 偏置闭合修正 |
| `doppler_resample.m` | `r, alpha, method` | `r_comp, N_out` | 宽带多普勒重采样补偿 |
| `sync_per_symbol_ofdm.m` | `r_comp, N, Ncp, P` | `alpha_m_vec, r_resampled` | OFDM 逐符号多普勒更新 |
| `sync_block_scfde.m` | `r_comp, tau0, alpha0, K, Ncp, P` | `blocks, n_starts` | SC-FDE 分块定时提取 |
| `cfo_estimate.m` | `Y_pilot, X_pilot, pilot_idx, N` | `epsilon_est` | 残余 CFO 导频估计 |
| `pll_carrier_sync.m` | `r, Kp, Ki, fs` | `r_pll, phi_track` | DD-PLL 载波同步跟踪 |
| `phase_track_ofdm.m` | `Y_m, X_pilot, H_est, pilot_idx` | `phi_m, r_corrected` | OFDM 逐符号相位跟踪 |
| `velocity_spectrum.m` | `r, hfm_pos, hfm_neg, fs, P` | `alpha_est, V_spectrum` | 速度谱扫描法多普勒估计 |
| `peak_interp_parabola.m` | `corr_mag, n_peak` | `tau_precise` | 抛物线插值精化相关峰 |

**参数结构体 `P`（同步模块通用）**：

```matlab
P.fs          % 采样率（Hz）
P.fc          % 载频（Hz）
P.f0_hfm      % HFM+ 起始频率（Hz）
P.f1_hfm      % HFM+ 终止频率（Hz）
P.T_hfm       % HFM 信号时长（秒）
P.S_bias      % 偏置灵敏度 = T * f_bar / B（秒）
P.alpha_max   % 预期最大多普勒因子
P.tau_max     % 预期最大传播时延（秒）
P.Kp_pll      % PLL 比例增益
P.Ki_pll      % PLL 积分增益
P.N_fft       % OFDM FFT 点数
P.Ncp         % CP 长度
P.K           % SC-FDE 块长
P.Ncp_sc      % SC-FDE CP 长度
P.pilot_idx   % 导频子载波索引
P.sync_threshold % 相关峰检测阈值（相对最大值）
P.multipath_guard % 多径保护窗（秒），用于筛选首达峰
```

### 9.2 双 HFM 帧同步（含消偏）

**函数**：`sync_dual_hfm.m`

```matlab
function [tau_est, alpha_est, qual] = sync_dual_hfm(r, hfm_pos, hfm_neg, fs, P)
% 双 HFM 帧同步，输出无偏时延和多普勒因子
%
% 输入：
%   r        - 接收信号 [1×N]
%   hfm_pos  - HFM+ 本地模板（正扫频）[1×L]
%   hfm_neg  - HFM- 本地模板（负扫频）[1×L]
%   fs       - 采样率（Hz）
%   P        - 参数结构体
%
% 输出：
%   tau_est   - 无偏帧起始时延（秒）
%   alpha_est - 多普勒因子估计
%   qual      - 同步质量指标（主峰与背景噪声之比）

%% Step 1: 两路匹配滤波
corr_pos = abs(xcorr(r, hfm_pos)).^2;
corr_neg = abs(xcorr(r, hfm_neg)).^2;

% xcorr 输出零延迟位于 length(r) 处
lag_offset = length(r);

%% Step 2: 在有效搜索范围内找相关峰（抑制多径伪峰）
% 搜索范围：预期时延区间
tau_min_samp = round(P.tau_min * fs);
tau_max_samp = round(P.tau_max * fs);
search_range = lag_offset + tau_min_samp : lag_offset + tau_max_samp;

[peak_pos_val, peak_pos_idx] = max(corr_pos(search_range));
[peak_neg_val, peak_neg_idx] = max(corr_neg(search_range));

% 绝对样点位置
n_peak_pos = search_range(1) + peak_pos_idx - 1;
n_peak_neg = search_range(1) + peak_neg_idx - 1;

%% Step 3: 亚采样精化（抛物线插值）
delta_pos = (corr_pos(n_peak_pos+1) - corr_pos(n_peak_pos-1)) / ...
            (2*(2*corr_pos(n_peak_pos) - corr_pos(n_peak_pos+1) - corr_pos(n_peak_pos-1)));
delta_neg = (corr_neg(n_peak_neg+1) - corr_neg(n_peak_neg-1)) / ...
            (2*(2*corr_neg(n_peak_neg) - corr_neg(n_peak_neg+1) - corr_neg(n_peak_neg-1)));

tau_pos = (n_peak_pos - lag_offset + delta_pos) / fs;   % 秒
tau_neg = (n_peak_neg - lag_offset + delta_neg) / fs;

%% Step 4: 联合估计（偏置对消）
tau_est   = (tau_pos + tau_neg) / 2;                       % 无偏时延
alpha_est = (tau_neg - tau_pos) / (2 * P.S_bias);           % 多普勒因子

%% Step 5: 同步质量评估
noise_floor = mean([corr_pos(search_range); corr_neg(search_range)], 'all');
qual = (peak_pos_val + peak_neg_val) / (2 * noise_floor);   % 信噪比估计（线性）

%% Step 6: 合理性检验
if abs(alpha_est) > P.alpha_max
    warning('sync_dual_hfm: 估计多普勒因子 %.4f 超出预期范围，请检查', alpha_est);
end
end
```

**HFM 信号生成**：`gen_hfm.m`

```matlab
function hfm = gen_hfm(f0, f1, T, fs)
% 生成 HFM 信号（复基带）
% f0: 起始频率，f1: 终止频率，T: 时长，fs: 采样率
N = round(T * fs);
t = (0:N-1) / fs;

% 双曲调频参数
T0 = f0 * T / (f0 - f1);                     % 渐近时间

% 复包络
phase = -2*pi * f0 * T0 * log(1 - t/T0);
hfm = exp(1j * phase);

% 归一化
hfm = hfm / norm(hfm);
end
```

### 9.3 逐符号多普勒跟踪（OFDM）

**函数**：`sync_per_symbol_ofdm.m`

```matlab
function [alpha_m_vec, r_resampled] = sync_per_symbol_ofdm(r_comp, N, Ncp, P)
% OFDM 逐符号多普勒因子估计与精细重采样
%
% 原理：利用 CP 自相关对每个符号估计当前多普勒因子，
%        并通过线性外推预测下一符号的因子，逐符号精细重采样

Ns = N + Ncp;            % 符号总长度（含 CP）
M  = floor(length(r_comp) / Ns);   % 符号数估计

alpha_m_vec = zeros(1, M);
r_resampled = [];

alpha_prev = 0;          % 初始多普勒因子（来自帧头粗估计）
alpha_pprev = 0;

for m = 1:M
    % 取第 m 个符号段
    idx_start = (m-1)*Ns + 1;
    idx_end   = min(m*Ns + Ncp, length(r_comp));  % 多取一个 CP 用于相关
    seg = r_comp(idx_start : idx_end);

    % CP 自相关估计本符号多普勒
    % CP 是符号末尾 Ncp 个样点的副本，与符号头部的 CP 相关
    if length(seg) >= Ns + Ncp
        cp_received = seg(1:Ncp);
        cp_expected = seg(N+1:N+Ncp);    % 符号末尾 Ncp 样点
        R = sum(cp_received .* conj(cp_expected));
        delta_phase = angle(R);
        alpha_cp_m = delta_phase / (2*pi*P.fc*(Ncp/P.fs));  % 从相位差估计
    else
        alpha_cp_m = alpha_prev;  % 无法估计时沿用上一个值
    end

    % 线性外推预测当前符号的最佳重采样因子
    alpha_m = alpha_cp_m;
    alpha_predict_next = alpha_m + (alpha_m - alpha_prev);

    alpha_m_vec(m) = alpha_m;

    % 精细重采样（仅对数据部分，去掉 CP）
    data_seg  = seg(Ncp+1 : Ncp+N);
    t_orig    = (0:N-1);
    t_new     = (0:N-1) / (1 + alpha_m);
    t_new     = min(t_new, N-1);

    re_seg = interp1(t_orig, real(data_seg), t_new, 'spline');
    im_seg = interp1(t_orig, imag(data_seg), t_new, 'spline');
    r_resampled = [r_resampled, re_seg + 1j*im_seg];

    alpha_pprev = alpha_prev;
    alpha_prev  = alpha_m;
end
end
```

### 9.4 DD-PLL 载波同步

**函数**：`pll_carrier_sync.m`

```matlab
function [r_pll, phi_track] = pll_carrier_sync(r, x_dec, Kp, Ki, fs)
% 决策导向锁相环（DD-PLL）
% r     - 重采样后的基带信号
% x_dec - 判决符号序列（来自初步解调）
% Kp    - 比例增益
% Ki    - 积分增益

N = length(r);
phi_track  = zeros(1, N);    % 相位轨迹
phi_acc    = 0;               % 积分器状态
r_pll      = zeros(1, N, 'like', 1j);

for n = 1:N
    % 相位补偿
    r_pll(n) = r(n) * exp(-1j * phi_track(n));

    % 相位误差检测（决策导向）
    if n <= length(x_dec) && x_dec(n) ~= 0
        e_n = imag(r_pll(n) * conj(x_dec(n)));  % 相位误差
    else
        e_n = 0;   % 无判决时不更新
    end

    % 环路滤波（比例 + 积分）
    phi_acc = phi_acc + Ki * e_n;
    phi_corr = Kp * e_n + phi_acc;

    % 更新下一时刻的相位补偿量
    if n < N
        phi_track(n+1) = phi_track(n) + phi_corr;
    end
end
end
```

---

## 10. 参数设计指南

### 10.1 HFM 参数设计

**偏置灵敏度 $S_{bias}$ 的选取**：

$$S_{bias} = \frac{T\bar{f}}{B}$$

偏置灵敏度与多普勒估计精度和定时同步鲁棒性之间存在矛盾：

- $S_{bias}$ 大 → 同等速度下偏置量大（同步不稳健）→ 但两路峰值差大，多普勒估计精度高
- $S_{bias}$ 小 → 偏置量小（同步稳健）→ 但两路峰值差小，多普勒估计精度低

设计原则：根据最高允许定时偏置 $\Delta\tau_{max}$ 和最大速度 $v_{max}$：

$$S_{bias} < \frac{\Delta\tau_{max}}{\alpha_{max}} = \frac{\Delta\tau_{max} \cdot c}{v_{max}}$$

典型水声系统参数范围：

| 参数 | 推荐范围 | 说明 |
|------|---------|------|
| 带宽 $B$ | 2~8 kHz | 相关增益与偏置量折中 |
| 时长 $T$ | 20~100 ms | 长则多普勒精度高，但偏置大 |
| $\bar{f}/B$ 比值 | 1.5~4 | 越小偏置越大，典型取 2~3 |
| 时间带宽积 $TB$ | ≥ 50 | 保证足够相关增益 |

### 10.2 CP 长度设计（考虑多普勒余量）

标准 CP 长度需覆盖最大时延扩展：

$$N_{cp}^{standard} = \lceil \tau_{max} \cdot f_s \rceil$$

时变信道下，多普勒使有效符号长度变化，额外需要多普勒余量：

$$N_{cp}^{total} = \lceil \tau_{max} \cdot f_s \rceil + \lceil \alpha_{max} \cdot N \rceil$$

其中 $\alpha_{max} \cdot N$ 为一个符号长度内由多普勒引起的最大样点漂移量。

### 10.3 PLL 环路带宽设计

PLL 跟踪带宽 $B_L$ 须满足以下约束：

**下限（跟踪约束）**：$B_L > \Delta f_{max,rate}$，其中 $\Delta f_{max,rate}$ 为最大相位变化速率

$$B_L > \frac{|\dot{\alpha}|_{max} \cdot f_c}{2\pi} \quad \text{（跟踪加速度引起的相位变化）}$$

**上限（噪声约束）**：$B_L < f_s / (2\pi C)$，其中 $C$ 取决于信噪比要求

$$\sigma_\phi = \sqrt{\frac{B_L N_0}{2 E_s}} < \frac{5\pi}{180} \text{ rad} \quad \Rightarrow \quad B_L < \frac{(5\pi/180)^2 \cdot 2E_s}{N_0}$$

实际典型取值：$B_L = 5 \sim 50$ Hz（视运动速度和信噪比而定）。

### 10.4 各体制同步开销对比

| 体制 | 同步信号 | 占帧比例 | 多普勒跟踪方式 |
|------|---------|---------|--------------|
| SC-TDE | 前导码（双 HFM） | 5~15% | DD-PLL 逐符号 |
| SC-FDE | 前导码 + 后导码（双 HFM） | 10~20% | 分块定时修正 |
| OFDM | 前导码 + 连续导频子载波 | 10~25% | 逐符号导频相位跟踪 |
| OTFS | 整帧 CP + DD 域嵌入导频 | 5~10%（CP）+ 导频格点 | DD 域天然处理 |

---

## 11. 性能评估指标

### 11.1 帧同步评估

| 指标 | 定义 | MATLAB |
|------|------|--------|
| 定时均方根误差（RMSE） | $\sqrt{E[(\hat{\tau} - \tau_{true})^2]}$ | `sqrt(mean((tau_est - tau_true).^2))` |
| 多普勒估计 RMSE | $\sqrt{E[(\hat{\alpha} - \alpha_{true})^2]}$ | `sqrt(mean((alpha_est - alpha_true).^2))` |
| 同步成功率 | $P(\|\hat{\tau} - \tau_{true}\| < T_{symbol}/2)$ | `mean(abs(tau_err) < Tsym/2)` |
| 误同步率（FAR） | 无帧时触发同步的概率 | 仿真统计 |
| 峰值信噪比（PSNR） | 相关峰与噪声底的比值 | `qual` 输出 |

**CRLB 参考**（HFM 定时估计的理论下界）：

$$\text{CRLB}(\tau) = \frac{1}{SNR \cdot (2\pi)^2 \int_{-\infty}^{\infty} f^2 |S(f)|^2 df} = \frac{6}{\text{SNR} \cdot (2\pi)^2 B^2 T}$$

对于多普勒估计的 CRLB：

$$\text{CRLB}(\alpha) = \frac{6}{\text{SNR} \cdot (2\pi f_c)^2 T^3 / T_s}$$

### 11.2 载波同步评估

| 指标 | 定义 | 典型要求 |
|------|------|---------|
| 相位误差 RMS | $\sigma_\phi$ | $< 5°$（QPSK），$< 2°$（16QAM） |
| 残余 CFO | $\|\hat{\epsilon} - \epsilon_{true}\|$ | $< 0.01 \Delta f_{sub}$ |
| 相位跟踪延迟 | PLL 建立时间 | $< 5$ 个符号 |

### 11.3 端到端 BER 评估参考

蒙特卡洛仿真建议扫描维度：

```matlab
SNR_range   = -5 : 3 : 25;           % dB
alpha_range = [0, 0.001, 0.003, 0.006, 0.01];   % 对应 0~15 m/s
N_trials    = 200;                     % 每点仿真次数

% 关键对比配置
configs = {'无同步（基线）', 'LFM同步', '双HFM同步', '双HFM+消偏'};
```

---

*文档版本：v1.0 | 最后更新：2026-04 | 覆盖体制：SC-TDE / SC-FDE / OFDM / OTFS*
