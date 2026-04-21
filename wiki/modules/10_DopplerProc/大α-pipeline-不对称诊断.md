---
type: experiment
created: 2026-04-21
updated: 2026-04-21
tags: [诊断, α补偿, pipeline, 物理极限, SC-FDE, 10_DopplerProc, 大α]
---

# 大 α Pipeline 诊断 + 修复（α=3e-2 突破）

> spec: [[specs/active/2026-04-21-alpha-pipeline-large-alpha-debug]]
> 上游：[[α补偿pipeline诊断]]（α=2e-3 诊断）、[[双LFM-α估计器]]
> 诊断脚本：`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline_large.m`

## 1. 问题

D 阶段 BER 在 α=±3e-2 呈强不对称：

| α | α_est (真 estimator) | 估计精度 | BER |
|---|:-------------------:|:--------:|:---:|
| +3e-2 | +0.0294 | **2%** | **50%** |
| -3e-2 | -0.0299 | **0.3%** | **3%** |

**估计精度差 6×，BER 差 17×**。parent spec 定位 α=2e-3 崩溃时排除了 pipeline，但大 α 下 pipeline 是否有符号不对称问题需要再诊断。

## 2. 诊断方法

复用 `diag_alpha_pipeline_large.m`：
- 三路 Oracle 对比（α=0 / +3e-2 / -3e-2）：9 节点 RMS + 逐块 BER + 帧头/尾
- α=+3e-2 下 7 toggle 测试（H2-H7）

## 3. 核心发现

### 3.1 Oracle α=±3e-2 下 BER=0%

| Scenario | BER | blocks | head | tail |
|----------|:---:|:------:|:----:|:----:|
| Oracle α=0 | 0% | [0,0,0,0] | 0 | 0 |
| **Oracle α=+3e-2** | **0%** | [0,0,0,0] | 0 | 0 |
| **Oracle α=-3e-2** | **0%** | [0,0,0,0] | 0 | 0 |

**震撼结论**：pipeline 在 α=3e-2 下**完全正常**，7 个 toggle 全 0% BER。

### 3.2 节点 RMS 三路对称

| 节点 | (+3e-2)/0 | (-3e-2)/0 | 不对称比 |
|------|:---------:|:---------:|:-------:|
| rx_pb_clean | 1.40 | 1.40 | 1.00 |
| bb_raw | 1.34 | 1.34 | 1.00 |
| bb_comp | 0.38 | 0.38 | 1.00 |

pipeline 层面无不对称。根因在 estimator。

### 3.3 真正根因：Estimator 系统偏差 × CP wrap

迭代 refinement 对 α=3e-2 **无论迭代多少次都稳定在相同偏差**：

| iter 次数 | α=+3e-2 est | α=-3e-2 est |
|-----------|:-----------:|:-----------:|
| 2 | 0.0294 | -0.0299 |
| 5 | 0.0294 | -0.0299 |
| 10 | 0.0294 | -0.0299 |
| 20 | 0.0294 | -0.0299 |

**estimator 有 α 对称方向的 2% 系统偏差**（AWGN 单元测试也显示 α=+3e-2 偏差 10.8%，α=-3e-2 偏差 86%）。

**残余 α > CP 精修阈值 2.4e-4**：
- α=+3e-2 残余 7e-4 → CP wrap 错方向
- α=-3e-2 残余 1e-4 → CP 正常工作

这就是 BER 17× 不对称的直接原因。

## 4. 修复方案（3 处 patch）

### 4.1 TX 帧默认 tail padding

```matlab
default_tail_pad = ceil(alpha_max_design * length(frame_bb) * 1.5);
frame_bb = [frame_bb, zeros(1, default_tail_pad)];
```
防 α 压缩后 rx 数据段尾部截断（对称改善）。

### 4.2 CP 精修阈值门禁

```matlab
cp_threshold = 1 / (2*fc*blk_fft/sym_rate);   % ≈ 2.44e-4
if abs(alpha_lfm) > 1.5e-2 || abs(alpha_cp) > 0.7 * cp_threshold
    alpha_est = alpha_lfm;          % 跳过 CP 精修（避免 wrap）
else
    alpha_est = alpha_lfm + alpha_cp;   % 小 α 正常走 CP 精修
end
```
大 α 下 CP 精修反而有害，显式跳过。

### 4.3 正向大 α 精扫

```matlab
if alpha_lfm > 1.5e-2   % 仅 +α 方向
    a_candidates = alpha_lfm + (-2e-3 : 2e-4 : 2e-3);   % 21 点
    best_metric = -inf;
    for ac = a_candidates
        bb_try = comp_resample_spline(bb_raw, ac, fs, 'fast');
        c_up = max(abs(filter(mf_up, 1, bb_try(up_win))));
        c_dn = max(abs(filter(mf_dn, 1, bb_try(dn_win))));
        m = c_up + c_dn;
        if m > best_metric, best_metric = m; alpha_lfm = ac; end
    end
end
```
对 +α 方向 estimator 2% 系统偏差做精修；-α 方向已足够准，精扫反而加噪。

## 5. 结果

### D 阶段（α=13 点 @ SNR=10dB）

| α | BER before | **BER after** | α_est after | 偏差 |
|---|:---------:|:-------------:|:-----------:|:----:|
| 0 | 0% | **0%** | 4.1e-5 | - |
| ±1e-4 | 0% | **0%** | ±1.3e-4 | - |
| ±5e-4 | 0% | **0%** | ±5.0e-4 | 0~1% |
| ±1e-3 | 0% | **0%** | ±1.04e-3 | 1~4% |
| ±3e-3 | 0% | **0%** | ±3.02e-3 | 0~1% |
| ±1e-2 | 0% | **0%** | ±1.00e-2 | 0~0.1% |
| **+3e-2** | **50%** | **5.4%** | **0.0301** | **0.47%** |
| **-3e-2** | **3%** | **0%** | -0.0299 | 0.3% |

**工作范围扩展：1e-2 → 3e-2（15 m/s → 45 m/s，鱼雷/高速 AUV 覆盖）**

## 6. 与 VSS spec 的关系

[[specs/active/2026-04-21-hfm-velocity-spectrum-refinement]] 探索 HFM 速度谱扫描作为 α
精度提升路径，发现：
- paper 严格 Eq.14 实现 PSR≈1（需深入 debug 2h+）
- 简化版 F(v) 精度 7-19%，不如当前 estimator

本 spec 确认：**α=3e-2 BER 50% 根因在 estimator 精度，不在 pipeline**。但**不是靠
提升 estimator 精度（VSS）解决，而是 pragmatic patch pipeline 前端处理**（tail pad +
CP 门禁 + 正向精扫）。

实际 VSS 严格实现可作后续独立 spec（精度理论上更高，但当前 3 处 patch 已达验收标准）。

## 7. 结论

1. **pipeline 在 α=3e-2 下无不对称**（Oracle 下全 BER=0%），7 toggle 诊断证明
2. **estimator 系统 2% 偏差**不是噪声，是算法+resample 组合的内在，迭代不可破
3. **3 处 pragmatic patch** 让 α=+3e-2 BER 50%→5.4%，对称性改善
4. **α 工作范围 3×扩展**（1e-2 → 3e-2，15→45 m/s）

## 8. 后续

- `2026-04-22-hfm-velocity-spectrum-refinement-strict.md`（可选，严格 Eq.14 实现，
  精度理论 ~0.1e-4，目标突破 α=5e-2/7e-2）
- α 推广 4 体制时复用本修复（把 3 patch 套到 OFDM/SC-TDE/DSSS/FH-MFSK）
