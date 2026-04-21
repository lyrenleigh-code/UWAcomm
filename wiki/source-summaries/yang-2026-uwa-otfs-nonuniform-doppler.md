---
type: source-summary
source_type: paper
authors: Yang Yang, Lu Ma, Songzuo Liu, Gang Qiao, Yang Song, Tong Li
year: 2026
journal: IEEE Journal of Oceanic Engineering, Vol. 51, No. 1, Jan 2026, pp. 641-658
affiliation: 哈工程水声 (HEU)
status: 已读摘要
created: 2026-04-21
updated: 2026-04-21
tags: [论文, OTFS, 多普勒, 信道估计, 非均匀多普勒, 哈工程]
---

# Underwater Acoustic OTFS With Nonuniform Doppler Shifts: Modeling and Off-Grid Block-Sparse Channel Estimation Algorithm

> Yang et al. (2026). *IEEE JOE*, 51(1), 641-658.
> Raw: `raw/papers/Underwater_Acoustic_OTFS_With_Nonuniform_Doppler_Shifts_Modeling_and_Off-Grid_Block-Sparse_Channel_Estimation_Algorithm.pdf`

---

## 核心贡献

宽带水声信道下 OTFS 每径 Doppler 因子不同 → 频带上**非均匀 Doppler 频移**，时域 resample 只能补偿公共分量，**残余 Doppler 效应即使补完 resample 仍存在**。论文推导了含残余 Doppler 的 DD 域输入输出关系，证明 UWA-OTFS 具有 block-sparse 属性，并提出 **off-grid block-sparse OMP + ML** 的信道估计算法。

## 研究问题

传统 OTFS 信道模型假设所有径**共享 α**：时域 resample 后信道等效回单 α，DD 域稀疏模型干净。

但实际水声场景：
- 水平运动 + 多径几何 → 每径 ν_p = α_p · f_c 不同（几何相关性）
- 宽带信号 → Doppler 以 **伸缩**形式作用于整个频带，而非单一频移
- resample 取公共 α 后，每径残余 (α_p - α_common)·f_c 仍导致 **频带依赖的残余频移**
- DD 域的二维冲激假设被破坏 → 分散到邻近 Doppler bin（off-grid 泄漏）

## 方法/算法

### 1. 含残余 Doppler 的 DD 域输入输出关系

重新推导：除 delay τ_p 和主 Doppler ν_p 外，加入"残余 Doppler 展宽项"ξ_p(k)——对第 k 个子载波有不同频率响应。

### 2. Block-sparse 证明

Doppler 展宽在 DD 域表现为**局部块状非零**（非单点冲激），数学上证明了块稀疏结构。

### 3. 估计算法

**Off-grid block-sparse OMP (OBS-OMP)**：
- Block：按 Doppler 邻域分块而非逐点搜
- Off-grid：允许 Doppler 落在网格间（不是整 ν 网格点）
- ML 细调：OMP 粗定位 + ML 精估连续 ν

## 关键结果

- 数值仿真 + 海试数据验证 Doppler 分辨率与 BER 优于传统 on-grid OMP / 冲激 pilot DD 估计
- 特别在**径间 Δα 较大**场景优势明显（水平拖体、多径几何差异大的场景）

## 与项目的关联（高优先）

| 关联项 | 说明 |
|--------|------|
| **🔴 OTFS 32% BER 专项 debug** | 本文模型直接解释 B 阶段 benchmark 中 OTFS 在 disc-5Hz/hyb-K* 独自卡 32% 的现象——离散 Doppler 每径不同 ν，而 `ch_est_otfs_dd/zc/superimposed` 当前均基于**均匀 Doppler + on-grid** 假设 |
| `ch_est_otfs_dd` | 当前 impulse pilot + DD 域 on-grid 峰搜，对非均匀 Doppler 鲁棒性差 |
| `ch_est_otfs_zc` | ZC 序列 pilot，虽降 PAPR，但仍假设 on-grid |
| `eq_otfs_lmmse` | BCCB 2D-FFT 对角化前提是单 α + on-grid，非均匀 Doppler 破坏此假设 |
| `test_otfs_timevarying.m` | Jakes fd=5Hz 下 BER 50%（conclusion #10）：Jakes 连续谱也是非均匀 Doppler 的一种 |

## H0 假设（待 debug 时验证）

**H0**：OTFS 在离散 Doppler 信道的 32% BER 瓶颈根源在于 **径间 ν_p 差异** + **on-grid 估计假设**，不在 SNR/pilot/BEM。若把信道模型改为"所有径共享 ν_common"（绑定单 α），应能回到 0%。

## 后续可能引入的改造

1. 先用"单 ν_common"场景验证 H0（最小代价隔离）
2. 若 H0 成立，参考本文 block-sparse 假设改造 `ch_est_otfs_dd`（加 block 邻域搜索）
3. off-grid ML 细调作为可选 Phase 2（复杂度 tradeoff）

## 引用与关联

- **相关论文**：[[zheng-2025-dd-turbo-sc-uwa]]（另一条 DD 域思路，对比 SC vs OTFS）
- **相关模块**：`modules/07_ChannelEstEq/ch_est_otfs_*`
- **相关 spec**：`specs/active/2026-04-21-otfs-disc-doppler-32pct-debug.md`（待建）
- **相关 benchmark**：`wiki/comparisons/e2e-timevarying-baseline.md`（B 阶段 OTFS 独异常）
