# UWAcomm 水声通信算法开发进度

> 框架参考：`raw/notes/framework-history/framework_v6.html`
> Turbo 均衡方案：`modules/12_IterativeProc/turbo_equalizer_implementation.md`
> 调试记录：`wiki/debug-logs/{模块名}/`
> 测试结果矩阵：`wiki/comparisons/e2e-test-matrix.md`
> 关键技术结论：`wiki/conclusions.md`
> 6 种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 开发量统计（2026-04-19）

| 指标 | 数值 |
|------|------|
| MATLAB 函数文件 | 266 个 |
| 代码总行数 | 39,821 行 |
| 文档文件 (md+html) | 40+ 个 |
| Git 提交数 | 226 次 |
| README 文档总行数 | ~6000 行（含算法推导+断言表+LaTeX 公式） |
| 模块数 | 14 个（13 算法模块 + 1 流式仿真框架） |

---

## 各模块状态

| 模块 | 文件夹 | 文件数 | 状态 |
|------|--------|--------|------|
| 01 信源编解码 | `01_SourceCoding/` | 5 | ✅ Huffman+均匀量化, 14 项测试全通过 |
| 02 信道编解码 | `02_ChannelCoding/` | 12 | ✅ SISO (BCJR max-log/log-map/sova) + tail_mode 参数 |
| 03 交织/解交织 | `03_Interleaving/` | 8 | ✅ |
| 04 符号映射/判决 | `04_Modulation/` | 6 | ✅ |
| 05 扩频/解扩 | `05_SpreadSpectrum/` | 17 | ✅ 18 项测试+可视化 (V1.1) |
| 06 多载波+CP | `06_MultiCarrier/` | 19 | ✅ 含 OTFS per-sub-block CP |
| 07 信道估计与均衡 | `07_ChannelEstEq/` | 48 | ✅ 含 OTFS LMMSE/UAMP/MP/ZC/Superimposed + Rake + MMSE-IC-TV-FDE |
| 08 同步+帧组装 | `08_Sync/` | 22 | ✅ 三层同步（帧/符号/位）, sync_dual_hfm V1.1 |
| 09 脉冲成形/变频 | `09_Waveform/` | 9 | ✅ 19 项测试+可视化 (V1.1) |
| 10 多普勒处理 | `10_DopplerProc/` | 15 | ✅ comp_resample farrow V5+spline V7 统一方向 |
| 11 阵列预处理 | `11_ArrayProc/` | 8 | ✅ |
| 12 Turbo 迭代调度 | `12_IterativeProc/` | 7 | ✅ 5 均衡器 + La_dec_info 反馈修复 |
| 13 端到端仿真 | `13_SourceCode/` | 27 | 🔶 6 体制 E2E 完成；rx_otfs oracle 已标注但未重写 |
| 14 流式仿真框架 | `14_Streaming/` | 58 | ✅ P1-P3 完成 + 真同步 + 深色科技风 UI + 8 tab 可视化 |

---

## 逐体制状态概览

> 详细 BER 表格见 `wiki/comparisons/e2e-test-matrix.md`

| 体制 | 版本 | 状态 | 备注 |
|------|------|------|------|
| SC-FDE | V4.0 + V2.1.0（14/rx） | ✅ | 两级分离架构；convergence 三选一判据 + est_snr 修复 |
| OFDM | V4.3 + est_snr 修复 | ✅ | OMP + nv_post + 跳过 CP + 空子载波 CFO + DD-BEM；去 sps 减法 |
| SC-TDE | V5.2 | ✅ | 时变跳过训练精估+nv_post 兜底 |
| OTFS | V2.0 | ✅ | 通带+离散 Doppler（含分数）0%@10dB+，Rician 混合 K=5~20 |
| DSSS | V1.0 | ✅ | Rake(MRC)+DBPSK+DCD，96.8bps，static 0%@-15dB+ |
| FH-MFSK | V1.0 | ✅ | 8-FSK+16 位跳频+能量检测，750bps，唯一全信道可工作 |

---

## 算法版本固化

