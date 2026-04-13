# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

UWAcomm — 水声通信（Underwater Acoustic Communication）算法仿真项目。MATLAB开发，覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强接收。

框架参考：`wiki/architecture/system-framework.md`（历史版本：`raw/notes/framework-history/`）
同步技术框架：`modules/08_Sync/sync_framework.html` + `modules/08_Sync/sync_documentation.md`
多普勒技术规范：`modules/10_DopplerProc/UWA_Doppler_MATLAB_Spec.md`
开发进度：`todo.md`
调试记录：`D:\Obsidian\workspace\1-Projects\UWAcomm\{模块名}\` (按模块分文件夹，PARA架构)

## Directory Structure

```
UWAcomm/
├── .claude/                         # Claude Code harness（hooks/rules）
├── .obsidian/                       # Obsidian vault 配置 + wiki 页面模板
├── wiki/                            # 项目知识层（概念、架构、摘要、探索）
│   └── architecture/               # 系统框架文档
├── raw/                             # 只读原始资料（论文、文章、笔记等）
│   └── notes/framework-history/    # 框架图历史版本（v2~v6）
├── scripts/                         # 自动化脚本（lint_wiki/sync_index/scrape/transcribe）
├── workflows/                       # 操作流程文档（知识闭环 + 开发闭环）
├── modules/                         # === 所有算法模块 ===
│   ├── 01_SourceCoding/src/Matlab/  # 信源编解码
│   ├── 02_ChannelCoding/src/Matlab/ # 信道编解码（含SISO/BCJR）
│   ├── 03_Interleaving/src/Matlab/  # 交织/解交织
│   ├── 04_Modulation/src/Matlab/    # 符号映射/判决
│   ├── 05_SpreadSpectrum/src/Matlab/# 扩频/解扩
│   ├── 06_MultiCarrier/src/Matlab/  # 多载波变换+CP
│   ├── 07_ChannelEstEq/src/Matlab/  # 信道估计与均衡（最大模块）
│   ├── 08_Sync/src/Matlab/          # 同步+帧组装
│   ├── 09_Waveform/src/Matlab/      # 脉冲成形/上下变频
│   ├── 10_DopplerProc/src/Matlab/   # 多普勒估计补偿
│   ├── 11_ArrayProc/src/Matlab/     # 阵列接收预处理
│   ├── 12_IterativeProc/src/Matlab/ # Turbo迭代调度
│   └── 13_SourceCode/src/Matlab/    # 端到端仿真（集成测试）
│       ├── common/                  # 公共函数
│       └── tests/{SC-FDE,OFDM,...}  # 各体制测试
├── CLAUDE.md
└── todo.md                          # 开发进度
```

## 知识管理

### 知识闭环

```
raw/ → ingest → wiki/ → query → promote → Ohmybrain Hub wiki/
```

### 自动化保障（Hooks）

| 时机 | 检查内容 | 脚本 |
|------|---------|------|
| PreToolUse（Edit/Write） | 拦截 raw/ 写入 | `scripts/check_raw_write.py` |
| PostToolUse（Edit/Write） | Wiki 结构快速检查 | `scripts/lint_wiki.py --quick` |
| Stop | Wiki index/log 同步检查 | `scripts/check_index_log_sync.py` |
| Stop | 任务完整性验证 | `scripts/validate_task.py` |

### 常用脚本

| 命令 | 用途 |
|------|------|
| `python scripts/lint_wiki.py` | Wiki 结构检查 |
| `python scripts/sync_index.py` | 同步 index 页面计数 |
| `python scripts/scrape.py <URL>` | 网页抓取到 raw/ |
| `python scripts/transcribe.py <文件>` | 音视频转录到 raw/ |

## 开发原则（重要）

### 1. 模块复用优先

**在端到端集成（模块13）和调试中，必须优先使用已开发模块的函数，而非重新实现。**

各模块提供的核心能力和对外接口：

| 模块 | 核心能力 | 对外接口函数 | 端到端中的调用位置 |
|------|---------|------------|------------------|
| 02 信道编解码 | 卷积编码 + SISO(BCJR)译码 | `conv_encode`, `siso_decode_conv`, `sova_decode_conv` | TX编码, RX译码 |
| 03 交织 | 随机交织/解交织 | `random_interleave`, `random_deinterleave` | TX交织, RX解交织, Turbo迭代环 |
| 07 静态信道估计 | LS/MMSE/OMP/SBL/GAMP/AMP/VAMP/Turbo-VAMP/Turbo-AMP | `ch_est_ls`, `ch_est_mmse`, `ch_est_omp`, `ch_est_sbl`, `ch_est_gamp`, `ch_est_amp`, `ch_est_vamp`, `ch_est_turbo_vamp`, `ch_est_turbo_amp` | **RX静态信道估计** |
| 07 时变信道估计 | ✅ BEM(CE/DCT)/DD-BEM/T-SBL/SAGE | `ch_est_bem`✅, `ch_est_bem_dd`✅, `ch_est_tsbl`✅, `ch_est_sage`✅ | **RX时变信道估计（P3-2核心）** |
| 07 OTFS估计 | DD域导频估计 | `ch_est_otfs_dd` | OTFS信道估计 |
| 07 信道跟踪 | ✅ Kalman AR(1) | `ch_track_kalman`✅ | RX逐符号信道跟踪 |
| 07 均衡(TDE) | RLS/LMS/DFE/BiDFE/线性RLS | `eq_rls`, `eq_lms`, `eq_dfe`, `eq_bidirectional_dfe`, `eq_linear_rls` | SC-TDE均衡 |
| 07 均衡(FDE) | MMSE-FDE/MMSE-IC/ZF/时变FDE/ICI-aware时变IC-FDE/BEM-Turbo-FDE | `eq_mmse_fde`, `eq_mmse_ic_fde`, `eq_ofdm_zf`, `eq_mmse_tv_fde`, `eq_mmse_ic_tv_fde`, `eq_bem_turbo_fde` | SC-FDE/OFDM均衡 |
| 07 均衡(OTFS) | LMMSE-BCCB/UAMP/MP消息传递 | `eq_otfs_lmmse`, `eq_otfs_uamp`, `eq_otfs_mp`, `eq_otfs_mp_simplified` | OTFS均衡 |
| 07 软信息 | LLR↔符号映射 + ISI消除 | `soft_demapper`, `soft_mapper`, `llr_to_symbol`, `symbol_to_llr`, `interference_cancel` | Turbo迭代软信息交换 |
| 08 同步(L1帧) | LFM/HFM/ZC/Barker + 帧检测(**V2含多普勒补偿**) | `gen_lfm`, `gen_hfm`, `gen_zc_seq`, `gen_barker`, `sync_detect`(V2) | TX前导生成, RX帧同步 |
| 08 同步(L2符号) | Gardner/MM/超前滞后 TED | `timing_fine`, `cfo_estimate` | 符号定时+CFO估计 |
| 08 同步(L3位) | ✅ PLL/DFPT/Kalman相位跟踪 | `phase_track`✅ | 位同步/相位跟踪 |
| 08 帧结构 | 4体制帧组装/解析 | `frame_assemble_sctde`, `frame_parse_sctde`, `..._scfde`, `..._ofdm`, `..._otfs` | 帧组装+解析 |
| 09 波形 | RRC成形/匹配 + 上下变频 + FSK + DA/AD | `pulse_shape`, `match_filter`, `upconvert`, `downconvert`, `gen_fsk_waveform`, `da_convert`, `ad_convert` | TX成形+上变频, RX下变频+匹配 |
| 10 多普勒 | 估计(xcorr/CAF/CP/ZoomFFT) + 补偿(spline/farrow/CFO/ICI) | `est_doppler_xcorr`, `est_doppler_caf`, `est_doppler_zoomfft`, `comp_resample_spline`, `comp_cfo_rotate`, `comp_ici_matrix`, `doppler_coarse_compensate` | RX多普勒估计+补偿 |
| 10 阵列信道 | ✅ M阵元ULA信道 | `gen_uwa_channel_array`✅ | 阵列信道仿真 |
| 12 Turbo迭代 | 4体制Turbo均衡调度+跨块+OTFS UAMP选项 | `turbo_equalizer_scfde`, `turbo_equalizer_sctde`, `turbo_equalizer_ofdm`, `turbo_equalizer_otfs`, `turbo_equalizer_scfde_crossblock` | RX迭代均衡+译码 |
| 13 信道仿真 | 多径+Jakes+多普勒 | `gen_uwa_channel` | 信道仿真 |

### 2. 调试规则

- **全模块检索复用优先（关键）**：开发任何新功能前，必须先检索全部13个模块（01~13）的README和函数列表，确认是否已有可复用的实现。**禁止在端到端测试或单个模块中重新实现其他模块已提供的功能**。例如：信道估计必须调用模块07、同步必须调用模块08、多普勒处理必须调用模块10。
- 调试中发现模块函数缺陷（如eq_dfe的h_est未使用），应修复模块本身而非绕过
- **接收端禁用发射端参数（关键）**：接收端处理链路**严禁使用实际系统中无法获得的发射端参数**。包括但不限于：已知多普勒因子(dop_rate)、已知发射符号(all_cp_data/info_bits)、真实信道(ch_info.h_time)、已知SNR。这些参数**只能用于性能对比基准（oracle baseline），不能作为最终系统的输入**。接收端可用的信息仅限于：接收信号(bb_raw/rx_pb)、已知前导码/训练序列模板、帧结构参数（帧长、CP长度等协议约定）、系统参数（fs/fc/sps等）
- **信道估计规则**：端到端测试**必须调用模块07的ch_est_*函数**（如ch_est_gamp）从接收信号估计信道。Oracle只能作为性能对比基准
- 当前SC-FDE/OFDM端到端仍使用oracle H_est，属**待修正项**
- **每次提交同步更新笔记并清理txt**：每次git commit后，必须同步更新Obsidian笔记，记录本次变更内容、测试结果和关键发现；同时**删除测试目录下的临时txt结果文件**（`test_*_results.txt`等调试产物，不纳入版本控制）。笔记存放规则：
  - 路径：`D:\Obsidian\workspace\1-Projects\UWAcomm\{模块名}\`，如 `08_Sync\`、`13_SourceCode\`
  - 模块文件夹不存在时**直接新建**
  - **调试日志合并策略（关键）**：不再按日期创建独立文件。每个体制（SC-FDE/OFDM/SC-TDE/OTFS/DSSS/FH-MFSK）和每个模块各维护**一个累积调试日志**，新的调试记录作为带日期的章节**追加到对应日志末尾**。例如：
    - 端到端体制日志：`13_SourceCode/SC-FDE调试日志.md`、`OFDM调试日志.md`、`SC-TDE调试日志.md`
    - 模块日志：`08_Sync/同步调试日志.md`、`07_ChannelEstEq/时变信道估计与均衡调试笔记.md`
  - **双向链接必须**：每个调试日志头部必须包含 `[[模块概览]]` `[[关联体制日志]]` `[[UWAcomm MOC]]` 等wikilink，确保在Obsidian关系图谱中可见关联
  - **标签必须**：每个笔记必须包含体制标签（如`#SC-FDE`）和类型标签（如`#调试日志`、`#模块概览`、`#算法详解`）
  - 跨模块变更放在主要涉及的模块文件夹下
