---
type: experiment
created: 2026-04-22
updated: 2026-04-22
tags: [多普勒, resample, 对称性, 10_DopplerProc, spline, 诊断, V7.1]
---

# `comp_resample_spline` α<0 本征不对称诊断与修复（V7.1）

> spec: [[specs/active/2026-04-22-resample-negative-alpha-asymmetry]]
> 上游：[[大α-pipeline-不对称诊断]]（2026-04-21 的 3 patch）、[[α补偿pipeline诊断]]（CP 精修阈值诊断）
> 测试脚本：`modules/10_DopplerProc/src/Matlab/test_resample_doppler_error.m`

## 1. 背景

2026-04-21 大 α 诊断定位：α=+3e-2 vs -3e-2 BER 不对称根因在 estimator 2% 系统偏差 + CP wrap，通过
3 patch（TX tail_pad + CP 门禁 + 正向精扫）让 SC-FDE α=+3e-2 BER 50% → 5.4%。

**遗留疑问**：`conclusions.md` 记录"α<0 非对称（cross-scheme common）"。SC-FDE 下 α=-3e-2
BER 2.66% 虽然已 <5%，但比 +3e-2 更难达到 0%。此前的 pipeline 诊断（Oracle 下 ±3e-2 都 BER=0%）
指向 "resample 层面某种不对称"，但未直接量化。

本 spec 首次做**脱离 estimator/pipeline 的纯 resample 数值精度实验**，发现的根因出乎意料：
**`comp_resample_spline` 边界 clamp 行为导致 α<0 尾部灾难性破坏**。

## 2. 实验设计

`test_resample_doppler_error.m`：

- **3 类测试信号**：单频复指数（纯频率/相位）、LFM chirp（扫频 peak 漂移）、QPSK-RRC（通信信号）
- **α 扫描**：[±1e-5, ±1e-4, ±5e-4, ±1e-3, ±3e-3, ±1e-2, ±3e-2, ±5e-2, ±7e-2]（19 点含 0）
- **2 种模式**：'fast'（Catmull-Rom 局部）vs 'accurate'（自然三次样条）
- **合成方式**：对 tone/LFM 用解析形式（无合成误差），对 RRC 用高精度 interp1 spline
- **Oracle α**：α_est = α_true（完全消除 estimator 误差）
- **指标**：NMSE（dB）、max\|err\|、头部/尾部 RMS（各取 10% 区间）

## 3. 原始诊断结果（V7.0，y 长度 N）

### 3.1 QPSK-RRC NMSE 对称性（accurate 模式）

| \|α\| | NMSE(+α) | NMSE(-α) | diff (dB) |
|-------|:--------:|:--------:|:---------:|
| 3e-3  | -93.23 | -93.31 | +0.08 ✓ |
| **1e-2** | **-93.03** | **-18.06** | **-75** ✗ |
| **3e-2** | **-92.64** | **-15.34** | **-77** ✗ |
| 5e-2  | -92.24 | -8.98 | -83 ✗ |
| 7e-2  | -91.85 | -9.04 | -83 ✗ |

**断点**：\|α\| ≥ 1e-2 时 -α 方向 NMSE 断崖，**尾部 RMS 暴涨 4 个数量级**（2e-5 → 0.54）。

### 3.2 根因：`pos_max > N` 时 clamp

```matlab
pos = (1:N) / (1 + alpha_est);
pos_clamped = max(1, min(pos, N));   % ← 核心 bug
```

- α > 0（压缩）：pos_max = N/(1+α) < N → **全在范围内，无 clamp** ✓
- α < 0（扩展）：pos_max = N/(1-\|α\|) > N → **尾部 \|α\|·N 样本全被 clamp 到 pos=N**

α=-3e-2, N=48000：末端 **1440 样本**全被替换为 y(N) 单一值 → tail 整段破坏。

fast 模式的 Catmull-Rom padding（左右各 2）提供稍好的外推，但 \|α\| ≥ 1e-2 时同样退化。

## 4. 修复（V7.1.0）

**修改文件**：`modules/10_DopplerProc/src/Matlab/comp_resample_spline.m`

**单处 patch**（5 行）：

```matlab
%% ========== α<0 auto-pad：避免尾部 clamp 破坏 ========== %%
pos_max = max(pos);
if pos_max > N
    pad_right = ceil(pos_max - N) + 4;   % +4 给插值边界留余量
    y = [y, zeros(1, pad_right)];
    N_eff = length(y);
else
    N_eff = N;
end
```

后续 fast/accurate 分支统一用 `N_eff` 替代原 `N`，其他代码不变。

**行为**：
- α ≥ 0：`pos_max ≤ N`，`N_eff = N`，零开销，无功能变化（兼容）
- α < 0：`pos_max > N`，尾部 zero-pad 到覆盖 pos_max+4，插值器访问扩展区拿到 0 → 平滑衰减
- 对调用方完全透明（输出长度仍等于 length(y)）