| 函数 | 版本 | 状态 | 说明 |
|------|------|------|------|
| ch_est_bem | V2.0.0 | ✅ | 向量化重构+可选 BIC+自适应正则化 |
| ch_est_bem_dd | V1.0.0 | ✅ | DD-BEM 判决辅助迭代精化 |
| ch_est_tsbl | V2.0.0 | ✅ | T-SBL 多快照联合稀疏 |
| ch_est_sage | V1.0.0 | ✅ | SAGE 联合时延+增益+多普勒 |
| ch_track_kalman | V1.0.0 | ✅ | 稀疏 Kalman AR(1) |
| ch_est_otfs_dd | V2.0.0 | ✅ | 自适应阈值（静态 3σ/时变 1σ） |
| ch_est_otfs_zc | V1.0.0 | ✅ | ZC 序列导频 DD 信道估计 |
| ch_est_otfs_superimposed | V1.0.0 | ✅ | 叠加导频共享 DD 网格 |
| eq_dfe | V3.1.0 | ✅ | h_est 初始化 |
| eq_lms | V1.1.0 | ✅ | 修复 DD QPSK 判决 |
| eq_mmse_ic_fde | V2.0.0 | ✅ | Turbo 核心 |
| eq_mmse_ic_tv_fde | V1.0.0 | ✅ | 时变 Turbo+ICI 消除 |
| eq_otfs_lmmse | V1.1.0 | ✅ | BCCB 2D-FFT 对角化 |
| eq_otfs_uamp | V1.0.0 | ✅ | Onsager 修正+EM 噪声 |
| eq_rake | V1.0.0 | ✅ | DSSS Rake 合并 |
| **eq_bem_turbo_fde** | **V1.1.0** | ⚠️ | 加 Oracle 警告（未真去 oracle，详见下方待办） |
| turbo_equalizer_scfde | V1.1.0 | ✅ | **La_dec_info 反馈修复（2026-04-19）** |
| turbo_equalizer_ofdm | V1.1.0 | ✅ | La_dec_info 反馈修复 |
| turbo_equalizer_sctde | V8.1.0 | ✅ | DFE iter1 + La_dec_info 反馈 |
| turbo_equalizer_otfs | V3.1.0 | ✅ | MP/UAMP + La_dec_info 反馈 |
| turbo_equalizer_scfde_crossblock | V1.1.0 | ✅ | 跨块 Turbo + La_dec_info 反馈 |
| **turbo_decode** | **V1.1.0** | ✅ | Lc 缩放外提迭代循环（2026-04-19 性能优化） |
| **siso_decode_conv** | **V3.1.0** | ✅ | 加 tail_mode 参数（'zero' / 'unknown'）|
| sync_detect | V2.0.0 | ✅ | 含 doppler 方法 |
| sync_dual_hfm | V1.1.0 | ✅ | α 公式修正 |
| phase_track | V1.0.0 | ✅ | PLL/DFPT/Kalman |
| comp_resample_spline | **V7.1.0** | ✅ | 正 α = 时间压缩；**V7.1（2026-04-22）新增 α<0 auto-pad，单元 NMSE 对称性 75-83→<3 dB** |
| **comp_resample_farrow** | **V5.0.0** | ✅ | 方向统一（2026-04-19 代码审查 HIGH-3 修复） |
| **decode_convergence** | **V1.0.0** | ✅ | 三选一收敛判据 helper（新建，供全体 decoder 扩散） |
| **detect_frame_stream** | **V1.0.0** | ✅ | P3 流式 HFM+ 匹配滤波帧检测（本次新建） |
| test_channel_est_eq | V2.0.0 | ✅ | 24 项测试+6 张可视化 |

---

## 活跃 TODO

### 🔴 高优先

| 任务 | 状态 | 说明 |
|------|------|------|
| **L5/L6 ch_est_gamp V1.1→V1.4 修复链 + SNR 受限归档** | 2026-04-23 | 修订：真根因是 `ch_est_gamp.m`（不是 BEM，static 路径走 GAMP）；V1.1 divergence guard+LS fallback / V1.2 双跑 / V1.3 CV 撤回 / V1.4 偏 LS 0.8；30 seed Monte Carlo: 灾难率 10% → 0%/6.7%；残余 2/30 验证 SNR=15 恢复 0% → 边界 limitation，非 bug |
| ~~**（可选）static 路径换 `ch_est_ls`/`ch_est_omp` 替代 GAMP**~~ | ❌ 试败（2026-04-23） | spec `2026-04-23-scfde-omp-replace-gamp-and-oracle-clean.md`；OMP K=6 反而 +1e-2 灾难率 6.7%→10%（残差驱动选错 support）；保留作 `tog.use_omp_static` toggle，默认仍 GAMP V1.4 |
| **SC-FDE sps 相位选择真去 oracle**（架构改动） | 🟡 待开 | 试错 3 次（spec `archive/2026-04-23-scfde-omp-...` Phase B + spec `archive/2026-04-23-scfde-sps-deoracle-fourth-power`）：(1) `sum(\|st\|²)` 功率最大化失败 (2) `abs(sum(st^4))` QPSK 4 次方失败；纯 NDA blind 在 6 径 ISI + SNR=10 失效；下一轮试 LFM 模板尾部相关 / 帧加 training preamble / Gardner TED+量化；架构改动需独立 spec |
| **rx_chain.rx_otfs 真重写（main_sim_single 改造）** | 骨架占位 | rx_otfs_real 已加入 switch 路径但未实现；需 main_sim_single 开启真实 passband + 信道 + rx_otfs_real 填充。独立 spec 待创建 |
| ~~**OTFS 离散 Doppler 32% BER 专项 debug**~~ | ✅ 2026-04-21 | 根因 = `pilot_mode='sequence'` regression（非 Doppler 问题）。回滚 default → impulse，3 信道 × 3 trial BER 0-0.04%。详见 `wiki/modules/13_SourceCode/OTFS调试日志.md` |
| ~~**α 补偿推广到其他 4 体制**~~ | 🟡 部分完成（2026-04-21） | OFDM/DSSS/FH-MFSK 推广成功（A2 全 0%，D |α|≤1e-2 大部分工作）；SC-TDE 失败（下游 α 敏感，独立 spec 待开） |

