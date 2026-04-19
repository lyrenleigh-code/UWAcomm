# UWAcomm — 水声通信算法仿真平台

> Underwater Acoustic Communication Algorithm Simulation Platform

MATLAB 全栈水声通信仿真系统，覆盖 **6 种通信体制** 的完整端到端链路，含信源/信道编码、调制解调、多载波变换、信道估计与均衡、同步、多普勒处理、阵列接收及 Turbo 迭代均衡。

## 项目规模

| 指标 | 数值 | 说明 |
|------|------|------|
| MATLAB 函数文件 | 266 个 | 含测试 / 可视化 / 辅助 |
| 代码总行数 | 39,821 行 | 2026-04-19 统计 |
| 算法模块 | 14 个 | 01-13 算法 + 14 流式仿真框架 |
| Git 提交数 | 226 次 | |
| 通信体制 | 6 种 | SC-FDE / OFDM / SC-TDE / DSSS / OTFS / FH-MFSK |
| 模块 README (含 LaTeX 公式推导) | ~5,000 行 | |

## 6 种通信体制

| 体制 | 速率 | 静态信道 | fd=1Hz | fd=5Hz | 特点 |
|------|------|---------|--------|--------|------|
| **SC-FDE** | ~6 kbps | 0% | 0.20% | 50% | 频域均衡，两级分离架构 |
| **OFDM** | ~6 kbps | 0% | ~1% | 50% | 逐子载波 MMSE-IC + DD-BEM |
| **SC-TDE** | ~6 kbps | 0% | 0.76%@15dB | ~45% | 时域 DFE + BEM 时变估计 |
| **DSSS** | 96.8 bps | 0%@-15dB | 0%@0dB | ~36% | Rake(MRC) + DBPSK + DCD |
| **FH-MFSK** | 750 bps | 0%@10dB | 0%@5dB | 0%@0dB | 跳频分集，无需信道估计 |
| **OTFS** | ~5.4 kbps | 0%@10dB | 0%@10dB | 0%* | DD域处理，离散Doppler最优 |

\*OTFS 在离散 Doppler 信道(含分数频移, max 5Hz)下实现 0% BER@10dB+；Jakes 连续谱信道下受限于 BCCB 模型。

## 模块架构

```
UWAcomm/
├── 01_SourceCoding/       # 信源编解码 (Huffman + 均匀量化)
├── 02_ChannelCoding/      # 信道编解码 (卷积码 + SISO/BCJR/SOVA)
├── 03_Interleaving/       # 随机交织/解交织
├── 04_Modulation/         # 符号映射/软判决 (BPSK/QPSK/8PSK/16QAM)
├── 05_SpreadSpectrum/     # 扩频/解扩 (Gold/Kasami/Walsh-Hadamard)
├── 06_MultiCarrier/       # 多载波变换 (OFDM/OTFS + CP)
├── 07_ChannelEstEq/       # 信道估计与均衡 (最大模块, 48 文件 / 41 对外函数)
│   ├── 静态估计: LS/MMSE/OMP/SBL/GAMP/AMP/VAMP/Turbo-VAMP
│   ├── 时变估计: BEM(CE/DCT)/DD-BEM/T-SBL/SAGE/Kalman
│   ├── OTFS 估计: DD pilot / ZC 序列 / 叠加导频
│   ├── 均衡器(TDE): RLS/LMS/DFE/BiDFE/Rake
│   ├── 均衡器(FDE): ZF/MMSE-FDE/MMSE-IC/时变 FDE/MMSE-IC-TV-FDE/BEM-Turbo-FDE
│   └── 均衡器(OTFS): LMMSE-BCCB/MP 消息传递/MP-Simplified/UAMP
├── 08_Sync/               # 同步 (三层: 帧/符号/位) + 帧组装 (SC-FDE/OFDM/SC-TDE/OTFS)
├── 09_Waveform/           # 脉冲成形 (RRC) + 上下变频 + FSK + DA/AD
├── 10_DopplerProc/        # 多普勒估计 (xcorr/CAF/ZoomFFT/CP) + 补偿 (spline/Farrow/CFO/ICI)
├── 11_ArrayProc/          # 阵列接收预处理 (MVDR/DAS + 非均匀采样重建)
├── 12_IterativeProc/      # Turbo 迭代均衡调度 (SC-FDE/OFDM/SC-TDE/OTFS/Crossblock)
├── 13_SourceCode/         # 端到端仿真 + 集成测试
│   ├── common/            # 公共函数 (gen_uwa_channel / tx_chain / rx_chain)
│   └── tests/{SC-FDE,OFDM,SC-TDE,OTFS,DSSS,FH-MFSK}/  # 各体制 static / timevarying / discrete_doppler
└── 14_Streaming/          # 流式仿真框架: text → wav → 信道 → wav → text
    ├── tx/rx/channel/     # 发射/接收/信道 daemon（P1-P3 demo 路径）
    ├── common/            # 统一 modem API + 帧头 + CRC + wav I/O + 流式帧检测
    ├── ui/                # P1/P2/P3 交互 GUI（深色科技风 + 8 tab 可视化）
    └── tests/             # P1-P3 端到端测试
```

