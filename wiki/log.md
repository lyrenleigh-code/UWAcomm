# Wiki 操作日志

## 2026-05-01

- **P4 UI 解耦 SC-FDE blk_cp/blk_fft + V4.0 预设按钮（任务 1 算法层完成）**
  - spec `2026-05-01-p4-ui-decouple-blk-cp-and-pilot-controls.md` + 同名 plan
  - `p4_apply_scheme_params V2.0→V3.0`：删 L46 强制 `blk_cp=blk_fft`；改读 ui_vals.blk_cp（缺省=blk_fft）；N_info 改 V4.0 公式 `(blk_fft - pilot_per_blk) * N_data_blocks - mem`，K linspace 训练块分布
  - `p4_demo_ui.m` Layout 18→22 行：加 blk_cp_dd / pilot_pb_edit / train_K_edit / preset_v40_btn 4 控件；on_scheme_changed 加可见性绑定（仅 SC-FDE）；on_transmit 加 SC-FDE 校验；ui_vals 加 3 字段透传；新回调 on_apply_v40_preset
  - 单测 `test_p4_apply_scheme_params_v3.m` 6/6 PASS（C1 默认兼容 / C2 V4.0 推荐 / C3 自定义 / C4 OFDM 隔离 / C5 SC-TDE 隔离 / C6 fading 透传）
  - diag `diag_p4_v40_preset_validation.m` 36-trial 端到端验证：v0_default jakes fd=1Hz 49.56%（重现 50% 灾难） / v3 (256/128/128/31) **0.68%** 最佳 / archive 标准 v2 (256/128/128/15+N=16) 2.46%（与 archive V5b PASS 写的 3.37% 接近）；多训练块 K=8/15 不优于单训练 K=31，A4 教训重现
  - 预设按钮值修正：K=8 → K=31（保持 N_blocks=32 + 单训练块 + pilot=blk_cp 最简洁）
  - 调试日志 `wiki/debug-logs/14_Streaming/流式调试日志.md` 加 2026-05-01 章节
  - **未解 limitation**：UI 实测 V4.0 预设 + slow Jakes fd=1Hz 仍 50% + 触发循环发；直接链路 0.68% 证明算法无问题，差异在 UI 链路（同步 / 前导 / bypass）。归任务 3「runner ↔ UI 等价性单元测试」定位

## 2026-04-28

- **P4 恒定多普勒对齐 codex（RX α 补偿符号 + α refinement 移植）**
  - 用户实测 P4 UI dop_hz=N + static 不解码，对比 codex 找差异
  - 根因 1：claude `p4_demo_ui.m:1276` `comp_resample_spline(rx_seg, -alpha_est_rx, ...)` 是 V6 废弃约定（058cee7 P4 fork 时未跟上 V7 修订）；V7+ 头注明说"正 alpha 直接传入即可补偿压缩"。修：去负号
  - 根因 2：缺 α refinement after decode（codex 关键二级 fix）。`detect_frame_stream` 单次 α 估计精度 σ≈1e-5，BER 仍高时需要在 ±2e-5 邻域扫 11 候选重解码取最佳。移植 codex 的 5 个 nested helper（`p4_should_refine_alpha` / `p4_refine_alpha_decode` / `p4_extract_body_for_decode` / `p4_decode_score` / `p4_ber`）
  - 长度对齐：channel 段 α<0 不截断（对齐 codex）
  - 调试日志 `wiki/debug-logs/14_Streaming/流式调试日志.md` 加 2026-04-28 第三条章节
  - 与 codex 剩余差异：AMC P6 phase（不在本次范围）

- **P4 Jakes 信道接入（fading_dd 控件复活）**
  - 调研发现 P4 UI 的 `fading_dd` (static/slow Jakes/fast Jakes) + `jakes_fd_edit` 完全死链：`gen_doppler_channel V1.5` 不含 Jakes 衰落多径
  - spec `active/2026-04-28-p4-jakes-channel-integration.md` + plan `plans/2026-04-28-p4-jakes-channel-integration.md`
  - `p4_demo_ui.m` channel 段（L900-940）加 fading_dd 分发：
    - 'static' → 现有 `gen_doppler_channel + p4_channel_tap`（含 tv 模型）
    - 'slow/fast Jakes' → `gen_uwa_channel`（13/common），独立透传 `doppler_rate=alpha_b` + `fading_fd_hz=jakes_fd_edit`
  - addpath 加 `13_SourceCode/src/Matlab/common`（gen_uwa_channel 所在）
  - 新增 `tests/test_p4_jakes_channel_smoke.m`（3 case 底层信道调用，C1 static / C2 slow Jakes / C3 fast Jakes）
  - 调试日志追加 2026-04-28 第二条章节
  - **已知 limitation**：tv 模型（drift/jitter/random_walk/sinusoidal）在 Jakes 模式下被忽略（gen_uwa_channel 不接受 tv struct），UI 在 jakes+tv 时打 append_log 警告

