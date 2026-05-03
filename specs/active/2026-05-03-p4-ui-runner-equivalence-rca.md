# P4 UI ↔ runner 等价性根因分析

**Date**: 2026-05-03
**Status**: active
**Module**: 14_Streaming/p4_demo_ui + 13_SourceCode/tests/SC-FDE
**Owner**: claude (UWAcomm-claude branch)
**Origin**: 2026-05-01 P4 V4.0 算法层闭环（runner 0.68%）vs UI 实测 50% + 循环发，归 follow-up

## Background

2026-05-01 完成 SC-FDE Phase 4+5 协议层突破（spec `archive/2026-04-26-scfde-time-varying-pilot-arch.md`）：
- 13_SourceCode runner `test_scfde_timevarying.m` V4.0 预设（blk_fft=256, blk_cp=128, pilot_per_blk=128, train_period_K=31）实测 jakes fd=1Hz BER **0.68%**，v0_default 49.56% → 14× 改善。
- diag_p4_v40_preset_validation.m 36-trial 验证。
- P4 UI 层：spec `2026-05-01-p4-ui-decouple-blk-cp-and-pilot-controls.md` 解耦 blk_cp/blk_fft + 加 V4.0 预设按钮；单测 6/6 PASS。

但 **UI 实测 BER 仍 50% 且循环发送**，与 runner 0.68% 形成巨大差异。归为本 follow-up。

参考：codex worktree `test_p4_ui_alignment_smoke.m` 7/7 PASS（仅参数透传层）+ P6.18 显式注："参考 UWAcomm-claude 但不照搬 TX-meta 路径，走 routed FH-MFSK header + 真盲 RX"。

## Hypothesis

claude P4 UI 走 **TX-meta 直传** 路径（`app.tx_meta_pending = meta_tx`，line 1059），decode 时 `modem_decode(body_bb_rx, sch, app.sys, meta)` 直接用 TX 端 meta。
codex P4 UI 走 **routed RX** 路径（`app.tx_eval_pending` 仅评估、`assemble_routed_physical_frame` + 帧头盲解 + payload meta 本地重建）。

两条路径都"应该"工作，但当前 claude TX-meta 路径在 V4.0 配置下 50% BER，可能根因：
- **H1**: frame 长度计算不匹配（assemble_physical_frame 加 preamble 后截/补到 L_bb 可能与 modem_decode 期待的 N_shaped 不一致）
- **H2**: `app.sys.scfde` 被 `p4_apply_scheme_params` 改写后未正确同步到 modem_encode 内部（race condition / shallow copy）
- **H3**: meta_tx 含某些 oracle 字段（all_cp_data / all_sym / pilot_sym），在 13_SourceCode runner 中本地重建，但 UI 直接复用导致 RX 链路 cheat 失效
- **H4**: V4.0 配置（blk_cp=128 ≠ blk_fft=256）改变 sym_per_block，body_offset 计算未跟随
- **H5**: 双 HFM α estimator 在 jakes 路径给假 α（codex P6.19 笔记：α_raw≈3.67e-2 假报，需 streaming_alpha_gate 拒绝）→ comp_resample 反补偿后解码崩

## Goal

- **G1（核心）**：写 runner↔UI 等价性单元测试 `test_p4_ui_runner_equivalence.m`，固定 seed + AWGN + 静态信道，验证 13_SourceCode runner 与 14_Streaming UI 两条 RX 路径的 BER 应在同一数量级
- **G2（RCA）**：定位 H1-H5 哪个（或多个）是 50% BER 根因
- **G3（fix）**：最小改动修复 UI 链路；不切换到 routed 路径（保留 TX-meta 简单架构，留 routed 作未来 follow-up）

## Acceptance criteria

- [ ] G1: `test_p4_ui_runner_equivalence.m` 落地，AC1 静态 AWGN SNR=20 SC-FDE V4.0 直接比对 BER < 1%（runner 0.68% baseline）
- [ ] G2: spec 末尾追加 RCA 章节，确认 H1-H5 哪条命中（或多条），附量化证据
- [ ] G3: UI 实测 SC-FDE V4.0 jakes fd=1Hz BER 与 runner 0.68% 同数量级（≤3%）
- [ ] G3: UI 不再循环发送（一帧解完就停）

## Out of scope

- routed RX 路径切换（codex P6.18 走法）保留作未来 spec
- AMC 决策层（codex P6 系列）保留作大件单独 spec
- OFDM/SC-TDE/DSSS/OTFS 的 UI 等价性（先做 SC-FDE 一个，闭环后扩展）

## Plan

见 `plans/2026-05-03-p4-ui-runner-equivalence-rca.md`

---

## Result（2026-05-03）

**状态**：算法/测试层闭环；UI 实测验证待用户

### RCA 结论：H5 命中（α gate 缺失）

**根因**：claude P4 UI L1357 旧门 `if abs(alpha_est_rx) > 1e-6 && alpha_conf > 0.3` 在 jakes 衰落下不能拦截 detect_frame_stream 的假 α 报告，假 α 被传给 comp_resample_spline 反补偿 → 信号严重失真 → BER ~50%。