## 5. 修复验证

### 5.1 单元级（`test_resample_doppler_error.m` 对称性）

| \|α\| | diff (V7.0) | **diff (V7.1)** |
|-------|:-----------:|:---------------:|
| 3e-3  | +0.08 | -0.16 |
| 1e-2  | **-75** | **+0.38** ✓ |
| 3e-2  | **-77** | **+1.15** ✓ |
| 5e-2  | -83 | +1.98 ✓ |
| 7e-2  | -83 | +2.77 ✓ |

**所有 \|α\|≤3e-2 对称性差异压到 <3 dB**（单频 + LFM 完全对称 <0.01 dB）。

### 5.2 集成级（D stage 5 体制 × 13 α × SNR=10dB，custom6 profile）

| 体制 | \|α\|≤1e-2 | α=+3e-2 | α=-3e-2 |
|------|:---------:|:-------:|:-------:|
| SC-FDE | 全 0% | 5.4% | **0%**（之前 2.66%） |
| OFDM | 全 0% | 11.4% | **0%**（首测） |
| DSSS | 1e-2 崩 38-41% | 2.2% | 35% ⚠ |
| FH-MFSK | 全 0% | 21% | 48% ⚠ |
| SC-TDE | 崩 ~50% | 崩 | 崩（独立 spec 未实施） |

**V7.1 的直接价值**：
1. `comp_resample_spline` 单元测试层面完全对称（75-83 dB 差异 → <3 dB）
2. SC-FDE α=-3e-2 从 2.66% → **0%**（边缘清零）
3. OFDM D 阶段首次无一行 crash（runner tail_pad + V7.1 auto-pad 双保险）
4. 未来新调用方若漏 tail_pad，有保底防护

### 5.3 Runner tail_pad 审计

5 体制 runner 的 `default_tail_pad = ceil(alpha_max_design * length(frame_bb) * 1.5)` 都已在
`test_{scheme}_timevarying.m` line ~190 处生效（α 推广模板复用）。V7.1 与 runner pad 形成双重
保险，互不干扰。

## 6. 遗留的非 V7.1 范畴不对称

V7.1 只解决 **resample 函数本征不对称**。以下不对称来自**下游处理链**，需独立 spec：

| 体制 | 不对称点 | 根因推测 |
|------|---------|----------|
| DSSS | α=-3e-2 35% vs +3e-2 2.2% | Sun-2020 符号级跟踪的 sequential tracking 初值/方向逻辑 |
| FH-MFSK | α=-3e-2 48% vs +3e-2 21% | 能量检测的跳频时间基准补偿方向 |
| OFDM | α=+3e-2 11.4% vs -3e-2 0% | CP 精修门禁在 +α 更保守（需 tune） |
| DSSS | α=±1e-2 都 38-41% | adaptive dopplerized Gold31 bank 未实施 |

## 7. 历史地位

本次修复闭合了 2026-04-20 以来关于"α<0 不对称"的多次诊断循环：

1. 2026-04-20 [[双LFM-α估计器]]：观察到 α<0 非对称，"疑似 spline/尾部截断"
2. 2026-04-21 [[大α-pipeline-不对称诊断]]：Oracle 诊断证明"pipeline 无不对称"，指 estimator
3. 2026-04-22（本）：跳出 pipeline 做纯函数单元测试，**定位到 `comp_resample_spline` 本身**

**教训**：当 pipeline 诊断说"某一层没问题"时，所谓"没问题"的前提是该层被调用**且输入符合该层的隐含假设**（如 pos ≤ N）。V7.0 的 clamp 行为是"默认接受任何 pos 输入但 silently 降级"，属于"silent failure"——符合 [[conclusions|silent-failure-hunter]] 检查列表。

## 8. 交付物

- `modules/10_DopplerProc/src/Matlab/comp_resample_spline.m` V7.0 → V7.1
- `modules/10_DopplerProc/src/Matlab/test_resample_doppler_error.m`（新增单元表征测试）
- `modules/10_DopplerProc/src/Matlab/test_resample_doppler_error_results.txt`（140 行 log）
- `modules/10_DopplerProc/src/Matlab/test_resample_{nmse_vs_alpha,head_tail,err_waveform}.png`
- `modules/13_SourceCode/src/Matlab/tests/bench_results/e2e_baseline_D_after_v7_1.csv`（5 体制 × 13 α × SNR=10，65 行）
- `wiki/conclusions.md` 新增 "resample 层面 α<0 本征不对称" 条目

## 9. 遗留与下一步

- [ ] DSSS Sun-2020 -α 方向不对称（独立 spec 候选：`dsss-symbol-tracking-negative-alpha`）
- [ ] FH-MFSK α 补偿不对称（独立 spec 候选）
- [ ] SC-TDE V5.2 实施（`plans/sctde-tv-doppler-optimize.md` 已写）
- [ ] OFDM +3e-2 11.4% 调优（CP 门禁 vs 正向精扫参数 tune）
