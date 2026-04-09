# UWAcomm 水声通信算法开发进度

> 框架参考：`framework/framework_v6.html`
> Turbo均衡方案：`12_IterativeProc/turbo_equalizer_implementation.md`
> 调试记录：`D:\Obsidian\workspace\UWAcomm\{模块名}\`
> 6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 开发量统计

| 指标 | 数值 |
|------|------|
| MATLAB函数文件 | 173个 |
| 代码总行数 | 20,865行 |
| 文档文件(md+html) | 27个 |
| Git提交数 | 170次 |
| README文档总行数 | ~4500行（含算法推导+断言表+LaTeX公式） |
| 模块数 | 13个（12个算法模块 + 1个集成模块） |

---

## 各模块状态

| 模块 | 文件夹 | 文件数 | 状态 |
|------|--------|--------|------|
| 01 信源编解码 | `01_SourceCoding/` | 5 | ✅ Huffman+均匀量化, 14项测试全通过 |
| 02 信道编解码 | `02_ChannelCoding/` | 12 | ✅ 含SISO(BCJR max-log/log-map/sova) |
| 03 交织/解交织 | `03_Interleaving/` | 8 | ✅ |
| 04 符号映射/判决 | `04_Modulation/` | 6 | ✅ |
| 05 扩频/解扩 | `05_SpreadSpectrum/` | 17 | ✅ 18项测试+可视化(V1.1) |
| 06 多载波+CP | `06_MultiCarrier/` | 15 | ✅ |
| 07 信道估计与均衡 | `07_ChannelEstEq/` | 42 | ✅ 统一测试V2(24项), BEM V2+DD-BEM |
| 08 同步+帧组装 | `08_Sync/` | 18 | ✅ 三层同步(帧/符号/位), sync_dual_hfm V1.1 |
| 09 脉冲成形/变频 | `09_Waveform/` | 9 | ✅ 19项测试+可视化(V1.1) |
| 10 多普勒处理 | `10_DopplerProc/` | 15 | ✅ comp_resample V7, 13项测试(V2.0) |
| 11 阵列预处理 | `11_ArrayProc/` | 8 | ✅ |
| 12 Turbo迭代调度 | `12_IterativeProc/` | 7 | ✅ V8(DFE iter1)+跨块版本 |
| 13 端到端仿真 | `13_SourceCode/` | 12 | 🔶 SC-FDE V4.0改造完成，OFDM/SC-TDE待改造 |

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

**注意：模块07测试中 `doppler_rate=0`（未含真实多普勒频偏），仅测试了Jakes衰落下的信道估计+均衡能力**

**fd=5Hz（多BEM方法对比）**

| SNR | oracle | BEM(CE) | BEM(DCT) | DD-BEM |
|-----|--------|---------|----------|--------|
| 0dB | 0.16% | 0.47% | 0.36% | 0.78% |
| 5dB | 0.05% | 0% | 0.10% | 0.21% |
| 10dB+ | 0% | 0% | 0% | 0% |

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

### SC-FDE V4.0 — 两级分离架构 ✅（2026-04-09）

帧结构：`[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]`
RX：①LFM相位+CP估α ②resample补偿 ③LFM2精确定时 ④BEM+Turbo(6轮)

| 验证 | static | fd=1Hz | fd=5Hz |
|------|--------|--------|--------|
| Oracle α | 0% | 0% | 0.24%@5dB |
| **盲估计** | **0%** | **0.20%@5dB, 0%@10+** | 50%（待攻关） |

### OFDM V2.0 — 待改造 🔶

| 体制 | static | fd=1Hz | fd=5Hz | 多普勒 | 同步 |
|------|--------|--------|--------|--------|------|
| OFDM(当前) | 0% | 0% | <2% | **oracle dop_rate** | **无噪声信号** |

### SC-TDE V4.2 — 待改造 🔶

| 体制 | static | fd=1Hz | fd=5Hz 5dB | 多普勒 | 同步 |
|------|--------|--------|-----------|--------|------|
| SC-TDE(当前) | 0% | 0% | 15% | **oracle dop_rate** | **无噪声信号** |

---

## 逐体制开发计划

### ✅ P1→V4.0: SC-FDE — 帧结构改造完成
- 两级分离架构，fd<=1Hz盲估计可工作
- fd=5Hz: α·fc=5Hz落在Jakes[-5,+5]Hz内，10种方案失败，需联合迭代

### 🔶 P2: OFDM — 待V4.0改造
- 当前: oracle dop_rate + 无噪声sync
- 目标: 套用SC-FDE V4.0模式（处理链路几乎一致）

### 🔶 P3: SC-TDE — 待V4.0改造
- 当前: oracle dop_rate + 无噪声sync + CAF fallback
- 注意: 时域均衡（DFE），帧结构改造需单独处理

### ⬜ P4: OTFS — 待开始
### ⬜ P5: DSSS — 待P4
### ⬜ P6: FH-MFSK — 待P5

---

## 算法版本固化

| 函数 | 版本 | 状态 | 说明 |
|------|------|------|------|
| ch_est_bem | V2.0.0 | ✅ | 向量化重构+可选BIC+自适应正则化 |
| ch_est_bem_dd | V1.0.0 | ✅ | DD-BEM判决辅助迭代精化 |
| ch_est_tsbl | V2.0.0 | ✅ | T-SBL多快照联合稀疏 |
| ch_est_sage | V1.0.0 | ✅ | SAGE联合时延+增益+多普勒 |
| ch_track_kalman | V1.0.0 | ✅ | 稀疏Kalman AR(1) |
| eq_dfe | V3.1.0 | ✅ | h_est初始化（测试中建议不传） |
| eq_lms | V1.1.0 | ✅ | 修复DD QPSK判决 |
| eq_mmse_ic_fde | V2.0.0 | ✅ | Turbo核心 |
| turbo_equalizer_sctde | V8.0.0 | ✅ | DFE iter1 |
| turbo_equalizer_scfde_crossblock | V1.0.0 | ✅ | 跨块Turbo |
| test_channel_est_eq | V2.0.0 | ✅ | 24项测试+6张可视化 |
| sync_detect | V2.0.0 | ✅ | 新增doppler方法(二维时延-多普勒补偿搜索) |
| sync_dual_hfm | **V1.1.0** | ✅ | α公式修正（帧间隔压缩项） |
| phase_track | V1.0.0 | ✅ | 位同步: PLL/DFPT/Kalman |
| pll_carrier_sync | V1.0.0 | ✅ | DD-PLL载波同步 |

---

## 待办事宜

| 优先级 | 任务 | 状态 | 说明 |
|--------|------|------|------|
| ✅ | SC-FDE V4.0两级分离架构 | **完成** | `80bfe14`, fd<=1Hz盲估计可工作 |
| ✅ | CLAUDE.md接收端禁用发射端参数规则 | **完成** | `a68c12f` |
| 🔴 高 | **OFDM端到端V4.0改造** | **待做** | 去oracle dop_rate, 套用SC-FDE V4.0帧结构+两级架构 |
| 🔴 高 | **SC-TDE端到端V4.0改造** | **待做** | 去oracle dop_rate, 时域均衡需单独处理帧结构 |
| 🔴 高 | **模块07 doppler_rate=0修正** | **待做** | test_channel_est_eq.m第701行, 时变均衡测试应含真实Doppler频偏 |
| 🟡 中 | SC-FDE fd=5Hz联合迭代多普勒 | **保留** | α·fc∈Jakes频谱, 需Turbo环内CFO跟踪或更高fc |
| 🟡 中 | fd=10Hz BER非单调问题 | 待分析 | oracle也非零→接近系统ICI极限 |
| 🔵 低 | P4 OTFS端到端 | 可开始 | DD域处理+通带 |
| 🔵 低 | P5 DSSS端到端 | 待P4 | 扩频+Rake |
| 🔵 低 | P6 FH-MFSK端到端 | 待P5 | 跳频+能量检测 |

---

## 关键技术结论

1. **散布导频是精度决定性因素**：比算法选择影响大10-20dB
2. **BEM(DCT)+散布导频最优**：高fd下全面优于CE-BEM和DD-BEM
3. **FDE在长时延信道下全面优于TDE**：有5dB编码增益优势
4. **两级分离架构有效**：多普勒估计与精确定时解耦(SC-FDE V4.0)
5. **fd=5Hz的物理极限**：α·fc=5Hz落在Jakes衰落频谱[-5,+5]Hz内，单次实现中无法分离
6. **三个端到端测试均用oracle dop_rate**：OFDM/SC-TDE待改造，SC-FDE已部分改造(fd<=1Hz盲)
7. **模块07测试未含真实多普勒频偏**：doppler_rate=0，仅测Jakes衰落下的估计+均衡能力
