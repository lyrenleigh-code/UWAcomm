---
type: experiment
created: 2026-04-20
updated: 2026-04-20
tags: [诊断, α补偿, pipeline, SC-FDE, 10_DopplerProc, CP精修]
---

# α 补偿 Pipeline 诊断（α=2e-3 断崖根因 + 修复）

> spec: [[specs/active/2026-04-20-alpha-compensation-pipeline-debug]]
> plan: [[plans/alpha-compensation-pipeline-debug]]
> 数据：`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_results/`
> 上游：[[双LFM-α估计器]]、[[comparisons/e2e-timevarying-baseline]]

## 1. 问题

Refinement spec（双 LFM estimator）让 α ≤ 1e-3 完美工作，但 **α ≥ 2e-3 断崖式 50% BER**。
四重排除实验已证明：
- ❌ Estimator 精度不是主因（oracle α=真值也崩）
- ❌ Resample 方法不是主因（spline 和 MATLAB 多相一致）
- ❌ Multi-path 耦合不是主因（单径信道也崩）
- ❌ CP 精修残余不是主因（强制 alpha_cp=0 也崩）

本 spec 深度 pipeline 诊断找根因。

## 2. 诊断方法

`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline.m`：
- 在 runner 里 8 节点插桩（frame_bb → rx_pb_clean → bb_raw → bb_comp → rx_sym_all → Y_freq → LLR → hard_coded）
- 10 个 toggle（H1-H8 + 2 BEM Q 值）独立验证
- α=0 vs α=2e-3 Oracle 两次跑 + RMS ratio 对比
- 逐块 coded BER（帧头 vs 帧尾对称诊断）

## 3. 核心发现

### 3.1 Oracle α + CP 精修 baseline = BER 0%

| Toggle | BER @ α=2e-3 oracle | blocks |
|--------|:-------------------:|:------:|
| baseline | **0%** | [0, 0, 0, 0] |
| H1_skip_resample | 51% | [0.52, 0.48, 0.50, 0.49] |
| H2_skip_lpf | 0% | [0, 0, 0, 0] |
| H3_best_off0 | 0% | [0, 0, 0, 0] |
| H4_oracle_h | 0% | [0, 0, 0, 0] |
| H5_force_lfm | 0% | [0, 0, 0, 0] |
| H6_pad_tail | 0% | [0, 0, 0, 0] |
| H7_skip_cp | 0% | [0, 0, 0, 0] |
| H8_bem_q0 | 0% | [0, 0, 0, 0] |
| H8_bem_q4 | 0% | [0, 0, 0, 0] |

**发现**：Oracle α + CP 精修 baseline 完美（0%），除 H1 skip_resample 外所有 toggle 无影响。Pipeline 本身没问题。

**之前 "oracle α + alpha_cp=0 → 47% BER" 的结论错了**——那次测试强制 alpha_cp=0 切断了 CP 精修链路。真正 oracle 是 alpha_lfm=真值 **并保留** alpha_cp 精修。

### 3.2 真正根因：CP 精修的相位模糊阈值

CP 自相关公式：`α_cp = angle(R_cp) / (2π · fc · T_block)`，其中 T_block = blk_fft / sym_rate。

无相位模糊范围（|angle| < π）：

```
|α_残余| < 1 / (2 · fc · T_block)
        = 1 / (2 · 12000 · 1024/6000)
        = 2.44e-4
```

Estimator alpha_lfm 有系统性 ~14% 低估（在 6 径信道下）：

| α_true | α_est (单次) | 残余 |α - α_est| | > CP 阈值 2.4e-4? | BER |
|--------|:-----------:|:--------------:|:----------------:|:---:|
| 5e-4 | 4.3e-4 | 7e-5 | ✓ 在阈值内 | 0% |
| 1e-3 | 8.9e-4 | 1.1e-4 | ✓ 勉强在阈值内 | 0.1%（边缘不稳） |
| **2e-3** | **1.72e-3** | **2.8e-4** | **✗ 超阈值** | **47%（CP wrap）** |

α=2e-3 时残余超阈值，CP 相位卷绕估反方向，`α_est = α_lfm + α_cp_错方向 = 过度补偿或欠补偿`，最终崩盘。

## 4. 修复：迭代 α refinement

**思路**：est_alpha_dual_chirp 基于 peak 位置（无相位模糊），对 resample 后的信号再估残余 α，多次迭代收敛到 CP 阈值内。

