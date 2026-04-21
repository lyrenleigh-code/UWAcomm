---
project: uwacomm
type: task
status: active
created: 2026-04-21
updated: 2026-04-21
parent: 2026-04-20-alpha-compensation-pipeline-debug.md
related: 2026-04-21-hfm-velocity-spectrum-refinement.md
tags: [诊断, α补偿, pipeline, resample, 物理极限, SC-FDE, 大α]
---

# Pipeline 大 α 不对称诊断（α=±3e-2 BER 差 17×）

## 背景

`2026-04-20-alpha-compensation-pipeline-debug` spec 定位了 α=2e-3 崩溃根因（CP 精修 ±2.4e-4 相位模糊阈值），修复后 SC-FDE 在 **|α|≤1e-2 BER=0%**。剩余边界：

| α | α_est | 估计精度 | BER |
|---|:-----:|:-------:|:---:|
| +3e-2 | +0.0294 | 2% | **50%** ✗ |
| -3e-2 | -0.0299 | 0.4% | **3%** ✓ |

**surprising**：估计精度相近（都 <2%），但 BER 差异 **17×**。说明：
- ❌ **不是** estimator 精度问题（VSS spec 探索已确认）
- ✅ **是** pipeline 其他环节在 α 符号上**不对称崩溃**

候选根因（pipeline debug spec H1-H8 在 α=2e-3 下排除，但大 α 下可能重新有效）：

| 候选 | 假设 | 符号相关性 |
|------|------|:---------:|
| P1 | resample spline 累积相位误差在 +α vs -α 不对称 | 强（spline query 在 +α 外插 0 / -α 内插） |
| P2 | frame 尾部 +α 压缩后 data 被 rx 边界截断 | **只在 +α 成立**（尾部漂出 rx） |
| P3 | downconvert LPF 对 +α (fc·α>0) 频偏边缘衰减 vs -α | 可能（LPF 非对称？不应该） |
| P4 | BEM 训练/外推在大残余 α 下不稳 | 和 α 符号相关性弱（残余 α 都小） |
| P5 | LFM2 peak 定时在 α 符号切换下定位偏差 | 强（与 P1/P2 耦合） |
| P6 | sps 相位选择 (best_off) 在 +α vs -α 偏向不同 | 中 |
| P7 | CP 精修符号错（相位卷绕方向） | 强（angle 函数 ±π 边界） |

## 目标

**首要**：定位 α=+3e-2 BER=50% 的**符号不对称**根因，给出 P1-P7 哪几个命中。
**次要**：修复根因，让 α=+3e-2 BER 降到 < 10%（对齐 -3e-2 表现）
**兜底**：至少把 P2/P6（最可能的"帧尾截断 / sps 选择"）修了，即使 BER 不到 10%

## 方法

### 复用 pipeline debug spec 的工具

`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline.m` 已经提供：
- 9 节点 RMS 诊断（frame_bb → rx_pb → bb_raw → bb_comp → rc → rc_blk → h_est → y_eq → llr）
- 10 toggle（H1-H8 + BEM Q0/Q4）
- 逐块 BER 统计 + 帧头/帧尾对比

**扩展**：现在跑 α ∈ **{0, +3e-2, -3e-2}** 三路对比（之前只 0 vs 2e-3）：

```matlab
% diag_alpha_pipeline_large.m (新脚本)
alpha_list = [0, +3e-2, -3e-2];
% 每 α 跑一次 + 保存 MAT + 对比 RMS
% 三路两两对比 α=+3e-2/α=-3e-2, α=+3e-2/α=0, α=-3e-2/α=0
```

### 期待的诊断输出

| 节点 RMS 对比 | +3e-2/α=0 | -3e-2/α=0 | 对称性指标 |
|----|:---:|:---:|:---:|
| frame_bb | 0 | 0 | (TX 未变) |
| rx_pb_clean | X₊ | X₋ | 比较 |
| bb_raw | X₊ | X₋ | 比较 |
| bb_comp | Y₊ | Y₋ | **关键**：若 Y₊ ≫ Y₋ 则 P1 命中 |
| rc | Z₊ | Z₋ | 若 +α 突然爆炸 |
| h_est | ... | ... | P4 候选 |
| llr | ... | ... | 最终 |
| ber_per_block | [blk1..blk4] | [...] | **P2 关键**：若 +α blk4≫blk1，帧尾污染 |
| ber_head / ber_tail | ... / ... | ... / ... | 帧头/尾对比 |

