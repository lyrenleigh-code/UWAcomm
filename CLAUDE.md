# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

UWAcomm — 水声通信（Underwater Acoustic Communication）算法仿真项目。MATLAB开发，覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强接收。

框架参考：`framework/framework_v5.html`（待升级v6）
开发进度：`todo.md`
调试记录：`D:\Obsidian\workspace\UWAcomm\端到端帧组装调试笔记.md`

## Directory Structure

```
UWAcomm/
├── 01_SourceCoding/src/Matlab/      # 信源编解码
├── 02_ChannelCoding/src/Matlab/     # 信道编解码（含SISO/BCJR）
├── 03_Interleaving/src/Matlab/      # 交织/解交织
├── 04_Modulation/src/Matlab/        # 符号映射/判决
├── 05_SpreadSpectrum/src/Matlab/    # 扩频/解扩
├── 06_MultiCarrier/src/Matlab/      # 多载波变换+CP
├── 07_ChannelEstEq/src/Matlab/      # 信道估计与均衡（最大模块）
├── 08_Sync/src/Matlab/              # 同步+帧组装
├── 09_Waveform/src/Matlab/          # 脉冲成形/上下变频
├── 10_DopplerProc/src/Matlab/       # 多普勒估计补偿
├── 11_ArrayProc/src/Matlab/         # 阵列接收预处理
├── 12_IterativeProc/src/Matlab/     # Turbo迭代调度
├── 13_SourceCode/src/Matlab/        # 端到端仿真（集成测试）
│   ├── common/                      # 公共函数
│   └── tests/{SC-FDE,OFDM,SC-TDE,...}  # 各体制测试
├── framework/                       # 框架图
└── todo.md                          # 开发进度
```

## 开发原则（重要）

### 1. 模块复用优先

**在端到端集成（模块13）和调试中，必须优先使用已开发模块的函数，而非重新实现。**

各模块提供的核心能力和对外接口：

| 模块 | 核心能力 | 对外接口函数 | 端到端中的调用位置 |
|------|---------|------------|------------------|
| 02 信道编解码 | 卷积编码 + SISO(BCJR)译码 | `conv_encode`, `siso_decode_conv`, `sova_decode_conv` | TX编码, RX译码 |
| 03 交织 | 随机交织/解交织 | `random_interleave`, `random_deinterleave` | TX交织, RX解交织, Turbo迭代环 |
| 07 信道估计 | LS/MMSE/OMP/SBL/GAMP/VAMP/Turbo-VAMP | `ch_est_ls`, `ch_est_mmse`, `ch_est_omp`, `ch_est_sbl`, `ch_est_gamp`, `ch_est_vamp`, `ch_est_turbo_vamp` | **RX信道估计（从训练序列）** |
| 07 均衡 | RLS-DFE/双向DFE/MMSE-IC/频域MMSE | `eq_dfe`, `eq_bidirectional_dfe`, `eq_mmse_ic_fde`, `eq_linear_rls` | RX均衡 |
| 07 软信息 | LLR↔符号映射 | `soft_demapper`, `soft_mapper` | Turbo迭代中的软信息交换 |
| 08 同步 | LFM/HFM/ZC/Barker生成 + 帧同步检测 | `gen_lfm`, `sync_detect` | TX前导生成, RX帧同步 |
| 09 波形 | RRC成形/匹配 + 上下变频 | `pulse_shape`, `match_filter`, `upconvert`, `downconvert` | TX成形+上变频, RX下变频+匹配 |
| 10 多普勒 | 估计(xcorr/CAF/CP/ZoomFFT) + 补偿(spline/farrow) | `est_doppler_xcorr`, `comp_resample_spline`, `doppler_coarse_compensate` | RX多普勒估计+补偿 |
| 12 Turbo迭代 | 4体制Turbo均衡调度 | `turbo_equalizer_scfde`, `turbo_equalizer_sctde`, `turbo_equalizer_ofdm`, `turbo_equalizer_otfs` | RX迭代均衡+译码 |
| 13 信道仿真 | 多径+Jakes+多普勒 | `gen_uwa_channel` | 信道仿真 |

### 2. 调试规则