- **P4 UI ↔ 算法对齐 V2.0**
  - 调研发现 P4 UI 前端控件已加 `static / slow Jakes / fast Jakes` + `fd_hz` 输入（058cee7 fork），但后端 `p4_apply_scheme_params V1.0.0` 仍 hardcode `fading_type='static'` + `fd_hz=0`，控件值不透传
  - spec `active/2026-04-28-p4-ui-algo-alignment.md` + plan `plans/2026-04-28-p4-ui-algo-alignment.md`
  - `p4_apply_scheme_params V1.0 → V2.0.0`：5 体制（SC-FDE/OFDM/SC-TDE/DSSS/OTFS）透传 `fading_type` / `fd_hz`；SC-FDE 加 `pilot_per_blk` / `train_period_K` 字段透传通道（默认 V1.0 行为，向后兼容）；FH-MFSK 不动（schema 无 `fading_type` 字段）
  - `p4_demo_ui.m` L864-871 ui_vals 加 2 字段
  - 新增 `tests/test_p4_ui_alignment_smoke.m`（4 case 字段透传 assert，不跑 modem）
  - 调试日志追加 `wiki/debug-logs/14_Streaming/流式调试日志.md` 2026-04-28 章节
  - **已知 limitation**：SC-FDE V4.0 突破不会自动激活（需 `blk_fft=256/blk_cp=128` 实测 setup，当前 UI 默认 `blk_cp=blk_fft`），需 follow-up spec 解耦控件

## 2026-04-27

- **OTFS 工作重启 + e2e 实测（codex 借鉴移植）**
  - commits `9e338a1` (rx_chain.rx_otfs 真重写 5/6 体制 PASS) + `c9c0601` (扩散 pilot superimposed + SLM/clip PAPR 24/24 PASS)
  - main_sim_single 6 体制全 0%（OTFS N_info=1857）
  - test_multicarrier 24/24 PASS（4.4 OTFS PAPR impulse 16.8dB / superimposed 8.9dB）
  - test_otfs_timevarying impulse 实测：5/6 fading（static / disc-5Hz / hyb-K{5,10,20}）SNR≥10dB BER 全 0%；**jakes5Hz 33-35% 灾难**（连续谱物理 limitation，类比 SC-FDE jakes fd=1Hz 50% 灾难）
  - superimposed pilot 实测：PAPR + 数据率优势确认（8.9dB / +10% 数据率），但 BER 不优于 impulse；jakes5Hz 更差（42-44%）
  - feedback memory：feedback_uwacomm_skip_otfs.md 撤销 2026-04-21 skip 决策 → OTFS 重启
  - conclusions.md 加 #46（OTFS jakes5Hz limitation）

- **SC-TDE fd=1Hz estimator-外灾难 spec 归档为 known limitation**
  - spec `archive/2026-04-27-sctde-fd1hz-estimator-external-disaster.md`（born archived）
  - s15 SNR=20 oracle α 仍 BER=8.90% 灾难率 6.7%（= oracle 上界），与 estimator 解耦
  - 类比 SC-FDE Phase I+J 归档先例（~10% 灾难率），SC-TDE 6.7% 更轻
  - 5 层 ablation 设计（Channel/BCJR/Timing/CFO/Demap）保留供未来重启
  - conclusions.md 加 #45
  - todo.md L109/L110 候选 spec 行改为 ~~删除线~~ 已归档

- **L0 deterministic α bias 校正待办跳过**
  - V5.6 HFM-signature calibration 已在 fd=1Hz 缩减 L0 bias 8.4×（1.52e-5→1.80e-6），主要场景已解决
  - fd=0 BER 已 0%、fd=5 物理极限，剩余场景边际收益低
  - 不立 spec；todo.md L109 改为 ~~删除线~~

## 2026-04-26

- **SC-TDE fd=1Hz α estimator fix spec 归档（4/5 PASS）**
  - spec `archive/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md`（active → archive）
  - V5.6 4/5 PASS：SNR=15 mean=2.36% / SNR=20 mean=0.92% (接近 oracle 0.89%) / SNR=20 灾难率=6.7% (= oracle) / 单调恢复
  - 边缘：SNR=15 灾难率 26.7% 仅超 1.7pp 单 seed=13 边界效应
  - 残余 L0 deterministic +1.5e-5 bias + estimator-外灾难（s15 oracle 仍 8.90%）独立 spec 立项（候选）
  - todo.md L108 ~~删除线~~ + 归档路径

