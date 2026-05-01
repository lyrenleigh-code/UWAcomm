# P4 UI ↔ 算法对齐 — 实施计划

参考 spec：`specs/active/2026-04-28-p4-ui-algo-alignment.md`

## 决策记录

**Q1: 是否在本 spec 让 V4.0 突破自动激活（pilot_per_blk = blk_cp）？**
**A1**: 不。诊断发现 Phase 5 实测 setup `blk_fft=256 / blk_cp=128`（diag_a3/a4），而 P4 UI 默认 `blk_cp = blk_fft = 128`。强行设 `pilot_per_blk = blk_cp = blk_fft` 会让 `N_data_per_blk = 0`（编码 0 比特灾难）。解耦 `blk_cp` 与 `blk_fft` 控件超本 spec 范围，留 follow-up。

**Q2: SC-TDE/DSSS 透传如何？**
**A2**: 仅传 `fading_type` / `fd_hz`。14_Streaming `modem_decode_sctde` / `modem_decode_dsss` 已不带 post-CFO 伪补偿（仅 13_SourceCode runner 受影响），UI 路径天然干净。

**Q3: OTFS？**
**A3**: 透传 `fading_type` / `fd_hz`（OTFS 时变路径已支持，c9c0601 spread pilot + rx_chain real）。

**Q4: FH-MFSK？**
**A4**: 不动。`sys.frame` schema 不含 `fading_type`，信道层独立处理。

## 步骤

### S1 — `p4_apply_scheme_params.m` V2.0
- 新版本头注释：V2.0.0（2026-04-28 P4 UI ↔ 算法对齐）
- 6 体制按 schema 透传 `fading_type` / `fd_hz`（FH-MFSK 例外）
- SC-FDE 分支加 `pilot_per_blk` / `train_period_K` 默认值（V1.0 行为：0 / N_blocks-1）
- 加 2 个 local helper：`local_parse_fading(ui_str)` + `local_get_or_default(s, fname, default_val)`

### S2 — `p4_demo_ui.m` `ui_vals` 构造
- L864 ui_vals 加 2 字段：`fading_type` (从 `app.fading_dd.Value`) / `fd_hz` (从 `app.jakes_fd_edit.Value`)
- 不加新控件（pilot_per_blk / train_period_K 留 follow-up）

### S3 — Smoke 测试 `tests/test_p4_ui_alignment_smoke.m`
- 4 case 全 assert sys 字段透传，不跑 modem encode/decode
- 测试遵循 CLAUDE.md MATLAB 测试调试流程（clear functions → cd → diary → run）

### S4 — 用户验收
- (用户跑) `test_p4_ui_alignment_smoke` 期望 4/4 PASS
- (用户跑) P4 demo UI 实测 — slow Jakes fd=5Hz SC-TDE/OTFS 看 BER 曲线变化

### S5 — 文档同步
- `wiki/debug-logs/14_Streaming/流式调试日志.md` 加 2026-04-28 章节
- 不归档 spec（待 S4 验收 + follow-up V4.0 激活完成）

## 测试矩阵

| 测试 | 类型 | 期望 |
|---|---|---|
| `test_p4_ui_alignment_smoke.m` | 单元（结构透传） | 4/4 PASS |
| (用户) UI fast Jakes fd=5Hz SC-TDE | E2E demo | sys.sctde 字段透传 + BER 反映时变 |
| (用户) UI static fd=0（回归） | E2E demo | 与 28a4bc6 baseline 等价 |

## 不在范围

- p3_apply_scheme_params 不动
- SC-FDE pilot_per_blk / train_period_K UI 控件
- SC-FDE V4.0 自动激活（需 blk_cp/blk_fft 解耦）
- 14_Streaming P5/P6