- **每次更新todo.md必须同步更新项目仪表盘**：`todo.md`与`D:\Obsidian\workspace\1-Projects\UWAcomm\项目仪表盘.md`保持一致。任何对待办事项、体制进度、已知问题、技术结论的变更，必须同时更新两个文件
- **模块更新必须同步README**：每次新增、修改或删除模块内的函数文件时，必须同步更新该模块的 `src/Matlab/README.md`（详见下方README要求）

### 3. MATLAB测试调试流程（详见模块08 sync调试经验）

每次运行 `test_*.m` 单元测试时，**必须**按以下流程执行：

```matlab
% 1. 清除函数缓存（防止git分支切换或外部编辑后用旧版本）
clear functions; clear all;

% 2. 切换到测试所在目录
cd('D:\TechReq\UWAcomm\modules\XX_模块\src\Matlab');

% 3. 用diary输出测试结果到txt
diary('test_xxx_results.txt');
run('test_xxx.m');
diary off;
```

**关键规则：**
- **必须 `clear functions`**：MATLAB会缓存已加载的.m文件，git切换分支或Claude Code修改文件后，MATLAB内存中仍是旧版本，导致测试结果与磁盘代码不一致
- **测试结果保存为txt**：每次测试运行必须保存结果到 `test_*_results.txt`，便于对比和追溯。**debug阶段所有测试脚本必须在末尾用fopen/fprintf/fclose自动保存关键指标**（BER、同步信息、多普勒估计、信道估计等），不依赖外部diary
- **测试与可视化分离**：测试逻辑（assert/pass/fail计数）和可视化绘图代码必须在**独立的try/catch块**中，避免绘图失败导致测试误判
- **诊断输出**：测试失败时catch块必须打印实际值（不仅仅是"误差过大"），便于定位问题
- **每个测试须有可视化输出**：测试完成后必须生成可视化figure，展示关键中间结果和最终性能（如波形对比、星座图、BER曲线、频谱、相关输出等），可视化代码放在独立try/catch中，不影响测试计数
- **断言条件须在README中明确记录**：每个test用例的assert判据（阈值、不等式、期望值）必须在模块README的测试覆盖章节逐条列出，格式示例：