## 端到端信号流

```
=== TX ===
信源 → 卷积编码(R=1/2) → 随机交织 → QPSK映射
→ [体制相关调制] → 脉冲成形(RRC) → 帧组装(LFM同步+保护间隔+数据)
→ 上变频(fc) → 通带实信号

=== 信道 ===
多径时变信道(gen_uwa_channel) + 通带实噪声

=== RX ===
下变频 → 匹配滤波 → 同步检测(LFM相关)
→ 多普勒估计+补偿(两级分离架构)
→ 信道估计(BEM/OMP/GAMP) → Turbo均衡(均衡器⇌BCJR译码器)
→ 解交织 → 译码 → 信宿
```

## 项目状态（2026-04-19）

- ✅ 01-13 六体制端到端链路全部跑通（static / timevarying / discrete_doppler）
- ✅ 14_Streaming P1-P3 流式仿真 + 统一 modem API + 深色科技风 UI + 真同步
- ✅ 全项目 code review 修复完成（Turbo La_dec_info 反馈 / Doppler 方向统一 /
  SC-FDE convergence 三选一判据扩散 / Oracle 显式标注等 10 条）
- 🚧 P4-P6（帧头路由 / 并发 / AMC）规划中
- 🚧 P3 demo Doppler 接入（`doppler_edit` 链路整合）

## 关键技术特色

### 两级分离多普勒架构
- **粗估计**: 双 LFM 相位差 → 多普勒因子 alpha
- **精估计**: CP 相关 / 训练序列 / 空子载波 → 残余 CFO
- **补偿**: spline 重采样 + 符号率 CFO 旋转

### 时变信道估计
- **BEM(DCT)**: 散布导频是精度决定性因素 (比算法选择影响大 10-20dB)
- **DD-BEM**: BCJR 软符号扩展观测集，判决辅助迭代精化
- **Kalman AR(1)**: 逐符号信道跟踪

### OTFS 延迟-多普勒域处理
- Per-sub-block CP 消除跨子块 beta 因子
- DD 域导频嵌入 + 自适应阈值信道估计
- BCCB 2D-FFT 对角化 LMMSE 均衡
- 离散 Doppler 验证: 0% BER@10dB+ (含分数频移)
- Rician 混合信道建模 (离散强径 + 弱 Jakes 散射)

## 环境要求

- **MATLAB** R2020b 或更高版本（`clim()` 替代 `caxis()` 需 R2022a+；更老版本
  按 CLAUDE.md 说明手动回退即可）
- 无需额外 Toolbox（纯 MATLAB 实现）

## 快速开始

```matlab
% 1. clone 后进入项目根目录
cd('UWAcomm');

% 2a. 运行端到端集成测试（以 OTFS 时变为例）
cd('modules/13_SourceCode/src/Matlab/tests/OTFS');
run('test_otfs_timevarying.m');

% 2b. 运行模块单元测试（以信道估计为例）
cd('modules/07_ChannelEstEq/src/Matlab');
run('test_channel_est_eq.m');

% 2c. 运行 14_Streaming 流式仿真 demo（深色科技风 UI，8 tab 可视化）
cd('modules/14_Streaming/src/Matlab/ui');
p3_demo_ui   % 交互式 GUI：TX 文本 → 信道 → RX 解码 + 实时同步/信道/质量历史
```

## 文档

- 每个模块 `modules/NN_xxx/README.md` 含算法推导（LaTeX 公式）、接口说明、测试覆盖
- `wiki/index.md` — 项目 wiki 索引（架构 / 函数索引 / 调试日志 / 结论）
- `wiki/conclusions.md` — 36 条累积技术结论（含体制对比、时变信道、OTFS 等）
- `wiki/architecture/system-framework.md` — 系统框架 v6
- `wiki/function-index.md` — 全 14 模块函数索引
- `wiki/debug-logs/` — SC-FDE / SC-TDE / OFDM / OTFS / FH-MFSK / 流式 调试日志
- `specs/active/` — 进行中的任务规格；`specs/archive/` — 已归档
- `todo.md` — 开发进度清单

## 许可

本项目为学术研究用途。
