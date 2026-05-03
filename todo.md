# UWAcomm 水声通信算法开发进度

> 框架参考：`raw/notes/framework-history/framework_v6.html`
> Turbo 均衡方案：`modules/12_IterativeProc/turbo_equalizer_implementation.md`
> 调试记录：`wiki/debug-logs/{模块名}/`
> 测试结果矩阵：`wiki/comparisons/e2e-test-matrix.md`
> 关键技术结论：`wiki/conclusions.md`
> 6 种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 开发量统计（2026-04-26）

| 指标 | 数值 |
|------|------|
| MATLAB 函数文件 | 378 个（含 tests/diag） |
| 代码总行数 | 59,579 行 |
| 文档文件 (md+html) | 60+ 个 |
| Git 提交数 | 295 次 |
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
| 14 流式仿真框架 | `14_Streaming/` | 70+ | ✅ P1-P3 完成 + P4 scheme routing 4/4 PASS（2026-04-27 移植 codex）+ 真同步 + 深色科技风 UI + 8 tab 可视化 |

---

## 逐体制状态概览

> 详细 BER 表格见 `wiki/comparisons/e2e-test-matrix.md`

| 体制 | 版本 | 状态 | 备注 |
|------|------|------|------|
| SC-FDE | V4.1（14/rx）+ V4.0（14/tx） | ✅ | Phase 4+5 协议层突破：cfg.pilot_per_blk=128 → fd=1Hz 47%→3.37% (14×)；pre-Turbo BEM；jakes 时变 limitation 已突破（吞吐损失 50%） |
| OFDM | V4.3 + est_snr 修复 | ✅ | OMP + nv_post + 跳过 CP + 空子载波 CFO + DD-BEM；去 sps 减法 |
| SC-TDE | V5.6 | ✅ | V5.4 post-CFO fix + V5.5 fd=1Hz iter=0 + V5.6 HFM-signature calibration 4/5 PASS |
| OTFS | V5.1 (test_otfs_timevarying) + real (rx_otfs_real) | ✅ + jakes5Hz limitation | 2026-04-27 重启：移植 codex rx_chain 真重写 + spread-pilot + SLM/clip PAPR；5/6 fading SNR≥10dB 全 0%；**jakes5Hz 33-44% 灾难（连续谱物理 limitation，需协议层改动）**；spread-pilot PAPR 16.8→8.9dB |
| DSSS | V1.2 | ✅ | Rake(MRC)+DBPSK+DCD，96.8bps，static 0%@-15dB+；α=+1e-2 43%→0% post-CFO 修 |
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
| ~~**SC-TDE α=+1e-2 100% 灾难根因深挖**~~ | ✅ 2026-04-23 | RCA 完成（spec `2026-04-23-sctde-alpha-1e2-disaster-root-cause.md`）。10 步 diag（D0b→D10）锁定根因：`test_sctde_timevarying.m:436-441` 的 `exp(-j·2π·α·fc·t)` 在基带 Doppler 模型下是伪补偿。D10 验证 disable 后 α=+1e-2 BER 50%→0.29%。**副发现**：α=+1e-3 原来也是 100% 灾难（历史认知错误）。Fix spec + cross-scheme audit spec 已开 |
| ~~**SC-TDE 删除 post-CFO 伪补偿**（fix）~~ | ✅ 2026-04-24 | spec `archive/2026-04-24-sctde-remove-post-cfo-compensation.md`；runner V5.4（删 D6/D7 pre-CFO + post-CFO 默认 skip + `diag_enable_legacy_cfo` 反义 toggle + `row.alpha_est` CSV）；V1 α 扫描 PASS（+1e-3 50.66%→0%，+1e-2 50.36%→0.29%）V2 α=0 gate PASS（1.84%→0.04%）；**plan C 证伪**（时变 apply post-CFO 反让 fd=1Hz SNR=20 0%→37%），回滚到全 skip；fd=1Hz 非单调 BER vs SNR 独立 investigation spec |
| ~~**SC-TDE fd=1Hz 非单调 BER vs SNR investigation**~~ | ✅ 2026-04-25 闭环 | spec `archive/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md`；3 阶段 102 trial（diag_sctde_fd1hz_monte_carlo V2 / replay_seed42 / h4_oracle_alpha / h4_oracle_full）；**H4 confirmed**：α estimator 偏差是 SNR=15→20 mean 反弹（4.33→4.55%）直接根因，oracle 下单调恢复（2.43→0.89%）SNR=20 灾难率 33%→6.7%；s11 BER 10.57%→0.07%；衍生发现 runner RNG seed 依赖 fading_cfgs 行号 fi（单行 bench_fading_cfgs 偏离 default 验证条件） |
| ~~**SC-TDE fd=1Hz α estimator fix（V5.5+V5.6 主目标达成）**~~ | ✅ 2026-04-26 归档（4/5 PASS + 1 边缘） | spec `archive/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md`；V5.5 Phase 1.2/2 量化+ablation；V5.5 fix runner fd-conditional iter (3/5 PASS)；V5.6 path A 证伪后转 path E：HFM signature (dtau_diff=-1) 在 fd=1Hz Jakes 是 deterministic 指纹，触发 fd-specific calibration（`alpha_lfm -= 1.5e-5`）；**V5.6 4/5 PASS**（SNR=15 mean ≤3% ✓、SNR=20 mean ≤1.5% **0.92% 接近 oracle 0.89%** ✓、灾难率 ≤15% **6.7% 等于 oracle** ✓、单调✓；SNR=15 灾难率 26.7% 边缘 partial 仅超 1.7pp 单 seed=13 边界效应）；L0 偏差 SNR=20 缩减 8.4× (1.52e-5→1.80e-6)；fd=0/5 V5.4 baseline 完全保留；commit 链 `6613041` (V5.4) + `3cb4660` (V5.5) + `c2dede1` (V5.6) |
| ~~**L0 deterministic α bias 校正**~~ | ✅ 2026-04-27 跳过（V5.6 已部分 cover） | V5.6 HFM-signature calibration 已在 fd=1Hz 缩减 L0 bias 8.4×（1.52e-5→1.80e-6）；fd=0 BER 已 0%、fd=5 物理极限，剩余场景边际收益低；不立 spec |
| ~~**SC-TDE fd=1Hz estimator-外灾难调研**~~ | ✅ 2026-04-27 归档为 known limitation | spec `archive/2026-04-27-sctde-fd1hz-estimator-external-disaster.md`（born archived）；s15 SNR=20 oracle α BER 8.90% 是当前路径物理 limitation 上界，灾难率 6.7%（1/15）= oracle 上界；类比 SC-FDE Phase I+J 归档先例（~10% 灾难率未锁定根因）；5 层 ablation 设计（Channel/BCJR/Timing/CFO/Demap）保留供未来重启 |
| **SC-TDE fd=1Hz SNR=10 残余灾难（known limitation）** | 🟢 已记 | conclusions.md：oracle α 后 SNR=10 灾难率仍 46.7%，与 α 无关，归低 SNR 物理极限/非 α 机制；与非单调主问题解耦 |
| ~~**CFO postcomp 横向检查 5 体制**（audit）~~ | ✅ 2026-04-24 | spec `archive/2026-04-24-cfo-postcomp-cross-scheme-audit.md`；grep 全覆盖 6 体制+common+14_Streaming；命中 4 runner（SC-TDE tv/dd + DSSS tv/dd）全部 V1.2/V5.4 fix；OFDM 不同类（合法 ML CFO 估计）；SC-FDE/FH-MFSK/OTFS 无；DSSS D10 验证 α=+1e-2 43.28%→0.00% 单一根因锁定 |
| ~~**DSSS α=+1e-2 100% 灾难根因深挖**~~ | ✅ 2026-04-24 | **根因 = post-CFO 伪补偿（与 SC-TDE 同 bug）**，非 Sun-2020。D10 验证 5 seed 全清零（43.28%→0.00%），α_est 精度 <0.01%。**Sun-2020 spec 重定位**：保留作时变 α（加速度 α=+3e-2 51%→2.2%）方向，与恒定 α 解耦 |
| **L5/L6 ch_est_gamp V1.1→V1.4 修复链 + SNR 受限归档** | 2026-04-23 | 修订：真根因是 `ch_est_gamp.m`（不是 BEM，static 路径走 GAMP）；V1.1 divergence guard+LS fallback / V1.2 双跑 / V1.3 CV 撤回 / V1.4 偏 LS 0.8；30 seed Monte Carlo: 灾难率 10% → 0%/6.7%；残余 2/30 验证 SNR=15 恢复 0% → 边界 limitation，非 bug |
| ~~**（可选）static 路径换 `ch_est_ls`/`ch_est_omp` 替代 GAMP**~~ | ❌ 试败（2026-04-23） | spec `2026-04-23-scfde-omp-replace-gamp-and-oracle-clean.md`；OMP K=6 反而 +1e-2 灾难率 6.7%→10%（残差驱动选错 support）；保留作 `tog.use_omp_static` toggle，默认仍 GAMP V1.4 |
| ~~**SC-FDE sps 相位选择真去 oracle**（架构改动）~~ | ✅ 2026-04-24（Phase 1+2） | spec `archive/2026-04-24-scfde-sps-deoracle-arch.md`；**第 4 次尝试成功**：迁移 14_Streaming 架构（第 0 block=training seed=77，RX 本地重建）；sps+GAMP 去 oracle 完成；Phase 3 BEM 单 block 证伪（fd=1Hz 0.16%→49.64%）回滚，BEM 判决反馈 2 阶段留 Phase 3b（spec `active/2026-04-24-scfde-bem-decision-feedback-arch.md`）；static/discrete_doppler 加 OFFLINE ORACLE BASELINE 声明 |
| **rx_chain.rx_otfs 真重写（main_sim_single 改造）** | 骨架占位 | rx_otfs_real 已加入 switch 路径但未实现；需 main_sim_single 开启真实 passband + 信道 + rx_otfs_real 填充。独立 spec 待创建 |
| ~~**OTFS 离散 Doppler 32% BER 专项 debug**~~ | ✅ 2026-04-21 | 根因 = `pilot_mode='sequence'` regression（非 Doppler 问题）。回滚 default → impulse，3 信道 × 3 trial BER 0-0.04%。详见 `wiki/modules/13_SourceCode/OTFS调试日志.md` |
| ~~**α 补偿推广到其他 4 体制**~~ | 🟡 部分完成（2026-04-21） | OFDM/DSSS/FH-MFSK 推广成功（A2 全 0%，D |α|≤1e-2 大部分工作）；SC-TDE 失败（下游 α 敏感，独立 spec 待开） |