**实现**：在 runner 的 `est_alpha_dual_chirp` 调用之后插入：

```matlab
if bench_alpha_iter > 0 && abs(alpha_lfm) > 1e-10
    for iter_a = 1:bench_alpha_iter
        bb_iter = comp_resample_spline(bb_raw, alpha_lfm, fs, 'fast');
        [delta_raw, ~] = est_alpha_dual_chirp(bb_iter, LFM_bb_n, LFM_bb_neg_n, ...
                                              fs, fc, k_chirp, cfg_alpha);
        alpha_lfm = alpha_lfm + (-delta_raw);  % 符号对齐
    end
end
```

默认迭代 2 次。之后 CP 精修照常执行，此时残余已 <2.4e-4。

## 5. 结果（SC-FDE @ SNR=10dB）

### D 阶段（13 α 点）

| α_true | Before | MVP (single est) | **After iter (2×)** |
|--------|:------:|:----------------:|:-------------------:|
| 0 | 0% | 0% | **0%** |
| ±1e-4 | 0%/50% | 0%/0% | **0%/0%** |
| ±5e-4 | 49%/50% | **0%/2.4%** | **0%/0%** |
| ±1e-3 | 49%/50% | 0.1%/41% | **0%/0%** |
| ±3e-3 | 49%/50% | 50%/46% | **0%/0%** |
| ±1e-2 | 50%/50% | 50%/50% | **0%/0%** |
| +3e-2 | 50% | 50% | 50% (边界) |
| -3e-2 | 48% | 50% | **3%** |

### A2 阶段（α × SNR）

| α | Before | MVP | **After iter** |
|---|:------:|:---:|:--------------:|
| 5e-4 @ SNR=10 | 48.7% | 0% | **0%** |
| 1e-3 @ SNR=10 | 49.2% | 2% | **0%** |
| **2e-3 @ SNR=10** | 51.8% | 47% | **0%** |
| 2e-3 @ SNR=5 | - | 44% | 0.1% |
| 2e-3 @ SNR=15 | - | 48% | 0% |
| 2e-3 @ SNR=20 | - | 50% | 0% |

### 覆盖范围演进

| 阶段 | 可工作 α 上限 | 对应速度 (v=α·c) |
|------|:-------------:|:----------------:|
| 旧 estimator (LFM 相位差) | < 1e-4 | < 0.15 m/s（锚泊） |
| Refinement MVP | 1e-3 | 1.5 m/s（步行 AUV） |
| **迭代 α refinement** | **1e-2** | **15 m/s（快艇/AUV）** |

**10× 范围扩展**。

## 6. α=3e-2 物理极限讨论

α=+3e-2 after iter BER 仍 50%（α=-3e-2 部分工作 3%）。原因：
- resample 补偿 α·总帧长 ≈ 0.03 × ~37000 = **1100 样本**的全局时间压缩
- spline 插值 + 长信号累积相位误差
- downconvert LPF（~8kHz）对 α·fc=360Hz CFO 的边缘效应

这是 **resample 自身物理极限**，不是 estimator 或 CP 问题。改造需要 "预先 coarse resample + bandpass filter 扩展 + 迭代" 组合，属于独立 spec。

## 7. 可视化

- `figures/D_alpha_est_vs_true_{before,mvp,after_iter}.png` — 3 代 estimator 精度对比
- `figures/D_ber_vs_alpha_{before,mvp,after_iter}.png` — BER 崩溃阈值演进

## 8. 结论

1. **pipeline 各节点无瓶颈**（H2-H8 不救），resample 必需（H1 skip 崩）
2. **根因是 CP 精修 ±2.4e-4 相位模糊阈值**，配合 estimator 14% 系统误差在 α≥2e-3 下进入卷绕区
3. **迭代 α refinement（2 次）是完美修复**：每次迭代残余缩小 10×，快速收敛到阈值内
4. **α≤1e-2 工作范围**（15 m/s 相对速度）覆盖所有实用水声工况；α=3e-2 是 resample 物理极限

## 9. 后续 spec 候选

1. `2026-04-21-alpha-extreme-physical-limit.md`：α>1e-2 的 resample 优化（bandpass 扩展 + 迭代重采样，突破 3e-2 上限）
2. `2026-04-21-other-schemes-iter-refinement.md`：OFDM/SC-TDE/DSSS/FH-MFSK 同款迭代精修推广
3. `2026-04-22-otfs-dd-alpha-estimation.md`：OTFS DD 域 α 估计（无 HFM 对场景）
