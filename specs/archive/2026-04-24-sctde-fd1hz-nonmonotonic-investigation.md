---
project: uwacomm
type: investigation
status: archived
created: 2026-04-24
updated: 2026-04-25
tags: [SC-TDE, fd=1Hz, 非单调, Turbo+BEM, H4-confirmed, 13_SourceCode]
branch: investigate/sctde-fd1hz-nonmonotonic
parent_spec: specs/archive/2026-04-24-sctde-remove-post-cfo-compensation.md
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

- [x] 阶段 1 多 seed 表格产出（V2 修正后）
- [x] 阶段 1.5 seed=42 复现 spec 历史表（4/4 SNR 误差 <0.01pp）
- [x] 阶段 2 H4 oracle α 隔离（4 坏 seed → 全 15 seed × 3 SNR）
- [x] H4 confirmed → 开 fix spec
- [x] todo.md 同步

## Result

**主结论：H4 confirmed — α estimator 偏差是 fd=1Hz 非单调的直接根因**

### 阶段 1（修正版 V2）：15 seed × 3 SNR 多 seed MC

`bench_common/diag_sctde_fd1hz_monte_carlo.m`（5.4 min, 45 trial）

| SNR | mean | median | std | 灾难率(>5%) | 严重率(>30%) |
|-----|------|--------|-----|---|---|
| 10 | 10.06% | 7.79 | 11.45 | 8/15 (53.3%) | 2/15 (13.3%) |
| 15 | **4.33%** | 0.49 | 6.35 | 5/15 (33.3%) | 0 |
| 20 | **4.55%** | 0.83 | 6.57 | 5/15 (33.3%) | 0 |

**关键观察**：mean 15→20 反弹 **4.33→4.55**（Δ=+0.22pp，违反单调），spec 描述的非单调真实存在。

### 阶段 1.5：seed=42 复现验证（脚本配置 bug 修正）

`bench_common/diag_sctde_fd1hz_replay_seed42.m`（0.29 min, 12 trial）

| SNR | spec 历史 | 实测 seed=42 | 差异 |
|-----|---|---|---|
| 5 | 21.70% | 21.70% | 0.00 |
| 10 | 17.39% | 17.39% | 0.00 |
| 15 | 27.96% | 27.96% | 0.00 |
| 20 | **0.00%** | **0.00%** | 0.00 |

**关键发现**：runner L179/L269 的 RNG seed 依赖 `fi`（fading 行号）→ 单行 `bench_fading_cfgs={fd=1Hz,...}`（fi=1）与 default 3 行（fi=2）跑出**完全不同的 trial 实例**。spec 历史表是 fi=2 trial。修正后 4/4 SNR 完美复现（误差 <0.01pp）。

### 阶段 2 · H4 Oracle α 全量

`bench_common/diag_sctde_fd1hz_h4_oracle_full.m`（8.74 min, 45 trial, `diag_oracle_alpha=true`）

| SNR | base mean | oracle mean | Δ | base 灾难率 | oracle 灾难率 | Δ |
|-----|---|---|---|---|---|---|
| 10 | 10.06% | 8.45% | -1.6 | 53.3% | 46.7% | -6.7 |
| 15 | 4.33% | **2.43%** | **-1.9** | 33.3% | 20.0% | -13.3 |
| 20 | **4.55%** | **0.89%** | **-3.6** | 33.3% | **6.7%** | -26.7 |

**判定**：

✓ **15→20 非单调消除**：oracle mean **2.43→0.89 单调递降**（vs baseline 4.33→4.55 反弹）— **spec 主目标 H4 confirmed**

✓ SNR=20 基本健康化：灾难率 33%→6.7%（仅 s15 残留 8.9%）

🟡 SNR=10 残余灾难（46.7% 仅微降）：seed-by-seed 对比显示
- α 敏感：s11（30.95→**7.72**，-23pp）
- α 无关：s5/s13/s15（oracle 下微恶化）
- SNR=10 灾难**与 α 无关**，属低 SNR 物理极限或其他机制（独立问题）

### 派生工作

1. **fix α estimator** spec：`2026-04-25-sctde-fd1hz-alpha-estimator-fix.md`（H4 confirmed → fix）
2. **SNR=10 残余灾难**：另起 investigation（H2/H3 候选 + 物理极限可能）
3. spec 自身归档（本 investigation 主目标达成）

### 衍生发现 — 测试脚本配置 bug

SC-TDE runner（及其他 timevarying runner）的 `rng(uint32(mod(N + fi*M + ...)))` 设计让 fading 行号 `fi` 进入 RNG seed。任何 bench/diag 脚本传单行 `bench_fading_cfgs` 都会偏离 default 3 行验证条件。**改进建议**：runner 内 RNG seed 改用 `fading_label` 哈希而非 `fi` 索引（独立技术债，非本 spec 范围）。