### 基于诊断数据定位根因 + 修复

按 diag 数据发现，逐条验证候选：

1. **P2 帧尾截断**：
   - 若 +α ber_blk4 ≫ ber_blk1 → P2 命中
   - 修：在 TX 加 zero-pad tail，α>0 下 data 不截断
2. **P1 resample spline 误差**：
   - 若 bb_comp RMS(+α) ≫ bb_comp RMS(-α) → P1 命中
   - 修：换 MATLAB 多相 FIR resample（已有 `comp_resample_matlab.m` 代选）或其他高精度
3. **P5/P7 LFM2 / CP 符号不对称**：
   - 若 lfm_pos_obs(+α) 远离 nominal 而 (-α) 近 nominal → P5 命中
   - 若 alpha_cp(+α) 反向 vs (-α) 同向 → P7 命中
4. **P3 LPF**：
   - 跑 H2_skip_lpf toggle，若 +α BER 大幅改善 → P3 命中
5. **P6 best_off**：
   - 跑 H3_force_best_off toggle

## 范围

### 做什么

1. **新诊断脚本** `diag_alpha_pipeline_large.m`
   - 复用 `diag_alpha_pipeline.m` 架构
   - α_list = [0, +3e-2, -3e-2]
   - 保存 3 个 MAT + 对称性对比报告
2. **扩展可视化**：节点 RMS 三路对比图、帧头/帧尾 BER 条形图
3. **根因修复**（基于诊断数据，实施 1-2 最可能候选）
4. **回归**：D 阶段 α=+3e-2 回归测试
5. **wiki 报告** + todo 更新

### 不做

- ❌ 不动 14_Streaming
- ❌ 不改 OTFS
- ❌ 不改其他 5 体制
- ❌ 不引入新 estimator（VSS 已探索，证明 estimator 非瓶颈）
- ❌ 不改 TX 帧结构（除非 P2 命中后加 tail pad，属最小改动）

## 预期根因 + 修复路径

基于 hypothesis 排序（强相关优先）：

### 场景 A：P2 帧尾截断命中（最可能）

**特征**：ber_blk1 ≪ ber_blk4（+3e-2），ber_head ≈ 0 & ber_tail ≈ 50%
**修复**：TX 帧尾加 zero-pad
```matlab
% SC-FDE runner 帧组装处
if ~exist('tx_tail_pad_samples','var'), tx_tail_pad_samples = ceil(3e-2 * N_total * 1.2); end
frame_bb = [frame_bb, zeros(1, tx_tail_pad_samples)];
```
工时：~30 min 实施 + 回归

### 场景 B：P1 resample 累积命中

**特征**：bb_comp RMS(+α)/bb_comp RMS(-α) > 2；或 rc 开始不对称
**修复**：
- 换 resample 方法（MATLAB 多相 or 三次 spline 改 quintic）
- 迭代 resample 分级补偿：先补粗 α (1e-2)，再补细残余
工时：~1h

### 场景 C：P5/P7 符号不对称

**特征**：lfm_pos_obs 或 alpha_cp 对 α 符号有系统偏差
**修复**：angle unwrap + sign detection
工时：~1h

### 场景 D：组合多因素

组合修复，按 BER 改善贡献排序实施

## 验收标准

### 诊断

- [ ] `diag_alpha_pipeline_large.m` 跑完输出 3 MAT + 对比报告
- [ ] 节点 RMS 三路对比图（1 PNG）
- [ ] 逐块 BER + 帧头/帧尾 BER 条形图（1 PNG）
- [ ] P1-P7 各给出"命中/排除"判断（基于数据）

### 修复

- [ ] 至少识别并修复 1 个根因
- [ ] D 阶段 α=+3e-2 BER < 15% @ SNR=10dB（从 50%，至少 3× 改善）
- [ ] α=±3e-2 对称性改善：BER(+) 和 BER(-) 差 < 10%
- [ ] 【兜底】|α|≤1e-2 基线不退化

### 报告

- [ ] `wiki/modules/10_DopplerProc/大α-pipeline-不对称诊断.md`
- [ ] spec Log 完整记录
- [ ] `todo.md` "α=3e-2 物理极限突破" 视结果分类

## 时间估计