### 🟡 中优先

| 任务 | 状态 | 说明 |
|------|------|------|
| **P3 demo Doppler 链路接入** | 待做 | `app.doppler_edit` 字段 UI 有但 TX 链路未用；spec 预占位 `2026-04-18-p3-doppler-integration.md`（待创建） |
| **α estimator 符号约定参数化** | 待做 | `est_alpha_dual_chirp` 当前与 `gen_uwa_channel.doppler_rate` 反号，runner 里 hack `-alpha_lfm_raw`；建议在 estimator 内加 `sign_convention` 参数 |
| ~~**α<0 不对称修复**（resample 层）~~ | ✅ 2026-04-22 | spec `2026-04-22-resample-negative-alpha-asymmetry.md`；根因 = `comp_resample_spline` 边界 clamp；V7.1 auto-pad 解决；单元 NMSE 差异 75-83→<3 dB，SC-FDE α=-3e-2 BER 2.66%→0%。**下游链路不对称**（DSSS/FH-MFSK/OFDM α 符号敏感）属独立 spec |
| ~~**α=3e-2 物理极限突破**~~ | ✅ 完成（2026-04-21） | 诊断显示 Oracle 下 pipeline 无问题，根因是 estimator 2% 系统偏差 + CP wrap；3 patch 修复让 α=+3e-2 BER 50% → 5.4%，工作范围扩到 15→45 m/s |
| **14_Streaming 去 Oracle α**（推广 13 的盲估计） | 待做 | 14_Streaming/P2/P3 仍 oracle α（从 chinfo 读），需将 13_SourceCode 的双 LFM + 迭代推广，属 `2026-04-16-deoracle-rx-parameters` 范畴 |
| **SC-FDE runner oracle 清理** | 待做 | `test_scfde_timevarying.m:229` 仍用 `all_cp_data(1:10)` 做 sps 相位选择，属 §7 oracle 泄漏 |
| **E2E benchmark C 阶段（多 seed 检测率）** | 待做 | 需让 `bench_seed` 驱动 runner 内 rng，改 11 runner 的 rng 调用 |
| **E2E benchmark profile 扩展** | 待做 | 当前仅 custom6，需 runner 支持 `bench_channel_profile` 切换 ch_params（exponential 等） |
| **E2E benchmark NMSE/sync/turbo iter 填充** | 待做 | CSV schema 有字段但本期全 NaN，需 runner 暴露 h_est / sync_tau_err / 逐轮 BER |
| **p3_demo_ui.m refactor Step C** | 进行中 | 主文件 1649→≤900 行（嵌套函数物理分段），spec `2026-04-17-p3-demo-ui-refactor.md` |
| **OTFS 通带 2D 脉冲整形 Phase 4** | Phase 2 完成 | 端到端 BER 验证待做；spec `2026-04-13-otfs-pulse-shaping.md` |
| **OTFS PAPR 专项降低** | 待做 | 需 SLM/PTS/削峰等专用技术 |
| **OTFS 扩散 pilot** | 待做 | spec `2026-04-14-otfs-spread-pilot.md` |
| **14_Streaming P4** | 待 P3 真同步验收 | 帧头 FH-MFSK + payload 按 scheme 分发 |
| **14_Streaming P5** | 待 P4 | TX/Channel/RX 三进程并发 |
| **14_Streaming P6** | 待 P5 | 物理层 AMC（link quality → scheme 自适应）；`amc/` 目录已占位 |