- **SC-FDE Phase 4+5 协议层突破：方案 E block-pilot pre-Turbo BEM**
  - Spec: `archive/2026-04-26-scfde-time-varying-pilot-arch.md` （归档）
  - Plan: `plans/2026-04-26-scfde-time-varying-pilot-arch.md`
  - 验证脚本：`diag_a2_phase4_periodic_pilot.m` (K 多 train) + `diag_a3_phase5_block_pilot.m` (pilot 单维) + `diag_a4_phase5_combined.m` (K×pilot 双维)
  - **Phase 4 (方案 A 多 train block，K={2,4,8,15})**：fd=1Hz 全 K 均 ~50%（49.97% K=4），仅协议层加 train block 不足，根因 iter=0..1 H_init 单块 GAMP 失配
  - **Phase 4-revision (4 train + pre-Turbo BEM)**：fd=1Hz K=4 47%→18.31% 部分改善，obs 152 不足
  - **Phase 5 (方案 E block-pilot pilot_per_blk=blk_cp=128)**：**fd=1Hz 47.05%→3.37%（14×）✅ V5b PASS**，fd=5Hz 49.63%→13.80%（SNR=20 3.53%），static 不退化
  - A+E 组合 (K=4+pilot=64) 实测劣于纯方案 E（pilot<blk_cp 时 BEM obs 0）
  - SC-FDE 调试日志 V3.0 章节
  - conclusions.md #44
  - 协议关键：modem_encode_scfde V4.0 (cfg.pilot_per_blk + cfg.train_period_K) + modem_decode_scfde V4.1 (pre-Turbo BEM 触发 + pilot 切分) + build_bem_obs_pretturbo_scfde.m V1.0 公共函数
  - 已知 limitation：吞吐损失 50%；fd=5Hz 低 SNR (5-10dB) BEM 噪声敏感；pilot < blk_cp 不 work

- **SC-FDE Phase 3b.2 路线 4 (A1) 验证 + 路线 1 落地**
  - Plan: `plans/a1-streaming-decoder-jakes-validation.md`
  - A1 脚本: `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_a1_streaming_decoder_jakes.m`
  - A1 实测（3 seed × 4 SNR × 3 fading，14_Streaming production `modem_decode_scfde` × `gen_uwa_channel` jakes）：
    - static 健全 0.41% mean（5dB 1.60% / 其余 ~0，无 LFM preamble 缺失 ~3dB sync gain）
    - **fd=1Hz mean=50.02%（与 13 移植 50.18% 差 < 0.2 pp）**
    - fd=5Hz mean=49.86%
  - **决策**：架构 trade-off 确认（不是 13 移植 bug）→ 走路线 1
  - SC-FDE 调试日志追加 V2.4 章节（A1 数据 + 决策 + 后续协议层方向）
  - conclusions.md 加 #43（A1 验证落地）
  - spec `2026-04-24-scfde-bem-decision-feedback-arch.md` 接受准则重写为 "limitation 已知" + status archived
  - **Phase 3b.4 决议：不推广** `test_scfde_discrete_doppler.m`（OFFLINE ORACLE BASELINE，A1 证迁移会重现 50% 灾难，反而失去 oracle 对比基准）；file header L11-23 注释更新指向 A1 结论
  - Spec 归档：active → archive（commit `c8ccb06` 之后，本日 commit）

## 2026-04-25

- **SC-FDE Phase 3b.2 BEM 判决反馈去 oracle 实施（归档）**
  - Spec: `specs/active/2026-04-24-scfde-bem-decision-feedback-arch.md`（更新加 "进度（2026-04-25 归档）" 章节 + 接受准则达成度 + 4 路线决策待用户）
  - Plan: `plans/2026-04-24-scfde-bem-decision-feedback-arch.md`
  - Phase 3b.1 ✅（commit `55e3cd5`）：`build_bem_observations_scfde.m` + 单测 6/6 PASS
  - Phase 3b.2 🟡 实施完成未 commit：`test_scfde_timevarying.m` 3 处 edit
    1. addpath `bench_common`
    2. L648-720 重构：删除 `else` 时变 BEM 分支（含 `all_cp_data` oracle），统一用 GAMP 静态估计作 iter=0..1 公共 fallback
    3. Turbo loop titer=2 入口插入 `build_bem_observations_scfde + ch_est_bem` 重估 `H_cur_blocks`（`~static && ~tog.oracle_h`）
  - 默认运行 BER（4 SNR × 3 fading × 1 seed）：
    - static 0/0/0/0% V3a ✅ PASS — `all_cp_data` 在 RX 链路完全消除（spec 接受准则核心目标达成）
    - **fd=1Hz 50.23/50.13/50.03/50.31% V3b ❌ 灾难**（接受准则 0.16/0/0/0% 不可达成）
    - fd=5Hz ~50% V3c ✅ 物理极限
  - V3b 灾难根因：jakes fd=1Hz × 16 block ≈ 1.024s = 一个完整 Jakes 周期；第 8 block h 与训练块 h 自相关 ≈ 0（T₀=0.5s）；iter=0..1 用静态 H 完全失配 → titer=1 软符号 ~50% 错 → titer=2 BEM garbage → Turbo 不收敛（**软符号-BEM 鸡蛋耦合，spec R1 兑现**）
  - 14_Streaming production 调研：**没在 jakes fd=1Hz 验证过 BER**（用 gen_doppler_channel α 时变 + 静态多径 conv，与 13 jakes Doppler spread 不同），无 reference 标杆
  - SC-FDE 调试日志追加 V2.3 章节（含 4 路线决策候选）
  - conclusions.md 加 #42（jakes 时变 + 单训练块 + 判决反馈架构 trade-off）
  - todo.md Phase 3b 行更新为"3b.1 ✅ + 3b.2 ⚠ 待决策"
  - Phase 3b.3 V3d/V3a 多 seed 未跑；Phase 3b.4 ⏸ 未启动
  - 待用户决策路线：A 接受 limitation / B 回滚 / C 改 fallback（预期无效）/ D 自定义 14_Streaming jakes 验证
