---
type: source-summary
source_type: paper
authors: Tonghui Zheng, Chengbing He, Lianyou Jing, Qiankun Yan
year: 2025
journal: IEEE Journal of Oceanic Engineering, Vol. 50, No. 2, April 2025, pp. 1500-1517
status: 已读摘要
created: 2026-04-21
updated: 2026-04-21
tags: [论文, DD域, Turbo均衡, 单载波, OTFS, doubly-selective]
---

# Delay-Doppler Domain Turbo Equalization for Single-Carrier Underwater Acoustic Communications

> Zheng et al. (2025). *IEEE JOE*, 50(2), 1500-1517.
> Raw: `raw/papers/Delay-Doppler_Domain_Turbo_Equalization_for_Single-Carrier_Underwater_Acoustic_Communications.pdf`

---

## 核心贡献

提出 **DD-MMSE-TEQ**：在 DD 域做 MMSE turbo 均衡、时域做译码，借 DD 域把"时变信道"转成"准静态信道"的性质，**保留单载波低 PAPR 的同时获得 OTFS 的高动态鲁棒性**。

通过**酉变换**连接 DD 域均衡器与时域译码器，实现跨域软信息交换——同时有单载波的低 PAPR 和多载波对时变的鲁棒性。

丹江口水库 2022 年 7 月实测数据验证，BER 优于频域 turbo 均衡；与传统 OTFS 性能相当，代价是接收端复杂度增加。

## 研究问题

| 方案 | PAPR | 时变鲁棒 | 代价 |
|------|------|---------|------|
| SC-FDE + Turbo | 低 | 弱（依赖 BEM 跟踪） | OK |
| OTFS | 高 | 强（2D DD 二维冲激） | PAPR=7-8dB |

目标：**在单载波低 PAPR 发射端 + DD 域接收端**兼得两者优点。

## 方法/算法

### 1. 发射

常规单载波 + CP（不是 ISFFT 预编码，不增 PAPR）。

### 2. 接收

- DFT → DD 域（借 CP 做 BCCB 结构）
- DD 域 MMSE-IC 均衡（复用 OTFS LMMSE 的 BCCB 对角化）
- **酉变换回时域做 BCJR/Viterbi**（单载波流结构）
- 软信息：DD 域 extrinsic LLR → unitary → 时域 prior → 时域 extrinsic → unitary⁻¹ → DD 域 prior

### 3. 关键定理

酉变换保证**软信息在两域间无损**传递（Parseval 保序 → 跨域 turbo 不丢信息）。

## 关键结果

- BER 在 doubly selective 信道下 5dB 以上明显优于 FDE-TEQ
- 与 OTFS 持平（预期：算法在 DD 域等价，发射端换了）
- 接收复杂度略高于 FDE-TEQ（多一次 unitary）
- **PAPR 保持单载波水平**（本质上发射是单载波）

## 与项目的关联

| 关联项 | 说明 |
|--------|------|
| `modules/12_IterativeProc/turbo_equalizer_scfde.m` V1.1.0 | 当前 FDE-TEQ + La_dec_info 反馈修复；本文提供 **DD-TEQ 升级路径**作为 Phase 2 |
| `modules/12_IterativeProc/turbo_equalizer_otfs.m` V3.1.0 | 两者在 DD 域应共享 kernel；可重构出公共 DD-MMSE 核 |
| `modules/04_Modulation/` 发射端 | 本文方案**不改发射端**（单载波）——最小侵入式升级路径 |
| SC-FDE fd≥1Hz Jakes 50% BER | B 阶段 benchmark 的 SC-FDE 时变 50% 瓶颈，DD-TEQ 可能救一部分 |

## 引进改造的工程成本

- 不改 TX：✅
- RX 新增：DFT → DD 域 → unitary（已有 OTFS 库里有 DD→TD 变换） → 时域 BCJR（已有）
- 复用率高：~70%

## 引用与关联

- **相关论文**：[[yang-2026-uwa-otfs-nonuniform-doppler]]（DD 域 + 非均匀 Doppler 估计）
- **相关模块**：`turbo_equalizer_scfde` + `eq_otfs_lmmse`
- **相关调试**：`wiki/modules/13_SourceCode/SC-FDE调试日志.md`
- **潜在新 spec**：`2026-04-22-scfde-dd-turbo-upgrade.md`（不在本 branch 范畴）
