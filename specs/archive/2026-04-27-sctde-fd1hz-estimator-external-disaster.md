---
project: uwacomm
type: investigation
status: archived
created: 2026-04-27
updated: 2026-04-27
archived: 2026-04-27
archived_reason: 接受 known limitation（边际价值低，类比 SC-FDE Phase J 同模式归档先例）
parent_spec: specs/archive/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md
related: SC-FDE Phase J 类比、V5.6 4/5 PASS 后残余 estimator-外灾难
tags: [SC-TDE, fd=1Hz, disaster, estimator-外机制, Jakes, BCJR, BEM, Turbo, 13_SourceCode, known-limitation]
branch: investigate/sctde-fd1hz-estimator-external-disaster
---

# SC-TDE fd=1Hz estimator-外灾难调研（s15 oracle 仍 8.90%）

## 背景

V5.5+V5.6 主目标已达成（4/5 PASS，spec `archive/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md`）：
- SNR=20 mean 0.92%（oracle 0.89%）✅
- SNR=20 灾难率 6.7%（= oracle）✅
- 单调恢复 ✅

**但 SNR=20 的 6.7% 灾难率 = 1/15 seed（s15）= oracle 残留**。H4 oracle α 实验已确认：alpha 给真值后 s15 仍 BER=8.90%（SNR=20），即**非 estimator 偏差驱动**。

类比 SC-FDE Phase I+J（archive/2026-04-23-scfde-phase-i-j-deterministic-disaster？）：30 seed Monte Carlo 灾难率 10%（mean 5%、median 0%），oracle α 仍 ~50%，非单调 BER vs SNR；候选根因 5 层（Channel 极性 / BCJR 固定点 / Frame timing / CFO 边界 / Soft demap）。

V5.6 后 SC-TDE estimator-外灾难定位：fd=1Hz × seed=15 × SNR=20 这个稀有点，是当前 SC-TDE fd=1Hz 路径的物理 limitation 上界。

## 目标

锁定 s15 oracle 8.90% 灾难根因，分以下三档收尾：

1. **可修复机制**（如 BEM Q 选错、Turbo 固定点）→ fix 让 s15 → ~0%，灾难率 6.7%→0%
2. **物理极限机制**（如低 SNR + Jakes 深衰落）→ 量化 + 归档为 known limitation
3. **稀有 seed 边界效应**（不可一般化）→ 加大样本（30+ seed）确认是否 isolated

## 调研步骤

### Step 1：复现 + 量化

写 `tests/bench_common/diag_sctde_fd1hz_s15_disaster.m`：
- 锁定 s15 配置（fd=1Hz, SNR=20, oracle α）
- 重跑 + dump 中间变量：
  - Jakes h_time 时间序列（CIR 沿 frame 演化）
  - LMMSE-IC 后 x_tilde、mu、nv_tilde
  - BCJR 输入 LLR（Le_eq_deint）+ 输出 Lpost_info
  - turbo iter=1..6 收敛轨迹（每轮 BER + |LLR| median）
  - frame timing 偏差 sync_tau_err
  - CFO 估计/补偿值
- 输出 .mat + 关键时刻图

### Step 2：候选根因 5 层 ablation

类比 SC-FDE Phase J：

| 层 | 假设 | Ablation 验证 |
|---|---|---|
| **L1 Channel 极性** | h_time 在 frame 中段 dominant tap 极性翻转，导致 BEM 内插错误 | dump h_time，检查 dominant tap 极性是否在 frame 中段反号 |
| **L2 BCJR 固定点** | 卷积码软输出在低 LLR 区收敛到错误固定点 | 修改 BCJR 初值（La 注入 0.1·random）看 BER 是否变 |
| **L3 Frame timing** | sync_tau_err 在边界 ±2 sps 时定时偏移导致 ICI | force `sync_tau_err=0`（用 oracle timing）看是否改善 |
| **L4 CFO 边界** | 低 SNR 下 fc 估计抖动导致残余 CFO | 跳过 CFO 估计/补偿（cfg.skip_cfo=true）看是否改善 |
| **L5 Soft demap** | LLR 截断 ±30 在边界饱和，BCJR 输入失真 | 放松 LLR clip 到 ±60 或 ±100 看是否改善 |

