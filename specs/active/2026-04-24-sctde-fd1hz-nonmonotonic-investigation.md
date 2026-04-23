---
project: uwacomm
type: investigation
status: active
created: 2026-04-24
updated: 2026-04-24
tags: [SC-TDE, fd=1Hz, 非单调, Turbo+BEM, known-limitation, 13_SourceCode]
branch: investigate/sctde-fd1hz-nonmonotonic
parent_spec: specs/active/2026-04-24-sctde-remove-post-cfo-compensation.md
---

# SC-TDE fd=1Hz 非单调 BER vs SNR 调研

## 背景

2026-04-24 post-CFO fix 验证过程中发现 SC-TDE 在 fd=1Hz（Jakes 时变）下 BER vs SNR 非单调，且两版 fix 路径都无法消除：

| 场景 | 5dB | 10dB | 15dB | 20dB |
|------|-----|------|------|------|
| plan A（全 skip post-CFO） | 21.70% | 17.39% | 27.96% | **0.00%** |
| plan C（时变 apply post-CFO）| 20.03% | 47.71% | 35.74% | 37.20% |

**plan A** 下：SNR=15 27.96% / SNR=20 突降 0%（Turbo 救回），呈"稀有触发+高 SNR 救回"模式。

**plan C** 下：apply post-CFO 反而全盘崩坏，确认 post-CFO 非救星（见 parent spec）。

历史 V5.2（2026-04-14）日志记载 fd=1Hz SNR=15 = 0.76%，**不可复现**。中间代码演化（bench_seed 注入、alpha_est 门禁、E2E C 阶段改动）累积差异。

## 疑似根因（待验证）

### H1. Turbo+BEM 稀有触发

类似 SC-FDE Phase I+J 观察到的"~10% deterministic 灾难触发"模式（memory: `project_uwacomm_2026-04-23_session`），seed=42 fd=1Hz 恰好落在触发区。
- 多 seed Monte Carlo → 分布（mean/median/灾难率）可量化

### H2. BEM Q 阶数选择

diary 3 显示 fd=1Hz `[BEM] Q=5, obs=610, cond=26979`。Q=5 对应 Nyquist 多普勒 ~10 Hz，fd=1Hz 下过度拟合（model capacity 过剩）。
- BIC 自适应选阶（ch_est_bem V2.0 有此能力）是否被启用？

### H3. nv_post 噪声估计偏差

diary 3: `nv_post=2.66e-02, nv_eq_orig=6.91e-03`。nv_post 是 nv_eq_orig 的 ~4×。V5.2 的 "nv_post 实测兜底" 可能在 fd=1Hz 下过度保守。

### H4. α estimator 偏估

fd=1Hz: est=1.30e-4 vs true=8.33e-5（误差 ~56%）。α_est 偏估 50% 可能让 comp_resample_spline 过补偿导致残余 ISI。

### H5. 定时粗糙

diary 显示 fd=1Hz `[对齐] corr=0.804, off=1`，相比 static 的 corr=0.779 还要高。但 LFM 定时 lfm_pos=9817（static 相同），未偏移。

## 调研矩阵（提议）

### 阶段 1：多 seed Monte Carlo 基线

```
h_seeds  = 1:15              % 15 seed
h_snr    = [10, 15, 20]      % 3 SNR
h_fading = {'fd=1Hz','slow',1,1/fc}  % 固定 fd=1Hz
```

产出：
- mean/median/min/max BER，灾难率（BER>5%）
- 判定 H1（seed=42 稀有触发 vs 普遍性）

### 阶段 2：H2/H3/H4 隔离实验（按需）

启用 `diag_oracle_alpha=true` → 排除 H4
启用 `diag_oracle_h=true` → 排除 Q 阶数/BEM 问题
diag 观察 nv_post vs 真实 noise_var → 验证 H3

### 阶段 3：Fix / Workaround（按需）

根据阶段 1/2 结果定。

## 非目标

- ❌ 不改 ch_est_bem、turbo_equalizer_sctde 本体
- ❌ 不涉及 post-CFO 相关（已在 parent spec 关闭）
- ❌ 不扩展到 fd=5Hz（物理极限）/fd=0.1Hz（边界）

## 优先级

🟡 中优先。主目标（α 常数多普勒 static 下 RCA fix）已达成，fd=1Hz 属次要场景。可以在 SC-TDE α=+1e-2 主 fix 归档后独立起工。

## 接受准则

- [ ] 阶段 1 多 seed 表格产出
- [ ] 若 H1 确认（灾难率 < 15%）→ 标记 known limitation，记入 conclusions.md
- [ ] 若 H2/H3/H4 确认 → 开 fix spec
- [ ] todo.md 追加本条 investigation 完成标记