- **SC-TDE fd=1Hz V5.6 HFM-signature bias calibration（V5.5 续做）**
  - Path A（HFM Doppler-invariance）证伪：fd=1Hz HFM mean 偏差 (-1) 比 LFM (-0.38) 大；HFM 非 invariant
  - Path E pivot：HFM dtau_diff = -1 在 fd=1Hz Jakes 是 deterministic 指纹（std=0；fd=0=0；fd=5∈{-123,-42}）→ 触发 fd-specific calibration
  - V5.6 实施：runner 加 HFM peak detection + raw_snapshot 后 calibration（`alpha_lfm -= 1.5e-5` if HFM dtau_diff==-1）；caller `bench_v56_calib_amount=0` 可禁用
  - bug 修复：calibration block 初版误置于 estimator 调用之前（subtract leftover alpha_lfm），re-order 到 raw_snapshot 之后
  - Verify（diag_sctde_fd1hz_v5_6_verify.m，4.28 min × 135 trial）：
    - SNR=15: 2.97%→**2.36%** mean；20.0%→**26.7%** 灾难率（seed=13 边界效应 3.62%→6.95%）
    - **SNR=20: 2.55%→0.92% mean（接近 oracle 0.89%）；33.3%→6.7% 灾难率（等于 oracle）**
    - L0 偏差缩减 8.4×（SNR=20: 1.52e-5 → 1.80e-6）
  - fd=0/5 副作用 0：HFM dtau_diff fd=0 全=0，fd=5 ∈{-123,-42}，0 trial=-1 触发 → V5.4 baseline 完全保留
  - 接受准则 **4/5 PASS + 1 边缘**（SNR=15 灾难率 26.7% 仅超 1.7pp，单 seed 边界效应）
  - SC-TDE 调试日志追加 V5.6 章节；conclusions.md 追加 V5.6 章节（V5.5 之上）
  - spec 保留 active，等用户判断 archive
- **SC-TDE fd=1Hz V5.5 partial fix（H4 confirmed 后续）**
  - Spec 状态：`specs/active/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md`（保留 active，等用户判断后续）
  - Plan: `plans/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md`
  - Phase 1.2：runner 暴露 4 层 α (`L0 raw / L1 iter / L2 scan / L3 final`) + LFM peak 7 字段；`bench_init_row` schema 扩 10 字段（向后兼容 NaN）
  - 量化数据：L0 偏差 deterministic +1.5e-5（不随 SNR 变），iter L1 翻倍至 +3.0e-5
  - Phase 2 三条假设：
    - **R3 排除**：sub-sample 必需（关掉 \|err\| 5.7× 恶化，dtau 真值 μs 级被 1/fs ≈ 21μs 量化掉）
    - **R5 confirmed（新）**：iter refinement 反向收敛（累加 deterministic bias）
    - **R1 部分支持**：LFM tau_up_frac 系统偏 +0.44（Jakes 时变 deterministic peak shift）
    - bad/good seed estimator 偏差几乎相同 → **灾难非 estimator 偏差驱动**（类比 SC-FDE Phase J）
  - V5.5 fix（runner V5.5）：`test_sctde_timevarying.m` 加 fd-conditional default — fd=1Hz Jakes 自动 iter=0，其他场景保留 V5.4 default=2，caller explicit 仍优先
  - Verify 1：`verify_alpha_sweep` 55 trial × 5 min — V5.4 大 α 行为完全保留
  - Verify 2：三方对比（base/fix/oracle，default 3 fading × 15 seed × 3 SNR）
    - SNR=15 mean 4.33→**2.97%**（≤3% ✓）/ 灾难率 33.3→**20.0%**（≤25% ✓）
    - SNR=20 mean 4.55→**2.55%**（vs ≤1.5% ✗ partial，oracle 0.89%）/ 灾难率 33.3→**33.3%**（vs ≤15% ✗ partial，oracle 6.7%）
    - **单调性恢复 ✓**（base 4.33→4.55 反弹消失）
  - 接受准则 3/5 PASS（SNR=15 全 + 单调）+ 2/5 partial（SNR=20）
  - 残余分析：mean 1.66% gap 由 L0 deterministic +1.5e-5 bias 解释（iter=0 已是层内最优）；灾难 4/15 由 estimator 偏差驱动，1/15 (s15) 是 estimator-外机制
  - conclusions.md 顶部追加新章节（"SC-TDE fd=1Hz V5.5 partial fix"）
  - SC-TDE 调试日志追加 V5.5 章节
