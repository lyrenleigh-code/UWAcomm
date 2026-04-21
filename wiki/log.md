# Wiki 操作日志

## 2026-04-22

- **`comp_resample_spline` V7.1 α<0 本征不对称修复**
  - spec: `specs/active/2026-04-22-resample-negative-alpha-asymmetry.md`
  - 诊断脚本：`modules/10_DopplerProc/test_resample_doppler_error.m`（单元表征）
  - 根因：V7.0 `pos_clamped = min(pos, N)` 在 α<0 时尾部 |α|·N 样本全被 clamp 到 y(N)，
    QPSK-RRC |α|≥1e-2 NMSE +α vs -α 差 75-83 dB（单元级），尾部 RMS 暴涨 4 个数量级
  - 修复：V7.1 单处 5 行 patch，检测 `pos_max > N` 时内部 zero-pad y 尾部
  - 验证：单元 NMSE 差异 75-83→<3 dB；D 阶段 SC-FDE α=-3e-2 BER 2.66%→**0%**；
    OFDM/DSSS/FH-MFSK 首次 D α 扫描完成（65 行 CSV）
  - 回流：`wiki/modules/10_DopplerProc/resample-negative-alpha-fix.md` + conclusions.md 新条目
  - 历史：闭合 2026-04-20~21 多次"α<0 非对称，疑似 spline/尾部"诊断循环的真根因

- **P4 真实多普勒 fork + gen_doppler_channel V1.1 相位修复（调试中）**
  - spec: `specs/active/2026-04-22-p4-real-doppler-fork.md`，plan 同名
  - 已完成：P3 refactor 收尾（Step 2+3，主文件 1832→1359）+ P4 fork 16 文件 + 接入 gen_doppler_channel
  - 发现 V1.0 bug：基带相位公式 `α·fs·t`（fs/fc=4× 过快） → P4 dop=12Hz 实际等价 P3 dop=48Hz → 碰 4-20 诊断的 24Hz 断崖
  - V1.1 修复：新增 `fc` 可选参数，相位改 `2π·fc·cumsum(α_t)/fs`，t_stretched 起点 0，`snr_db=Inf` 跳过内部加噪
  - 单元 case 6 通过；UI 实测待用户数据
  - 诊断工具：`tests/diag_p4_doppler_isolate.m`（DC 基带 FFT 峰位 + MATLAB 缓存 + t_stretched 对齐 + paths roundtrip）
  - 回流：`wiki/debug-logs/14_Streaming/流式调试日志.md` 坑 8

- **DSSS 符号级 Doppler 跟踪（Sun-2020）**（spec `2026-04-22-dsss-symbol-doppler-tracking.md`）
  - 新模块：`est_alpha_dsss_symbol.m`（Sun-2020 JCIN 2020）+ `comp_resample_piecewise.m`
  - 原理：相邻 Gold31 peak 时差 → 瞬时 α；三点余弦内插 + IIR 平滑
  - DSSS runner 加 `doppler_track_mode='block|symbol|symbol_per_sym'` 开关
  - 关键数字：**D α=+3e-2 BER 51% → 2.2%**（25× 改善）；A2/D |α|≤3e-3 维持 0%
  - 对比：均值 resample 优于逐符号（静态 α 下 per-sym boundary 不连续）
  - 遗留：α=±1e-2 改善有限（需 adaptive Gold31 bank）、α=-3e-2 仍 35%

## 2026-04-21

- **α 推广 4 体制（3/4 成功）**（spec `2026-04-21-alpha-refinement-other-schemes.md`）
  - OFDM: A2 全 0%, D |α|≤1e-2 全 0%, α=+3e-2 BER 11.4%
  - DSSS: A2 全 0%, D |α|≤3e-3 全 0%（扩频固有限制 α≥1e-2）
  - FH-MFSK: A2 全 0%, D |α|≤1e-2 **全 0%**（新增 α 补偿，原无）
  - SC-TDE: 失败（α≠0 下游敏感，BER 50%），留独立 spec
  - 关键 patch 差异：OFDM CP 精修禁用（空子载波 CFO 接替），FH-MFSK 新增 α 补偿
  - 覆盖：A2/A3/D（timevarying runner），discrete_doppler 未改（B 阶段旧 baseline）

- **大 α pipeline 诊断 + α=3e-2 突破**（spec `2026-04-21-alpha-pipeline-large-alpha-debug.md`）
  - 新 wiki：`wiki/modules/10_DopplerProc/大α-pipeline-不对称诊断.md`
  - 诊断脚本：`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline_large.m`
  - 中断的 VSS spec：`specs/active/2026-04-21-hfm-velocity-spectrum-refinement.md`（保留 est_alpha_dual_hfm_vss 代码 + 单元测试作未来入口）
  - **关键发现**：Oracle α=±3e-2 下 BER=0%（pipeline 完全正常）；根因是 estimator 2% 系统偏差 × CP 精修 wrap，迭代无法突破
  - **修复（3 patch）**：TX 默认 tail pad + CP 精修阈值门禁 + 正向大 α 精扫
  - **结果**：α=+3e-2 BER **50% → 5.4%**，α=-3e-2 3% → 0%，|α|≤1e-2 全 0% 维持
  - **工作范围扩展 1e-2 → 3e-2**（15→45 m/s，鱼雷/高速 AUV 覆盖）

