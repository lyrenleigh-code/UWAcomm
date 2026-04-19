# UWAcomm 水声通信算法开发进度

> 框架参考：`framework/framework_v6.html`
> Turbo 均衡方案：`12_IterativeProc/turbo_equalizer_implementation.md`
> 调试记录：`wiki/debug-logs/{模块名}/`
> 测试结果矩阵：`wiki/comparisons/e2e-test-matrix.md`
> 关键技术结论：`wiki/conclusions.md`
> 6 种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 开发量统计

| 指标 | 数值 |
|------|------|
| MATLAB 函数文件 | 186 个 |
| 代码总行数 | 25,830 行 |
| 文档文件 (md+html) | 30 个 |
| Git 提交数 | 205 次 |
| README 文档总行数 | ~5000 行（含算法推导+断言表+LaTeX 公式） |
| 模块数 | 13 个（12 个算法模块 + 1 个集成模块） |

---

## 各模块状态

| 模块 | 文件夹 | 文件数 | 状态 |
|------|--------|--------|------|
| 01 信源编解码 | `01_SourceCoding/` | 5 | ✅ Huffman+均匀量化, 14 项测试全通过 |
| 02 信道编解码 | `02_ChannelCoding/` | 12 | ✅ 含 SISO（BCJR max-log/log-map/sova） |
| 03 交织/解交织 | `03_Interleaving/` | 8 | ✅ |
| 04 符号映射/判决 | `04_Modulation/` | 6 | ✅ |
| 05 扩频/解扩 | `05_SpreadSpectrum/` | 17 | ✅ 18 项测试+可视化 (V1.1) |
| 06 多载波+CP | `06_MultiCarrier/` | 15 | ✅ 含 OTFS per-sub-block CP |
| 07 信道估计与均衡 | `07_ChannelEstEq/` | 44 | ✅ 含 OTFS LMMSE/UAMP/MP 均衡器 |
| 08 同步+帧组装 | `08_Sync/` | 21 | ✅ 三层同步（帧/符号/位）, sync_dual_hfm V1.1 |
| 09 脉冲成形/变频 | `09_Waveform/` | 9 | ✅ 19 项测试+可视化 (V1.1) |
| 10 多普勒处理 | `10_DopplerProc/` | 15 | ✅ comp_resample V7, 13 项测试 (V2.0) |
| 11 阵列预处理 | `11_ArrayProc/` | 8 | ✅ |
| 12 Turbo 迭代调度 | `12_IterativeProc/` | 7 | ✅ V8(DFE iter1)+跨块版本+OTFS UAMP 选项 |
| 13 端到端仿真 | `13_SourceCode/` | 18 | 🔶 6 体制 E2E 完成，离散 Doppler 信道对比完成 |

---

## 逐体制状态概览

> 详细 BER 表格见 `wiki/comparisons/e2e-test-matrix.md`

| 体制 | 版本 | 状态 | 备注 |
|------|------|------|------|
| SC-FDE | V4.0 | ✅ | 两级分离架构，fd≤1Hz 盲估计可工作 |
| OFDM | V4.3 | ✅ | 鲁棒架构固化（OMP + nv_post + 跳过 CP + 空子载波 CFO + DD-BEM） |
| SC-TDE | V5.2 | ✅ | 时变跳过训练精估+nv_post 兜底（Jakes 伪瓶颈改动保留） |
| OTFS | V2.0 | ✅ | 通带+离散 Doppler（含分数）0%@10dB+，Rician 混合 K=5~20 可工作 |
| DSSS | V1.0 | ✅ | Rake(MRC)+DBPSK+DCD，96.8bps，static 0%@-15dB+ |
| FH-MFSK | V1.0 | ✅ | 8-FSK+16 位跳频+能量检测，750bps，唯一全信道可工作 |

---

## 算法版本固化