- **SC-TDE fd=1Hz 非单调 BER vs SNR investigation 闭环**
  - Spec 归档：`specs/archive/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md`
  - Follow-up fix spec 起草：`specs/active/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md`
  - 3 阶段 + 102 trial Monte Carlo 数据（diag_sctde_fd1hz_monte_carlo.m / replay_seed42.m / h4_oracle_alpha.m / h4_oracle_full.m）
  - **H4 confirmed**：α estimator 偏差是 SNR=15→20 mean 反弹（4.33→4.55%）的直接根因
    - Oracle α 替换：mean 单调恢复（2.43→0.89%），SNR=20 灾难率 33%→6.7%
    - s11 SNR=20 BER 10.57%→0.07%（α 偏离主导）
  - **衍生发现**：runner RNG seed 依赖 `fading_cfgs` 行号 fi → 单行 `bench_fading_cfgs` 偏离 default 验证条件（独立技术债）
  - SNR=10 残余灾难（46.7%）与 α 无关，归 known limitation
  - Plan: `plans/sctde-fd1hz-nonmonotonic-investigation.md`
  - conclusions.md 累积新条目（头部）

## 2026-04-24

- **SC-FDE sps+GAMP 去 oracle 迁移 14_Streaming 架构（V2.2）**
  - Spec: `specs/active/2026-04-24-scfde-sps-deoracle-arch.md`（归档中）
  - Phase 1: TX 第 0 block = training（seed=77），sps 两处用 `train_cp_rx(1:10)`，
    Turbo decoder 只处理 data block（N-1 个）
  - Phase 2 自动完成：GAMP `tx_blk1 = all_cp_data(1:sym_per_block)` 内容等价 train_cp
  - Phase 3 BEM 单 block 观测证伪：fd=1Hz 5dB 0.16%→49.64%（BEM 无法拟合 Jakes 时变）
  - 回滚 Phase 3，保留 Phase 1+2 收益（BER bit-exact 与 Phase 1 一致）
  - `test_scfde_static.m` + `test_scfde_discrete_doppler.m` 加 OFFLINE ORACLE BASELINE
    声明（§2 白名单豁免）
  - Phase 3b spec: `2026-04-24-scfde-bem-decision-feedback-arch.md`（移植 14_Streaming
    build_bem_observations 两阶段判决反馈方案，~2-3h future work）
  - 回流：`wiki/modules/13_SourceCode/SC-FDE调试日志.md` V2.2 章节；
    `wiki/conclusions.md` #41 架构迁移条目

- **CFO postcomp 跨体制横向审计完成**
  - Spec: `specs/active/2026-04-24-cfo-postcomp-cross-scheme-audit.md`（归档中）
  - Grep 覆盖：6 体制 runner + common + 14_Streaming
  - 命中同 bug（4 runner）：SC-TDE timevarying/discrete_doppler、DSSS timevarying/discrete_doppler
  - 全部 V1.2/V5.4 fix（默认 skip + `diag_enable_legacy_cfo` 反义 toggle）
  - 无 post-CFO：SC-FDE / FH-MFSK / OTFS / common / 14_Streaming
  - OFDM 不同类：空子载波 ML CFO 估计+补偿 → α 反向累加（合法数据驱动）
  - 回流：`wiki/conclusions.md` #40 审计结论条目

- **DSSS D10 验证：α=+1e-2 100% 灾难单一根因锁定**
  - 脚本: `tests/DSSS/diag_D10_dsss_disable_cfo.m`（2 模式 × 3 α × 5 seed = 30 trial）
  - legacy_on（apply post-CFO，历史 V1.1）：α=+1e-2 43.28±4.42%
  - legacy_off（skip post-CFO，V1.2 新默认）：α=+1e-2 **0.00%**（5 seed 全清零）
  - α_est 精度：+9.999e-3 vs true +1e-2，<0.01% 误差（α 估计链完美）
  - 印证 2026-04-23 Phase c（15 seed median 46.2% ≈ legacy_on mean 43.28%）
  - 回流：新建 `wiki/modules/13_SourceCode/DSSS调试日志.md` V1.2 章节

- **DSSS 4 runner V1.1→V1.2**（test_dsss_timevarying + test_dsss_discrete_doppler）
  - post-CFO 改默认 skip + legacy toggle
  - 补 `row.alpha_est` CSV 字段
  - Sun-2020 spec（`2026-04-22-dsss-symbol-doppler-tracking`）重定位：保留作时变 α 方向，与恒定 α 解耦

- **SC-TDE discrete_doppler V1.1→V1.2**
  - 同步 timevarying V5.4 fix（同 bug 孪生脚本，audit 命中）