- **OTFS 32% BER 根因定位**（spec `2026-04-21-otfs-disc-doppler-32pct-debug.md`）
  - 新 wiki：`wiki/modules/13_SourceCode/OTFS调试日志.md`
  - 诊断脚本：`modules/13_SourceCode/src/Matlab/tests/OTFS/diag_otfs_32pct.m`
  - 诊断数据：`diag_results/otfs_32pct_diag.mat` + `.txt`
  - **关键发现**：32% BER 根因是 `pilot_mode='sequence'` 在 SNR=10dB 下的 regression，
    不是离散 Doppler 非均匀性问题（H4 Yang 2026 理论证伪）
  - 结果（均值，SNR=10dB）：impulse **0-0.04%**，sequence **28-32%**，superimposed 0-0.4%
  - 修复：`test_otfs_timevarying.m:20` 默认回滚 `impulse`；补 `10_DopplerProc` addpath
  - conclusions.md 新增 #38，#37 补撤销说明

- **摄入 6 篇 Doppler 论文**（/ingest 批量）
  - [[yang-2026-uwa-otfs-nonuniform-doppler]] — UWA OTFS 非均匀 Doppler 建模 + off-grid block-sparse 估计（IEEE JOE 2026，哈工程）— **OTFS 32% BER debug 的关键理论参考**，直接解释离散 Doppler 下径间 Δν 导致 on-grid 假设失败
  - [[zheng-2025-dd-turbo-sc-uwa]] — DD 域 MMSE Turbo 均衡 + 单载波低 PAPR（IEEE JOE 2025）— 潜在 `turbo_equalizer_scfde` 升级路径
  - [[wei-2020-dual-hfm-speed-spectrum]] — 双 HFM + 速度谱扫描（IEEE SPL 2020）— 项目 `est_alpha_dual_chirp` 思路来源正式引用
  - [[muzzammil-2019-cpofdm-doppler-interp]] — CP-OFDM 自相关闭式 + 3 种细内插（ICICSP 2019，哈工程）— 对应 `est_doppler_cp` 理论支撑
  - [[sun-2020-dsss-passband-doppler-tracking]] — DSSS 符号级通带 Doppler 跟踪（JCIN 2020，哈工程）— 未来 DSSS 时变改造参考
  - [[lalevee-2025-dichotomic-doppler-fpga]] — 滤波器组二分搜索 FPGA 实现（OCEANS 2025）— 工程实现参考（低优先）

## 2026-04-20

- **α 补偿 Pipeline 诊断 + 迭代 α refinement（SC-FDE）**（spec `2026-04-20-alpha-compensation-pipeline-debug.md`）
  - 新 wiki：`wiki/modules/10_DopplerProc/α补偿pipeline诊断.md`
  - 新图：`figures/D_*_after_iter.png`（3 张，与 before/mvp 对比）
  - 诊断脚本：`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline.m` + 8 节点插桩 + 10 toggle
  - 根因定位：**CP 精修 ±2.4e-4 相位模糊阈值** + estimator 14% 系统误差
  - 修复：runner 内加 2 次迭代 est_alpha_dual_chirp
  - 关键数字：**SC-FDE α=2e-3 BER 47% → 0%**；工作范围从 1e-3 到 **1e-2**（15 m/s 快艇覆盖）

- **双 LFM α 估计器改造落地（SC-FDE）**（spec `2026-04-20-alpha-estimator-dual-chirp-refinement.md`）
  - 新模块 `modules/10_DopplerProc/src/Matlab/est_alpha_dual_chirp.m` + 单元测试（9/9 核心范围 PASS）
  - SC-FDE 帧结构 LFM2 改为 down-chirp，guard 扩展；α 估计入口切换
  - 新 wiki：`wiki/modules/10_DopplerProc/双LFM-α估计器.md`
  - D/A2 before/after 对比图：`figures/D_{alpha_est_vs_true, alpha_rel_error, ber_vs_alpha}_{before,after}.png`
  - 关键数字：A2 α=5e-4 BER **48.7% → 0%**，α=1e-3 **49% → 2%**（SNR=10dB）
  - 遗留：α<0 不对称、α>1e-3 BEM 外推不动、α∈[1e-2,3e-2] 边界，留后续 incremental

## 2026-04-19