- **新功能先查模块07~12是否已有实现**，避免重复开发
- 调试中发现模块函数缺陷（如eq_dfe的h_est未使用），应修复模块本身而非绕过
- **信道估计规则**：端到端测试**必须调用模块07的ch_est_*函数**（如ch_est_gamp）从接收信号估计信道。**Oracle（ch_info.h_time真实信道）只能作为性能对比基准，不能作为最终结果**。最终提交的端到端BER曲线必须基于估计信道
- 当前SC-FDE/OFDM端到端仍使用oracle H_est，属**待修正项**
- 每次调试结果记录到 `D:\Obsidian\workspace\UWAcomm\` 的笔记中

### 3. 模块README要求

每个模块的README.md必须包含：
1. **模块总体功能**：一句话描述该模块在系统中的角色
2. **对外接口列表**：其他模块/端到端应调用的函数及其签名
3. **使用示例**：典型调用代码片段
4. **内部函数列表**：辅助/测试函数（不建议外部直接调用）
5. **依赖关系**：该模块依赖的其他模块

## 端到端信号流（V3最终版）

```
=== TX ===
02 conv_encode → 03 random_interleave → QPSK映射
09 pulse_shape(RRC) → 09 upconvert → 通带实数
08 gen_lfm(通带实LFM) → 功率归一化
08 帧组装: [LFM_pb | guard | data_pb | guard | LFM_pb]  全实数

=== 信道仿真 ===
等效基带帧 → 13 gen_uwa_channel(多径+Jakes+多普勒)
09 upconvert → +实噪声

=== RX ===
09 downconvert → 复基带
08 sync_detect(基带LFM参考, 直达径窗口50样本)
10 est_doppler_xcorr(前后LFM) → 10 comp_resample_spline(alpha)
提取数据段 → 09 match_filter(RRC)
07 ch_est_*(训练序列→信道估计)  ← 必须调用模块07
07 eq_dfe(h_est初始化) 或 12 turbo_equalizer_*(h_est用于ISI消除)
03 random_deinterleave → 02 siso_decode_conv → bits_out
```

## 关键技术方案

### 通带帧组装
- 帧信号为**通带实数**（DAC可输出）
- LFM: `gen_lfm`通带实信号, 功率归一化匹配数据段RMS
- 信道在**等效基带**施加（复增益×复信号=正确）
- 通带闭环: 基带→upconvert→实噪声→downconvert

### 同步检测
- 无噪声信号上做一次(per fading config)
- 直达径窗口(50样本内搜索), 避免误检反射径/LFM2
- sync偏移→有效时延调整(整数循环移位+分数相位斜坡)

### 信道估计
- 训练序列构建Toeplitz矩阵: `T_mat(col:end, col) = training(1:end-col+1)'`
- 调用模块07: `ch_est_omp(y_obs, T_mat, L_h, K)` 等
- 估计结果用于: DFE权重初始化 + Turbo ISI消除

### 多普勒补偿
- `comp_resample_spline` V7: 传 **正alpha**（函数内部已改为pos=(1:N)/(1+α)，正alpha=补偿压缩）
- 信道seed不依赖SNR索引（同一信道，只变噪声）

### Turbo均衡（SC-TDE）
- iter 1: DFE(31,90) + h_est初始化 → LLR → BCJR
- iter 2+: 软ISI消除 conv(x_bar, h_est) → 单抽头ZF → LLR → BCJR
- 跨块Turbo（SC-FDE/OFDM）: LMMSE-IC + DD信道更新 + BCJR

## 已知问题

| 问题 | 状态 | 说明 |
|------|------|------|
| eq_dfe h_est初始化 | 已修复 | V3.1: 匹配滤波初始化前馈+ISI消除初始化反馈 |
| comp_resample_spline方向 | **已修复** | V7: 内部改为pos=(1:N)/(1+alpha)，正alpha直接传入 |
| est_doppler_xcorr搜索越界 | 已绕过 | xcorr全局max命中LFM2, fallback到已知alpha |
| 多普勒估计精度 | 搁置 | 多径下虚假峰问题, 独立课题 |
| OTFS通带实现 | 搁置 | DD域二维脉冲成形, 需专项 |

## Language & Conventions

- 主要语言：MATLAB（.m 文件）
- 函数文件命名：小写下划线风格 `ch_est_ls.m`
- 完整中文注释头（功能、版本、输入/输出参数、备注）
- 函数内部按章节分割：`%% 1. 入参解析 → 2. 参数校验 → 3~N. 核心算法`
- 参数校验使用中文错误提示
- 每个模块含 `test_*.m` 单元测试和 `README.md` 文档

## Cross-Module Dependencies

```matlab
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
```

## Reference Materials

- `framework/framework_v5.html` — 系统框架图
- `12_IterativeProc/turbo_equalizer_implementation.md` — Turbo均衡实现方案
- `refrence/` — 哈工程殷敬伟课题组学位论文 + Turbo_VAMP参考实现
- `D:\ProjectTask\Turbo Equalization/` — SC-TDE工程参考