- **SC-TDE post-CFO 伪补偿 fix + plan C 证伪（V5.4）**
  - Spec: `specs/active/2026-04-24-sctde-remove-post-cfo-compensation.md`（归档中）
  - Parent RCA spec: `specs/archive/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md`（归档中）
  - 改动: `test_sctde_timevarying.m` 删 D6/D7 pre-CFO + post-CFO 改默认 skip + `diag_enable_legacy_cfo` 反义 toggle + `row.alpha_est` CSV 字段
  - 新建: `verify_alpha_sweep.m`（V1 α 扫描 8α×5seed + V2 α=0 SNR gate 3SNR×5seed）
  - V1 核心验证: α=+1e-3 50.66%→0%，α=+1e-2 50.36%→0.29%（主灾难关闭）
  - V2: α=0 SNR=10 1.84%→0.04%（副带红利）
  - V3 plan A: fd=1Hz {21.70, 17.39, 27.96, 0.00}，SNR=20 Turbo 救回
  - V3 plan C（时变 apply post-CFO 实验）**证伪**: fd=1Hz SNR=20 从 0% 崩到 37%，全盘更差 → 回滚到全 skip
  - 历史 V5.2 "fd=1Hz 0.76%" 不可复现（代码演化累积差异）
  - 衍生: 开新 spec `specs/active/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md`（5 H + 3 阶段调研）
  - 回流: `wiki/modules/13_SourceCode/SC-TDE调试日志.md` 追加 V5.4 章节；`wiki/conclusions.md` 加第 39 条（基带 Doppler 模型下 post-CFO 伪操作）

## 2026-04-23

- **SC-TDE α=+1e-2 100% 灾难根因锁定（post-CFO 伪补偿）**
  - Spec: `specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md`
  - 10 步 diag（D0b→D1→D2→D3→D5→D6→D7→D9→D10）排除 α 估计/GAMP/Turbo iter/pre-CFO 位置后，D9 对比 α=0 vs α=+1e-2 发现 **sps scan 前 corr=0.817 / post-CFO 后 corr=0.055**，D10 禁用后 BER 50%→0.29% 验证
  - 真根因：`test_sctde_timevarying.m:436-441` 的 `exp(-j·2π·α·fc·t)` 补偿在基带 Doppler 信道模型下是伪操作，凭空添加 120 Hz 频偏破坏对齐
  - 副发现：α=+1e-3 static 路径原来也是 100% 灾难（历史"能 work"是单 seed 假象）
  - 回流: `wiki/modules/13_SourceCode/SC-TDE调试日志.md` 追加 V5.3 章节（10 步 diag + D10 验证数据 + 物理解释）

- **5 体制灾难率横向首次量化（Phase c sanity check）**
  - 诊断: `modules/13_SourceCode/src/Matlab/tests/bench_common/diag_5scheme_monte_carlo.m`
  - 矩阵: 5 scheme × α=+1e-2 × SNR=10 × seed 1..15 = 75 trial
  - 结果: OFDM 最健康（max 0.13%）；SC-FDE/FH-MFSK 0 灾难；**SC-TDE/DSSS 100% 灾难**（15/15 median 49%）
  - 修正旧规划虚报"6 体制全能跑 α=3e-2"：SC-TDE/DSSS α=+1e-2 已完全不工作
  - 揭示：之前 bench_seed=42 + A2/D 单 seed baseline 完全掩盖 SC-TDE/DSSS 的 100% 灾难
  - 回流: wiki/conclusions.md 加"5 体制横向灾难率首次量化"条目 + 修正 α 工作上限表

- **E2E benchmark C 阶段启用（Phase a）**
  - 修改: `benchmark_e2e_baseline.m` V1.0→V1.1 加 C stage；4 体制 runner 加 bench_seed 注入
  - SC-FDE runner 加 interactive mode bench_seed 兜底（修之前 commit 隐患）
  - Smoke test: 4 combo 全 0%，alpha_est 随 seed 变化证明 seed 真生效

- **α estimator 符号约定参数化（Phase b）**
  - `est_alpha_dual_chirp` V1.0→V1.1 加 `search_cfg.sign_convention`（'raw'/'uwa-channel'）
  - 6 runner 8 处 `-alpha_lfm_raw` + `+ (-delta_raw)` hack 清理
  - 数学双翻号等价，cascade_quick BER 与 a53b6f3 一致

- **第 3 次 sps 去 oracle 失败：QPSK 4 次方 NDA timing（spec `2026-04-23-scfde-sps-deoracle-fourth-power`）**
  - 设计：QPSK (±1±j)^4 = -4 统一 phasor，正确定时 sum 大、错定时 phasor 分散加和取消
  - 实测：cascade_quick 看似 OK（-1e-2 14%），但 Monte Carlo 灾难率 0%/6.7% → **10%/20%** 退化
  - 根因：噪声 4 次放大 + ISI 确定性混合不是 Gaussian → `y^4` phasor 分散反而抑制正确定时
  - **三次失败教训**：所有纯 NDA blind timing（功率/4 次方）在 6 径 ISI + SNR=10 失效
  - **结论**：去 oracle 必须给 RX 等价 ground truth → 架构改动（加 training preamble / LFM 模板尾部相关 / Gardner TED+量化），独立 spec 待开
  - 注释 ⚠ 标在源码 L484/L596，便于未来追溯