```markdown
## 测试覆盖 (test_xxx.m Vx.x, N项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|---------|---------|------|
| 1.1 | LFM信号生成 | length == round(fs*dur), isreal | 长度精确，实信号 |
| 2.1 | 无噪声同步 | abs(pos - true_pos) <= 1, peak > 0.9 | 位置偏差≤1样本，峰值>0.9 |
| 3.1 | CFO互相关估计 | abs(est - true) < 20 Hz | 频偏误差<20Hz |
```

### 4. 模块README要求

每个模块的README.md必须包含以下内容，缺一不可：

1. **模块总体功能**：一句话描述该模块在系统中的角色
2. **对外接口列表**：其他模块/端到端应调用的函数，每个函数须列出：
   - 函数名、功能描述
   - 完整输入/输出参数说明（参数名、类型、含义、默认值）
3. **内部函数接口列表**：辅助/测试函数的接口定义（与对外接口同等详细度），标注"不建议外部调用"
4. **核心算法技术描述**：对模块中的关键算法，须包含：
   - **算法原理**：用文字和数学公式描述核心思想（如BEM展开、GAMP消息传递、RLS递推等）
   - **关键公式推导**：给出主要公式的简要推导过程（如MMSE权重推导、Kalman增益推导），不需要完整证明但须展示从输入到输出的推导链
   - **公式格式**：关键公式必须使用**块级LaTeX**（`$$...$$`），禁止用代码块包裹公式。示例：