每层 ablation 跑 s15 + 邻近 seed（s11, s12, s14, s16）各 SNR=20，~5min/层，~30min 总。

### Step 3：根因锁定

按 ablation 结果分支：
- 若某层 ablation 让 s15 BER 大幅降低 → 锁定该层为根因，进 Step 4 fix
- 若 5 层都不显著 → 进 Step 5 加大样本看是否 isolated seed

### Step 4：Fix 实施（如适用）

- L1 Channel 极性：BEM Q 提升 / 更好基函数（Karhunen-Loeve / Slepian）
- L2 BCJR 固定点：log-map 替代 max-log / iter 重启
- L3 Frame timing：精同步 sub-sample（分数 sps）
- L4 CFO 边界：CFO 估计稳健化（chirp loop / window 平均）
- L5 Soft demap：LLR clip 自适应 / log-domain demap

### Step 5：加大样本确认

如 5 层 ablation 无果，跑 50 seed + SNR=20 oracle α，统计灾难率：
- 若 1/50 → 极稀有 seed，归 known limitation
- 若 ≥3/50 → 有系统机制，需更深调研

## 非目标

- ❌ V5.6 4/5 PASS 已达成，不重做 estimator
- ❌ SNR=10/15 灾难（已知 limitation，与 estimator-外机制不同）
- ❌ 修改其他体制 (DSSS/OFDM/SC-FDE) 灾难（独立 spec）
- ❌ Jakes 信道模型本身（gen_uwa_channel 不动）

## 接受准则

- [ ] Step 1 诊断脚本 + dump 数据
- [ ] Step 2 5 层 ablation 完成
- [ ] Step 3 根因锁定（具体某层 / 多层 / 稀有 seed）
- [ ] Step 4 fix 实施（如适用）让 s15 BER 大幅降低
- [ ] OR Step 5 50 seed 样本确认稀有度
- [ ] conclusions.md 累积条目
- [ ] todo.md 同步

## 工时估算

- Step 1：诊断脚本 + 跑 = 1h
- Step 2：5 层 ablation = 1h
- Step 3：分析 = 30 min
- Step 4 (如适用)：fix + 验证 = 2-3h
- Step 5 (备选)：50 seed = 30 min + 分析
- **总计：~3-5h**（无 fix）/ ~5-7h（有 fix）

## 优先级

🟡 中优先（V5.6 主目标已 PASS，本 spec 是收尾完美主义；s15 灾难率 6.7% 实际可接受为已知 limitation）

## 用户决策（2026-04-27）：接受 known limitation 跳过

走选项 3。理由：
- V5.6 主目标 4/5 PASS 已达成（SNR=20 mean 0.92% / 灾难率 6.7% / 单调），灾难率 = oracle 物理上界
- s15 灾难率 6.7%（SNR=20）即 oracle 残留，与 estimator 无关，物理 layer 限制
- 类比 SC-FDE Phase I+J 归档先例：~10% 灾难率 4 诊断未锁定根因，最终归档；SC-TDE 现状 6.7% 比 SC-FDE 还轻
- 5h 调研 marginal value 低（已知非 estimator，BEM/BCJR/timing/CFO/demap 5 层 ablation 期望产出 isolated 单 seed 边界）

## 接受 known limitation

- SC-TDE fd=1Hz × seed=15 × SNR=20 oracle α BER 8.90% 灾难是当前 SC-TDE fd=1Hz 路径的物理 limitation 上界
- 与 estimator 偏差解耦（H4 oracle α 实验已确认）
- 6.7% 灾难率（1/15 seed）= V5.6 实测 = oracle 上界 = 物理极限
- conclusions.md / SC-TDE 调试日志记录归档原因

## 后续（如未来重启需要）

如果未来需要降低 SC-TDE fd=1Hz 灾难率（如新场景要求 < 1% seed 灾难率），可重新激活本 spec 走 Step 1-5。当前不强求。

类似机制（estimator-外灾难）若在其他体制 / 其他 fd 出现 → 类比本 spec 设计（5 层 ablation）。
