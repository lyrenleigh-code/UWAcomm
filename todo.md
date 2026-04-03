# UWAcomm 水声通信算法开发进度

> 框架参考：`framework/framework_v5.html`（待升级v6）
> Turbo均衡方案：`12_IterativeProc/turbo_equalizer_implementation.md`
> 调试记录：`D:\Obsidian\workspace\UWAcomm\端到端帧组装调试笔记.md`
> 6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 开发量统计

| 指标 | 数值 |
|------|------|
| MATLAB函数文件 | 165个 |
| 代码总行数 | 18,223行 |
| 文档文件(md+html) | 25个 |
| Git提交数 | 120次 |
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
| 07 信道估计与均衡 | `07_ChannelEstEq/` | 35 | 3,092 | ✅ 含GAMP/VAMP/Kalman跟踪+DFE h_est初始化 |
| 08 同步+帧组装 | `08_Sync/` | 17 | 1,199 | ✅ |
| 09 脉冲成形/变频 | `09_Waveform/` | 9 | 1,099 | ✅ |
| 10 多普勒处理 | `10_DopplerProc/` | 14 | 1,200 | ✅ comp_resample V7(正alpha) |
| 11 阵列预处理 | `11_ArrayProc/` | 8 | 607 | ✅ |
| 12 Turbo迭代调度 | `12_IterativeProc/` | 7 | 979 | ✅ V8(DFE iter1)+跨块版本 |
| 13 端到端仿真 | `13_SourceCode/` | 12 | 2,864 | P1+P2完成, P3调试中 |

---

## 端到端验证结果

### SC-FDE (P1) + OFDM (P2) — 通带帧组装 ✅

三体制统一帧结构：`[LFM_pb|guard|data_pb|guard|LFM_pb]` 全实数

| 体制 | static | fd=1Hz 5dB | fd=1Hz 20dB | fd=5Hz 5dB | fd=5Hz 20dB |
|------|--------|-----------|------------|-----------|------------|
| SC-FDE V2.1 | 0% | 0% | 0% | 0.54% | 0% |
| OFDM V2.0 | 0% | 0% | 0% | 0.54% | 0% |

均衡方式：跨块Turbo(LMMSE-IC + DD信道更新 + BCJR) 6次迭代

### SC-TDE (P3) — 静态信道 ✅

信道估计方法对比（Turbo_DFE(31,90) × 6次迭代，SNR=0dB起无误码）:

| 方法 | 0%BER起点 | -3dB BER | 与oracle差距 |
|------|----------|---------|-------------|
| oracle | 0dB | 12.91% | 基准 |
| MMSE | 3dB | 38.99% | 差~3dB |
| OMP | 0dB | 13.76% | ~1dB |
| SBL | 0dB | 15.07% | ~1dB |
| **GAMP** | **0dB** | **12.96%** | **≈oracle** |
| VAMP | 0dB | 13.26% | ~0.5dB |
| Turbo-VAMP | 0dB | 10.41% | 优于oracle |

推荐：Turbo_DFE + GAMP信道估计

### SC-TDE (P3) — 时变信道（调试中）

基带独立测试（模块07, test_tv_eq.m）:

| 方法 | fd=1Hz 20dB | fd=5Hz 20dB | 说明 |
|------|------------|------------|------|
| Turbo+orc(固定h) | 40.24% | 49.00% | ISI消除用冻结快照→失败 |
| DFE+TV-orc(每符号h) | 42.99% | 4.50% | DFE错误传播限制fd=1Hz |
| **LE+TV-orc** | **34.98%** | **0.00%** | LE无错误传播+完美跟踪=最优 |
| LE+Kalman | 42.14% | 49.90% | Kalman跟踪精度不足 |

结论：LE iter1(避免错误传播) + 时变ISI消除(需精确信道跟踪)是正确方向。Kalman受限于LE软判决质量。

---

## 逐体制开发计划

### ✅ P1: SC-FDE — 完成
- 通带实数帧组装(LFM+guard)
- 无噪声同步+直达径窗口+有效时延偏移
- 跨块Turbo(LMMSE-IC+DD+BCJR) 6次
- 信道seed固定(per fading), SNR只变噪声
- comp_resample V7(正alpha)

### ✅ P2: OFDM — 完成
- 与SC-FDE统一帧架构和信号流
- 结果与SC-FDE一致（处理链路相同）

### ⏳ P3: SC-TDE — 静态通过，时变调试中
- 静态：Turbo_DFE(31,90) + GAMP信道估计, 0dB起无误码
- 时变：LE iter1无错误传播+TV-orc ISI消除可行(fd=5Hz=0%)
- 待解决：Kalman跟踪精度提升 / LE iter1质量提升

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

### 通带帧组装（V3统一架构）
```
TX: QPSK → 09 RRC成形 → 09上变频(通带实数)
    08 gen_lfm(通带实LFM) → 功率归一化
    帧: [LFM_pb | guard(800) | data_pb | guard(800) | LFM_pb]
CH: 等效基带帧 → 13 gen_uwa_channel → 09上变频 → +实噪声
RX: 09下变频 → 08 sync_detect(无噪声,直达径窗口50样本)
    10 comp_resample_spline(alpha) → 07 ch_est_*(训练序列)
    07 eq_*/12 turbo_equalizer_* → 03解交织 → 02 BCJR → bits
```

### 信道估计（模块07）
- 训练序列→Toeplitz矩阵→稀疏估计(GAMP/VAMP推荐)
- 估计结果用于：DFE权重初始化 + Turbo ISI消除
- 静态：固定h_est, 时变：需Kalman或DD跟踪

### Turbo均衡
- SC-FDE/OFDM: 跨块LMMSE-IC + DD信道更新 + BCJR (turbo_equalizer_scfde_crossblock)
- SC-TDE: DFE(31,90) iter1 + 软ISI消除 iter2+ (turbo_equalizer_sctde V8)
- 时变SC-TDE: LE iter1(无错误传播) + Kalman/TV ISI消除(待完善)

### 多普勒补偿
- comp_resample_spline V7: `pos=(1:N)/(1+alpha)`, 正alpha=补偿压缩
- est_doppler_xcorr: 前后LFM互相关, 无噪声信号上做

---

## 已知问题

| 问题 | 状态 | 说明 |
|------|------|------|
| SC-TDE时变Kalman跟踪 | **调试中** | LE软判决质量不足→Kalman偏移, 需更鲁棒方案 |
| DFE错误传播 | 已分析 | 长时延(90sym)频选+时变→DFE数据段发散, 改用LE iter1 |
| 多普勒估计精度 | 搁置 | 多径下xcorr虚假峰, 独立课题 |
| OTFS通带实现 | 搁置 | DD域二维脉冲成形, 需专项 |
| framework v5→v6升级 | 待完成 | P1-P6完成后统一更新 |

---

## 框架图演进

| 版本 | 文件 | 主要变更 |
|------|------|----------|
| v1-v4 | framework_v1~v4.html | 模块递增+PTR+Turbo参考 |
| v5 | framework_v5.html | Turbo外信息迭代,交织纳入迭代环 |
| **v6（待）** | — | 通带实数帧,跨块编码,GAMP信道估计,Kalman跟踪 |
