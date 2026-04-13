# 水声通信算法系统 MOC

> 6种通信体制：SC-TDE / SC-FDE / OFDM / OTFS / DSSS / FH-MFSK + 阵列增强
> 代码仓库：`D:\TechReq\UWAcomm\`  |  框架图：`framework/framework_v6.html`

---

## 系统框架

- [[水声通信算法模块化框架v5]]
- [[项目仪表盘]]

---

## 发射链路

```
bits → 01编码 → 02信道编码 → 03交织 → 04调制 → 05扩频 → 06多载波 → 09成形+上变频 → 08帧组装 → DAC
```

| 序号 | 模块 | 功能 | 核心接口 | 笔记 |
|------|------|------|---------|------|
| 01 | 信源编解码 | Huffman + 均匀量化 | `huffman_encode/decode` | [[01_信源编解码]] |
| 02 | 信道编解码 | 卷积码 + SISO(BCJR) + Turbo/LDPC | `conv_encode`, `siso_decode_conv` | [[02_信道编解码]] |
| 03 | 交织/解交织 | 随机/块/卷积交织 | `random_interleave/deinterleave` | [[03_交织解交织]] |
| 04 | 符号映射 | QAM/PSK/MFSK 调制解调 | `qam_modulate/demodulate` | [[04_符号映射判决]] |
| 05 | 扩频/解扩 | DSSS/CSK/M-ary/FH | `dsss_spread/despread` | [[05_扩频解扩]] |
| 06 | 多载波变换 | OFDM/SC-FDE/OTFS + CP | `ofdm_modulate`, `scfde_add_cp` | [[06_多载波变换]] |
| 09 | 脉冲成形 | RRC成形 + 上下变频 + FSK | `pulse_shape`, `upconvert` | [[09_脉冲成形与变频]] |

---

## 同步与帧结构

```
TX: 08帧组装 [前导HFM+ | guard | data | guard | 后导HFM-]
RX: 08帧同步(L1) → 符号同步(L2) → 相位跟踪(L3) → 帧解析
```

| 层级 | 功能 | 核心接口 | 笔记 |
|------|------|---------|------|
| L1 帧同步 | LFM/HFM/ZC 检测 + 双HFM消偏 | `sync_detect`, `sync_dual_hfm` | [[08_同步与帧结构]] |
| L2 符号同步 | Gardner/MM TED | `timing_fine`, `cfo_estimate` | [[08_同步与帧结构]] |
| L3 相位跟踪 | PLL/DFPT/Kalman | `phase_track`, `pll_carrier_sync` | [[2026-04-09_双HFM消偏帧同步+PLL载波同步]] |
| 帧组装 | 4体制帧组装/解析 | `frame_assemble_*`, `frame_parse_*` | [[08_同步与帧结构]] |

---

## 接收链路

```
ADC → 09下变频+匹配 → 10多普勒补偿 → 08帧同步 → 07信道估计 → 12 Turbo均衡 → 03解交织 → 02译码 → bits
```

| 序号 | 模块 | 功能 | 核心接口 | 笔记 |
|------|------|------|---------|------|
| 10 | 多普勒处理 | 估计(CAF/xcorr) + 重采样补偿 | `doppler_coarse_compensate` | [[10_多普勒处理]] |
| 07 | 信道估计与均衡 | 静态(10种) + 时变(BEM/SAGE) + TDE/FDE均衡 | `ch_est_*`, `eq_*` | [[07_信道估计与均衡]] |
| 12 | Turbo迭代 | 4体制 SISO均衡+译码迭代调度 | `turbo_equalizer_*` | [[12_迭代调度器]] |
| 11 | 阵列预处理 | DAS/MVDR波束形成 | `bf_das`, `bf_mvdr` | [[11_阵列接收预处理]] |

---

## 信道估计与均衡专题 (模块07)

> 系统最大模块：35个对外函数

### 信道估计方法

| 类别 | 方法 | 推荐度 |
|------|------|--------|
| 静态 | LS, MMSE | 基线 |
| 静态(稀疏) | OMP, GAMP, VAMP, SBL, TurboVAMP | GAMP/VAMP ★★★ |
| 时变 | BEM(CE/DCT), DD-BEM, T-SBL, SAGE | BEM(DCT)+散布导频 ★★★ |
| 跟踪 | Kalman AR(1) | 低fd适用 |
| OTFS | DD域导频 | `ch_est_otfs_dd` |

### 均衡器

| 域 | 方法 | 适用体制 |
|----|------|---------|
| TDE | RLS, LMS, DFE, BiDFE | SC-TDE |
| FDE | MMSE-FDE, MMSE-IC, ZF, TV-FDE | SC-FDE, OFDM |
| DD域 | MP消息传递 | OTFS |

### 专题笔记
- [[水声信道估计与均衡器详解]]
- [[时变信道估计与均衡调试笔记]]

---

## 端到端仿真 (模块13)

- [[水声通信算法模块化框架v5]]
- [[端到端帧组装调试笔记]]

### 各体制调试日志
- [[SC-FDE调试日志]] — V4.0 两级分离架构, fd<=1Hz完成
- [[OFDM调试日志]] — V4.3 鲁棒架构固化
- [[SC-TDE调试日志]] — V5.1 LFM修复, 时变待优化

### 信号流

```
TX: 02编码 → 03交织 → QPSK → [散布导频] → 09 RRC成形 → 09上变频
    → 08帧组装 [HFM+ | guard | data | guard | HFM-]
CH: 等效基带 → 13 gen_uwa_channel(多径+Jakes) → 09上变频 → +噪声
RX: 09下变频 → 10重采样(α) → 残余CFO补偿
    → 08 sync_detect(首达径) → 提取数据 → 09匹配滤波
    → 07信道估计 → 12 Turbo均衡 → 03解交织 → 02 BCJR译码
```

---

## 模块依赖关系

```
01 → 02 → 03 → 04 → 05 → 06 → 09 → 08(帧组装)
                                         ↓
                              08(帧同步) → 10 → 07 → 12 → 03 → 02
                                                ↑
                                          11(阵列，可选)
                              13 集成以上所有模块
```