- **恒定多普勒 α 估计器诊断**（spec `2026-04-19-constant-doppler-isolation.md`）
  - 复用 E2E benchmark 扩 stage D：α=13 点 × SNR=10dB × SC-FDE，29.7s
  - 新 PNG：`figures/D_{alpha_est_vs_true, alpha_rel_error, ber_vs_alpha}.png`
  - **surprising finding**：α 估计**全部失效** — 所有非零 α 估成 ~1e-5 噪声，误差 ≈ α_true
  - 根因：LFM1/LFM2 是**同一波形**，双 LFM 相位法对 α 数学上不灵敏；真正估 α 应该用双 HFM（up+down chirp）时延差
  - 下一步：升格 spec `2026-04-20-lfm-alpha-estimator-refinement.md` 走 est_alpha_dual_hfm 改造路径

- **E2E 时变信道 6 体制基线 benchmark 完成**（spec `2026-04-19-e2e-timevarying-baseline.md`，S1+S2+S3 推进）
  - 新增 `wiki/comparisons/e2e-timevarying-baseline.md` + 10 PNG
  - 4 新工具：`tests/benchmark_e2e_baseline.m` + `bench_run_single` + `bench_build_fading_cfgs` + `bench_get_fft_params`
  - 4 阶段扫描：A1 Jakes (180 pts, 4.7 min) / A2 固定α (100 pts, ~3 min) / A3 2D (288 pts, 9.0 min) / B 离散 (120 pts, 3.1 min)
  - 688 组合 0 失败，关键发现：**OTFS 在 B 离散信道独自卡 32% BER，其他 5 体制全通**；SC-FDE/OFDM/SC-TDE 对 Jakes fd≥1Hz 和固定 α≥5e-4 全崩；FH-MFSK 跨 fd/α 域最抗时变

- **P3 UI OTFS 采样率桥接完成**（spec `2026-04-19-p3-otfs-sampling-bridge.md` 归档）
  - Step 1: `modem_encode_otfs` V2.0.0 加 RRC 上采样（sym_rate → fs）
  - Step 2: `modem_decode_otfs` V2.0.0 匹配滤波 + 本地 pilot 参考的符号定时 + 下采样
  - Step 3: UI dropdown 恢复 OTFS；sys_params_default 加 `sys.otfs.rolloff/span`
  - 回归 7/7 PASS（test_p3_unified_modem 2/2 + test_p3_2_ofdm_sctde 2/2 + test_p3_3_dsss_otfs 3/3）
  - OTFS body_bb 从 3072 样本 @ 6kHz → 24608 样本 @ 48kHz，与其他 5 体制接口统一

- **高优先算法实施（HP1/HP2/HP3）**
  - HP1 `eq_bem_turbo_fde` V2.0.0 真去 Oracle：h_time_block_oracle → h_est_block1；
    Q 保守上界估计（取 fd_est_from_hest vs fd_hz_max*0.1 最大值）；判决引导 LS 逻辑保留
  - HP2 `rx_chain.rx_otfs` 分路：加 `params.rx.otfs_mode='real'` 入口 + rx_otfs_real 骨架
    （error 抛指向 test_otfs_timevarying 为参考）；oracle baseline 路径保留
  - HP3 OTFS 两级同步架构：审查发现 `frame_assemble/parse_otfs` V2.0.0 已落地 + 
    test_otfs_timevarying 已迁移（use_oracle=false 默认）；补填 Result 并归档 spec
- P3 demo UI 加入 OTFS scheme dropdown（current_scheme 后端已支持）
- test_p3_3_dsss_otfs 3/3 PASS 回归验证

- **全项目 Code Review + 修复完成**（5 个并行 Agent 审计 + 4 批修复）
  - Batch A（极低代价）：5 个 turbo_equalizer_* 加 `La_dec_info = Le_dec_info` 反馈；OFDM est_snr 去 sps 减法；comp_resample_farrow V4→V5 方向统一
  - Batch B（局部修复）：新建 `common/decode_convergence.m` 三选一判据 helper，扩散到 modem_decode_{ofdm,sctde,otfs}.m；LDPC LLR 符号对齐；07 README OTFS 均衡器签名修正
  - Batch C（接口变更）：`eq_bem_turbo_fde` h_time_block→h_time_block_oracle + 显眼警告；`rx_chain.rx_otfs` 多重 Oracle 显式标注
  - Batch D（Turbo 理论）：`turbo_decode` Lc 缩放外提循环；`siso_decode_conv` V3.1.0 加 tail_mode 参数（'zero'/'unknown'）
- 全量回归：test_p3_unified_modem 2/2 + test_p3_2_ofdm_sctde 2/2 + test_p3_3_dsss_otfs 3/3 = **7/7 PASS**
- conclusions.md 追加结论 30-36（6 条本次修复）

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