$$\hat{h} = (\Phi^H \Phi + \lambda I)^{-1} \Phi^H y$$
   - **参数选择依据**：关键参数（如BEM阶数Q、正则化系数λ、遗忘因子λ_RLS）的选择公式或经验规则
   - **适用条件与局限性**：该算法在什么条件下有效、什么条件下失效
5. **使用示例**：典型调用代码片段
6. **依赖关系**：该模块依赖的其他模块
7. **测试覆盖**：测试文件名、版本、测试项数，并逐条列出每个用例的**编号、名称、断言条件、说明**（格式见上方测试调试流程中的示例表格）
8. **可视化说明**：测试生成的figure列表及其展示内容（如"Figure 1: 扩频码自相关/互相关/正交矩阵"）

## 端到端信号流（V5 — 三体制统一两级分离架构）

```
=== TX（三体制通用）===
02 conv_encode → 03 random_interleave → QPSK映射
[SC-TDE时变] 插入散布导频(簇长140, 间隔300) → 混合帧[训练|导频+数据交替]
[SC-FDE/OFDM] 分块+CP
09 pulse_shape(RRC) → 功率归一化
帧组装: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]  基带复信号

=== 信道仿真 ===
等效基带帧 → 13 gen_uwa_channel(多径+Jakes+多普勒)
09 upconvert → +实噪声

=== RX（两级分离架构）===
09 downconvert → 复基带
阶段1: LFM匹配滤波→双LFM相位差→alpha_lfm(粗估)
        粗补偿→[SC-FDE/OFDM: CP精估 | SC-TDE: 训练精估]→alpha_est
阶段2: 精补偿→LFM2匹配定时→数据段提取
09 match_filter(RRC) → 训练序列相关对齐
[SC-TDE残余CFO] alpha_est*fc Hz频偏补偿(符号率)
[静态] 07 ch_est_gamp(Toeplitz) → 12 turbo_equalizer_sctde(DFE+BCJR)
[时变SC-TDE] 07 ch_est_bem('dct',训练+散布导频) → per-symbol MMSE ISI消除
              iter2+: BCJR软符号 → DD-BEM重估计 → 全ISI消除+MMSE → BCJR
[时变SC-FDE/OFDM] 07 ch_est_bem('dct',CP段) → LMMSE-IC + DD信道更新 + BCJR
03 random_deinterleave → 02 siso_decode_conv → bits_out
```

## 关键技术方案

