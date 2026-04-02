# UWAcomm 水声通信算法开发进度

> 框架参考：`framework/framework_v5.html`（待升级v6）
> Turbo均衡方案：`12_IterativeProc/turbo_equalizer_implementation.md`
> 6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 开发量统计

| 指标 | 数值 |
|------|------|
| MATLAB函数文件 | 162个 |
| 代码总行数 | 17,359行 |
| 文档文件(md+html) | 23个 |
| Git提交数 | 118次 |
| 模块数 | 13个（12个算法模块 + 1个集成模块） |

---

## 各模块状态

| 模块 | 文件夹 | 文件数 | 代码行 | 状态 |
|------|--------|--------|--------|------|
| 01 信源编解码 | `01_SourceCoding/` | 5 | 722 | ✅ |
| 02 信道编解码 | `02_ChannelCoding/` | 12 | 2,153 | ✅ 含SISO(BCJR max-log/log-map/sova) |
| 03 交织/解交织 | `03_Interleaving/` | 8 | 715 | ✅ |
| 04 符号映射/判决 | `04_Modulation/` | 6 | 774 | ✅ |
| 05 扩频/解扩 | `05_SpreadSpectrum/` | 17 | 1,196 | ✅ |
| 06 多载波+CP | `06_MultiCarrier/` | 15 | 1,623 | ✅ |
| 07 信道估计与均衡 | `07_ChannelEstEq/` | 34 | 2,759 | ✅ 最大模块 |
| 08 同步+帧组装 | `08_Sync/` | 17 | 1,199 | ✅ |
| 09 脉冲成形/变频 | `09_Waveform/` | 9 | 1,099 | ✅ |
| 10 多普勒处理 | `10_DopplerProc/` | 14 | 1,197 | ✅ |
| 11 阵列预处理 | `11_ArrayProc/` | 8 | 607 | ✅ |
| 12 Turbo迭代调度 | `12_IterativeProc/` | 6 | 869 | ✅ |
| 13 端到端仿真 | `13_SourceCode/` | 10 | ~2,400 | P1+P2完成，P3-P6进行中 |

---

## 模块13 端到端集成

### 目录结构

```
13_SourceCode/src/Matlab/
├── common/                    公共函数（6个）
│   ├── gen_uwa_channel.m      水声信道（多径+Jakes+多普勒+AWGN）
│   ├── sys_params.m           6体制参数配置
│   ├── tx_chain.m             通用发射链路
│   ├── rx_chain.m             通用接收链路
│   ├── main_sim_single.m      单SNR点6体制仿真
│   └── adaptive_block_len.m   自适应块长选择
├── tests/
│   ├── SC-FDE/                ✅ P1
│   │   ├── test_scfde_static.m        静态SNR vs BER（通带）
│   │   └── test_scfde_timevarying.m   时变fd=[0,1,5]Hz × SNR
│   ├── OFDM/                  ✅ P2
│   │   ├── test_ofdm_e2e.m           静态SNR vs BER（通带）
│   │   └── test_ofdm_timevarying.m   时变fd=[0,1,5]Hz × SNR
│   ├── SC-TDE/                ⬜ P3
│   ├── OTFS/                  ⬜ P4
│   ├── DSSS/                  ⬜ P5
│   └── FH-MFSK/              ⬜ P6
└── README.md
```

### 通带仿真信号流

```
TX: info → 02编码 → 03交织 → 04 QPSK → 加CP → 09 RRC成形 → 09上变频 → 通带实信号(DAC)
信道: RRC成形基带(复数) → gen_uwa_channel(多径+Jakes+多普勒)
通带: 信道后基带 → 09上变频 → +实噪声 → 09下变频 → 复基带
RX: 09 RRC匹配 → 下采样 → 去CP+FFT → 07 MMSE均衡 → LLR → 03解交织 → 02 BCJR译码
```

### 仿真信道

```
6径水声信道（最大时延~15ms）:
  时延(ms): [0, 0.83, 2.5, 6.7, 10.0, 15.0]
  增益:     [1, 0.6, 0.45, 0.3, 0.2, 0.12] (归一化)
  CP = 128符号 > 90符号最大时延
```

