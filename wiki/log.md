# Wiki 操作日志

## 2026-04-17

- 新增 `comparisons/e2e-test-matrix.md`：从 `todo.md` 迁入模块 07 统一测试结果、E2E 逐体制验证表、离散 Doppler 全体制对比矩阵、均衡器调试发现
- `todo.md` 瘦身 333 → ~120 行：去除与 `conclusions.md` 重复的 13 条"关键技术结论"，测试表格迁至 wiki
- `todo.md` 调试路径从 `D:\Obsidian\workspace\UWAcomm\{模块}` 改为 `wiki/debug-logs/{模块}/`（与 CLAUDE.md 对齐）
- UWAcomm `CLAUDE.md` 第 197 行 `refrence/` 拼写修正为 `reference/`，物理目录同步重命名
- **P3 demo UI 深色科技风 V2 视觉升级（4 step 完成）**：新增 8 个 ui/ helper（p3_style / p3_pick_font / p3_semantic_color / p3_metric_card / p3_sonar_badge / p3_animate_tick / p3_plot_channel_stem / p3_style_axes）；顶栏声纳 badge、TX/RX 头像、info bento、tab Unicode、呼吸灯/flash 动效；spec `2026-04-17-p3-demo-ui-polish.md`
- **SC-FDE convergence_flag 误判修复（14_Streaming/rx/modem_decode_scfde.m V2.1.0）**：三选一判据（med_llr>5 / 硬判决稳定 / 高置信 LLR>70%）+ 去除 `10*log10(sps)` 错误减法。conv 从 0 恢复为 1，est_snr 从 4.9dB 恢复为 13.9dB（真实 15dB），BER=0 保持，test 2/2 PASS。调试细节追加至 `modules/13_SourceCode/SC-FDE调试日志.md`，结论 27-29 入 `conclusions.md`
- `function-index.md` 新增 `14_Streaming/ui/` helper 清单（11 项含既有 + 新增）
- 清理 UWAcomm 全域 34 份 `test_*_results.txt` 临时产物（已在 `.gitignore` 中）
- **项目级代码梳理**：14 模块 261 .m 全量 mlint（387 警告分类）；HIGH 70 条审核为误报/设计（if false 占位、try/catch 单行）；MEDIUM 批量替换 `caxis → clim` 9 条；LOW 215 条（变量大小 / 未使用赋值）留待后续重构
- `modules/07_ChannelEstEq/src/Matlab/README.md` 文件数 41→48，补入 OTFS/TV 均衡 5 个新函数（ch_est_otfs_{zc,superimposed} / eq_otfs_{lmmse,uamp} / eq_mmse_ic_tv_fde / eq_rake）分类到 OTFS 估计 / OTFS 均衡 / FDE 均衡 / TDE 均衡小节
- `wiki/function-index.md` 同步补入上述 6 个函数；删除 `MMSE`/`OTFS` 两条误条目；顶部统计更新（13→14 模块，261 文件）；加入 14_Streaming 模块概览行
- `modules/14_Streaming/README.md` 的 amc/ 目录标注 "[P6 占位，待实现]" + 关联 spec
- 再次清理 UWAcomm 全域 16 份中间 test diary txt（_v2/_v3/_v4/_debug/_diag 等）；删除 sessions/ 下 248 个旧会话（保留最近 5 个，~1GB 释放）
- **P3 demo 真同步 + 两个可视化 tab 完成**（spec `2026-04-17-p3-demo-ui-sync-quality-viz.md`）：
  - Step 0 新建 `common/detect_frame_stream.m`（152 行）：passband FIFO HFM+ 匹配滤波帧检测器，替代 `frame_start_write` 共享捷径。单元测试 `tests/test_detect_frame_stream.m` AWGN -5~15dB / 多径 6/6 PASS，偏差 ≤1 样本
  - Step 1 扩展 6 个 `modem_decode_*.m` info 字段：SC-FDE/OFDM/SC-TDE 加 sym_off_corr/best；FH-MFSK 加 hop_peaks/hop_pattern/snr_per_sym；DSSS 加 chip_off_corr + rake_finger_delays/gains；OTFS 加 dd_path_info
  - Step 2 新建 `ui/p3_render_quality.m`（118 行）+ Quality tab：BER 语义染色散点 + SNR/iter 双 Y 轴
  - Step 3 新建 `ui/p3_render_sync.m`（152 行）+ Sync tab：HFM+/- 匹配滤波曲线 + scheme 分支符号级（Turbo corr / FH-MFSK hop / DSSS rake / OTFS DD path）+ 同步偏差轨迹
  - UI 底部 tab 6 → 8；test_p3_unified_modem 2/2 PASS

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
