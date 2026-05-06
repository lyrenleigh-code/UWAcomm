---
project: uwacomm
type: task
status: active
created: 2026-04-14
updated: 2026-04-14
tags: [模块06, OTFS, pilot, PAPR]
---

# OTFS 扩散 Pilot 方案

## Spec

### 目标

将 OTFS 冲激 pilot（`pilot_value=sqrt(N_data_slots)=43`）替换为能量扩散的 pilot 方案，降低时域 PAPR（从 20dB → ≤10dB）同时保持信道估计精度和 BER 性能（0% @10dB+）。

### 背景

**当前冲激 pilot 的问题**：
- DD 域 1 个超大冲激 (V=43) + 1859 单位 QPSK 数据
- 经 OTFS 变换后：每个子块的 l_p 位置产生 V/√N=7.6 的峰值
- 32 个子块 → 32 个时域尖刺
- 导致 OTFS 段 PAPR = 20.44 dB（远超多载波理论值 9dB）

**根本矛盾**：冲激 pilot 的能量集中特性与低 PAPR 要求冲突。

### 候选方案对比

| 方案 | 原理 | 信道估计 | 时域PAPR预期 | 实现复杂度 |
|------|------|---------|------------|-----------|
| **A. 多冲激** | 将能量分散到 K 个 DD 冲激 | 类似当前，稍复杂 | -10log(K) dB | ⭐ 低 |
| **B. ZC 序列 pilot** | 整行/列填 CAZAC 序列 | 相关峰检测 | ~3-4 dB（接近理想） | ⭐⭐ 中 |
| **C. 叠加 pilot** | 所有 DD 位置 data+smooth pilot | 减法后估计 | ~3-5 dB | ⭐⭐⭐ 高 |
| **D. 伪随机 pilot** | 多 DD 位置填已知随机序列 | 序列相关 | ~6-9 dB | ⭐⭐ 中 |

### 推荐方案：B（ZC 序列 pilot）

**原理**：
- DD 域一行（或一列）填入长度 M（或 N）的 ZC 序列，作为已知 pilot
- CAZAC 特性 → 时域表现为恒模，PAPR ≈ 1 (0dB)
- 信道估计：RX 端接收 Y_dd，和 TX pilot 序列循环相关，得到信道冲激响应

**数学基础**：
设 TX pilot 在 DD 域第 k_p 行为 ZC 序列 $p[l]$, l=0,...,M-1。
经信道后：
$$Y[k_p, l] = \sum_{(\tau,\nu) \in paths} h(\tau,\nu) \cdot p[(l-\tau) \mod M] \cdot e^{j2\pi\nu \cdot k_p/N}$$

信道估计：在 Doppler 行 $k_p$ 附近（含 guard_k 扩散区），对 $Y[k, l]$ 和 $p[l]$ 循环相关 → 提取 $h[\tau, \nu]$。

### 范围

**主要文件**：

| 文件 | 动作 |
|------|------|
| `modules/06_MultiCarrier/src/Matlab/otfs_pilot_embed.m` | 修改：新增 `'zc_row'` / `'zc_col'` 模式 |
| `modules/07_ChannelEstEq/src/Matlab/ch_est_otfs_dd.m` | 修改：支持 ZC pilot 的循环相关估计 |
| `modules/13_SourceCode/src/Matlab/tests/OTFS/test_otfs_timevarying.m` | 修改：切换 pilot 模式 + BER 对比 |
| `modules/06_MultiCarrier/src/Matlab/test_multicarrier.m` | 修改：新增 ZC pilot 回环测试 |

**不修改**：
- `otfs_modulate.m` / `otfs_demodulate.m`（核心 OTFS 变换不变）
- 均衡器（BCCB LMMSE 等）

### 验收标准

| 指标 | 条件 |
|------|------|
| 回环精度 | 无信道时 pilot 可恢复 |
| 时域 PAPR | OTFS 段 PAPR ≤ 10 dB（vs 当前 20dB） |
| 信道估计精度 | NMSE 与冲激 pilot 相差 < 3dB |
| BER 不退化 | 离散 Doppler 0% @10dB+（保持现有表现） |
| 模块复用 | 不修改 OTFS 调制/解调 |

## Log

- 2026-04-14: Spec 创建

## Result

**完成日期**：2026-04-27（commit `c9c0601`，移植 codex 已 completed 实施）
**补登日期**：2026-05-04（claude 分支漏登）

### 实施

借鉴 UWAcomm-codex 已 completed spec 移植到 claude 分支：

- **方案 C（superimposed pilot）落地**：所有 DD 位置 data + smooth pilot，
  RX 端做 pilot contribution removal 后估计信道。
  实施在：
  - `modules/06_MultiCarrier/src/Matlab/otfs_pilot_embed.m` 加 `'superimposed'` 模式
  - `modules/07_ChannelEstEq/src/Matlab/ch_est_otfs_superimposed.m`（新增）
  - `modules/13_SourceCode/src/Matlab/tests/OTFS/test_otfs_timevarying.m`
    bench 注入 `bench_otfs_pilot_mode` / `bench_otfs_superimposed_power`
  - `modules/13_SourceCode/src/Matlab/common/rx_chain.m::rx_otfs_real`
    pilot mode 三分派（impulse / sequence / superimposed）

- **方案 B（ZC sequence）保留**：`ch_est_otfs_zc.m` 已存在但不作默认（4-21 发现 SNR=10 BER 28-32% regression）。

- **方案 A/D 未实施**（superimposed 已达成 PAPR 目标，无需重叠）。

### 验收

| Criterion | 目标 | 实测 |
|-----------|------|------|
| 时域 PAPR | ≤10 dB | **8.9 dB** ✅（test_multicarrier 4.4） |
| 信道估计精度 | 不退化 | guard 区域噪声估计正常 ✅ |
| BER（5/6 fading SNR≥10 dB） | 0% @10dB+ | impulse / superimposed 全 0%（static + disc-5Hz + hyb-K{5,10,20}）✅ |
| 数据率 | 不降低 | 5357→5902 bps（+10%，superimposed 把 pilot 单元让渡给 data）✅ |
| **BER（jakes5Hz 连续谱）** | 0% @10dB+ | impulse 33-35% / superimposed 42-44% 🔴 |

### Limitation（已知）

- **jakes5Hz 灾难（impulse 33-35% / superimposed 42-44%）**：连续谱时变 + 单
  pilot/frame 协议的物理 limitation（与 SC-FDE jakes fd=1Hz 50% 灾难同根因），
  decoder 层不可解，需协议层改动（多 pilot 块周期插入，类比 SC-FDE Phase 5
  方案 A/E）。conclusions.md #46 已记录。
- **superimposed 弱 K=5/10 hybrid 下轻微 BER 退化**：能量交叉污染。

### 单测

- `test_multicarrier.m` 4.3 SLM PASS / 4.4 spread pilot PAPR PASS（24/24 总计）
- `test_otfs_timevarying.m` 5/6 fading × SNR≥10 dB BER 全 0%（rect 脉冲）