### 已验证性能

**SC-FDE / OFDM 静态信道（通带仿真）：**

| SNR | 0dB | 3dB | 5dB+ |
|-----|-----|-----|------|
| BER | 0.56% | 0% | 0% |

**OFDM 时变信道（通带仿真, SNR=[5,10,15,20]dB）：**

| 衰落 | 5dB | 10dB | 15dB | 20dB | 块长 |
|------|-----|------|------|------|------|
| static | 0% | 0% | 0% | 0% | 1024 |
| fd=1Hz | 0.07% | 0% | 0% | 0% | 256 |
| fd=5Hz | 8.50% | 3.86% | 4.05% | 1.69% | 128 |

---

## 逐体制开发计划

### ✅ P1: SC-FDE — 完成
- 通带仿真（基带信道→上变频→实噪声→下变频）
- 跨块编码 + 自适应块长 + oracle H_est
- 已知α补偿 + 对角MMSE
- 静态+时变测试脚本

### ✅ P2: OFDM — 完成
- 与SC-FDE相同通带链路
- 6径15ms信道
- 静态SNR曲线 + 时变BER矩阵
- 可视化（波形/频谱/CIR/频响/星座/BER曲线）

### ⬜ P3: SC-TDE
- RLS+PLL时域自适应均衡
- 训练序列帧结构
- 时变：RLS跟踪+单抽头ZF IC

### ⬜ P4: OTFS
- DD域处理（信道circshift模型）
- 通带实现待专项（二维脉冲成形）
- MP均衡 + BCJR

### ⬜ P5: DSSS
- 扩频+Rake接收
- 多普勒补偿

### ⬜ P6: FH-MFSK
- 跳频+能量检测
- 多普勒补偿

---

## 关键技术方案

### Turbo均衡（模块12，已完成）
- LMMSE-IC: x̃ = x̄ + IFFT(G·(Y-HX̄))
- SISO(BCJR): max-log / log-map / sova 三模式
- 外信息交换: Le = Lpost - La
- 4体制收敛: SC-FDE/OFDM/SC-TDE/OTFS

### 时变信道处理
- 10-1粗多普勒: 已知α重采样（估计精度作为独立课题）
- 自适应块长: static=1024, fd=1Hz→256, fd=5Hz→128
- 跨块编码: 编码和均衡解耦（长码字高增益+短块低ICI）
- Oracle H_est: 块中点时变信道
- BEM-Turbo ICI均衡: eq_bem_turbo_fde（可选，计算量大）

### 通带仿真
- 信道施加在基带复数信号（复数增益×复数信号=正确）
- 通带闭环: 基带→upconvert→实噪声→downconvert
- 模块09: upconvert/downconvert（载波搬移）+ pulse_shape/match_filter（RRC带限）
- 物理一致: alpha = fd/fc, fading_type='slow'（无5倍放大）

---

## 已知问题

| 问题 | 状态 | 说明 |
|------|------|------|
| gen_uwa_channel复数增益×实信号 | 已绕过 | 信道在基带施加，通带仅做上/下变频+加噪 |
| OTFS通带实现 | 搁置 | DD域二维脉冲成形，需专项攻关 |
| 多普勒估计精度 | 搁置 | 多径下前后导频xcorr虚假峰问题，作为独立课题 |
| fd=5Hz BER地板~2-4% | 保留 | Jakes衰落块内ICI，非多普勒补偿可解 |
| doppler_coarse_compensate接口 | 保留 | 矩阵维度错误，当前用已知α替代 |
| gen_uwa_channel fading_type='fast' | 已修正 | fast模式fd×5倍放大，统一用'slow'避免 |
| framework v5→v6升级 | 待完成 | P1-P6全部完成后统一更新 |

---

## 框架图演进

| 版本 | 文件 | 主要变更 |
|------|------|----------|
| v1-v4 | framework_v1~v4.html | 模块递增+PTR+Turbo参考 |
| v5 | framework_v5.html | Turbo外信息迭代,交织纳入迭代环 |
| **v6（待）** | — | 通带仿真链路,跨块编码,BEM-ICI,模块13结构 |
