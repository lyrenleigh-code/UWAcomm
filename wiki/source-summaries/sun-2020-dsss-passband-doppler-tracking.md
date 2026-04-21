---
type: source-summary
source_type: paper
authors: Dajun Sun, Xiaoping Hong, Hongyu Cui, Lu Liu
year: 2020
journal: Journal of Communications and Information Networks, Vol. 5, No. 2, June 2020, pp. 167-175
affiliation: 哈工程水声
status: 已读摘要
created: 2026-04-21
updated: 2026-04-21
tags: [论文, DSSS, 多普勒跟踪, 通带处理, 符号级, 三点内插, 哈工程]
---

# A Symbol-Based Passband Doppler Tracking and Compensation Algorithm for Underwater Acoustic DSSS Communications

> Sun et al. (2020). *JCIN*, 5(2), 167-175.
> Raw: `raw/papers/A_Symbol-Based_Passband_Doppler_Tracking_and_Compensation_Algorithm_for_Underwater_Acoustic_DSSS_Communications.pdf`

---

## 核心贡献

在 **通带** 对 DSSS 信号做 **符号级** Doppler 跟踪：利用相邻符号相关峰的时延差推导 Doppler 因子，**三点余弦内插**获取 fractional 时延。

## 研究问题

长时 DSSS 信号（秒级）下，块估计法（包头+包尾双导）假设 α 常值不成立：
- AUV 机动 / 波动 → α 动态变化
- 符号内相干性在 α 漂移 ppm 级即衰减

传统 DFE+PLL / Sharif 闭锁环 / Singer 宽带迭代：依赖 TX 符号判决 → 星座模糊 + 解码错误敏感
Zakharov 叠加结构 MBA：SNR 损失
CW pilot：占用带宽

## 方法/算法

### 1. 通带操作

因 UWA fc 仅几 kHz，passband 相关计算量可接受，而**时延估计精度高于 baseband**（band-passband 时钟分辨率对 fc 敏感）。

### 2. 符号级 Doppler 估计

相邻符号相关峰时差：
$$\Delta \tau = \tau_{k+1} - \tau_k = \alpha \cdot T_{sym}$$

每符号得一个瞬时 α。

### 3. 三点余弦内插

用 peak 邻 ±1 采样点的相关幅度值做余弦模型拟合：
$$R(\tau) \approx A \cos(\omega(\tau - \tau_0))$$

取 arg max 做 sub-sample 精度。

### 4. 先验 Doppler 限制细化

给定 AUV 最大速度 → α 先验范围 → 限制搜索窗口，提升效率。

### 5. 自适应本地参考

根据滤波后的 α 自适应选择本地 DSSS 参考序列（dopplerized 版本），补偿相关幅度畸变。

## 关键结果

- 仿真 BER 优于常规 DFE+PLL + Sharif 闭锁环
- 跟踪时变 α 能力强（ppm 级动态）
- 计算量主要在 passband 相关（可 FPGA 化）

## 与项目的关联

| 关联项 | 说明 |
|--------|------|
| `modules/13_SourceCode/src/Matlab/tests/DSSS/` | 项目 DSSS V1.0 当前仅 Rake+DCD，**无 Doppler 跟踪**；B 阶段 Jakes 下 BER ~48%（与 Zheng 的 SC 无 TEQ 类似） |
| DSSS 时变信道改造（未立项） | 本文提供可直接落地的 **符号级 Doppler 跟踪** 工程方案 |
| α 补偿迭代机制 | 项目 SC-FDE 用的双 LFM + 2 次迭代 refinement，**本文的"每符号更新 α"相当于 DSSS 版本的连续 refinement** |

## 引进路径

DSSS runner 加 `doppler_track_mode='symbol_based' / 'block'` 开关：
1. 块估计：现有的双 HFM 方式
2. 符号跟踪：本文方法，每 Gold31 chip 序列符号更新一次 α
3. 自适应参考：本地 dopplerized Gold31 bank

## 引用与关联

- **相关论文**：[[wei-2020-dual-hfm-speed-spectrum]]（块估计）、[[muzzammil-2019-cpofdm-doppler-interp]]（CP 内插）
- **相关模块**：`modules/13_SourceCode/src/Matlab/tests/DSSS/`、`eq_rake.m`
- **潜在 spec**：`2026-04-22-dsss-symbol-doppler-tracking.md`（当前未立项）
