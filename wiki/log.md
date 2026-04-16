# Wiki 操作日志

## 2026-04-16

- P3.1 UI V3.0 重构：解码历史(20条)+信道时/频域拆分+日志 tab+TX 信号信息面板+音频监听
- P3.1 SC-FDE 三个 bug 修复：零填充→随机填充、σ²_bb 公式 4→8、NV 实测覆盖兜底化
- P3.1 SC-FDE 重构：手写 Turbo 循环改调 turbo_equalizer_scfde_crossblock（模块 12）
- P3.2 完成：OFDM + SC-TDE 统一 modem API
  + modem_encode/decode_ofdm: OMP(静态)/BEM(时变)+空子载波 CFO+Turbo MMSE-IC
  + modem_encode/decode_sctde: GAMP+turbo_sctde(静态)/BEM+逐符号 ISI 消除(时变)
  + dispatch 扩展到 4 体制，UI scheme 下拉同步更新
- 14_流式仿真框架.md 追加 P3.1 调试记录 + V3 UI 功能更新

## 2026-04-15

- 新增 `modules/14_Streaming/14_流式仿真框架.md`，P1 + P2 完成补完整实施记录
- conclusions.md 加 #20–22（流式框架方案A、Doppler漂移、MATLAB链式赋值陷阱）
- conclusions.md 加 #23–26（流式 hybrid 检测、软判决 LLR、FH-MFSK ISI 限制、LPF 暖机）
- 新增 `wiki/debug-logs/14_Streaming/流式调试日志.md` (P1+P2 实施期 7 个调试坑记录)
- function-index.md 加 14_Streaming 全 25 个函数索引
- P3.1 完成：14_Streaming 加入 `modem_dispatch / modem_encode / modem_decode` 统一 API
  + SC-FDE encode/decode 抽取；FH-MFSK 适配；test_p3_unified_modem 双体制 0%@5dB+ 通过
- 14_流式仿真框架.md 追加 P3.1 实施记录

## 2026-04-14

- conclusions.md 新增结论 #4（模块07 doppler_rate 基线）、#8（nv_post 兜底）、#9（时变跳过训练精估）

## 2026-04-13

- 初始化 wiki 目录结构，对齐 ohmybrain-core 模板
