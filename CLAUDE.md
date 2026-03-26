# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

UWAcomm — 水声通信（Underwater Acoustic Communication）算法仿真项目。属于 `D:\TechReq\` 技术需求工作区的子项目，使用 MATLAB 开发。

研究方向涵盖：单载波通信、扩频通信、MIMO、时域均衡、移动多用户通信。

## Directory Structure

- **SourceCode/** — 主体源码（通信系统端到端仿真链路）
- **Modulation/** — 调制/解调算法（BPSK, QPSK, OFDM, 扩频等）
- **Sync/** — 同步算法（定时同步、载波同步、帧同步）
- **refrence/** — 参考文献（学位论文 PDF）

## Language & Conventions

- 主要语言：MATLAB（.m 文件）
- 函数文件命名：小写下划线风格，如 `channel_estimate.m`
- 每个 .m 文件需包含完整中文注释头（功能描述、输入输出参数、作者、日期）
- 函数内部按章节分割：参数校验 → 核心算法 → 输出整理
- 辅助函数（仅供内部调用）放在主函数文件末尾作为 local function

## Running

```bash
# MATLAB 命令行运行仿真脚本
matlab -batch "run('SourceCode/main_sim.m')"
```

无专门的构建系统或测试框架；通过 MATLAB 脚本直接运行仿真并观察 BER 曲线等输出。

## Reference Papers

`refrence/` 目录下论文覆盖的关键技术点：
- 单载波时域均衡（SC-TDE）：浅海信道下的判决反馈均衡
- 扩频通信与多址接入（CDMA/DSSS）
- MIMO 水声信道容量与空时编码
- 快时变信道下的自适应通信
- 移动多用户场景下的干扰抑制