### 通带帧组装
- 帧信号为**通带实数**（DAC可输出）
- LFM: `gen_lfm`通带实信号, 功率归一化匹配数据段RMS
- 信道在**等效基带**施加（复增益×复信号=正确）
- 通带闭环: 基带→upconvert→实噪声→downconvert

### 同步检测（P3-2更新）
- 无噪声信号上做一次(per fading config)
- **首达径检测**：取第一个超过最强峰60%的位置（防多径回波锁定，P3-2关键修复）
- 训练序列相关对齐：用完整训练序列做符号级对齐搜索

### 信道估计
- **静态**：训练序列构建Toeplitz → `ch_est_gamp` 或 `ch_est_omp` 等
- **时变(P3-2)**：`ch_est_bem('dct')` 散布导频BEM时变估计，输出h_tv(P×N_tx)每径每时刻增益
  - 导频参数：簇长=max_delay+50, 间隔300, 有效观测~610个
  - 自动Q选择：Q = max(5, 2*ceil(fd*T_frame)+3)
  - iter2+ DD-BEM重估计：BCJR软符号扩展观测集(置信度>0.5门控)

### 多普勒补偿（P3-2更新）
- `comp_resample_spline` V7: 正alpha直接传入（内部pos=(1:N)/(1+α)）
- **残余CFO补偿**：重采样后基带仍残留alpha*fc Hz频偏，须在符号率上去除
- 信道seed不依赖SNR索引（同一信道，只变噪声）

### Turbo均衡（SC-TDE，P3-2 V4.2）
- **静态**：GAMP估计 → turbo_equalizer_sctde(DFE+BCJR) → 0%BER
- **时变**：BEM(DCT) per-symbol MMSE ISI消除 + Turbo BCJR
  - iter 1: 已知位置ISI精确消除 + 未知位置ISI功率建模为噪声 → MMSE单抽头
  - iter 2+: BCJR软符号 → DD-BEM重估计 → 全ISI消除 + MMSE
  - nv_post: 从训练段实测（防高SNR时LLR过度自信）
- **SC-FDE/OFDM跨块Turbo**: LMMSE-IC + DD信道更新 + BCJR

### OTFS均衡（P4 V2.0）
- **LMMSE-BCCB**：2D-FFT对角化，per-frequency MMSE权重，Turbo 3轮
- **UAMP**：Onsager修正+EM噪声估计（研究用，对BCCB无优势）
- **关键发现**：Jakes连续Doppler谱导致BCCB模型失效(50% BER)，离散Doppler(含分数频移)下完美工作
- 实际水声信道(Rician混合K=5~20)与离散模型更匹配，0%@10dB+

### 关键技术结论

1. **散布导频是精度决定性因素**：比算法选择影响大10-20dB
2. **BEM(DCT)+散布导频最优**：高fd下全面优于CE-BEM和DD-BEM
3. **FDE在长时延信道下全面优于TDE**：有5dB编码增益优势
4. **两级分离架构有效**：多普勒估计与精确定时解耦
5. **Jakes ≠ 实际水声信道**：Jakes连续Doppler谱过度悲观，实际水声是Rician混合(离散强径+弱散射)
6. **OTFS在离散Doppler下完美工作**：含分数频移(max 5Hz)→0% BER@10dB+，BCCB模型精确
7. **UAMP对BCCB无优势**：LMMSE per-frequency权重已最优，UAMP Turbo不稳定
8. **Jakes连续谱确认为伪瓶颈(2026-04-13)**：6体制×6信道对比，离散Doppler下全部可工作
9. **离散Doppler下全部6体制可工作**：disc-5Hz/Rician混合信道，高速体制5-10dB达0%BER
10. **SC-TDE在离散Doppler下逆袭**：Jakes ~48%@全SNR → disc-5Hz **0%@5dB+**，改善最大
11. **FH-MFSK唯一全信道可工作**：Jakes也在0dB即0%，跳频分集+能量检测天然抗Doppler

## 已知问题