### 🟡 中优先

| 任务 | 状态 | 说明 |
|------|------|------|
| ~~**P3 demo Doppler 链路接入**~~ | ✅ 2026-04-24 stale | 探索发现 UI→TX 链路 2026-04-22 之前已接入（`p3_demo_ui.m:864` on_transmit callback：`dop_hz → α → comp_resample_spline + exp(j·2π·fc·α·t)`）；RX 侧 α 补偿按 P4 spec 非目标显式保留为 known limitation（`specs/active/2026-04-22-p4-real-doppler-fork.md`）；P3 已冻结，后续 Doppler 工作归 P4 范围 |
| ~~**α estimator 符号约定参数化**~~ | ✅ 2026-04-23 | `est_alpha_dual_chirp` V1.1 加 `sign_convention` 参数（'raw'/'uwa-channel'），6 runner 8 处 `-alpha_lfm_raw` hack 清理；数学双翻号等价，BER 与 a53b6f3 一致 |
| ~~**α<0 不对称修复**（resample 层）~~ | ✅ 2026-04-22 | spec `2026-04-22-resample-negative-alpha-asymmetry.md`；根因 = `comp_resample_spline` 边界 clamp；V7.1 auto-pad 解决；单元 NMSE 差异 75-83→<3 dB，SC-FDE α=-3e-2 BER 2.66%→0%。**下游链路不对称**（DSSS/FH-MFSK/OFDM α 符号敏感）属独立 spec |
| ~~**α=3e-2 物理极限突破**~~ | ✅ 完成（2026-04-21） | 诊断显示 Oracle 下 pipeline 无问题，根因是 estimator 2% 系统偏差 + CP wrap；3 patch 修复让 α=+3e-2 BER 50% → 5.4%，工作范围扩到 15→45 m/s |
| **14_Streaming P1/P2 去 Oracle α**（2026-04-23 Phase d） | ✅ 2026-04-23 | `rx_stream_p1/p2` V1.0→V1.1 默认调 `estimate_alpha_dual_hfm` 盲估，`opts.use_oracle_alpha=true` 回退；P3/P4/P5/P6 待后续 spec |
| ~~**SC-FDE runner sps oracle 清理**~~ | ✅ 2026-04-24 已闭环 | spec `archive/2026-04-24-scfde-sps-deoracle-arch.md`；L515 `all_cp_data(1:10)` → `train_cp_rx(1:10)` (RX 本地重建 training preamble)；剩余 BEM `x_vec(pp) = all_cp_data(idx)` (L694) 属 A2 BEM Phase 3b spec 范围 |
| ~~**SC-FDE BEM 判决反馈 Phase 3b（去最后一处 oracle）**~~ | ✅ 2026-04-26（路线 1 已落地，limitation 已知） | spec `archive/2026-04-24-scfde-bem-decision-feedback-arch.md`；commits `55e3cd5` (3b.1) + `c8ccb06` (3b.2 + A1) + `f6526ff` (3b.4 决议 + 归档)；**3b.1 ✅** `build_bem_observations_scfde.m` + 单测 6/6 PASS；**3b.2 ✅** `test_scfde_timevarying.m` 3 处 edit（all_cp_data 在 RX 链路完全消除，spec 接受准则核心目标达成）；实测 — static 0/0/0/0% PASS，fd=1Hz ~50% (limitation), fd=5Hz ~50% (物理极限)；**路线 4 (A1) 验证** `diag_a1_streaming_decoder_jakes.m`：14_Streaming production decoder × jakes fd=1Hz 也 50.02% mean（与 13 移植 50.18% 差 < 0.2 pp）→ **架构 trade-off 确认**（不是 13 移植 bug），软符号-BEM 鸡蛋耦合在 14 production 也无法解；**3b.4 决议不推广** `test_scfde_discrete_doppler.m`（OFFLINE ORACLE BASELINE，迁移会重现灾难）；后续协议层方向（多训练块/导频 superimposed/超训练块）需开新 spec；详 [[wiki/modules/13_SourceCode/SC-FDE调试日志]] V2.3 + V2.4 |
| ~~**SC-FDE 协议层突破 jakes fd=1Hz 50% limitation（Phase 4+5）**~~ | ✅ 2026-04-26（V5b PASS：fd=1Hz 47%→3.37% 14×） | spec `archive/2026-04-26-scfde-time-varying-pilot-arch.md`；plan `plans/2026-04-26-scfde-time-varying-pilot-arch.md`；**Phase 4 方案 A 多 train block FAIL**（fd=1Hz K=4 49.97%，根因 RX 单块 GAMP H_init）；**Phase 4-revision pre-Turbo BEM 部分改善**（fd=1Hz K=4 47%→18.31%，obs 152 不足）；**Phase 5 方案 E block-pilot 末插入 PASS** — `cfg.pilot_per_blk=128 (=blk_cp)`，CP 全 pilot → ~1178 干净 BEM obs/帧 → pre-Turbo BEM 替代单块 GAMP；fd=1Hz 47.05%→**3.37% (14×)**，fd=5Hz 49.63%→13.80% (SNR=20 3.53%)，static SNR≥10 全 0%；**A+E 组合不优于纯方案 E**（pilot<blk_cp 时 BEM obs 几乎 0）；改动文件：modem_encode_scfde V4.0 (cfg.pilot_per_blk + cfg.train_period_K) + modem_decode_scfde V4.1 (pre-Turbo BEM + pilot 切分) + build_bem_observations_scfde V2.0 + build_bem_obs_pretturbo_scfde V1.0 + diag_a2/a3/a4_*.m + test_build_bem_obs_scfde V2.0 (3/3 PASS)；**limitation**：吞吐损失 50%；fd=5Hz 低 SNR (5-10dB) BEM 噪声敏感；pilot < blk_cp 不 work；后续方向（midamble pilot / iter BEM refinement / lambda 自适应）需开新 spec；详 [[wiki/modules/13_SourceCode/SC-FDE调试日志]] V3.0 |
| ~~**E2E benchmark C 阶段（多 seed 检测率）**~~ | ✅ 2026-04-23 | Phase a 启用：`benchmark_e2e_baseline.m` V1.1 + 4 体制 runner 加 bench_seed 注入（SC-FDE 已修），smoke 验证；270 pts 全矩阵未跑 |
| **E2E benchmark profile 扩展** | 待做 | 当前仅 custom6，需 runner 支持 `bench_channel_profile` 切换 ch_params（exponential 等） |
| **E2E benchmark NMSE/sync/turbo iter 填充** | 待做 | CSV schema 有字段但本期全 NaN，需 runner 暴露 h_est / sync_tau_err / 逐轮 BER |
| ~~**p3_demo_ui.m refactor Step 2+3**~~ | ✅ 2026-04-22 归档 | spec `archive/2026-04-17-p3-demo-ui-refactor.md`；主文件 1832 → 1359（外化 `p3_render_tabs.m` 486 / `p3_apply_scheme_params.m` 68 + setup 拆 4 nested build_*）；超 ≤1000 目标但结构清晰，遗留 render_channel/tx_panel/rx_panel 拆分作 P3.x optional |
| **OTFS 通带 2D 脉冲整形 Phase 4** | Phase 2 完成 | 端到端 BER 验证待做；spec `2026-04-13-otfs-pulse-shaping.md` |
| **OTFS PAPR 专项降低** | 待做 | 需 SLM/PTS/削峰等专用技术 |
| **OTFS 扩散 pilot** | 待做 | spec `2026-04-14-otfs-spread-pilot.md` |
| ~~**14_Streaming P4 scheme routing**~~ | ✅ 2026-04-27 | spec `active/2026-04-15-streaming-p4-scheme-routing.md`（codex completed）；commit `ef0ed49` 移植 codex 8 文件（common 4 + tx/rx_stream_p4 + channel_simulator_frame + test_p4_scheme_routing）；test 4/4 PASS（mixed-scheme "FHMFSKSCFDEOFDMSCTDEDSSSOTFS" 6 schemes CRC 全 1 + dispatch all 6 + payload CRC fail missing frame + header fail skip）；不动 modem_encode/decode_scfde（保留 claude Phase 4+5）；P4 demo UI 17 文件之前已 done |
| **14_Streaming P5（三进程并发）** | 待启动 | TX/Channel/RX 三进程并发；codex 已做 rx_daemon_p5/channel_daemon_p5/p5_channel_preset 可借鉴；spec `active/2026-04-15-streaming-p5-concurrent.md` |
| **14_Streaming P6（AMC）** | 待 P5 | 物理层 AMC（link quality → scheme 自适应）；`amc/` 目录已占位 |
| **14_Streaming P4 真多普勒** | 待启动 | spec `active/2026-04-22-p4-real-doppler-fork.md`（codex 实施）；从 P3 fork 接 gen_doppler_channel V1.0（时变 α(t) + 多径）；P4 demo UI 已存在但未接 real Doppler |
| ~~**P4 UI ↔ 算法对齐 + Jakes + 恒定多普勒**~~ | ✅ 2026-04-28 commit `44db87e` | spec active；3 段（V2.0 透传 + Jakes 接通 + α V7+refinement）已 commit |
| **SC-FDE bypass=ON dop=10 残余 35.9%（H2 fix 不彻底）** | 待 spec | bypass=ON dop=10 H2 fix 后 OFDM/SC-TDE 0%、SC-FDE 仍 35.9%；bypass=OFF 同条件 6.2%；与 SC-FDE turbo iter / SNR 紧 / seed 抖动相关，独立调查 |
| **SC-FDE bypass=OFF dop=0 BER 24% 抖动** | 待确认 | turbo_iter=2 + 单 seed 不稳；提高 iter 或多 seed 验证可能解；非紧迫 |
| ~~**P4 UI follow-up：解耦 SC-FDE blk_cp/blk_fft + 加 pilot 控件**（V4.0 自动激活）~~ | ✅ 2026-05-01 算法层 | spec/plan/code/单测6/6/diag 36-trial 全 PASS；V3.0 解耦 + pilot/train_period_K 控件 + V4.0 预设按钮（256/128/128/31）；直接链路 jakes fd=1Hz BER 0.68%（v0 baseline 49.56%，74× 改善）；**UI 实测 BER 仍 50% + 循环发 → 归 runner↔UI 等价性 follow-up 定位 UI 链路差异** |
| **P4 UI follow-up：暴露 oracle toggle**（runner 等价模式）| 待启动 | UI 加调试 checkbox，allow 透传 fading_type/sym_delays/noise_var 等 oracle 参数到 modem_decode；让用户能看到算法上界 |
| ~~**P4 UI follow-up：runner ↔ UI 等价性单元测试**~~ | ✅ 2026-05-03 算法/测试层闭环 | spec `active/2026-05-03-p4-ui-runner-equivalence-rca.md`；3 测试落地：alignment 7/7 + runner-equivalence (R 2.28% ≈ U1 2.22% AWGN 5 seed mean) + jakes-α-gate-e2e（**Path B 49.90% ← 复现 50% / Path C 9.48% ← gate 修复**）；H5 命中根因 = jakes 假 α 反补偿；移植 codex `streaming_alpha_gate.m` + 测试 5/5 + 修 `p4_demo_ui.m` 反补偿/refinement 双路加 gate；UI 实测验证留用户 |
| **P4 UI follow-up：tv 模型 + Jakes 组合** | 待启动 | 当前 jakes 模式下 tv 控件被忽略；`gen_uwa_channel` 不接受 tv struct，需写 jakes wrapper 或扩展 gen_uwa_channel |
| **AMC 移植到 14_Streaming claude**（codex 已有 1800+ 行 P6 phase）| 待 P5 | codex 完整 AMC：mode_selector / p4_default_amc_opts / amc_state / amc_btn / streaming_apply_modem_params / p4_clear_profile_overrides；待 P5 三进程完成后再考虑 |

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
| **P4 UI 解耦 SC-FDE blk_cp/blk_fft + V4.0 预设按钮** | **2026-05-01** | spec `active/2026-05-01-p4-ui-decouple-blk-cp-and-pilot-controls.md` + plan；`p4_apply_scheme_params V3.0` 删强制 blk_cp=blk_fft + N_info V4.0 公式；`p4_demo_ui` Layout 18→22 行加 4 控件（blk_cp/pilot_per_blk/train_period_K + V4.0 预设按钮）；单测 6/6 PASS；diag_p4_v40_preset_validation 36-trial 实测 v0_default 49.56% / v3 (256/128/128/31) **0.68%**（最佳）；预设值 K=8→K=31 修正；**UI 实测 50% 是 UI 链路独立问题，归 runner↔UI 等价性 follow-up** |
| **P4 UI bypass=ON 路径 H2 carrier-phase fix** | **2026-05-01** | spec `archive/2026-05-01-p4-bypass-on-doppler-ber-rca.md`；Phase 0 SNR sweep 证伪 H1（SNR 15→35 全 50%）；Phase 1 body 对比锁定 H2（dop=10 corr=0.03→0.996）；fix 在 try_decode_frame + p4_refine_alpha_decode 加 `exp(-j·2π·fc·α·t)`；OFDM/SC-TDE bypass=ON dop=10 BER 51%→0%、DSSS 2.75%→0%；SC-FDE 49%→35.9%（残余作 known limitation） |
| **P4 UI tx_pending leak 防御 + bypass=ON detect 路径修复 + FH-MFSK N_shaped 字段对齐** | **2026-05-01** | commit `062d1f3`/`44db87e`；try_decode_frame 整体 try/catch + modem_decode catch 清状态（防 fifo 残段 false-positive 循环触发）；detect_frame_stream 加 isreal 分支（bypass=ON complex baseband 跳过 downconvert）；modem_encode_fhmfsk 补 meta.N_shaped（对齐 5 体制） |
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
| **E2E benchmark C 阶段启用（Phase a）** | 2026-04-23 | `benchmark_e2e_baseline.m` V1.0→V1.1 + 4 体制 runner 加 bench_seed 注入；Smoke test 4 combo 全 0% + alpha_est 随 seed 变化；270 pts 全矩阵未跑 |
| **α estimator 符号约定参数化（Phase b）** | 2026-04-23 | `est_alpha_dual_chirp` V1.0→V1.1 加 `sign_convention`；6 runner 8 处 hack 清理；数学双翻号等价，BER 与 a53b6f3 一致 |
| **5 体制灾难率横向 sanity check（Phase c）** | 2026-04-23 | 诊断 `diag_5scheme_monte_carlo.m`：5 scheme × α=+1e-2 × SNR=10 × 15 seed；**OFDM/SC-FDE/FH-MFSK 0 灾难，SC-TDE/DSSS 100% 灾难**；修正旧虚报"6 体制全能跑 α=3e-2"；新高优先任务：SC-TDE / DSSS α 深挖 |
| **SC-TDE α=+1e-2 RCA 完成** | 2026-04-23 | spec `2026-04-23-sctde-alpha-1e2-disaster-root-cause.md`；10 步 diag（D0b-D10）锁定 `exp(-j·2π·α·fc·t)` post-CFO 伪操作；D10 disable 后 α=+1e-2 BER 50%→0.29%、α=+1e-3 50.66%→0%、α=0 1.84%→0.04%；副发现 α=+1e-3 static 原来也是 100% 灾难（历史认知错误，之前"能 work"是 bench_seed=42 单个例假象）；调试日志 V5.3 章节归档，fix + audit spec 已开 |
| **spec 状态审计 + 批量归档（11 张）** | **2026-04-25** | active 23→12；归档批次：constant-doppler-isolation（被 dual-chirp 取代）/ alpha-estimator-dual-chirp-refinement（α 工作范围 1e-4→1e-2）/ alpha-compensation-pipeline-debug（α=2e-3 修复）/ alpha-pipeline-large-alpha-debug（α=3e-2 突破）/ alpha-refinement-other-schemes（partial，4 体制推广 + SC-TDE 拆分线索）/ hfm-velocity-spectrum-refinement（📌parked，VSS estimator 工程代码留入口）/ dsss-symbol-doppler-tracking（partial，Sun-2020 25× 改善）/ streaming-p3-unified-modem / streaming-p3.2-ofdm-sctde（自标 done 已清理）/ p3-demo-ui-polish / p3-demo-ui-sync-quality-viz；每张 spec 追加 `## Result` 段（完成日期/状态/产出/后继 spec/归档时间） |

---

## 相关资源

- **详细测试矩阵**：`wiki/comparisons/e2e-test-matrix.md`
- **累积技术结论**：`wiki/conclusions.md`（36 条）
- **项目仪表盘**：`wiki/dashboard.md`
- **函数索引**：`wiki/function-index.md`
- **活跃 spec**：`specs/active/`（**12 张**，2026-04-25 spec 状态审计批量归档 11 张后；详见里程碑末行）
  - OTFS 2 张（pulse-shaping / spread-pilot）
  - 14_Streaming 5 张（framework-master / p4-scheme-routing / p4-real-doppler-fork / p5-concurrent / p6-amc）
  - 去 Oracle 1 张（deoracle-rx-parameters）
  - E2E / 多普勒 / 实施进行中 4 张（e2e-timevarying-baseline / resample-roundtrip-nodoppler-test / scfde-bem-decision-feedback-arch / sctde-fd1hz-alpha-estimator-fix）
- **活跃 plan**：`plans/`（9 张）
- **项目 CLAUDE.md**：根目录，含 Oracle §7 排查清单