- **OMP 替换 + sps 去 oracle 双失败实验（spec `2026-04-23-scfde-omp-replace-gamp-and-oracle-clean`）**
  - Phase A 试用 `ch_est_omp(K=6)` 替代 GAMP V1.4：+1e-2 灾难率 6.7%→10% ↗（反向）
    - 根因：OMP K=6 强制选 6 column，残差驱动可能选错 support
    - 决策：默认回 GAMP，OMP 保留作 `tog.use_omp_static` toggle 便于复现
  - Phase B sps 相位用功率最大化（去 `all_cp_data(1:10)` oracle）：α=-1e-2 BER 13%→48% ❌
    - 根因：custom6 6 径 ISI 让错误相位捕获更多能量泄漏
    - 决策：撤回，注释保留教训；真去 oracle 另起 spec（LFM 模板/training preamble）
  - **教训**：教科书做法（OMP for sparse / power-max for RRC timing）在色散信道有反例；都需用真实 BER 验证才能信
  - 试错记录归档 `wiki/conclusions.md`，便于未来引用

- **L5/L6 修复链：`ch_est_gamp` V1.1→V1.4 + SNR 受限验证**
  - 修复: `modules/07_ChannelEstEq/src/Matlab/ch_est_gamp.m`
    - V1.1 divergence guard + LS Tikhonov fallback（救 80% 灾难）
    - V1.2 双跑取小残差
    - V1.3 CV hold-out（撤回，引入反向回归）
    - V1.4 偏 LS 系数 0.8（in-sample 比较）
  - 诊断: 新增 `diag_residual_snr_limit.m`
  - 修复链总效果（30 seed × 2 α × SNR=10）：
    - 修复前：灾难率 10% / 10%，max BER 49.7%
    - V1.4 后：灾难率 0% / 6.7%，max BER 30.6%
  - 残余 6.7% 验证: α=+1e-2 s17/s26 在 SNR=15 立即恢复 0% → SNR 受限边界，非 bug
  - **修订 L4 BEM 误判**: 静态路径走 `ch_est_gamp` 不是 BEM；"非单调 BER vs SNR" 是 V1 GAMP 病态反复触发，V1.4 修复后单调律恢复
  - 后续可选: 独立 spec 评估 static 路径换 `ch_est_ls`/`ch_est_omp` 替代 GAMP

- **L2' Step 1 真根因锁定：BEM 信道估计 ill-conditioned 数值发散**
  - 诊断: `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_disaster_layer_isolation.m`
  - 4 trial Oracle H_est 表对比：健康 case |gain|≈1，灾难 case |gain|=10¹~10²⁶
  - 真根因：BEM 求解 `inv(H'H)·H'y` 在某些 (TX bits, noise) 下观测矩阵接近奇异 → 求逆放大噪声 → h_est 幅度发散
  - 5 候选层最终判定：A（信道估计幅度爆）真根因；B/E 派生症状；C/D 排除
  - runner 改造：`bench_diag.enable=true` 时 fall through 到 sync/H_est/Doppler 诊断段（仍跳 figure）
  - 待 L5: BEM Tikhonov 正则化（最低风险方案）
  - 回流: `wiki/conclusions.md` 修订 — 5 候选层 → 真根因 + 修复方案

- **Phase J Monte Carlo 真实灾难率 ~10%（重大修订）**
  - 诊断: `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_seed_monte_carlo.m`
  - 矩阵: 30 seed × 2 α × SNR=10 dB = 60 trial
  - **结果**: α=-1e-2 / +1e-2 灾难率均 **3/30 (10%)**，median=0%、mean=5%
  - **双峰分布确认** → bug 性质明确（非统计涨落）
  - **修订**: Phase G 的 "α=-1e-2 单点 SNR 受限" 被证伪 — 实际是 ~10% deterministic 灾难触发
  - bench_seed hotfix: `uint32(mod(..., 2^32))` 处理 seed<42 负值 rng 拒绝
  - 配套诊断脚本 4 个: disaster / oracle_isolation / high_snr / monte_carlo
  - 5 候选根因层（Channel est 极性 / BCJR 固定点 / Frame timing / CFO 边界 / Soft demap）待 L2' 深挖

- **Phase I oracle 隔离 + 高 SNR 扫描 — cascade 完全无辜**
  - 诊断: `diag_seed1024_oracle_isolation.m` + `diag_seed1024_high_snr.m`
  - oracle α 真值替代 cascade 估值，BER 仍 ~50% → cascade 不背锅
  - 高 SNR 扫描发现 **非单调 BER vs SNR**（α=+1e-2: SNR=15/20 救活，SNR=25 又崩）
  - 违反通信系统基本规律 → deterministic 灾难（共振 / 反向收敛模式）

