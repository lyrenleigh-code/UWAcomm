---
tags: [架构, 算法]
updated: 2026-04-14
---

# 关键技术方案

## 通带帧组装

- 帧信号为**通带实数**（DAC可输出）
- LFM: `gen_lfm` 通带实信号, 功率归一化匹配数据段RMS
- 信道在**等效基带**施加（复增益×复信号=正确）
- 通带闭环: 基带→upconvert→实噪声→downconvert

## 同步检测（P3-2更新）

- 无噪声信号上做一次(per fading config)
- **首达径检测**：取第一个超过最强峰60%的位置（防多径回波锁定，P3-2关键修复）
- 训练序列相关对齐：用完整训练序列做符号级对齐搜索

## 信道估计

- **静态**：训练序列构建Toeplitz → `ch_est_gamp` 或 `ch_est_omp` 等
- **时变(P3-2)**：`ch_est_bem('dct')` 散布导频BEM时变估计，输出h_tv(P×N_tx)每径每时刻增益
  - 导频参数：簇长=max_delay+50, 间隔300, 有效观测~610个
  - 自动Q选择：Q = max(5, 2*ceil(fd*T_frame)+3)
  - iter2+ DD-BEM重估计：BCJR软符号扩展观测集(置信度>0.5门控)

## 多普勒补偿（P3-2更新）

- `comp_resample_spline` V7: 正alpha直接传入（内部pos=(1:N)/(1+α)）
- **残余CFO补偿**：重采样后基带仍残留alpha*fc Hz频偏，须在符号率上去除
- 信道seed不依赖SNR索引（同一信道，只变噪声）

## Turbo均衡（SC-TDE，P3-2 V4.2）

- **静态**：GAMP估计 → turbo_equalizer_sctde(DFE+BCJR) → 0%BER
- **时变**：BEM(DCT) per-symbol MMSE ISI消除 + Turbo BCJR
  - iter 1: 已知位置ISI精确消除 + 未知位置ISI功率建模为噪声 → MMSE单抽头
  - iter 2+: BCJR软符号 → DD-BEM重估计 → 全ISI消除 + MMSE
  - nv_post: 从训练段实测（防高SNR时LLR过度自信）
- **SC-FDE/OFDM跨块Turbo**: LMMSE-IC + DD信道更新 + BCJR

## OTFS均衡（P4 V2.0）

- **LMMSE-BCCB**：2D-FFT对角化，per-frequency MMSE权重，Turbo 3轮
- **UAMP**：Onsager修正+EM噪声估计（研究用，对BCCB无优势）
- **关键发现**：Jakes连续Doppler谱导致BCCB模型失效(50% BER)，离散Doppler(含分数频移)下完美工作
- 实际水声信道(Rician混合K=5~20)与离散模型更匹配，0%@10dB+
