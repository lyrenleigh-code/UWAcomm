# UWAcomm Wiki Index

> 最后更新：2026-04-22
> 页面总数：51（gen_doppler_channel V1.5 + poly_resample 新增；详见 conclusions + log）

## Architecture（架构页）

- [system-framework](architecture/system-framework.md) — 系统框架文档 v6
- [uwacomm-moc](uwacomm-moc.md) — 项目地图（MOC）
- [dashboard](dashboard.md) — 项目仪表盘
- [function-index](function-index.md) — 全模块函数索引

## Modules（模块笔记）

- [01_信源编解码](modules/01_SourceCoding/01_信源编解码.md) + [函数索引](modules/01_SourceCoding/函数索引.md)
- [02_信道编解码](modules/02_ChannelCoding/02_信道编解码.md) + [函数索引](modules/02_ChannelCoding/函数索引.md)
- [03_交织解交织](modules/03_Interleaving/03_交织解交织.md) + [函数索引](modules/03_Interleaving/函数索引.md)
- [04_符号映射判决](modules/04_Modulation/04_符号映射判决.md) + [函数索引](modules/04_Modulation/函数索引.md)
- [05_扩频解扩](modules/05_SpreadSpectrum/05_扩频解扩.md) + [函数索引](modules/05_SpreadSpectrum/函数索引.md)
- [06_多载波变换](modules/06_MultiCarrier/06_多载波变换.md) + [函数索引](modules/06_MultiCarrier/函数索引.md)
- [07_信道估计与均衡](modules/07_ChannelEstEq/07_信道估计与均衡.md) + [函数索引](modules/07_ChannelEstEq/函数索引.md) + [时变调试笔记](modules/07_ChannelEstEq/时变信道估计与均衡调试笔记.md) + [均衡器详解](modules/07_ChannelEstEq/水声信道估计与均衡器详解.md)
- [08_同步与帧结构](modules/08_Sync/08_同步与帧结构.md) + [函数索引](modules/08_Sync/函数索引.md) + [同步调试日志](modules/08_Sync/同步调试日志.md)
- [09_脉冲成形与变频](modules/09_Waveform/09_脉冲成形与变频.md) + [函数索引](modules/09_Waveform/函数索引.md)
- [10_多普勒处理](modules/10_DopplerProc/10_多普勒处理.md) + [函数索引](modules/10_DopplerProc/函数索引.md) + [双LFM-α估计器](modules/10_DopplerProc/双LFM-α估计器.md) + [α补偿pipeline诊断](modules/10_DopplerProc/α补偿pipeline诊断.md) + [大α-pipeline-不对称诊断](modules/10_DopplerProc/大α-pipeline-不对称诊断.md) + [resample-negative-alpha-fix](modules/10_DopplerProc/resample-negative-alpha-fix.md) + `est_alpha_dsss_symbol.m`（Sun-2020）
- [11_阵列接收预处理](modules/11_ArrayProc/11_阵列接收预处理.md) + [函数索引](modules/11_ArrayProc/函数索引.md)
- [12_迭代调度器](modules/12_IterativeProc/12_迭代调度器.md) + [函数索引](modules/12_IterativeProc/函数索引.md)
- [13 函数索引](modules/13_SourceCode/函数索引.md) + [框架v5](modules/13_SourceCode/水声通信算法模块化框架v5.md)
- [SC-TDE调试日志](modules/13_SourceCode/SC-TDE调试日志.md) + [SC-FDE调试日志](modules/13_SourceCode/SC-FDE调试日志.md) + [OFDM调试日志](modules/13_SourceCode/OFDM调试日志.md) + [OTFS调试日志](modules/13_SourceCode/OTFS调试日志.md)
- [端到端帧组装调试笔记](modules/13_SourceCode/端到端帧组装调试笔记.md) + [离散Doppler全体制对比](modules/13_SourceCode/离散Doppler全体制对比.md)
- [14_流式仿真框架](modules/14_Streaming/14_流式仿真框架.md) + [流式调试日志](debug-logs/14_Streaming/流式调试日志.md)

## Concepts（概念页）

## Entities（实体页）

## Topics（专题页）

## Explorations（探索页）

## Comparisons（比较页）

- [e2e-test-matrix](comparisons/e2e-test-matrix.md) — 模块 07 + E2E 全体制 BER 测试矩阵（从 todo.md 迁入）
- [e2e-timevarying-baseline](comparisons/e2e-timevarying-baseline.md) — E2E 时变信道 6 体制基线（688 点 × 4 阶段 × 20 min，2026-04-19）
- `figures/D_*.png` — 恒定 α 估计器诊断图（见 spec `2026-04-19-constant-doppler-isolation.md`，2026-04-19）

## Source Summaries（资料摘要页）

### Doppler 估计与补偿（2026-04-21 摄入，6 篇）

- [yang-2026-uwa-otfs-nonuniform-doppler](source-summaries/yang-2026-uwa-otfs-nonuniform-doppler.md) — UWA OTFS 非均匀 Doppler 建模 + off-grid block-sparse 估计（**OTFS 32% debug 关键参考**，哈工程）
- [zheng-2025-dd-turbo-sc-uwa](source-summaries/zheng-2025-dd-turbo-sc-uwa.md) — DD 域 Turbo 均衡 + 单载波低 PAPR 结合（IEEE JOE 2025）
- [wei-2020-dual-hfm-speed-spectrum](source-summaries/wei-2020-dual-hfm-speed-spectrum.md) — 双 HFM + 速度谱扫描高精度 α 估计（**项目 est_alpha_dual_chirp 思路来源**）
- [muzzammil-2019-cpofdm-doppler-interp](source-summaries/muzzammil-2019-cpofdm-doppler-interp.md) — CP-OFDM 自相关闭式 + 3 种细内插（哈工程）
- [sun-2020-dsss-passband-doppler-tracking](source-summaries/sun-2020-dsss-passband-doppler-tracking.md) — DSSS 符号级通带 Doppler 跟踪（哈工程）
- [lalevee-2025-dichotomic-doppler-fpga](source-summaries/lalevee-2025-dichotomic-doppler-fpga.md) — 滤波器组二分搜索 FPGA 实现（OCEANS 2025）
