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

### ⏳ P3: SC-TDE — 静态通过，时变方案确定

**P3-1: 模块07时变均衡验证** — 已确定方案
- 测试文件：`07_ChannelEstEq/src/Matlab/test_tv_eq.m`
- 关键发现：**必须加入RRC过采样**(sps=8)消除块内ICI
- 最终方案：散布导频(190sym) + BEM(CE) + 分块LMMSE-IC + 跨块Turbo BCJR

| 条件 | oracle | BEM(CE) | 端到端(oracle) |
|------|--------|---------|---------------|
| static 5dB+ | 0% | 0% | 0% |
| fd=1Hz 5dB+ | 0% | 0% | 0% |
| fd=5Hz 5dB | 49% | 49% | **0.54%** |
| fd=5Hz 10dB+ | 0% | 0% | 0% |

- 与端到端差距：fd=5Hz低SNR(5dB) BEM估计精度不足→49%（端到端用oracle仅0.54%）
- 改善方向：低SNR下BEM正则化增强 / 多次BEM估计平均

**P3-2: SC-TDE端到端时变集成** — 待做
- 方案：BEM(CE)信道估计 + RRC过采样 + 分块LMMSE-IC
- 静态已通过：Turbo_DFE(31,90) + GAMP, 0dB起无误码

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

### 信道估计（模块07）— 端到端必须使用

**重要原则：端到端仿真必须调用模块07的信道估计函数（ch_est_*），不得使用oracle真实信道（ch_info.h_time）。Oracle仅用于模块级性能基准对比。**

当前状态：
- SC-FDE/OFDM端到端：⚠️ 当前使用oracle H_est（ch_info.h_time），需改为ch_est_*估计
- SC-TDE端到端：✅ 静态已使用GAMP估计，时变调试中

信道估计方式：
- 训练序列→Toeplitz矩阵→稀疏估计（GAMP/Turbo-VAMP推荐）
- 估计结果用于：DFE权重初始化 + LMMSE-IC频域均衡 + Turbo ISI消除
- 静态：固定h_est，时变：需分块估计或Kalman跟踪

信道估计算法体系（模块07）：
```
① 静态/单快照估计（已完成11个）
   经典: ch_est_ls / ch_est_mmse
   稀疏: ch_est_omp / ch_est_sbl / ch_est_amp
   消息传递: ch_est_gamp / ch_est_vamp / ch_est_turbo_vamp / ch_est_ws_turbo_vamp

② 时变信道估计（待开发）
   ch_est_tsbl.m     — T-SBL时序稀疏贝叶斯（多快照联合，稀疏+时变）
   ch_est_sage.m     — SAGE/EM空时交替EM（高分辨率多径参数估计）
   ch_est_bem.m      — BEM基扩展独立函数（CE-BEM/P-BEM/DCT-BEM）

③ 信道跟踪（待开发）
   ch_track_kalman.m — 稀疏Kalman跟踪（AR(1)+逐符号更新）
   ch_track_rls.m    — RLS自适应跟踪（遗忘因子，独立于eq_dfe）
```

### Turbo均衡
- SC-FDE/OFDM: 跨块LMMSE-IC + DD信道更新 + BCJR (turbo_equalizer_scfde_crossblock)
- SC-TDE: DFE(31,90) iter1 + 软ISI消除 iter2+ (turbo_equalizer_sctde V8)
- 时变SC-TDE: 分块频域均衡(LMMSE-IC) + Kalman信道跟踪(待完善)

### 多普勒补偿
- comp_resample_spline V7: `pos=(1:N)/(1+alpha)`, 正alpha=补偿压缩
- est_doppler_xcorr: 前后LFM互相关, 无噪声信号上做

---

## 待办事宜

| 优先级 | 任务 | 状态 | 说明 |
|--------|------|------|------|
| **P3-2** | **SC-TDE端到端时变集成** | **待做** | BEM+RRC+分块LMMSE-IC集成到端到端 |
| **P1/P2** | **SC-FDE/OFDM端到端改用BEM估计** | **待改** | 当前用oracle,需改为ch_est_bem |
| 07 | 低SNR BEM精度提升 | 待优化 | fd=5Hz 5dB=49%(端到端oracle=0.54%)，正则化/多次平均 |
| 07 | ch_track_rls.m | 待开发 | RLS遗忘因子信道跟踪，独立于eq_dfe |
| P4 | OTFS端到端 | 待P3 | DD域处理+通带 |
| P5 | DSSS端到端 | 待P4 | 扩频+Rake |
| P6 | FH-MFSK端到端 | 待P5 | 跳频+能量检测 |

## 已知问题

| 问题 | 状态 | 说明 |
|------|------|------|
| SC-TDE时变Kalman跟踪 | **P3-1调试中** | LE软判决质量~30%BER→Kalman偏移 |
| DFE错误传播 | 已分析 | 90sym频选+时变→DFE发散, 已改用LE iter1 |
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