| 函数 | 版本 | 状态 | 说明 |
|------|------|------|------|
| ch_est_bem | V2.0.0 | ✅ | 向量化重构+可选 BIC+自适应正则化 |
| ch_est_bem_dd | V1.0.0 | ✅ | DD-BEM 判决辅助迭代精化 |
| ch_est_tsbl | V2.0.0 | ✅ | T-SBL 多快照联合稀疏 |
| ch_est_sage | V1.0.0 | ✅ | SAGE 联合时延+增益+多普勒 |
| ch_track_kalman | V1.0.0 | ✅ | 稀疏 Kalman AR(1) |
| eq_dfe | V3.1.0 | ✅ | h_est 初始化（测试中建议不传） |
| eq_lms | V1.1.0 | ✅ | 修复 DD QPSK 判决 |
| eq_mmse_ic_fde | V2.0.0 | ✅ | Turbo 核心 |
| eq_otfs_lmmse | V1.1.0 | ✅ | BCCB 2D-FFT 对角化 |
| eq_otfs_uamp | V1.0.0 | ✅ | Onsager 修正+EM 噪声（研究用） |
| ch_est_otfs_dd | V2.0.0 | ✅ | 自适应阈值（静态 3σ/时变 1σ） |
| turbo_equalizer_sctde | V8.0.0 | ✅ | DFE iter1 |
| turbo_equalizer_scfde_crossblock | V1.0.0 | ✅ | 跨块 Turbo |
| turbo_equalizer_otfs | V3.0.0 | ✅ | MP/UAMP 选项 |
| test_channel_est_eq | V2.0.0 | ✅ | 24 项测试+6 张可视化 |
| sync_detect | V2.0.0 | ✅ | 含 doppler 方法 |
| sync_dual_hfm | V1.1.0 | ✅ | α 公式修正 |
| phase_track | V1.0.0 | ✅ | PLL/DFPT/Kalman |

---

## 活跃 TODO

### 🔴 高优先

| 任务 | 状态 | 说明 |
|------|------|------|
| OTFS 两级同步架构 | 待做 | 对齐其他体制 HFM+LFM 帧结构（spec：`specs/active/2026-04-13-otfs-sync-architecture.md`） |

### 🟡 中优先

| 任务 | 状态 | 说明 |
|------|------|------|
| OTFS 通带 2D 脉冲整形 | Phase 2 完成 | Hann 旁瓣降 13.8dB + 模糊度 PSL 降 33dB；待 Phase 4 端到端 BER 验证 |
| OTFS PAPR 专项降低 | 待做 | 需 SLM/PTS/削峰等专用技术，当前 `papr_clip.m` 可用 |
| 14_Streaming P4 帧头/payload 异构调制路由 | 待 P3+去 Oracle | header FH-MFSK + payload 按 scheme 分发 |
| 14_Streaming P5 三进程并发 | 待 P4 | TX/Channel/RX 独立 MATLAB |
| 14_Streaming P6 物理层 AMC | 待 P5 | LFM peak/SNR/delay/Doppler → 自适应切体制 |
| 去 Oracle 改造回归验证 | 代码完成待验证 (2026-04-16) | MATLAB 回归 6 类 oracle 修复（O1~O6） |

### ✅ 已完成（近期里程碑）

| 任务 | 完成日期 | 备注 |
|------|---------|------|
| 离散 Doppler 信道全体制对比 | 2026-04-13 | 6 体制 × 6 信道 BER 矩阵，Jakes 伪瓶颈确认 |
| SC-TDE V5.2 优化 | 2026-04-14 | 时变跳过训练精估+nv_post 兜底 |
| 14_Streaming P1 (FH-MFSK loopback + GUI) | 2026-04-15 | 17 文件，passband 信道 + Jakes 时变 |
| 14_Streaming P2 流式帧检测 + 多帧 + GUI | 2026-04-15 | 6 文件，hybrid 检测，软判决 LLR |
| 14_Streaming P3.1 统一 modem API + FH-MFSK + SC-FDE | 2026-04-16 | `modem_dispatch` 架构 + 3 个 bug 修复 |
| 14_Streaming P3.2 OFDM + SC-TDE 统一 API | 2026-04-16 | 静态 6 径 0%@15dB+ |
| 14_Streaming P3.3 DSSS + OTFS 统一 API | 2026-04-16 | Gold31 Rake+DCD + DD 域 LMMSE Turbo |
| 去 Oracle — RX 盲估计改造（代码） | 2026-04-16 | O1~O6 全部修复，待 MATLAB 回归验证 |

---

## 相关资源

- **详细测试矩阵**：`wiki/comparisons/e2e-test-matrix.md`
- **累积技术结论**：`wiki/conclusions.md`
- **项目仪表盘**：`wiki/dashboard.md`
- **函数索引**：`wiki/function-index.md`
- **活跃 spec**：`specs/active/`（10 张，其中 3 张 OTFS spec 待填 Result 再归档）