| 问题 | 状态 | 说明 |
|------|------|------|
| eq_dfe h_est初始化 | 已修复 | V3.1: 匹配滤波初始化前馈+ISI消除初始化反馈 |
| comp_resample_spline方向 | 已修复 | V7: 内部改为pos=(1:N)/(1+alpha)，正alpha直接传入 |
| 残余CFO未补偿 | **已修复(P3-2)** | 重采样后alpha*fc Hz频偏须在符号率上去除 |
| sync多径锁定 | **已修复(P3-2)** | 首达径检测(>60%最强峰)替代最强径检测 |
| SC-FDE/OFDM/SC-TDE去oracle | **代码完成** | V4/V5两级分离架构，已MATLAB验证 |
| fd=5Hz(Jakes) BER瓶颈 | **待重新评估** | Jakes连续谱过度悲观，实际水声Rician混合可能好得多 |
| OTFS通带2D脉冲整形 | 🔴待做 | 减少PAPR尖刺, 升余弦窗+频谱整形 |
| OTFS两级同步架构 | 🔴待做 | 对齐其他体制HFM+LFM帧结构 |
| SC-TDE fd=1Hz优化 | 🔶待优化 | nv_post兜底+时变跳过训练精估 |
| 离散Doppler全体制对比 | 🔴新计划 | apply_channel提取到common, 6体制×6信道BER矩阵 |

## 项目进度概览

| 体制 | 状态 | 说明 |
|------|------|------|
| **SC-TDE** | 🔶 V5.1 LFM同步修复 | static 0%@10dB+, fd=1Hz 0.76%@15dB, fd=5Hz待优化 |
| **SC-FDE** | ✅ V4.0验证 | static 0%, fd=1Hz盲0.20%, fd=5Hz待攻关 |
| **OFDM** | ✅ V4.3固化 | OMP+nv_post+跳过CP+null SC CFO+DD-BEM, 鲁棒架构, fd=1Hz ~1%@15dB+ |
| **OTFS** | ✅ V2.0验证 | 通带+离散Doppler: 0%@10dB+, LMMSE-BCCB+UAMP, Jakes失效 |
| **DSSS** | ✅ V1.0验证 | Rake(MRC)+DBPSK+DCD, 96.8bps, static 0%@-15dB+ |
| **FH-MFSK** | ✅ V1.0验证 | 8-FSK+16位跳频+能量检测, 750bps, fd=5Hz 0%@0dB+ |

**统计**: 186个MATLAB文件, 25830行代码, 205次提交, 30个文档, 13个模块README含完整算法推导+LaTeX公式+断言表

## Language & Conventions

- 主要语言：MATLAB（.m 文件）
- 函数文件命名：小写下划线风格 `ch_est_ls.m`
- 完整中文注释头（功能、版本、输入/输出参数、备注）
- 函数内部按章节分割：`%% 1. 入参解析 → 2. 参数校验 → 3~N. 核心算法`
- 参数校验使用中文错误提示
- 每个模块含 `test_*.m` 单元测试（含可视化）和 `README.md` 文档（含$$LaTeX$$公式）
- Git分支策略：`feat/xxx` 分支开发 → 合并到 `master`

## Cross-Module Dependencies

```matlab
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
```

## Reference Materials

- `wiki/architecture/system-framework.md` — 系统框架文档（v6）
- `raw/notes/framework-history/` — 框架图历史版本（v2~v6 HTML）
- `modules/08_Sync/sync_framework.html` — 三层同步技术框架（帧/符号/位同步）
- `modules/08_Sync/sync_documentation.md` — 同步技术文档（时变信道下）
- `modules/10_DopplerProc/UWA_Doppler_MATLAB_Spec.md` — 多普勒估计补偿规范v2.0
- `modules/12_IterativeProc/turbo_equalizer_implementation.md` — Turbo均衡实现方案
- `refrence/` — 哈工程殷敬伟课题组学位论文 + Turbo_VAMP参考实现
- `D:\ProjectTask\Turbo Equalization/` — SC-TDE工程参考

## 工程闭环（从 ohmybrain-core 派生）

### 目录补充

| 目录 | 职责 |
|------|------|
| `wiki/` | 项目知识层（概念、架构、模块、决策） |
| `specs/active/` | 当前任务 spec（含 Spec+Plan+Log+Result） |
| `specs/archive/` | 已完成任务 |
| `plans/` | 实现计划（可选，大任务使用） |
| `scripts/` | 自动化脚本（lint/sync/validate） |
| `workflows/` | 知识闭环 + 开发闭环流程文档 |
| `.claude/rules/` | 路径特定规则 |
| `.claude/skills/` | 可复用工作流 |
| `.claude/hooks/` | 行为钩子 |

### 开发闭环

```
specs/active/ → plan → 改代码(01~13模块) → 跑测试 → validate → specs/archive/
```

### 知识沉淀

项目级知识写入 `wiki/`，跨项目知识 promote 到 ohmybrain 的 wiki。