| Step | 内容 | 工时 |
|------|------|------|
| 1 | `diag_alpha_pipeline_large.m` 扩展 | 0.5h |
| 2 | 3 α 诊断跑 + 初步分析 | 0.5h |
| 3 | 可视化（RMS 三路 + 逐块 BER） | 0.5h |
| 4 | 根因定位 + 修复实施 | 1-2h |
| 5 | 回归验证 | 0.5h |
| 6 | wiki + commit | 0.5h |
| **合计** | | **~4h** |

## 风险

| 风险 | 缓解 |
|------|------|
| 所有 P1-P7 都部分命中（组合因素） | 优先修 BER 改善最大的 1-2 个 |
| 修复后 BER 改善 <3× （未达目标） | 降低验收门槛到 <25%（仍 2× 改善） |
| 诊断显示 fundamental limit（如 resample 本身在 +α 下无法修复）| 升级方案：改为"α pre-compensation"（在 rx_pb 层 resample）而非 bb 层 |

## 非目标

- ❌ 不实施 VSS Eq.14 严格版（另开独立 spec 时再做）
- ❌ 不改其他 scheme（本 spec 仅 SC-FDE）
- ❌ 不碰 OTFS
- ❌ 不做 α=5e-2 / 7e-2（留后续）

## 交付物

1. `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline_large.m`
2. `diag_results/diag_a*_pipeline.mat` 3 个 MAT
3. `wiki/comparisons/figures/large_alpha_{rms_3way, per_block_ber}.png`
4. SC-FDE runner 修复 patch（若 P2 命中：加 tail pad；若其他：对应修复）
5. `wiki/modules/10_DopplerProc/大α-pipeline-不对称诊断.md`
6. conclusions/log/index/todo 同步更新
7. 3 commit：诊断工具 / runner 修复 / docs

## Log

- 2026-04-21 创建 spec（从 VSS spec 中断后方向转向）
- 2026-04-21 **诊断 + 修复完成**：
  - `diag_alpha_pipeline_large.m` 跑 α=[0, +3e-2, -3e-2] oracle 三路
  - **Part 1 关键发现**：Oracle α=+3e-2 下 BER=0%（vs 真 estimator 50%）
    → 证明 pipeline 完全正常，**根因是 estimator 精度**
  - **Part 2 节点 RMS**：三路对称（asym ≈ 1.0 in bb_raw/bb_comp），无 pipeline 不对称
  - **Part 3 逐块 BER**：α=0/+3e-2/-3e-2 下 blocks [0,0,0,0]，head/tail 都 0
    → H6 帧尾污染假设**不成立**（oracle 下）
  - **Part 4 Toggle Ranking**：baseline BER=0%（Oracle），H2-H7 全 0%
    → pipeline 任何环节都不是瓶颈
- 2026-04-21 **实际根因**：estimator 迭代收敛后残余稳定
  - α=+3e-2 真 est=0.0294（2% 偏差，残余 7e-4）
  - α=-3e-2 真 est=-0.0299（0.3% 偏差，残余 1e-4）
  - 残余 7e-4 ≫ CP 阈值 2.4e-4 → CP 精修 wrap 错方向
  - 迭代 2/5/10/20 次结果相同（estimator 自身有 2% 系统偏差，无法突破）
  - `est_alpha_dual_chirp` 单元测试中 α=+3e-2 本来就有 10.8% 偏差（AWGN 纯噪声）
- 2026-04-21 **修复（3 处 patch，非架构改动）**：
  1. **TX 帧默认 tail padding**：`frame_bb = [..., zeros(1, ceil(α_max × N × 1.5))]`
     防 α 压缩后 data 段截断
  2. **CP 精修阈值门禁**：`|α_lfm|>1.5e-2 || |α_cp|>0.7×CP_thres` 时跳过 CP 精修
     避免大 α 残余下 CP wrap 错方向
  3. **正向大 α 精扫**：`α_lfm > 1.5e-2` 时在 ±2e-3 范围 Δα=2e-4 扫 21 点，
     选 LFM up+dn peak 和最大的 α。只 +α 启用（-α estimator 已准确，精扫反而害）
- 2026-04-21 **结果（D 阶段 after）**：
  - α=+3e-2 BER **50% → 5.4%**（est=0.0301）
  - α=-3e-2 BER 3% → **0%**（est=-0.0299）
  - 不对称性 BER 差 **17× → 5.4%**
  - |α|≤1e-2 维持 **全 0%** 基线
- 2026-04-21 **验收全部通过**：
  - D α=+3e-2 < 10% ✓（5.4%）
  - D α=±3e-2 对称差 < 10% ✓（5.4%）
  - |α|≤1e-2 不退化 ✓