### 🟢 低优先（技术债）

| 任务 | 状态 | 说明 |
|------|------|------|
| **`poly_resample` 去 Signal Toolbox 依赖** | 📌 parked（2026-04-22） | 手写 polyphase（h 按 phase 拆 p 个子滤波器，逐输出样本点积）+ 手写 Kaiser 窗（`besseli(0,·)`）。纯 base MATLAB，O(N) 峰值内存，速度 ≈ upfirdn 的 1/2-1/3。**目前不做**，等有"纯 base 需求"触发时再起 spec。|
| **mlint LOW 215 条** | 待做 | 变量预分配 / 未使用赋值，风险大收益小，留重构时统一处理 |
| **其他 05/06/07 的 HIGH/MEDIUM 修复** | 部分 | code review 报告中还有 SC-FDE FFT 归一化、LDPC 符号、OTFS O(M²) 等未修；评估必要性再做 |
| **13 下 test 文件 500+ 行拆分** | 待做 | `test_otfs_timevarying.m` 788 行最重 |

### ✅ 近期完成里程碑

| 任务 | 完成日期 | 备注 |
|------|---------|------|
| 离散 Doppler 信道全体制对比 | 2026-04-13 | 6 体制 × 6 信道 BER 矩阵 |
| SC-TDE V5.2 优化 | 2026-04-14 | 时变跳过训练精估+nv_post 兜底 |
| 14_Streaming P1（FH-MFSK loopback + GUI） | 2026-04-15 | passband 信道 + Jakes 时变 |
| 14_Streaming P2（流式帧检测 + 多帧） | 2026-04-15 | hybrid 检测，软判决 LLR |
| 14_Streaming P3.1（统一 modem API + FH-MFSK + SC-FDE） | 2026-04-16 | `modem_dispatch` 架构 |
| 14_Streaming P3.2（OFDM + SC-TDE） | 2026-04-16 | 静态 6 径 0%@15dB+ |
| 14_Streaming P3.3（DSSS + OTFS） | 2026-04-16 | Gold31 Rake+DCD + DD 域 LMMSE Turbo |
| 去 Oracle — RX 盲估计（14_Streaming） | 2026-04-16 | decode 层全部清理，7/7 PASS |
| **P3 demo UI 深色科技风 V2（4 step）** | **2026-04-17** | 声纳 badge + metric card bento + tab Unicode + 呼吸灯动效 |
| **SC-FDE convergence 修复** | **2026-04-17** | 三选一判据 + est_snr 偏低 10dB 修复 |
| **P3 真同步 + Quality/Sync tab** | **2026-04-17** | `detect_frame_stream` 替代 cheat，UI 6→8 tab |
| **全项目 code review + 4 批修复** | **2026-04-19** | 5 Agent 并行审计；Turbo La_dec_info / Doppler 方向 / convergence 扩散 / Oracle 标注等 10 条 |
| **根 README 更新对齐代码状态** | **2026-04-19** | 规模/架构/快速开始/项目状态同步 |
| **eq_bem_turbo_fde V2.0.0 真去 Oracle** | 2026-04-19 | h_time_block_oracle → h_est_block1；Q 保守上界估计 |
| **P3 UI 加 OTFS dropdown** | 2026-04-19 | scheme_dd 增加 OTFS 选项，后端 current_scheme 已支持 |
| **OTFS 两级同步架构（spec 归档）** | 2026-04-19 | frame_assemble/parse_otfs V2.0 + test 迁移，发现早已实施，补填 Result |
| **E2E 时变信道 6 体制 688 点基线 benchmark** | 2026-04-19 | spec `2026-04-19-e2e-timevarying-baseline.md`；4 阶段 20min 跑完；发现 OTFS 32% 独立异常 |
| **双 LFM α estimator + 迭代 refinement（SC-FDE）** | 2026-04-20 | spec `2026-04-20-alpha-estimator-dual-chirp-refinement.md` + `2026-04-20-alpha-compensation-pipeline-debug.md`；α 工作范围 1e-4 → **1e-2**（15 m/s），A2 α=2e-3 BER 47% → 0% |
| **OTFS 32% BER 根因定位** | 2026-04-21 | spec `specs/archive/2026-04-21-otfs-disc-doppler-32pct-debug.md`；根因 = pilot_mode='sequence' regression；impulse 回滚后 3 信道 × 3 trial BER 0-0.04%；Yang 2026 理论 (H4) 证伪 |
| **摄入 6 篇 Doppler 论文** | 2026-04-21 | yang-2026 / zheng-2025 / wei-2020 / muzzammil-2019 / sun-2020 / lalevee-2025；wiki/source-summaries/ 新建 |
| **DSSS 符号级 Doppler 跟踪（Sun-2020）** | 2026-04-22 | spec `2026-04-22-dsss-symbol-doppler-tracking.md`；est_alpha_dsss_symbol.m + comp_resample_piecewise.m；D α=+3e-2 BER **51% → 2.2%** (25× 改善)；Symbol mean > Symbol per-sym（静态 α），A2/D |α|≤3e-3 维持 0% |
| **α=3e-2 突破（SC-FDE）** | 2026-04-21 | spec `2026-04-21-alpha-pipeline-large-alpha-debug.md`；TX tail pad + CP 阈值门禁 + 正向大 α 精扫 3 patch；α=+3e-2 BER **50% → 5.4%**，工作范围 1e-2 → **3e-2（45 m/s 鱼雷覆盖）**；VSS spec 中断保留代码 |
| **SC-FDE cascade 盲估 OOM 修复（Patch D+E）** | 2026-04-23 | spec `2026-04-22-scfde-cascade-resample-oom-fix.md`；3 处 `rat()` 容差 `1e-7/1e-6 → 1e-5`，poly_resample 单次峰值 4 GB → 40 MB；试错链 Phase A guard 1e-3 副作用（α=5e-4 50% BER）+ Phase B 复用 stage1 双 bug 已记录在 plan；最终 5 点 BER 与 baseline 完全一致，内存 97% → <30% |
| **SC-FDE α=-1e-2 单点 SNR 受限确认** | 2026-04-23 | 诊断 `diag_neg_1e2_root_cause.m`：2 α × 3 SNR × 5 seed；α=-1e-2 SNR=10 13.14% → SNR=15 0% 断崖恢复；物理根因 estimator ±α 系统偏差不对称（+1e-2 偏 5e-6 在底，-1e-2 偏 2e-5 超底）；接受 limitation（SNR≥15 全 α 工作）；附带发现 `bench_seed` 不生效（5 seed std=0）→ 归 E2E C 阶段 |
| **SC-FDE cascade 全场景验证（Phase G）** | 2026-04-23 | 诊断 `diag_alpha_sweep_full.m`：10 α × 3 SNR = 30 trial；工作率 SNR=10 9/10、SNR≥15 10/10；**新发现**：α=-1e-2 是孤立异常点（α=-3e-2 BER=0% 证伪 ±α 系统单调不对称假设），疑似 HFM/LFM 模板对齐局部不连续，待精细扫描验证 |
| **`bench_seed` 注入修复（Phase H）** | 2026-04-23 | `test_scfde_timevarying.m` L163 + L257 加 `(bench_seed-42)*100000` 偏移，默认 42 时 backwards-compat；hotfix uint32 mod wrap 处理 seed<42 负值；多 seed 验证 α=-1e-2 std 从 0→20.89 |
| **Phase I+J SC-FDE ~10% deterministic 灾难触发归档** | 2026-04-23 | 4 诊断脚本：disaster/oracle_isolation/high_snr/monte_carlo；**oracle α 仍 ~50%** → cascade 无辜；**非单调 BER vs SNR**（α=+1e-2 SNR=15/20 救活、25 又崩）违反单调律；30 seed Monte Carlo 双峰确认：mean 5%、median 0%、灾难率 **3/30 (10%)** ±α 均；候选根因 5 层（Channel 极性 / BCJR 固定点 / Frame timing / CFO 边界 / Soft demap）待 L2' |

---

## 相关资源

- **详细测试矩阵**：`wiki/comparisons/e2e-test-matrix.md`
- **累积技术结论**：`wiki/conclusions.md`（36 条）
- **项目仪表盘**：`wiki/dashboard.md`
- **函数索引**：`wiki/function-index.md`
- **活跃 spec**：`specs/active/`（13 张）
  - OTFS 3 张（pulse-shaping / sync-architecture / spread-pilot）
  - 14_Streaming 6 张（framework-master / p3-unified / p3.2 / p4 / p5 / p6）
  - 去 Oracle 1 张（deoracle-rx-parameters）
  - P3 demo UI 3 张（refactor / polish / sync-quality-viz）
- **活跃 plan**：`plans/`（9 张）
- **项目 CLAUDE.md**：根目录，含 Oracle §7 排查清单
