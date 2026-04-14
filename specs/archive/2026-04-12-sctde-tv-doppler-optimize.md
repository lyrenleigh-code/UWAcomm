---
project: uwacomm
type: task
status: archived
created: 2026-04-12
updated: 2026-04-14
tags: [SC-TDE, 多普勒, 时变信道]
---

# SC-TDE V5.2 时变多普勒优化

## Spec

### 目标

优化 SC-TDE 端到端在 fd=1Hz 下的性能，目标 BER<0.5%@15dB，消除 20dB 反弹问题。

### 原因

SC-TDE V5.1 已修复 LFM 检测（static@5dB 从 50%→1.95%），但 fd=1Hz 下存在两个问题：
1. 多普勒估计误差 88%，15dB 可达 0.76% 但 20dB 反弹至 1.60%
2. 未对齐 OFDM V4.3 的鲁棒策略（时变跳过训练精估 + nv_post 兜底）

### 范围

- 代码仓库：`H:\UWAcomm`
- 主要文件：
  - `13_SourceCode/src/Matlab/tests/SC-TDE/test_sctde_timevarying.m`
  - `12_IterativeProc/src/Matlab/turbo_equalizer_sctde.m`
  - `07_ChannelEstEq/src/Matlab/` 相关均衡器

### 非目标

- 不解决 fd=5Hz（已知物理极限：alpha*fc 在 Jakes 频谱内）
- 不改变帧结构
- 不新增模块

### 验收标准

- [ ] fd=1Hz@15dB BER < 0.5%
- [ ] fd=1Hz@20dB BER < fd=1Hz@15dB（无反弹）
- [ ] static 性能不退化（0%@10dB+）
- [ ] 测试脚本可重复运行
- [ ] 关键发现写回 wiki

---

## Plan

（确认 spec 后填写）

### 参考

- OFDM V4.3 的 nv_post 兜底策略
- OFDM V4.3 的时变跳过 CP 精估策略

### 影响文件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `test_sctde_timevarying.m` | 修改 | 对齐 OFDM 鲁棒策略 |
| `turbo_equalizer_sctde.m` | 修改 | 加入 nv_post 兜底 |
| `07_ChannelEstEq/` 相关 | 可能修改 | 视调试情况 |

### 实现步骤

1. 分析 20dB 反弹根因（对比 OFDM V4.3 的 nv_post）
2. 在 turbo_equalizer_sctde 中加入 nv_post 兜底
3. 时变场景跳过训练精估（对齐 OFDM 策略）
4. 逐 SNR 点验证 fd=1Hz 性能
5. 回归验证 static 性能

### 测试策略

- 运行 `test_sctde_timevarying.m`，对比 V5.1 基线
- 覆盖 static / fd=1Hz / fd=5Hz 三个场景
- SNR 范围：0~25dB

### 风险

| 风险 | 概率 | 应对 |
|------|------|------|
| nv_post 参数需要针对 SC-TDE 重新调优 | 中 | 参考 OFDM 参数，逐步调整 |
| 跳过训练精估导致 static 退化 | 低 | static 单独测试，条件分支 |

---

## Log

（执行过程中记录）

---

## Result

### 代码改动（保留）

`test_sctde_timevarying.m` V5.1 → V5.2：
1. 时变跳过训练精估（`alpha_est = alpha_lfm`），对齐 OFDM V4.3
2. BEM 估计后实测 `nv_post_meas`，时变分支 `nv_eq = max(nv_eq, nv_post_meas)`

### 目标失效说明（2026-04-14）

spec 的原始目标「fd=1Hz@15dB BER<0.5%，消除 20dB 反弹」针对 Jakes 连续谱。2026-04-13 离散 Doppler 全体制对比确认 Jakes 连续谱为伪瓶颈（6 体制×6 信道矩阵），SC-TDE 离散 Doppler 下已 0%@5dB+（见 `test_sctde_discrete_doppler_results.txt`），继续优化 Jakes 路径无工程价值。

代码改动本身合理（与 OFDM V4.3 同构），保留作为时变路径的参考策略，但不再作为验收门。

### Promote 到 wiki

- `wiki/conclusions.md` #8 时变需 nv_post 兜底 nv_eq
- `wiki/conclusions.md` #9 时变应跳过训练/CP 精估
