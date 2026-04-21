---
type: debug-log
created: 2026-04-21
updated: 2026-04-21
tags: [调试日志, OTFS, 13_SourceCode, pilot_mode, 32pct]
---

# OTFS 调试日志

跟踪 `modules/13_SourceCode/src/Matlab/tests/OTFS/test_otfs_timevarying.m` 及相关 OTFS 端到端测试的典型故障与定位过程。

---

## 2026-04-21 — OTFS 32% BER 根因定位（pilot_mode regression）

### 背景

[[e2e-timevarying-baseline]] B 阶段（2026-04-19）发现 OTFS 在 4 类离散 Doppler 信道下独自卡 32% BER，起初假设为"非均匀 Doppler + on-grid 估计失败"（对应 [[yang-2026-uwa-otfs-nonuniform-doppler]] 理论）。

### 进 debug 前的 CSV 深挖

对 `e2e_baseline_A3.csv` 48 行 OTFS 数据按 (fd, α) 分组发现：

| 观察 | 证据 |
|------|------|
| **Harness 忽略 α** | 同 fd 下 α=0/5e-4/1e-3/2e-3 BER 完全相同（`apply_channel` static/discrete/hybrid 分支不做时间伸缩） |
| **static 就已 33%** | `fd=0_a=0 @ snr=10 → BER=33.0%`，与 B 阶段离散信道 32% 数值一致 |
| **BER 随 SNR 单调下降但 10-15dB 间拐点陡** | 5dB→44%, 10dB→33%, 15dB→2.7%（5-10dB 区间 BER 平台 30-44%，到 15dB 才恢复） |

对比 [[e2e-test-matrix]] 2026-04-11 数据（OTFS V2.0）：static 0% @ 5dB+。2026-04-11 至 2026-04-21 间发生 regression。

### 嫌疑定位

`test_otfs_timevarying.m:20`：
```matlab
pilot_mode = 'sequence';  % 'impulse'=A冲激, 'sequence'=B ZC, 'superimposed'=C叠加
```

对照 [[conclusions]] #37：默认从 `impulse` 改为 `sequence`（ZC），文档仅记 5dB/15dB trade-off，**10dB 未测**。

### 诊断设计

3 × 3 × 3 = 27 run 矩阵（spec：`specs/active/2026-04-21-otfs-disc-doppler-32pct-debug.md`）：

```
pilot_mode ∈ {impulse, sequence, superimposed}
channel    ∈ {static, disc-5Hz, hyb-K20}
trials     = 3（seed = 100·tr + pm_i）
SNR        = 10 dB
```

脚本：`modules/13_SourceCode/src/Matlab/tests/OTFS/diag_otfs_32pct.m`

### 结果（SNR=10dB，3 trials 均值 ± std）

| Channel | impulse | sequence | superimposed |
|---------|--------:|---------:|-------------:|
| static | **0.04% ± 0.06** | 28.06% ± 2.79 | 0.00% ± 0.00 |
| disc-5Hz | **0.00% ± 0.00** | 30.41% ± 1.40 | 0.08% ± 0.07 |
| hyb-K20 | **0.02% ± 0.03** | 32.56% ± 1.16 | 0.37% ± 0.56 |

**辅助指标**（impulse / sequence / superimposed）：
- NMSE_h_dd：-2.9 / +3.0 / NaN（sequence 估计器输出本身是垃圾）
- path_det_rate（检测径/5真径）：5.2-7.7 / 2.1-2.9 / 0.9-1.5

### 结论

**H1 确认**：`pilot_mode='sequence'` 在 SNR=10dB 的 OTFS 信道估计 regression 是 32% BER 的完整根因。

- `ch_est_otfs_zc` V3.0.0（最小二乘 Toeplitz + CAZAC 匹配滤波）在 SNR=10dB 下漏检约 40-60% 路径
- `ch_est_otfs_dd` V2.0.0（3σ/1σ 阈值检测）路径命中率 100-155%（含虚警），但关键路径都在
- NMSE 差距 6dB（-3dB vs +3dB）直接反映估计器本质性能差异

**H4 否定**：离散 Doppler + impulse 下 0% BER，[[yang-2026-uwa-otfs-nonuniform-doppler]] 的非均匀 Doppler + off-grid block-sparse OMP 理论在当前信道复杂度下**不需要**引入。保留作为未来深海场景（径间 Δα 更大）的备用方案。

### 修复

1. `test_otfs_timevarying.m:20` default `'sequence'` → `'impulse'`（保留参数化）
2. `test_otfs_timevarying.m` addpath 补 `10_DopplerProc`（原缺漏，`comp_resample_spline` 在此模块）

`14_Streaming` 侧无需修改（`sys_params_default.m:109` 已是 `'impulse'`）。

### Trade-off 重评估

| 属性 | impulse | sequence |
|------|--------:|---------:|
| BER @ 10dB | 0% | 28-32% |
| PAPR | 20 dB | 11 dB |
| 估计复杂度 | 低（阈值） | 高（LS） |
| 路径命中率 | 100%+ | ~50% |

结论：ZC pilot 的 PAPR 优势（-9dB）**不足以补偿** 28% BER 的 regression；降 PAPR 应走 SLM/PTS 等非 pilot 改动的方案（见 [[conclusions]] #16-19）。

### 后续工作

1. ~~回滚 default~~ ✅ 已完成
2. 确认 14_Streaming UI 默认值 `impulse`（已查，OK）
3. harness α 忽略 bug 独立修（归入 `specs/active/2026-04-21-alpha-refinement-other-schemes.md`）
4. ZC pilot 自身的 SNR 敏感性改造：留给 PAPR 优化专题（非本 spec）

### 产出

- 诊断脚本：`modules/13_SourceCode/src/Matlab/tests/OTFS/diag_otfs_32pct.m`
- 诊断数据：`diag_results/otfs_32pct_diag.mat` + `otfs_32pct_diag_log.txt`
- spec：[[2026-04-21-otfs-disc-doppler-32pct-debug]]（即将归档）

### 引用

- [[yang-2026-uwa-otfs-nonuniform-doppler]]（本次证伪 H4 的理论基准）
- [[e2e-timevarying-baseline]] B 阶段结果
- [[conclusions]] #37（pilot_mode 切换历史）
- `e2e_baseline_A3.csv` OTFS 48 行
