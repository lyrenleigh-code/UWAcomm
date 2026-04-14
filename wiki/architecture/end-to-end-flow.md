---
tags: [架构, 端到端]
updated: 2026-04-14
---

# 端到端信号流 V5 — 三体制统一两级分离架构

适用体制：SC-TDE / SC-FDE / OFDM

## TX（三体制通用）

```
02 conv_encode → 03 random_interleave → QPSK映射
[SC-TDE时变] 插入散布导频(簇长140, 间隔300) → 混合帧[训练|导频+数据交替]
[SC-FDE/OFDM] 分块+CP
09 pulse_shape(RRC) → 功率归一化
帧组装: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]  基带复信号
```

## 信道仿真

```
等效基带帧 → 13 gen_uwa_channel(多径+Jakes+多普勒)
09 upconvert → +实噪声
```

## RX（两级分离架构）

```
09 downconvert → 复基带
阶段1: LFM匹配滤波→双LFM相位差→alpha_lfm(粗估)
       粗补偿→[SC-FDE/OFDM: CP精估 | SC-TDE: 训练精估]→alpha_est
阶段2: 精补偿→LFM2匹配定时→数据段提取
09 match_filter(RRC) → 训练序列相关对齐
[SC-TDE残余CFO] alpha_est*fc Hz频偏补偿(符号率)
[静态] 07 ch_est_gamp(Toeplitz) → 12 turbo_equalizer_sctde(DFE+BCJR)
[时变SC-TDE] 07 ch_est_bem('dct',训练+散布导频) → per-symbol MMSE ISI消除
              iter2+: BCJR软符号 → DD-BEM重估计 → 全ISI消除+MMSE → BCJR
[时变SC-FDE/OFDM] 07 ch_est_bem('dct',CP段) → LMMSE-IC + DD信道更新 + BCJR
03 random_deinterleave → 02 siso_decode_conv → bits_out
```

## OTFS 独立流程

参见 `wiki/architecture/otfs-flow.md`（待建）—— frame_assemble_otfs V2.0 + sync_dual_hfm
