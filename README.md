# UWAcomm — 水声通信算法仿真平台

> Underwater Acoustic Communication Algorithm Simulation Platform

MATLAB 全栈水声通信仿真系统，覆盖 **6 种通信体制** 的完整端到端链路，含信源/信道编码、调制解调、多载波变换、信道估计与均衡、同步、多普勒处理、阵列接收及 Turbo 迭代均衡。

## 项目规模

| 指标 | 数值 |
|------|------|
| MATLAB 函数文件 | 186 个 |
| 代码总行数 | 25,830 行 |
| 算法模块 | 13 个 |
| Git 提交数 | 203 次 |
| 通信体制 | 6 种 |
| 模块 README (含 LaTeX 公式推导) | ~5,000 行 |

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
├── 07_ChannelEstEq/       # 信道估计与均衡 (最大模块, 42个函数)
│   ├── 静态估计: LS/MMSE/OMP/SBL/GAMP/AMP/VAMP/Turbo-VAMP
│   ├── 时变估计: BEM(CE/DCT)/DD-BEM/T-SBL/SAGE/Kalman
│   ├── 均衡器(TDE): RLS/LMS/DFE/BiDFE
│   ├── 均衡器(FDE): ZF/MMSE-FDE/MMSE-IC/时变FDE/BEM-Turbo-FDE
│   └── 均衡器(OTFS): LMMSE-BCCB/MP消息传递/UAMP
├── 08_Sync/               # 同步 (三层: 帧/符号/位) + 帧组装
├── 09_Waveform/           # 脉冲成形 (RRC) + 上下变频 + FSK + DA/AD
├── 10_DopplerProc/        # 多普勒估计 (xcorr/CAF/ZoomFFT) + 补偿 (spline/CFO/ICI)
├── 11_ArrayProc/          # 阵列接收预处理 (ULA)
├── 12_IterativeProc/      # Turbo 迭代均衡调度 (4体制)
└── 13_SourceCode/         # 端到端仿真 + 集成测试
    ├── common/            # 公共函数 (gen_uwa_channel 等)
    └── tests/             # 各体制端到端测试
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

- **MATLAB** R2020b 或更高版本
- 无需额外 Toolbox (纯 MATLAB 实现)

## 快速开始

```matlab
% 1. 添加路径
addpath(genpath('D:\TechReq\UWAcomm'));

% 2. 运行端到端测试 (以 OTFS 为例)
cd('13_SourceCode/src/Matlab/tests/OTFS');
run('test_otfs_timevarying.m');

% 3. 运行模块单元测试 (以信道估计为例)
cd('07_ChannelEstEq/src/Matlab');
run('test_channel_est_eq.m');
```

## 文档

- 每个模块包含 `README.md`，含完整算法推导 (LaTeX 公式)、接口说明、测试覆盖表
- `framework/framework_v6.html` — 系统框架图
- `08_Sync/sync_framework.html` — 三层同步技术框架
- `todo.md` — 开发进度与技术结论

## 许可

本项目为学术研究用途。
