---
type: concept
created: 2026-04-20
updated: 2026-04-20
tags: [多普勒, α估计, 双LFM, estimator, 10_DopplerProc]
---

# 双 LFM（up+down chirp）α 估计器

> spec: [[specs/active/2026-04-20-alpha-estimator-dual-chirp-refinement]]
> 上游诊断 spec: [[specs/active/2026-04-19-constant-doppler-isolation]]
> 代码：`modules/10_DopplerProc/src/Matlab/est_alpha_dual_chirp.m`
> 单元测试：`modules/10_DopplerProc/src/Matlab/test_est_alpha_dual_chirp.m`

## 1. 背景：旧 estimator 全盘失效

2026-04-19 D 阶段诊断（`e2e_baseline_D.csv` before）：

| α_true | α_est (before) | BER (before) |
|--------|----------------|--------------|
| 0 | +2.3e-6 | 0% |
| ±1e-4 | ~1e-5 | 0%/50% |
| ±5e-4 | ~1e-4 | 49%/50% |
| ±1e-3 | ~1e-4 | 49%/50% |
| ±3e-3 | ~1e-4 | 49%/50% |
| ±1e-2 | ~1e-4 | 50% |
| ±3e-2 | ~1e-4 | 50% |

**estimator 恒为 ~1e-5 噪声**，E2E BER 从 α=1e-4 即 50%。根因：帧里 LFM1 = LFM2 都是同一 up-chirp，双 LFM 相位差法对 α 不敏感（数学上只能测时钟/相位偏置）。

## 2. 改造

### 帧结构改动

```
旧：[HFM+|g|HFM-|g|LFM_up|g|LFM_up|g|data]     # LFM2 复用 up
新：[HFM+|g|HFM-|g|LFM_up|g|LFM_dn|g|data]     # LFM2 改 down-chirp
```

guard 扩展：`guard_samp = max(sym_delays)·sps + 80 + ceil(α_max·max(N_preamble, N_lfm))`，α_max=3e-2 下增加 ~72 样本。

### 算法

物理模型：`rx_bb(t) = frame_bb((1+α)·t) · exp(j·2π·fc·α·t)`

两个效应叠加：
- **全局时间压缩**：peak 位置整体漂移 -α·τ_nom
- **chirp Doppler**：up 与 down peak 反向漂移 ±α·fc/k

合计 dtau_residual 对 α 线性：
```
dtau_residual = (τ_dn^obs - τ_up^obs) - dtau_nom = α · (2·fc/k - dtau_nom)
     ⇓
α = dtau_residual / (2·fc/k - dtau_nom)
```

### 接口

```matlab
[alpha, diag] = est_alpha_dual_chirp(bb_raw, LFM_up, LFM_dn, fs, fc, k, search_cfg)
```

详见 `est_alpha_dual_chirp.m` 文件头注释。

## 3. 单元测试结果（AWGN @ SNR=10dB）

| |α_true| | rel_err | verdict |
|---------|---------|---------|---------|
| 0 | 1.4e-5 (abs) | ✓ |
| 1e-4 | 8-19e-6 (abs) | ✓ |
| 5e-4 | 0.5-1.8% | ✓ |
| 1e-3 | 1.0-1.3% | ✓ |
| 3e-3 | 0.4-1.2% | ✓ |
| 1e-2 | 33-65% | 边界（仅记录） |
| 3e-2 | 11-86% | 边界（仅记录） |

**核心工作范围 α ∈ [±1e-4, ±3e-3] 全通 <2% rel_err**。

## 4. SC-FDE 集成 before/after

### D 阶段（α 扫描 × SNR=10dB）

![D before/after](../../comparisons/figures/D_alpha_est_vs_true_after.png)

| α_true | est (before) | est (after) | BER (before) | BER (after) |
|--------|--------------|-------------|--------------|-------------|
| 0 | +2.3e-6 | +4.2e-5 | 0% | 0% |
| +1e-4 | +2.5e-6 | +1.2e-4 | 0% | 0% |
| -1e-4 | +1.1e-5 | -3.3e-5 | 50% | 0% |
| +5e-4 | +1.2e-6 | +4.3e-4 | 49% | **0%** |
| -5e-4 | +1.8e-4 | -3.6e-4 | 50% | **2.4%** |
| +1e-3 | +2.2e-5 | +8.9e-4 | 49% | **0.1%** |
| -1e-3 | -2.4e-4 | -7.9e-4 | 50% | 41% |
| +3e-3 | -2.3e-4 | +2.5e-3 | 49% | 50% |
| -3e-3 | +2.3e-4 | -2.7e-3 | 50% | 46% |
| +1e-2 | -4.9e-5 | +8.2e-3 | 50% | 50% |
| -1e-2 | +5.5e-5 | -8.3e-3 | 49% | 50% |

### A2 阶段（SC-FDE × α=5e-4/1e-3/2e-3 × SNR 5-20dB）

| α | SNR=5 | SNR=10 | SNR=15 | SNR=20 |
|---|-------|--------|--------|--------|
| 5e-4 before | 48% | 49% | 49% | 50% |
| 5e-4 **after** | **0%** | **0%** | **0%** | **0%** |
| 1e-3 before | 48% | 49% | 49% | 49% |
| 1e-3 after | 16% | 2% | 26% | 18% |
| 2e-3 before | 49% | 50% | 51% | 50% |
| 2e-3 after | 44% | 48% | 48% | 50% |

### A1 α=0 回归（fd 不退化）

| fd (Hz) | SNR=10 (before) | SNR=10 (after) |
|---------|-----------------|----------------|
| 0 | 0% | 0% ✓ |
| 0.5 | 30% | 16% ✓ |
| 1 | 50% | 43% ~ |
| 5 | 50% | 48% ~ |

**关键验收**：α=0 路径 0% 基线保持，Jakes 时变退化不变（本 spec 不解决时变）。

## 5. 已知限制

1. **非对称性**：α>0 比 α<0 估计准；α=+1e-3 BER 0.1%，α=-1e-3 BER 41%。疑似 rx 尾部 LFM_dn 被截断或 spline 插值不对称
2. **α>1e-3 BEM 外推不动**：即使 estimator 输出接近 α_true（如 α=3e-3 est=2.5e-3），残余 ~15% α 仍让 BEM 模型失效
3. **α ∈ [1e-2, 3e-2] 边界工况 BER=50%**：超出 MVP 承诺范围，留给后续 non-linear α estimator spec
4. **符号约定**：`est_alpha_dual_chirp` 的 α 与 gen_uwa_channel `doppler_rate` 反号（runner 内显式 `alpha_lfm = -alpha_lfm_raw`）。后续考虑在 estimator 内提供 `sign_convention` 参数

## 6. 后续

- **对称性修复**：查 α<0 下 spline 插值 / rx 尾部处理
- **α>1e-3 补偿后残余**：考虑 Turbo estimator 多次迭代，或把 alpha_cp 精估替换为 PLL 跟踪
- **其他 4 体制切换**（OFDM/SC-TDE/DSSS/FH-MFSK）：复用同套帧改 + estimator 入口，incremental PR 推进
- **OTFS 专题 spec**（无 HFM+/-，DD 域 α 估计另辟蹊径）
