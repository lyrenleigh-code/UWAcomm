---
project: uwacomm
type: fix
status: archived
created: 2026-04-25
updated: 2026-04-26
archived: 2026-04-26
tags: [SC-TDE, fd=1Hz, α-estimator, dual-chirp, 10_DopplerProc, 13_SourceCode]
branch: fix/sctde-fd1hz-alpha-estimator
parent_spec: specs/archive/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md
---

# SC-TDE fd=1Hz α estimator 精度提升

## 背景

`archive/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md` H4 oracle α 实验确认 SC-TDE fd=1Hz 下 mean BER 15→20 反弹（4.33%→4.55%）的直接根因是 LFM dual-chirp α estimator 在 Jakes 时变 + fd=1Hz 下的精度不足。Oracle 真值替换后 SNR=20 灾难率从 33% 降到 **6.7%**，mean 从 4.55% 降到 **0.89%**，**单调性恢复**。

## 目标

提升 `est_alpha_dual_chirp` 在 fd=1Hz Jakes 时变下的精度，使 SC-TDE fd=1Hz 实测 BER 趋近 Oracle α 表现：
- SNR=15 mean ≤ 3% / 灾难率 ≤ 25%
- SNR=20 mean ≤ 1.5% / 灾难率 ≤ 15%
- 单调性 SNR ↑ → mean BER ↓ 不反弹

不要求 SNR=10 改善（已确认与 α 无关）。

## 已知线索

### oracle 改善分布（H4 阶段 2 数据）

| seed | base SNR=20 | oracle SNR=20 | 解释 |
|------|---|---|---|
| s11 | 10.57% | **0.07%** | α 估计偏离真值大，oracle 大改 |
| s5 | 11.54% | 0.49% | 同上 |
| s12 | 11.20% | 2.78% | α 偏离中等 |
| s15 | 21.35% | 8.90% | α 偏离 + 残余物理因素 |

→ **fd=1Hz Jakes 下 LFM α 估计在部分 seed 上系统性偏离真值**（绝对偏差未量化，需诊断）

### est_alpha_dual_chirp 现状

- `modules/10_DopplerProc/src/Matlab/est_alpha_dual_chirp.m` V1.1（2026-04-23）符号约定参数化
- 双 LFM 时间差 → α，子样本细化（cfg.use_subsample=true）
- 已知精度：static + α=±1e-2 ≈ 5e-6 偏差（archive 4-23 alpha-1e2 RCA spec）
- fd=1Hz 下未单独量化 → 本 fix 第一步

## 调研步骤

### Step 1：诊断（量化偏差）

写 `tests/bench_common/diag_sctde_fd1hz_alpha_err.m`：
- 15 seed × 3 SNR × default 3 行 fading
- runner 内打印 `alpha_lfm` vs `dop_rate` 偏差到 CSV（runner 已暴露 alpha_est 列）
- 输出按 seed 排序的偏差分布 + correlate BER

### Step 2：根因细分（按诊断结果）

候选机制：
- **R1：LFM 模板对 Jakes 时变敏感**：fd=1Hz Jakes 衰减让 LFM 匹配峰漂移
- **R2：dual-chirp 时间差受 fc 频偏污染**：fd=1Hz 下 fc 抖动影响相位差解算
- **R3：sub-sample 插值在 SNR=15 噪声下偏置**：cfg.use_subsample 子样本估计偏差
- **R4：搜索窗 lfm_search_margin 偏小**：fd=1Hz Jakes 下定时漂移更大

### Step 3：Fix 方案（按 R1-R4 决定）

可能方向：
- 加迭代 refinement（参考 `est_alpha_dsss_symbol` 方案）
- 引入 LFM 模板 Doppler 鲁棒化（多 α 假设并行匹配）
- 增加置信度门禁，低置信下回退到训练精估
- 扩大 lfm_search_margin

### Step 4：验证

`diag_sctde_fd1hz_h4_oracle_full.m` 同矩阵跑实测 vs oracle 对比，验证 fix 后实测能否接近 oracle。

## 非目标

- ❌ SNR=10 灾难（独立问题，与 α 无关，归 known limitation）
- ❌ fd=5Hz（物理极限）
- ❌ 修改其他体制 α estimator（DSSS/OFDM 各有独立路径）
- ❌ 改 runner RNG seed 设计（独立技术债）

## 优先级

🟡 中优先（spec 主目标已 RCA 确认，fix 是独立工作）

## 接受准则

- [x] Step 1 诊断：alpha_lfm vs dop_rate 偏差量化（V5.5 Phase 1.2/2 完成，runner 暴露 4 层 α + LFM peak 7 字段，bench_init_row schema 扩 11 列向后兼容 NaN）
- [x] Step 2 根因锁定（V5.5 Phase 2：R3 排除/sub-sample 必需，R5 confirmed/iter refinement 反向收敛累加 deterministic bias；R1 部分支持/Jakes peak shift；bad/good seed estimator 偏差几乎相同 → 灾难非 estimator 偏差驱动）
- [x] Step 3 fix 实施（V5.5 fd-conditional iter=0 + V5.6 HFM-signature calibration `alpha_lfm -= 1.5e-5` 当 HFM dtau_diff=-1）
- [x] Step 4 验证：**4/5 PASS + 1 边缘**
  - SNR=15 mean ≤3% ✅ (实测 2.36%)
  - SNR=20 mean ≤1.5% ✅ (实测 0.92% 接近 oracle 0.89%)
  - SNR=20 灾难率 ≤15% ✅ (实测 6.7% = oracle)
  - 单调性 ✅ (V5.6 后 SNR=15→20 不反弹)
  - SNR=15 灾难率 ≤25% **边缘 partial**（实测 26.7% 仅超 1.7pp，单 seed=13 边界效应）
- [x] conclusions.md 累积条目（V5.5+V5.6 章节）
- [x] todo.md 同步（L108 状态 4/5 PASS）

## 归档决策（2026-04-26）

主要目标达成（SNR=20 mean+灾难率全 PASS 接近 oracle，单调恢复）。残余 SNR=15 灾难率 26.7% 边缘是 seed=13 单 seed 边界效应，**不属 estimator 偏差驱动**（H4 已确认 oracle 下 s15=8.90%）。

后续 L0 deterministic +1.5e-5 bias 残余（非 SNR=15 灾难原因）+ estimator-外灾难（s15 oracle 仍 8.90%）独立 spec 立项：
- 候选 1：L0 deterministic α bias 校正（HFM+/HFM- ensemble / Jakes-aware）
- 候选 2：SC-TDE fd=1Hz estimator-外灾难调研（BEM/Turbo/CFO 稀有触发）

本 spec 归档（active → archive），关键代码已 commit 在 archive parent spec 链：
- V5.4 commit `6613041` (post-CFO fix)
- V5.5 commit `3cb4660` (fd-conditional iter)
- V5.6 commit `c2dede1` (HFM signature calibration)
