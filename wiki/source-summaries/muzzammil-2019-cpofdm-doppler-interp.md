---
type: source-summary
source_type: paper
authors: Muhammad Muzzammil, Lei Wan, Hanbo Jia, Gang Qiao
year: 2019
journal: 2019 IEEE Int. Conf. on Information Communication and Signal Processing (ICICSP)
affiliation: 哈工程水声
status: 已读摘要
created: 2026-04-21
updated: 2026-04-21
tags: [论文, CP-OFDM, 多普勒, 自相关, 内插, 哈工程]
---

# Further Interpolation Methods for Doppler Scale Estimation in Underwater Acoustic CP-OFDM Systems

> Muzzammil et al. (2019). *ICICSP 2019*.
> Raw: `raw/papers/Further_Interpolation_Methods_for_Doppler_Scale_Estimation_in_Underwater_Acoustic_CP-OFDM_Systems.pdf`

---

## 核心贡献

推导 **CP-OFDM 接收信号自相关的闭式表达**，基于该闭式式提出 **3 种细 Doppler scale 内插方法**，在不增采样率的前提下提升估计精度。

## 研究问题

CP-OFDM 下，常规 α 估计用 CP 与 OFDM 主体的自相关峰位置差：
$$R(\tau) = \sum y(t) y^*(t + T/(1+\alpha))$$

峰位置分辨率 = 1/fs（采样点级别），若要更高精度需 oversample → 开销。

## 方法/算法

### 1. 闭式自相关推导

CP-OFDM 信号经多径（共享 α）→ downconvert → baseband：
$$y(t) = e^{-j2\pi\alpha f_c t/(1+\alpha)} \sum_k s[k] e^{j2\pi k t/((1+\alpha)T)} \sum_l \beta_l \cdot q(\cdot)$$

表现周期性 $y(t) = e^{j2\pi\alpha f_c T/(1+\alpha)} y(t - T/(1+\alpha))$，闭式自相关可解出 α。

### 2. 三种内插方法

论文未给出细节但按摘要描述：
- **Method 1**：粗峰邻域三点抛物线内插
- **Method 2**：基于闭式 R(τ) 的拟合（参数化模型拟合）
- **Method 3**：相位-幅度联合内插

### 3. 下采样因子分析

推导不同 downsampling rate 下 RMSE 表现，给出工程选型。

## 关键结果

- 单径信道：Method 2 和 3 的 RMSE 与 BER 优于 Method 1
- 多径信道：Method 1 反而更鲁棒
- 对应"平滑 vs 快速"tradeoff

## 与项目的关联

| 关联项 | 说明 |
|--------|------|
| `modules/10_DopplerProc/est_doppler_cp.m` | 当前项目的 CP-based α estimator；本文是其**理论支撑** |
| `modules/13_SourceCode/src/Matlab/tests/OFDM/test_ofdm_timevarying.m` | OFDM V4.3 的 CP 精估链路——可能从本文吸收内插改进 |
| `α 补偿 pipeline 诊断` 中 ±2.4e-4 相位模糊阈值 | CP 精估的分辨率限制根源即是"峰位置分辨率=1/fs"，本文方法可突破 |

## 工程启示

项目的双 LFM 时延差法 + CP 精修级联架构：
- LFM 粗估：本文方法不直接适用（非 CP 结构）
- **CP 精修段可引入本文 Method 2/3 的拟合/相位内插**，突破 ±2.4e-4 阈值

## 引用与关联

- **相关论文**：[[wei-2020-dual-hfm-speed-spectrum]]、[[sun-2020-dsss-passband-doppler-tracking]]（同为细内插思路）
- **相关模块**：`est_doppler_cp.m`
- **相关 spec**：`specs/active/2026-04-20-alpha-compensation-pipeline-debug.md`（CP 精修阈值分析处）
