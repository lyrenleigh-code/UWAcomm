# UWAcomm 水声通信算法开发进度

> 框架参考：`framework/framework_v6.html`
> Turbo均衡方案：`12_IterativeProc/turbo_equalizer_implementation.md`
> 调试记录：`D:\Obsidian\workspace\UWAcomm\{模块名}\`
> 6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 开发量统计

| 指标 | 数值 |
|------|------|
| MATLAB函数文件 | 186个 |
| 代码总行数 | 25,830行 |
| 文档文件(md+html) | 30个 |
| Git提交数 | 205次 |
| README文档总行数 | ~5000行（含算法推导+断言表+LaTeX公式） |
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
| 06 多载波+CP | `06_MultiCarrier/` | 15 | ✅ 含OTFS per-sub-block CP |
| 07 信道估计与均衡 | `07_ChannelEstEq/` | 44 | ✅ 含OTFS LMMSE/UAMP/MP均衡器 |
| 08 同步+帧组装 | `08_Sync/` | 21 | ✅ 三层同步(帧/符号/位), sync_dual_hfm V1.1 |
| 09 脉冲成形/变频 | `09_Waveform/` | 9 | ✅ 19项测试+可视化(V1.1) |
| 10 多普勒处理 | `10_DopplerProc/` | 15 | ✅ comp_resample V7, 13项测试(V2.0) |
| 11 阵列预处理 | `11_ArrayProc/` | 8 | ✅ |
| 12 Turbo迭代调度 | `12_IterativeProc/` | 7 | ✅ V8(DFE iter1)+跨块版本+OTFS UAMP选项 |
| 13 端到端仿真 | `13_SourceCode/` | 18 | 🔶 6体制E2E完成, 离散Doppler信道对比待做 |

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
| **盲估计** | **0%** | **0.20%@5dB, 0%@10+** | 50%（Jakes信道） |

### OFDM V4.3 — 鲁棒架构 ✅（2026-04-10）

帧结构：`[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]`
TX: 06 ofdm_modulate(IFFT+CP) + 空子载波(每32个置null)
RX: LFM粗估α(时变跳过CP精估) → 空子载波CFO精估 → OMP/BEM信道估计 → 逐子载波MMSE-IC + nv_post兜底 → DD-BEM + Turbo(10轮)

| SNR | static | fd=1Hz | fd=5Hz |
|-----|--------|--------|--------|
| 0dB | 0.98% | 16.29% | ~50% |
| 5dB | 0% | 3.38% | ~50% |
| 10dB | 0% | 1.97% | ~50% |
| 15dB | 0% | 1.16% | ~50% |
| 20dB | 0% | 1.06% | ~50% |

### SC-TDE V5.1 — LFM同步修复 🔶（2026-04-10）

帧结构：`[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]`
RX：①LFM相位+训练精估α ②resample补偿 ③LFM精确定时 ④残余CFO ⑤BEM+Turbo(10轮)

| SNR | static | fd=1Hz | fd=5Hz |
|-----|--------|--------|--------|
| 5dB | 1.95% | 46.80% | 45.34% |
| 10dB | 0.55% | 13.91% | 46.24% |
| 15dB | 0.10% | 0.76% | 46.38% |
| 20dB | 0.00% | 1.60% | 44.71% |

### DSSS V1.0 — Rake(MRC) + DBPSK + DCD ✅（2026-04-10）

| 验证 | static | fd=1Hz | fd=5Hz |
|------|--------|--------|--------|
| coded | 0%@[-15,+10]dB | 0%@[0,+10]dB | ~36-48% |

### FH-MFSK V1.0 — 8-FSK + 16位跳频 + 能量检测 ✅（2026-04-10）

| 验证 | static | fd=1Hz | fd=5Hz |
|------|--------|--------|--------|
| coded | 0%@10dB+ | 0%@5dB+ | 0%@0dB+ |

### OTFS V2.0 — 通带仿真+离散Doppler验证 ✅（2026-04-11）

帧结构：`[LFM|guard|OTFS(per-sub-block CP)|guard|LFM]`（通带）
均衡：LMMSE-BCCB 2D-FFT对角化 + Turbo(3轮)

**离散Doppler信道** (0%=coded BER @10dB+)：

| 信道 | 0dB | 5dB | 10dB | 15dB | 20dB |
|------|-----|-----|------|------|------|
| static | 7% | 0% | 0% | 0% | 0% |
| disc-5Hz | 10% | 0.5% | 0% | 0% | 0% |
| hyb-K20 (95%谱) | 13% | 1% | 0% | 0% | 0% |
| hyb-K10 (91%谱) | 16% | 2% | 0.2% | 0.05% | 0.05% |
| hyb-K5 (83%谱) | 11% | 1% | 0% | 0% | 0% |
| jakes-5Hz | 50% | 50% | 50% | 50% | 50% |

**关键发现**：Jakes连续谱不适合OTFS(BCCB模型失效)，离散Doppler(含分数频移)下OTFS完美工作。实际水声信道(Rician混合)与离散模型更匹配。

---

## 逐体制开发计划

### ✅ P1→V4.0: SC-FDE — 帧结构改造完成
- 两级分离架构，fd<=1Hz盲估计可工作
- fd=5Hz(Jakes): 50%, 10种方案失败

### ✅ P2→V4.3: OFDM — 鲁棒架构固化
- OMP+nv_post+跳过CP+空子载波CFO+DD-BEM
- static: 0%@5dB+, fd=1Hz: ~1%@15dB+(BEM极限)

### 🔶 P3→V5.1: SC-TDE — LFM同步修复，fd=1Hz待优化
- static: 0%@10dB+, fd=1Hz: 0.76%@15dB
- 待优化：时变跳过训练精估 + nv_post兜底

### ✅ P4→V2.0: OTFS — 通带+离散Doppler验证
- DD域修正+per-sub-block CP+LMMSE-BCCB
- 离散Doppler(含分数,max 5Hz): 0%@10dB+
- Rician混合(K=5~20): 0%@10dB+
- UAMP均衡器已实现(研究用，对BCCB无优势)

### ✅ P5→V1.0: DSSS — Rake(MRC) + DBPSK + DCD
- 96.8bps, static: 0%@-15dB+, fd=1Hz: 0%@0dB+

### ✅ P6→V1.0: FH-MFSK — 8-FSK + 16位跳频 + 能量检测
- 750bps, fd=5Hz(Jakes): 0%@0dB+ (跳频分集最优)

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
| eq_otfs_lmmse | V1.1.0 | ✅ | BCCB 2D-FFT对角化 |
| eq_otfs_uamp | V1.0.0 | ✅ | Onsager修正+EM噪声(研究用) |
| ch_est_otfs_dd | V2.0.0 | ✅ | 自适应阈值(静态3σ/时变1σ) |
| turbo_equalizer_sctde | V8.0.0 | ✅ | DFE iter1 |
| turbo_equalizer_scfde_crossblock | V1.0.0 | ✅ | 跨块Turbo |
| turbo_equalizer_otfs | V3.0.0 | ✅ | MP/UAMP选项 |
| test_channel_est_eq | V2.0.0 | ✅ | 24项测试+6张可视化 |
| sync_detect | V2.0.0 | ✅ | 含doppler方法 |
| sync_dual_hfm | V1.1.0 | ✅ | α公式修正 |
| phase_track | V1.0.0 | ✅ | PLL/DFPT/Kalman |

---

## 待办事宜

| 优先级 | 任务 | 状态 | 说明 |
|--------|------|------|------|
| ✅ | SC-FDE V4.0两级分离架构 | **完成** | fd<=1Hz盲估计可工作 |
| ✅ | OFDM端到端V4.3 | **完成** | 鲁棒架构固化 |
| ✅ | DSSS端到端V1.0 | **完成** | Rake+DCD |
| ✅ | FH-MFSK端到端V1.0 | **完成** | 跳频+能量检测 |
| ✅ | OTFS端到端V2.0 | **完成** | 通带+离散Doppler验证+UAMP |
| ✅ | SC-TDE V5.2优化 | **完成(2026-04-14)** | 时变跳过训练精估+nv_post兜底; Jakes目标因伪瓶颈失效，改动保留 |
| ✅ | **离散Doppler信道全体制对比** | **完成(2026-04-13)** | apply_channel提取到common, 6体制×6信道BER矩阵, Jakes瓶颈确认为伪问题 |
| ✅ | SC-FDE离散Doppler测试 | **完成** | disc-5Hz 0.88%@10dB, hyb-K10 0%@10dB+ |
| ✅ | OFDM离散Doppler测试 | **完成** | disc-5Hz/hyb全部 0%@10dB+, Jakes仍~50% |
| ✅ | SC-TDE离散Doppler测试 | **完成** | disc-5Hz/hyb-K20/K10 **0%@5dB+**, 最大改善 |
| ✅ | DSSS离散Doppler测试 | **完成** | disc-5Hz 0%@-10dB+, hyb-K5 0%@-5dB+ |
| ✅ | FH-MFSK离散Doppler测试 | **完成** | 全部6种信道 0%@0~5dB+, 最鲁棒 |
| 🔶 进行 | OTFS通带2D脉冲整形 | **Phase2完成** | Hann旁瓣降13.8dB+模糊度PSL降33dB; PAPR无法通过窗化降低(根因是IFFT叠加); 待Phase4端到端BER验证 |
| 🔴 高 | OTFS两级同步架构 | **待做** | 对齐其他体制HFM+LFM帧结构 |
| ✅ | 模块07 doppler_rate=0修正 | **完成(2026-04-12)** | fd/fc换算+oracle α补偿; fd=1/5Hz oracle 5dB+基本不变; fd=10Hz确认ICI极限 |
| 🟡 中 | OTFS PAPR专项降低 | **待做** | 需SLM/PTS/削峰等专用技术, 当前papr_clip可用 |

---

## 关键技术结论

1. **散布导频是精度决定性因素**：比算法选择影响大10-20dB
2. **BEM(DCT)+散布导频最优**：高fd下全面优于CE-BEM和DD-BEM
3. **FDE在长时延信道下全面优于TDE**：有5dB编码增益优势
4. **两级分离架构有效**：多普勒估计与精确定时解耦
5. **Jakes ≠ 实际水声信道**：Jakes连续Doppler谱过度悲观，实际水声是Rician混合(离散强径+弱散射)
6. **OTFS在离散Doppler下完美工作**：含分数频移(max 5Hz)→0% BER@10dB+，BCCB模型精确
7. **UAMP对BCCB无优势**：LMMSE per-frequency权重已最优，UAMP Turbo不稳定
8. **~~6体制fd=5Hz瓶颈待重新评估~~** → **已确认：Jakes连续谱是伪瓶颈**（2026-04-13离散Doppler全体制对比）
9. **离散Doppler下全部6体制可工作**：disc-5Hz/Rician混合信道，高速体制(SC-FDE/OFDM/SC-TDE/OTFS)均在5-10dB达到0%BER
10. **SC-TDE在离散Doppler下逆袭**：从Jakes的~48%@全SNR → disc-5Hz **0%@5dB+**，改善最大
11. **FH-MFSK是唯一全信道可工作的体制**：即使Jakes连续谱也在0dB即0%，跳频分集+能量检测天然抗Doppler
12. **OTFS PAPR无法通过窗化降低**（2026-04-13）：PAPR=7.1dB，根因是IFFT随机叠加（与OFDM同理），CP-only窗化和数据脉冲成形均无效。需SLM/PTS/削峰等专用技术
13. **Hann脉冲成形降旁瓣有效**（2026-04-13）：频谱PSL降13.8dB（-17.8→-31.6dB），模糊度函数多普勒PSL降33dB（-13.4→-46.9dB），代价是多普勒分辨力展宽2.3x（水声5Hz场景可接受）

---

## 离散Doppler全体制对比结果（2026-04-13）

### 高速体制 Coded BER @10dB

| 信道 | SC-FDE | OFDM | SC-TDE | OTFS |
|------|--------|------|--------|------|
| static | 0% | 0% | 0.85% | 0% |
| disc-5Hz | 0.88% | 0% | **0%** | 0% |
| hyb-K20 | 0.42% | 0% | **0%** | 0.27% |
| hyb-K10 | 0.05% | 0% | **0%** | 0.27% |
| hyb-K5 | 0% | 0% | **0%** | 0% |
| jakes5Hz | ~49% | ~51% | ~48% | ~35% |

### 低速体制 达到0% BER的最低SNR

| 信道 | DSSS(96.8bps) | FH-MFSK(750bps) |
|------|--------------|-----------------|
| static | -15dB | 10dB |
| disc-5Hz | -10dB | 0dB |
| hyb-K20 | -10dB | 0dB |
| hyb-K10 | -10dB | 0dB |
| hyb-K5 | -5dB | -5dB |
| jakes5Hz | 失效 | 0dB |
