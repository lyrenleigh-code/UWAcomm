# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

UWAcomm — 水声通信（Underwater Acoustic Communication）算法仿真项目。属于 `D:\TechReq\` 技术需求工作区的子项目，使用 MATLAB 开发。

覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强接收。

框架参考：`framework/framework_v4.html`（最新版）

## Directory Structure

```
UWAcomm/
├── 01_SourceCoding/src/Matlab/      # 模块1: 信源编解码 (Huffman + 均匀量化)
├── 02_ChannelCoding/src/Matlab/     # 模块2: 信道编解码 (Hamming/卷积/Turbo/LDPC)
├── 03_Interleaving/src/Matlab/      # 模块3: 交织/解交织 (块/随机/卷积)
├── 04_Modulation/src/Matlab/        # 模块4: 符号映射/判决 (QAM/PSK/MFSK + 星座图)
├── 05_SpreadSpectrum/src/Matlab/    # 模块5: 扩频/解扩 (DSSS/CSK/M-ary/FH + 4种码 + DCD/DED)
├── 06_MultiCarrier/src/Matlab/      # 模块6: 多载波变换+CP (OFDM/SC-FDE/OTFS + PAPR)
├── 07_ChannelEstEq/src/Matlab/      # 模块7: 信道估计与均衡 (10种估计+PTR+DFE+MP+LLR接口)
├── 08_Sync/src/Matlab/              # 模块8: 同步+帧组装 (4种序列 + 4种体制帧结构)
├── 09_Waveform/src/Matlab/          # 模块9: 脉冲成形/上下变频/FSK波形/DA/AD
├── 10_DopplerProc/src/Matlab/       # 模块10: 多普勒估计补偿 (10-1粗+10-2残余) [待开发]
├── 11_ArrayProc/src/Matlab/         # 模块11: 阵列接收预处理 [待开发]
├── 12_IterativeProc/src/Matlab/     # 模块12: 迭代调度器 (Turbo EQ调度7'⇌2') [待开发]
├── 13_SourceCode/src/Matlab/        # 模块13: 端到端仿真 [待开发]
├── framework/                       # 框架图 (v1/v2/v3/v4)
├── refrence/                        # 参考文献 (6篇学位论文PDF + Turbo_VAMP_TVC.m)
├── todo.md                          # 开发进度与待办清单
└── CLAUDE.md                        # 本文件
```

## Module Status

| 编号 | 模块 | 文件夹 | 状态 | 函数数 |
|------|------|--------|------|--------|
| 1 | 信源编解码 | 01_SourceCoding | ✅ | 5 |
| 2 | 信道编解码 | 02_ChannelCoding | ✅ | 11 |
| 3 | 交织/解交织 | 03_Interleaving | ✅ | 8 |
| 4 | 符号映射/判决 | 04_Modulation | ✅ | 6 |
| 5 | 扩频/解扩 | 05_SpreadSpectrum | ✅ | 17 |
| 6 | 多载波变换+CP | 06_MultiCarrier | ✅ | 16 |
| 7 | 信道估计与均衡 | 07_ChannelEstEq | ✅ | 27 |
| 8 | 同步+帧组装 | 08_Sync | ✅ | 17 |
| 9 | 脉冲成形/变频 | 09_Waveform | ✅ | 9 |
| 10 | 多普勒处理 | 10_DopplerProc | ⬜ | 0 |
| 11 | 阵列预处理 | 11_ArrayProc | ⬜ | 0 |
| 12 | 迭代调度器 | 12_IterativeProc | ⬜ | 0 |
| 13 | 端到端仿真 | 13_SourceCode | ⬜ | 0 |

## SC-TDE Turbo Equalization Flow (v4)

基于参考工程 `D:\ProjectTask\Turbo Equalization` 的完整流程：

```
TX: 卷积编码(02) → 交织(03) → QPSK映射(04) → IQ脉冲成形+上变频(09)
    → [LFM同步码 | 训练 | 数据 | 训练 | LFM同步码](08)

RX: 同步(08') → 下变频+匹配滤波(09') → LS信道估计(07) → PTR聚焦(07)
    → 第1次: 线性RLS(+PLL)(07) → LLR(07) → 解交织(03') → 卷积译码(02')
    → 第2~N次: 译码LLR → 软符号(07) → 交织(03) → 干扰消除(07)
              → DFE(RLS+PLL)(07) → LLR(07) → 解交织(03') → 译码(02')
```

## RX Processing Order (v4)

```
9'(下变频) → 8'(同步) → 11(阵列,可选) → 10-1(粗多普勒) → 6'(去CP+逆变换)
→ PTR(被动时反转,模块7) → 7'(信道估计+均衡) → 10-2(残余多普勒)
→ [↻迭代回环: 7'⇌10-2⇌2'] → 5'(解扩) → 4'(判决) → 3'(解交织) → 2'(译码) → 1'(解码)
```

## Language & Conventions

- 主要语言：MATLAB（.m 文件）
- 函数文件命名：小写下划线风格，如 `ch_est_ls.m`
- 每个 .m 文件需包含完整中文注释头（功能、版本、输入/输出参数、备注）
- 函数内部按章节分割：`%% 1. 入参解析 → 2. 参数校验 → 3~N. 核心算法 → 输出`
- 辅助函数放在主函数文件末尾作为 local function
- 参数校验使用中文错误提示
- 每个模块含 `test_*.m` 单元测试和 `README.md` 文档

## Cross-Module Dependencies

- `turbo_encode.m`（模块2）调用 `random_interleave.m`（模块3）
- 测试文件中使用 `addpath` 解决跨模块路径：
  ```matlab
  proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
  addpath(fullfile(proj_root, '04_Modulation', 'src', 'Matlab'));
  ```

## Reference Materials

- `refrence/` — 6篇哈工程殷敬伟课题组学位论文
- `10_DopplerProc/UWA_Doppler_MATLAB_Spec.md` — 多普勒估计补偿完整规范文档
- `refrence/Turbo_VAMP_TVC.m` — 稀疏信道估计算法族参考实现
- `D:\ProjectTask\Turbo Equalization/` — SC-TDE Turbo均衡工程参考（PTR+RLS-DFE+PLL+LLR）

## Key Design Decisions

- 模块10拆分为10-1（粗多普勒，6'之前重采样）和10-2（残余多普勒，7'之后CFO校正）
- CP插入/去除归入模块6（MultiCarrier）
- 迭代回环由12_IterativeProc调度，调用模块7均衡器和模块2译码器
- PTR被动时反转作为SC-TDE的必要预处理，放在模块7
- DFE使用RLS自适应+二阶PLL（参考Turbo EQ工程），输出LLR软信息
- 框架图中配置卡只展示每种体制实际启用的模块
- 所有模块文件夹添加编号前缀（01~13）
