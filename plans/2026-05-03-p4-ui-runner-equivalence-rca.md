# Plan: P4 UI ↔ runner 等价性 RCA

**Date**: 2026-05-03
**Spec**: `specs/active/2026-05-03-p4-ui-runner-equivalence-rca.md`

## 阶段

### Phase 1：alignment baseline 移植（codex 借鉴）

- 抄 codex `test_p4_ui_alignment_smoke.m` → claude（验证 V3.0 `p4_apply_scheme_params` 字段透传层是否正确）
- 期望：claude V3.0 应 7/7 PASS（参数层无问题）
- 不通过 → 先修参数层，再继续 Phase 2

### Phase 2：runner↔UI 等价性测试落地

- 新写 `tests/test_p4_ui_runner_equivalence.m`
- 静态 AWGN SNR=20，SC-FDE V4.0 预设
- 两路并行：
  - **Path R（runner-style）**：调 modem_encode → AWGN → modem_decode（不加 preamble、不下变频）
  - **Path U（UI-style）**：模拟 p4_demo_ui 流程：modem_encode → assemble_physical_frame → AWGN → detect_frame_stream → body 切片 → modem_decode
- 对比 BER + 关键中间变量（frame 长度 / body_offset / N_shaped / meta_tx 字段）

### Phase 3：H1-H5 分层 ablation

- 按测试结果定位假设：
  - 若 Path R 0.68%、Path U 50% → H1/H4 frame/body_offset 嫌疑
  - 若 Path R 0.68%、Path U 5% → H2 sys 同步问题
  - 若两路都 50% → V4.0 算法层有 regression（与 runner 0.68% 矛盾，需重跑 runner 复核）

### Phase 4：fix + UI 实测验证

- 实施 fix
- 跑 `test_p4_ui_runner_equivalence.m` 验证
- 用户跑实际 P4 UI 验证 jakes fd=1Hz 不再 50% + 不循环发
- spec/plan 归档 + commit

## Risk

- 测试脚本实现需准确模拟 UI 链路（不是简单调 encode/decode）
- frame 长度截/补逻辑容易踩坑（α<0 保留全长 vs 截到 L_bb）
- 多帧 fifo 模拟成本高，先做单帧测试
