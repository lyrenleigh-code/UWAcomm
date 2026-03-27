# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

UWAcomm — 水声通信（Underwater Acoustic Communication）算法仿真项目。属于 `D:\TechReq\` 技术需求工作区的子项目，使用 MATLAB 开发。

覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强接收。

框架参考：`framework/framework_v3.html`（最新版）

## Directory Structure

```
UWAcomm/
├── SourceCoding/src/Matlab/      # 模块1: 信源编解码 (Huffman + 均匀量化)
├── ChannelCoding/src/Matlab/     # 模块2: 信道编解码 (Hamming/卷积/Turbo/LDPC)
├── Interleaving/src/Matlab/      # 模块3: 交织/解交织 (块/随机/卷积)
├── Modulation/src/Matlab/        # 模块4: 符号映射/判决 (QAM/PSK/MFSK + 星座图)
├── SpreadSpectrum/src/Matlab/    # 模块5: 扩频/解扩 (DSSS/CSK/M-ary/FH + 4种码 + DCD/DED)
├── MultiCarrier/src/Matlab/      # 模块6: 多载波变换+CP (OFDM/SC-FDE/OTFS) [待开发]
├── ChannelEstEq/src/Matlab/      # 模块7: 信道估计与均衡 [待开发]
├── Sync/src/Matlab/              # 模块8: 同步+帧组装 (4种序列 + 4种体制帧结构)
├── Waveform/src/Matlab/          # 模块9: 脉冲成形/上下变频/FSK波形/DA/AD
├── DopplerProc/src/Matlab/       # 模块10: 多普勒估计补偿 (10-1粗+10-2残余) [待开发]
├── ArrayProc/src/Matlab/         # 模块11: 阵列接收预处理 [待开发]
├── SourceCode/src/Matlab/        # 模块13: 端到端仿真 [待开发]
├── IterativeProc/src/Matlab/     # (保留，迭代回环已融入模块7)
├── framework/                    # 框架图 (v1/v2/v3)
├── refrence/                     # 参考文献 (6篇学位论文PDF)
├── todo.md                       # 开发进度与待办清单
└── CLAUDE.md                     # 本文件
```

## Module Status

| 编号 | 模块 | 文件夹 | 状态 | 函数数 |
|------|------|--------|------|--------|
| 1 | 信源编解码 | SourceCoding | ✅ 完成 | 5 |
| 2 | 信道编解码 | ChannelCoding | ✅ 完成 | 10 |
| 3 | 交织/解交织 | Interleaving | ✅ 完成 | 7 |
| 4 | 符号映射/判决 | Modulation | ✅ 完成 | 6 |
| 5 | 扩频/解扩 | SpreadSpectrum | ✅ 完成 | 15 |
| 6 | 多载波变换+CP | MultiCarrier | ⬜ 待开发 | 0 |
| 7 | 信道估计与均衡 | ChannelEstEq | ⬜ 待开发 | 0 |
| 8 | 同步+帧组装 | Sync | ✅ 完成 | 16 |
| 9 | 脉冲成形/变频 | Waveform | ✅ 完成 | 8 |
| 10 | 多普勒处理 | DopplerProc | ⬜ 待开发 | 0 |
| 11 | 阵列预处理 | ArrayProc | ⬜ 待开发 | 0 |
| 13 | 端到端仿真 | SourceCode | ⬜ 待开发 | 0 |

## RX Processing Order (v3.0)

```
9'(下变频) → 8'(同步) → 11(阵列,可选) → 10-1(粗多普勒) → 6'(去CP+逆变换)
→ 7'(信道估计均衡) → 10-2(残余多普勒) → [↻迭代回环: 7'⇌10-2⇌2'] → 5'(解扩)
→ 4'(符号判决) → 3'(解交织) → 2'(信道解码) → 1'(信源解码)
```

迭代回环不是独立模块，由7'(均衡)、10-2(残余补偿)、2'(信道解码)组合实现。

## Language & Conventions

- 主要语言：MATLAB（.m 文件）
- 函数文件命名：小写下划线风格，如 `channel_est_ls.m`
- 每个 .m 文件需包含完整中文注释头（功能、版本、输入/输出参数、备注）
- 函数内部按章节分割：`%% 1. 入参解析 → 2. 参数校验 → 3~N. 核心算法 → 输出`
- 辅助函数放在主函数文件末尾作为 local function，用分隔线标注
- 参数校验使用中文错误提示：`error('参数x必须为正数！')`
- 每个模块含 `test_*.m` 单元测试和 `README.md` 文档（含测试断言说明）

## Cross-Module Dependencies

- `turbo_encode.m`（模块2）调用 `random_interleave.m`（模块3）
- 测试文件中使用 `addpath` 解决跨模块路径：
  ```matlab
  proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
  addpath(fullfile(proj_root, 'ModuleName', 'src', 'Matlab'));
  ```

## Running Tests

每个模块在其 `src/Matlab/` 目录下有独立测试：

```bash
# 在MATLAB中运行单个模块测试
cd('D:\TechReq\UWAcomm\SourceCoding\src\Matlab'); run('test_source_coding.m');
cd('D:\TechReq\UWAcomm\ChannelCoding\src\Matlab'); run('test_channel_coding.m');
cd('D:\TechReq\UWAcomm\Interleaving\src\Matlab'); run('test_interleaving.m');
cd('D:\TechReq\UWAcomm\Modulation\src\Matlab'); run('test_modulation.m');
cd('D:\TechReq\UWAcomm\SpreadSpectrum\src\Matlab'); run('test_spread_spectrum.m');
cd('D:\TechReq\UWAcomm\Sync\src\Matlab'); run('test_sync.m');
cd('D:\TechReq\UWAcomm\Waveform\src\Matlab'); run('test_waveform.m');
```

## Reference Materials

- `refrence/` — 6篇哈工程殷敬伟课题组学位论文（SC-TDE/扩频/MIMO/时变信道/移动多用户/干扰抑制）
- `DopplerProc/UWA_Doppler_MATLAB_Spec.md` — 多普勒估计补偿完整规范文档（含OFDM/SC-FDE/OTFS三种体制）
- `refrence/Turbo_VAMP_TVC.m` — 稀疏信道估计算法族参考实现（ISTA/AMP/VAMP/Turbo-VAMP/WS-Turbo-VAMP）

## Key Design Decisions

- 模块10拆分为10-1（粗多普勒，6'之前重采样）和10-2（残余多普勒，7'之后CFO校正），同一文件夹 `DopplerProc/`
- CP插入/去除归入模块6（MultiCarrier），不在模块8（Sync）
- 模块12（迭代处理）不再作为独立模块，改为7'/10-2/2'之间的迭代回环调度
- 框架图中配置卡只展示每种体制实际启用的模块，不展示未使用模块
