# UWAcomm 水声通信算法开发进度

> 框架参考：`framework/framework_v6.html`
> Turbo均衡方案：`12_IterativeProc/turbo_equalizer_implementation.md`
> 调试记录：`D:\Obsidian\workspace\UWAcomm\信道估计与均衡\时变信道估计与均衡调试笔记.md`
> 6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 开发量统计

| 指标 | 数值 |
|------|------|
| MATLAB函数文件 | 172个 |
| 代码总行数 | 20,118行 |
| 文档文件(md+html) | 28个 |
| Git提交数 | 141次 |
| 模块数 | 13个（12个算法模块 + 1个集成模块） |

---

## 各模块状态

| 模块 | 文件夹 | 文件数 | 状态 |
|------|--------|--------|------|
| 01 信源编解码 | `01_SourceCoding/` | 5 | ✅ Huffman+均匀量化, 14项测试全通过 |
| 02 信道编解码 | `02_ChannelCoding/` | 12 | ✅ 含SISO(BCJR max-log/log-map/sova) |
| 03 交织/解交织 | `03_Interleaving/` | 8 | ✅ |
| 04 符号映射/判决 | `04_Modulation/` | 6 | ✅ |
| 05 扩频/解扩 | `05_SpreadSpectrum/` | 17 | ✅ |
| 06 多载波+CP | `06_MultiCarrier/` | 15 | ✅ |
| 07 信道估计与均衡 | `07_ChannelEstEq/` | 42 | ✅ 统一测试V2(24项), BEM V2+DD-BEM |
| 08 同步+帧组装 | `08_Sync/` | 18 | ✅ 三层同步(帧/符号/位), phase_track V1.0, sync_detect V2.0(多普勒补偿), 22项测试 |
| 09 脉冲成形/变频 | `09_Waveform/` | 9 | ✅ |
| 10 多普勒处理 | `10_DopplerProc/` | 14 | ✅ comp_resample V7(正alpha) |
| 11 阵列预处理 | `11_ArrayProc/` | 8 | ✅ |
| 12 Turbo迭代调度 | `12_IterativeProc/` | 7 | ✅ V8(DFE iter1)+跨块版本 |
| 13 端到端仿真 | `13_SourceCode/` | 12 | P1+P2完成, P3调试中 |

---

## 模块07 信道估计与均衡 — 统一测试结果 (test_channel_est_eq.m V2)

### 1. 静态信道估计 NMSE（7种方法）

| 方法 | NMSE | 推荐度 |
|------|------|--------|
| LS / MMSE | -12.6dB | 基线 |
| OMP / GAMP | -34.2dB | ★★★ |
| VAMP / TurboVAMP | -34.3dB | ★★★ |
| SBL | -28.1dB | ★★ |

### 2. 时变信道估计（综合测试）

**2A: BEM NMSE vs fd（仅训练导频, SNR=15dB）**

| fd(Hz) | CE-BEM | DCT-BEM |
|--------|--------|---------|
| 0.5 | 4.7dB | 1.3dB |
| 1.0 | 7.0dB | 6.2dB |
| 5.0 | 2.8dB | 0.6dB |

**2C: DD-BEM迭代精化（3次DD迭代）**

| fd(Hz) | BEM(CE) | DD-BEM | 增益 |
|--------|---------|--------|------|
| 0.5 | 4.7dB | 0.0dB | +4.7dB |
| 1.0 | 7.0dB | -1.5dB | +8.5dB |
| 5.0 | 2.8dB | 0.1dB | +2.7dB |

**2F: 训练导频 vs 散布导频（fd=5Hz, SNR=15dB）**

| 方法 | 仅训练 | 散布导频 | 增益 |
|------|--------|---------|------|
| BEM(CE) | 2.2dB | -9.6dB | **+11.8dB** |
| BEM(DCT) | 2.3dB | **-19.4dB** | **+21.7dB** |
| DD-BEM | 0.2dB | -13.9dB | +14.1dB |
| Kalman | 2.1dB | 2.1dB | +0.0dB |

**结论：散布导频是精度决定性因素（比算法选择影响大10-20dB），BEM(DCT)+散布导频最优**

### 3. 均衡器 SNR vs SER

**3A: 时域均衡器（3径静态信道, GAMP估计）**

| SNR | eq_rls | eq_lms | eq_dfe | BiDFE |
|-----|--------|--------|--------|-------|
| 10dB | 12.3% | 6.5% | 9.3% | 7.2% |
| 15dB | 3.9% | 1.2% | 0% | 0.2% |
| 20dB | 1.3% | 0.2% | 0% | 0% |

**3B: 频域均衡器（6径静态信道, GAMP估计）**

| SNR | ZF | MMSE-FDE | MMSE-IC(1) | MMSE-IC(3) |
|-----|-----|----------|------------|------------|
| 10dB | 16.8% | 1.6% | 1.6% | 1.2% |
| 15dB | 0.8% | 0% | 0% | 0% |
| 20dB | 0% | 0% | 0% | 0% |

**3C: Turbo TDE vs FDE（同一6径信道, 公平对比）**

| SNR | TDE iter1 | TDE iter6 | FDE iter1 | FDE iter6 |
|-----|-----------|-----------|-----------|-----------|
| 0dB | 46.7% | 34.6% | **21.1%** | **20.8%** |
| 5dB | 48.6% | 0.6% | **0%** | **0%** |
| 10dB | 46.8% | 0% | **0%** | **0%** |

**结论：FDE在长时延信道下全面优于TDE，FDE有5dB编码增益优势**