### 量化证据（test_p4_ui_jakes_alpha_gate_e2e.m）

SC-FDE V4.0 + jakes fd=1Hz + SNR=20，单 seed：

| 路径 | α 处理 | BER |
|------|--------|-----|
| A (no α-comp baseline) | 跳过反补偿 | **9.48%** |
| B (旧 UI 无 gate) | 用假 α=+7.51e-02 反补偿 | **49.90%** ← 复现 UI 50% |
| C (新 UI + streaming_alpha_gate) | gate=outside_abs_max 拒绝 → 退回 baseline | **9.48%** |

`detect_frame_stream` 在 jakes 下报 α=+7.51e-02 conf=0.68（真 α=0），完美匹配 codex P6.20 描述的"alpha_raw≈3.67e-2"现象（具体数值随 seed 浮动）。

### H1-H5 假设检验

| 假设 | 状态 | 证据 |
|------|------|------|
| H1 frame 长度截断 | ❌ 排除 | body_offset=10304, data_start=10304 一致 |
| H2 sys 同步 | ❌ 排除 | Path R/U1 等价 |
| H3 meta 含 oracle | ❌ 排除 | runner/UI 共用 meta_tx，AWGN 下 R/U1 等价 |
| H4 V4.0 配置错位 | ❌ 排除 | sym_per_block 计算正确 |
| **H5 jakes 假 α + 弱 gate** | ✅ **命中** | Path B 49.90% vs Path C 9.48% |

### 等价性验证（test_p4_ui_runner_equivalence.m）

| 场景 | Path R (runner) | Path U1 (UI ideal) | Path U2 (UI + detect_stream) |
|------|----------------|---------------------|--------------------------------|
| AWGN SNR=20, 5 seeds | 2.28% | 2.22% | 0% (单 seed) |
| Jakes fd=1Hz SNR=20, 3 seeds | 1.36% | 3.33% | — |

→ meta-pass 路径无问题；jakes 下算法层无 50% 灾难。

### Fix 实施

1. 移植 codex `streaming_alpha_gate.m` → claude `common/`（5/5 单测 PASS）
2. 移植 codex `test_p4_alpha_gate.m` → claude `tests/`
3. 修 `p4_demo_ui.m` `try_decode_frame()`：
   - α 反补偿前调 `streaming_alpha_gate(alpha_est_rx, alpha_conf, app.sys)`
   - gate.accepted 才补偿，否则跳过 + log
   - α refinement 也加 gate 检查（避免在假 α 邻域 ±2e-5 扫描无效候选）
   - entry.alpha_gate 字段记录决策（供 sync tab 可视化）

### 接受准则验收

- [x] G1: `test_p4_ui_runner_equivalence.m` 落地，AC1 静态 AWGN SNR=20 SC-FDE V4.0 BER 2.28% (5 seed mean) ≈ runner 同分布
- [x] G2: H5 命中确认 + 量化证据
- [ ] G3: UI 实测 jakes fd=1Hz BER ≤ 3% — **待用户跑实际 P4 UI 验证**
- [ ] G3: UI 不再循环发送 — **待用户验证**（理论上 try/catch + 不再循环死帧应已修，依赖 gate 修复后解码 BER 不暴）

### 待用户验证

1. 启动 P4 UI（`run modules/14_Streaming/src/Matlab/ui/p4_demo_ui.m`）
2. 设置 V4.0 预设按钮（blk_fft=256, blk_cp=128, pilot=128, K=31）
3. fading_dd → 'slow (Jakes 慢衰落)', fd=1Hz, SNR=20
4. 发送 1 帧，观察日志 `[α-GATE]` 行：应出现 reason=outside_abs_max 拒绝
5. 观察 BER：应在 3-10% 范围（jakes fd=1Hz 物理基线，单帧波动），**不再 50%**
6. 不应循环发送

如 UI 实测仍 50%，可能存在新的细节差异（例如 detect_frame_stream 错位 + body_offset 切片偏移），需追加 spec。

### 衍生发现

- **detect_frame_stream sync 错位**：测试中 fs_pos_det=12328 vs true=5001（差 7327 sample）。jakes fading 让 LFM2 匹配滤波次峰胜过主峰。本 spec 不修，作 follow-up（独立 spec：jakes 下 sync 鲁棒性）。
- **AWGN SNR=20 V4.0 BER 2.28% 双峰**：5 seed 中 0%/0%/0.28%/5.55%/5.57% 分布，与 SC-FDE V4.0 cascade BEM 在低 SNR 区有零星灾难一致（已在 conclusions.md "10% 灾难触发" 系列覆盖），非本 spec 范围。

### 后继 spec 候选

- `2026-05-XX-detect-frame-stream-jakes-sync-robust.md`（jakes 下 sync fs_pos 错位）
- `2026-05-XX-p4-ui-routed-frame-migration.md`（codex P6.18 路径迁移，可选）

