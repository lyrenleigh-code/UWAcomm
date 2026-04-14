# CLAUDE.md

> **Hub**: `D:\Claude\Ohmybrain` — 跨项目知识中心（查询/回流用 `/promote`）
> **模板**: `D:\Claude\ohmybrain-core` — 项目模板源

## Project Overview

UWAcomm — 水声通信（Underwater Acoustic Communication）算法仿真。MATLAB 开发，覆盖 6 种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强接收。

- 开发进度：`todo.md`
- 项目仪表盘：`wiki/dashboard.md`
- 函数索引：`wiki/function-index.md`
- 端到端流程：`wiki/architecture/end-to-end-flow.md`
- 关键算法：`wiki/architecture/key-algorithms.md`
- 技术结论：`wiki/conclusions.md`
- 调试记录：`wiki/debug-logs/{模块名}/`

## Directory Structure

```
UWAcomm/
├── .claude/                    # Claude Code harness（hooks/rules/skills）
├── wiki/                       # 项目知识层
│   ├── architecture/          # 系统框架/算法方案
│   ├── debug-logs/            # 调试日志（按模块分）
│   ├── conclusions.md         # 技术结论累积
│   ├── function-index.md      # 跨模块函数索引
│   └── dashboard.md           # 项目仪表盘
├── raw/                        # 只读原始资料
├── specs/{active,archive}/     # 任务spec
├── plans/                      # 实现计划
├── scripts/                    # 自动化脚本
├── modules/                    # === 所有算法模块 ===
│   ├── 01_SourceCoding/src/Matlab/
│   ├── 02_ChannelCoding/src/Matlab/
│   ├── 03_Interleaving/src/Matlab/
│   ├── 04_Modulation/src/Matlab/
│   ├── 05_SpreadSpectrum/src/Matlab/
│   ├── 06_MultiCarrier/src/Matlab/
│   ├── 07_ChannelEstEq/src/Matlab/       # 最大模块
│   ├── 08_Sync/src/Matlab/
│   ├── 09_Waveform/src/Matlab/
│   ├── 10_DopplerProc/src/Matlab/
│   ├── 11_ArrayProc/src/Matlab/
│   ├── 12_IterativeProc/src/Matlab/
│   └── 13_SourceCode/src/Matlab/          # 端到端仿真
│       ├── common/
│       └── tests/{SC-FDE,OFDM,SC-TDE,OTFS,DSSS,FH-MFSK}/
├── CLAUDE.md
└── todo.md
```

## 核心开发规则

### 1. 模块复用优先

开发任何新功能前，**必须**先检索 13 个模块的 README 和 `wiki/function-index.md`，确认是否已有可复用实现。**禁止在端到端测试或单个模块中重新实现其他模块已提供的功能**。例如：
- 信道估计 → 模块 07 的 `ch_est_*`
- 同步 → 模块 08 的 `sync_*`
- 多普勒处理 → 模块 10 的 `est_doppler_*` / `comp_*`
- Turbo迭代 → 模块 12 的 `turbo_equalizer_*`

调试中发现模块函数缺陷，**修复模块本身**而非绕过。

### 2. 接收端禁用发射端参数（关键）

接收端处理链路**严禁使用实际系统中无法获得的发射端参数**：
- ❌ 已知多普勒因子 `dop_rate`
- ❌ 已知发射符号 `all_cp_data/info_bits`
- ❌ 真实信道 `ch_info.h_time`
- ❌ 已知 SNR

这些参数**只能用于性能对比基准（oracle baseline）**，不能作为最终系统输入。
接收端可用：接收信号 `bb_raw/rx_pb`、已知前导码/训练序列模板、帧结构参数（帧长、CP长度等协议约定）、系统参数（fs/fc/sps 等）。

### 3. 工程闭环

```
specs/active/ → plans/ → 改代码 → 跑测试 → 更新wiki → 归档specs → commit
```

非平凡任务必须先写 spec 讨论再实施。spec 模板见 `specs/active/` 现有文件。

### 4. 调试日志与笔记

- **路径**：`wiki/debug-logs/{模块名}/` 如 `wiki/debug-logs/08_Sync/`
- **合并策略**：每个体制/模块维护**一个累积调试日志**，新记录作为带日期章节**追加**到末尾
  - 端到端：`wiki/debug-logs/13_SourceCode/SC-FDE调试日志.md`
  - 模块：`wiki/debug-logs/08_Sync/同步调试日志.md`
- **双向链接**：正文用 `[[wikilink]]` 链接相关概念/模块
- **Frontmatter 标签必须**：`tags: [调试日志, SC-FDE]` 等
- **每次 commit 后**同步更新调试日志 + 删除 `test_*_results.txt` 临时产物
- 跨项目价值的调试经验用 `/promote` 回流 Hub

### 5. 模块变更必须同步 README

任何新增/修改/删除模块函数时，必须同步更新模块 README（模板：`wiki/conventions/module-readme-template.md`）。

## MATLAB 测试调试流程

每次运行 `test_*.m` 单元测试**必须**按此流程：

```matlab
clear functions; clear all;                              % 1. 清缓存
cd('D:\Claude\TechReq\UWAcomm\modules\XX_模块\src\Matlab');  % 2. cd目录
diary('test_xxx_results.txt');                           % 3. diary输出
run('test_xxx.m');
diary off;
```

**关键规则**：

- **必须 `clear functions`**：防 git 切分支或 Claude Code 改文件后 MATLAB 用旧缓存
- **测试结果保存 txt**：debug 阶段测试脚本末尾用 `fopen/fprintf/fclose` 自动保存 BER/同步信息/多普勒估计/信道估计等关键指标
- **测试与可视化分离**：assert/pass/fail 计数 与 可视化绘图 **分开独立 try/catch**
- **诊断输出**：测试失败时 catch 块打印实际值（不仅"误差过大"）
- **每个测试须有可视化**：figure 展示波形/星座/BER/频谱等
- **断言条件须在 README 中记录**：格式见 `wiki/conventions/module-readme-template.md`

## Language & Conventions

- 主语言：MATLAB (.m)
- 函数命名：小写下划线 `ch_est_ls.m`
- 完整中文注释头（功能、版本、输入/输出参数、备注）
- 函数分节：`%% 1. 入参解析 → 2. 参数校验 → 3~N. 核心算法`
- 参数校验用中文错误提示
- 每模块含 `test_*.m` 和 `README.md`（含 $$LaTeX$$ 公式）
- Git：`feat/xxx` 分支 → `master`

## Cross-Module Dependencies

```matlab
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
```

## Reference Materials

- `wiki/architecture/system-framework.md` — 系统框架 v6
- `modules/08_Sync/sync_framework.html` + `sync_documentation.md` — 同步技术框架
- `modules/10_DopplerProc/UWA_Doppler_MATLAB_Spec.md` — 多普勒规范 v2.0
- `modules/12_IterativeProc/turbo_equalizer_implementation.md` — Turbo 均衡方案
- `raw/notes/framework-history/` — 框架图历史版本
- `refrence/` — 哈工程殷敬伟课题组学位论文 + Turbo_VAMP 参考