### 4. 时变均衡（RRC+gen_uwa_channel+散布导频BEM）

**fd=5Hz（多BEM方法对比）**

| SNR | oracle | BEM(CE) | BEM(DCT) | DD-BEM |
|-----|--------|---------|----------|--------|
| 0dB | 0.16% | 0.47% | 0.36% | 0.78% |
| 5dB | 0.05% | 0% | 0.10% | 0.21% |
| 10dB+ | 0% | 0% | 0% | 0% |

**fd=10Hz（高多普勒，区分方法差异）**

| SNR | oracle | BEM(CE) | BEM(DCT) | DD-BEM |
|-----|--------|---------|----------|--------|
| 5dB | 0.3% | 4.4% | **1.2%** | 9.0% |
| 10dB | 0.7% | 9.2% | **3.1%** | 9.8% |
| 20dB | 1.5% | 12.6% | **4.7%** | 11.5% |

**结论：BEM(DCT)+散布导频在高fd下最优，DD-BEM在高fd下退化**

---

## 均衡器调试发现

| 问题 | 根因 | 修复 |
|------|------|------|
| eq_lms DD模式不收敛 | `sign(real(x))` BPSK判决 | 改为QPSK最近星座点 |
| DFE+PLL静态信道发散 | PLL在无多普勒时引入不稳定 | 静态信道关PLL |
| DFE训练越长越差 | λ=0.998遗忘太快 | λ→0.9995 |
| DFE h_est初始化反效果 | 初始权重过大致RLS过冲 | 不传h_est，纯RLS训练 |
| BiDFE单侧训练失败 | 后向DFE无训练序列 | 前向判决作后向伪训练 |
| RLS抽头数不足 | 31抽头 vs 91抽头信道 | 甜点=4×信道长度 |

---

## 端到端验证结果

### SC-FDE (P1) + OFDM (P2) — 通带帧组装 ✅

| 体制 | static | fd=1Hz 5dB | fd=5Hz 5dB | fd=5Hz 20dB |
|------|--------|-----------|-----------|------------|
| SC-FDE V2.1 | 0% | 0% | 0.54% | 0% |
| OFDM V2.0 | 0% | 0% | 0.54% | 0% |

### SC-TDE (P3) — 静态通过，时变方案确定

推荐：Turbo_DFE + GAMP信道估计，0dB起无误码

---

## 逐体制开发计划

### ✅ P1: SC-FDE — 完成
### ✅ P2: OFDM — 完成
### ⏳ P3: SC-TDE — 静态通过，时变方案确定

**P3-1: 模块07时变均衡验证** — ✅ 已完成
- BEM(CE/DCT)+散布导频+RRC+分块LMMSE-IC → fd≤5Hz 5dB+ 0%BER
- DD-BEM新增，低fd下额外2-8dB NMSE增益

**P3-2: SC-TDE端到端时变集成** — 待做
- 方案：BEM(DCT)信道估计 + RRC过采样 + 分块LMMSE-IC
- 注意：长时延信道下DFE不适用，推荐FDE方式

### ⬜ P4: OTFS — 待P3
### ⬜ P5: DSSS — 待P4
### ⬜ P6: FH-MFSK — 待P5

---

## 算法版本固化

| 函数 | 版本 | 状态 | 说明 |
|------|------|------|------|
| ch_est_bem | V2.0.0 | ✅ | 向量化重构+可选BIC+自适应正则化 |
| ch_est_bem_dd | V1.0.0 | ✅ | DD-BEM判决辅助迭代精化 |
| ch_est_tsbl | V2.0.0 | ✅ | T-SBL多快照联合稀疏 |
| ch_est_sage | V1.0.0 | ✅ | SAGE时延完美匹配 |
| ch_track_kalman | V1.0.0 | ✅ | 稀疏Kalman AR(1) |
| eq_dfe | V3.1.0 | ✅ | h_est初始化（测试中建议不传） |
| eq_lms | V1.1.0 | ✅ | 修复DD QPSK判决 |
| eq_mmse_ic_fde | V2.0.0 | ✅ | Turbo核心 |
| turbo_equalizer_sctde | V8.0.0 | ✅ | DFE iter1 |
| turbo_equalizer_scfde_crossblock | V1.0.0 | ✅ | 跨块Turbo |
| test_channel_est_eq | V2.0.0 | ✅ | 24项测试+6张可视化 |
| sync_detect | V2.0.0 | ✅ | 新增doppler方法(二维时延-多普勒补偿搜索) |
| phase_track | V1.0.0 | ✅ | 位同步: PLL/DFPT/Kalman三种相位跟踪 |
| test_sync | V2.0.0 | ✅ | 22项测试, 可视化与测试分离 |

---

## 待办事宜

| 优先级 | 任务 | 状态 | 说明 |
|--------|------|------|------|
| **P3-2** | **SC-TDE端到端时变集成** | **待做** | BEM(DCT)+RRC+LMMSE-IC |
| **P1/P2** | **SC-FDE/OFDM端到端改用BEM估计** | **待改** | 当前用oracle,需改为ch_est_bem |
| 07 | 测试运行速度优化 | 待优化 | 4fd×7SNR×4方法=112次Turbo，需减少或并行化 |
| 07 | fd=10Hz BER非单调问题 | 待分析 | oracle也非零→接近系统ICI极限 |
| P4 | OTFS端到端 | 待P3 | DD域处理+通带 |
| P5 | DSSS端到端 | 待P4 | 扩频+Rake |
| P6 | FH-MFSK端到端 | 待P5 | 跳频+能量检测 |