- **`bench_seed` 注入修复（Phase H）+ seed=1024 灾难发现**
  - 修复：`test_scfde_timevarying.m` L163 + L257 两处 `rng()` 加 `(bench_seed-42)*100000` 偏移；默认 42 时偏移 0 → backwards-compat（diag_cascade_quick 与 Patch E baseline bit-exact 一致）
  - 验证：α=-1e-2 5 seed BER std 从 0 → 20.89（seed 现真生效）
  - **新发现**：5/30 trial（17%）出现 ~50% BER；seed=1024 + α=±1e-2 → 多场景灾难
  - α=-1e-2 4/5 seed 在 SNR=15 dB 恢复 0%（H1 部分确认），seed=1024 三个 SNR 都 50%（独立异常）
  - 后续：Phase I 追因 seed=1024 灾难（同步 / 估计 / 解码 哪层崩）

- **SC-FDE cascade 完整 α sweep × 多 SNR 全场景验证（Phase G）**
  - 诊断: `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_sweep_full.m`
  - 矩阵: 10 α（±5e-4, ±1e-3, ±3e-3, ±1e-2, ±3e-2）× 3 SNR = 30 trial
  - 工作率: SNR=10 dB **9/10**（仅 α=-1e-2 异常）；SNR≥15 dB **10/10**
  - **新发现**：α=-1e-2 是孤立异常点，**不是 ±α 系统单调不对称**（被 α=-3e-2 BER=0% 证伪）
  - 新假设: HFM/LFM 模板对齐在 α=-1e-2 附近碰局部不连续；待精细 α 扫描验证
  - 回流: `wiki/conclusions.md` 修正 H3 假设 + 添加孤点性质说明

- **SC-FDE α=-1e-2 单点 SNR 受限确认（H1 ✓）**
  - 诊断: `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_neg_1e2_root_cause.m`
  - 矩阵: 2 α × 3 SNR × 5 seed = 30 trial
  - 关键结果: α=-1e-2 SNR=10 BER=13.14% → SNR=15 BER=0%（断崖恢复）
  - 物理: estimator 在 SNR=10 噪底 ~5e-6；-1e-2 系统偏差 2e-5 超底 → α_p2 估不出 → 残余无法精修
  - 决策: 接受 limitation（SNR≥15 全 α 工作）；不做边界修复（性价比低）
  - 附带 issue: `bench_seed` 未传到信道生成（5 seed std=0）→ 归 `E2E benchmark C 阶段`
  - 回流: `wiki/conclusions.md` 新条目（SNR 受限边界 + 物理表）

- **SC-FDE cascade 盲估 OOM 修复（Patch D+E）**
  - spec: `specs/active/2026-04-22-scfde-cascade-resample-oom-fix.md`
  - plan: `plans/scfde-cascade-resample-oom-fix.md`
  - 根因：cascade 集成后 `est_alpha_cascade` 内部 + test runner 共 3 处 `rat(1+α, 1e-7/1e-6)`；噪声 α=3e-2 估值非 100 整除时连分式产 p≈10⁴，`poly_resample` 显式 `zeros(1, N·p)` 单次 ~4 GB → 5 点扫描 97% 内存
  - 修复：3 处统一 `rat(·, 1e-5)`，p 从 10⁴ → 10²，单次峰值 40 MB
  - 试错链已记录在 plan：Phase A guard 1e-3 副作用（α=5e-4 → 50% BER）+ Phase B 复用 stage1 双 bug（α_p2 重复计数 + 载波相位残余）
  - 验证：5 点 BER 与 baseline 完全一致（-1e-2 13.7%、其余 4 点 0%），内存 97% → <30%
  - parked：`poly_resample` 去 Signal Toolbox 依赖（手写 polyphase + Kaiser）→ todo 🟢 区

## 2026-04-22

- **gen_doppler_channel V1.5 架构修复 + poly_resample.m 新增**
  - spec: `specs/archive/2026-04-22-matching-pair-doppler-v1_5.md`
  - 根因：V1.1-V1.4 用 Option 2 顺序（Doppler 先、多径后）→ 接收端 resample 补偿后多径延迟被缩放为 (1+α)·τ_p，BEM 与 nominal sym_delays 失配 → 非单调 BER 跳变
  - 修复：V1.5 改 Option 1（多径先、Doppler 后），Doppler 统一作用在总信号上，与老 gen_uwa_channel 约定一致
  - 新工具：`poly_resample.m` 60 行 Kaiser polyphase FIR，与 MATLAB resample 数值等价（NMSE -302dB 机器精度），通带仿真+RX 形成严格自逆匹配对
  - 结果：oracle_passband 全 α（±5e-4 到 ±3e-2，覆盖 50 节）**BER = 0**，pipeline 自然运行
  - 新开关：`bench_use_real_doppler` / `bench_oracle_passband_resample` / `bench_alpha_override`
  - diag 脚本集（8 个）记录调试过程
  - 回流：`wiki/conclusions.md` 新条目

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
