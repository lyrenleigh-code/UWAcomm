---
type: source-summary
source_type: paper
authors: A. Laleveé, P. Forjonel, P.-J. Bouvet, L.P. Pelletier
year: 2025
journal: OCEANS 2025 Brest, IEEE
affiliation: L@bISEN / ISEN Yncréa Ouest, France
status: 已读摘要
created: 2026-04-21
updated: 2026-04-21
tags: [论文, 多普勒估计, 滤波器组, 二分搜索, FPGA, 实现]
---

# New Dichotomous Implementation Approach for Doppler-Shift Estimation and Compensation in an Underwater Acoustic Modem

> Laleveé et al. (2025). *OCEANS 2025 Brest*, IEEE.
> Raw: `raw/papers/New_Dichotomous_Implementation_Approach_for_Doppler-Shift_Estimation_and_Compensation_in_an_Underwater_Acoustic_Modem.pdf`

---

## 核心贡献

把滤波器组（filter bank）Doppler 估计法的**线性搜索**改为**二叉树二分搜索**，在 FPGA 上实现——精度不变，复杂度从 O(n) 降到 O(log₂ n)。

## 研究问题

滤波器组法：准备 N 个不同 dopplerized 版本的已知 preamble，与收到信号做相关，取最大峰对应的 α。

- 精度：N 决定（更细网格 = 更精）
- 成本：N 次相关 → FPGA 资源、延时 O(n)

目标：在**实时嵌入式水声 modem** 上部署，同时保留精度。

## 方法/算法

### 1. 测试波形

BPSK 头 19.9ms + QPSK 数据 209.7ms，fc=27kHz，BW=4kHz，SRRC roll-off=0.4。

### 2. 二分搜索树

把 N 个 dopplerized preamble 组织成二叉树：
- Stage 1：测根节点左右两个（大间距 α_min 和 α_max）
- Stage 2：只展开"有相关峰"的那一侧
- 如果多峰，只保留幅度最大的
- 继续直到叶节点

示例：v=2.5 m/s 目标，stage 1 测 ±4m/s 无峰 → stage 2 测 ±2m/s，+2m/s 有峰 → stage 3 只测 +2m/s 的子节点 → 收敛。

### 3. 2 对比并行

每 stage 做 2 次相关 → FPGA 上并行实现，stage 数 log₂(n)/2 = 最终仅 log₂(n)/2 时间单位。

### 4. 阈值

峰值有效性判决：峰值 / 能量窗 > 阈值（示例 -9dB 主峰 vs -12dB 次瓣，防止误检）。

## 关键结果

- 精度与线性 filter bank 一致
- 复杂度 O(log₂ n) vs O(n)
- FPGA 资源占用小，适合实时 modem

## 与项目的关联

| 关联项 | 说明 |
|--------|------|
| `modules/10_DopplerProc/est_doppler_caf.m` | 当前 CAF 法也是网格扫描，**O(n) 复杂度**；可加 `'dichotomy'` 选项 |
| 14_Streaming P2 流式检测 | 流式场景对 Doppler 估计**实时性要求高**，本文的二分搜索可降低每帧估计延迟 |
| 未来 FPGA 移植（非本项目 scope 但相关） | 若项目未来需要硬件验证，本文提供二叉树架构 |

## 工程等级

此论文主要**工程实现**价值，算法本质还是滤波器组。对项目的启示：
- 离线仿真：不紧迫（当前算法已够快）
- 实时嵌入式：有参考价值（未来硬件部署时再引）

## 引用与关联

- **相关论文**：[[wei-2020-dual-hfm-speed-spectrum]]（非滤波器组，不同思路）、[[sun-2020-dsss-passband-doppler-tracking]]（符号级实时追踪）
- **相关模块**：`est_doppler_caf.m`
- **优先级**：低（算法不新，工程实现为主）
