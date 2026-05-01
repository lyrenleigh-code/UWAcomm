---
project: uwacomm
type: feature
status: active
created: 2026-04-28
parent: 2026-04-15-streaming-framework-master.md
related: [2026-04-22-p4-real-doppler-fork.md, 2026-04-26-scfde-time-varying-pilot-arch.md]
phase: P4-ui-alignment
tags: [流式仿真, 14_Streaming, UI, P4, 算法对齐, SC-FDE, Phase5]
---

# P4 UI ↔ 算法升级对齐

## 目标

把 2026-04-22 之后的算法层升级（**Jakes 时变衰落 + SC-FDE Phase 4+5 协议层参数**）真实透传到 P4 demo UI 后端：

**主目标**：用户在 UI 选 "slow Jakes" 时，`sys.{scheme}.fading_type` 真正变 `'jakes'` 且 `fd_hz` 取 UI 值（而非 hardcode `'static'/0`）—— 让 modem encode/decode 走时变路径。

**次目标**：暴露 SC-FDE V4.0 `cfg.pilot_per_blk` / `cfg.train_period_K` 透传通道（默认值保持 V1.0 行为：`pilot_per_blk=0` / `train_period_K=N_blocks-1`，向后兼容），为后续 follow-up spec（blk_cp < blk_fft 重设计 + pilot 控件 + V4.0 默认激活）铺路。

**不在本次范围**：V4.0 突破自动激活——实测 setup 要求 `blk_cp=128 < blk_fft=256`（diag_a3/a4），而 P4 UI 当前默认 `blk_cp = blk_fft`（apply_scheme_params V1.0 设计）。强行 `pilot_per_blk = blk_cp` 在 `blk_cp == blk_fft` 时会让 `N_data_per_blk = 0`，编码 0 比特。改此设计需重设计 SC-FDE 行（blk_fft 与 blk_cp 解耦控件），超本 spec 范围。

## 非目标

- **P3 不动**（已冻结 static-only 对比基准，2026-04-22 决议）
- **不接 14_Streaming P5/P6**（独立 phase）
- **不改 modem_encode/decode_scfde**（V4.0/V4.1 已 PASS）
- **不引入 SC-TDE V5.6 HFM signature toggle**（14_Streaming `modem_decode_sctde` 不带 post-CFO 伪补偿，仅 13_SourceCode runner 受影响；UI 走 14 路径天然干净）
- **不动 OTFS rx_chain 真重写**（已通过 dispatcher 路由）
- **不改 `gen_doppler_channel` 信道接入**（058cee7 已 fork 完）

## 不一致清单（调研结论 2026-04-28）

| 层 | 文件 / 位置 | 状态 |
|---|---|---|
| 算法 | `modem_encode_scfde V4.0` (`tx/`) + `modem_decode_scfde V4.1` (`rx/`) | ✅ 支持 `cfg.pilot_per_blk` / `cfg.train_period_K` |
| 算法 | SC-TDE V5.4 (runner) / DSSS V1.2 (runner) | ✅ 但 14_Streaming modem_decode 不带伪补偿，UI 路径不受影响 |
| 算法 | OTFS `rx_chain.rx_otfs` 真重写 + spread pilot + SLM/clip PAPR | ✅ 通过 dispatcher 路由 |
| 信道 | `gen_doppler_channel V1.5` 接入 P4 (058cee7) | ✅ `p4_demo_ui.m:918` |
| **UI 前端** | `p4_demo_ui.m:287/292` 已加 `static / slow Jakes / fast Jakes` 下拉 + `fd_hz` 输入 | ✅ 控件存在 |
| **UI 透传** | `p4_demo_ui.m:864` `ui_vals` 构造 | ❌ 不传 `fading_type` / `fd_hz` / `pilot_per_blk` / `train_period_K` |
| **UI 后端** | `p4_apply_scheme_params.m` V1.0.0 (2026-04-22 抽自 P3) | ❌ 6 体制全 hardcode `fading_type='static'` + `fd_hz=0` |

**后果**：用户在 UI 选 "slow Jakes" → channel 跑时变，但 modem encode/decode 用 static 配置 + V3 之前 SC-FDE 路径 → 重现 jakes fd=1Hz 50% 灾难，演示不到协议层突破。

## 实施步骤

### S1 — `p4_apply_scheme_params.m` V2.0（核心透传）
- 6 体制按 schema 透传 `ui_vals.fading_type` / `ui_vals.fd_hz`
- SC-FDE 加 `ui_vals.pilot_per_blk` / `ui_vals.train_period_K` 透传字段（默认保持 V1.0 行为：`pilot_per_blk=0` / `train_period_K=N_blocks-1`）
- 字段映射 helper：UI 字符串 'static (恒定)' → `'static'`；'slow ...' / 'fast ...' → `'jakes'`（fd_hz 字段单独承载快慢区分）

### S2 — `p4_demo_ui.m` `ui_vals` 构造改造（不加新控件）
- L864 `ui_vals` 加 2 字段（必需）：`fading_type` (从 `app.fading_dd.Value`) / `fd_hz` (从 `app.jakes_fd_edit.Value`)
- 不加 `pilot_per_blk` / `train_period_K` 控件（留给 follow-up spec，等 SC-FDE blk_cp/blk_fft 解耦后再加）

### S3 — Smoke 测试
- `tests/test_p4_ui_alignment_smoke.m`：4 case
  - C1 SC-FDE static + 默认控件 → assert `sys.scfde.fading_type=='static'` && `fd_hz==0` && `pilot_per_blk==0` && `train_period_K==N_blocks-1`（V1.0 兼容）
  - C2 SC-FDE slow Jakes (fd=1Hz) → assert `sys.scfde.fading_type=='jakes'` && `fd_hz==1`
  - C3 SC-TDE fast Jakes (fd=5Hz) → assert `sys.sctde.fading_type=='jakes'` && `fd_hz==5`
  - C4 OTFS slow Jakes (fd=2Hz) → assert `sys.otfs.fading_type=='jakes'` && `fd_hz==2`
- 不跑 modem_encode/decode（仅 assert sys 字段透传），避免引入信道层依赖

### S4 — 用户验收
- 在 P4 demo UI 实跑 SC-FDE / SC-TDE / DSSS / OTFS slow Jakes fd=1Hz 各一次，BER 进入合理区间（不再 50%）
- 注意：SC-FDE 在当前 UI 默认 `blk_cp=blk_fft` 下走单训练块路径（与 V3 之前等价），**jakes fd=1Hz 仍可能 ~50%**——这是已知 limitation（R1 + R4），需 follow-up spec 解决
- 记录到 `wiki/debug-logs/14_Streaming/流式调试日志.md` 2026-04-28 章节

## 接受准则

- [ ] `p4_apply_scheme_params V2.0` 4 体制（SC-FDE/OFDM/SC-TDE/DSSS/OTFS）正确透传 `fading_type` / `fd_hz`，FH-MFSK 不动（无 fading 字段）
- [ ] `p4_apply_scheme_params V2.0` SC-FDE 加 `pilot_per_blk` / `train_period_K` 透传字段（默认保持 V1.0）
- [ ] smoke 测试 4/4 PASS
- [ ] (用户验) UI slow Jakes fd=5Hz SC-TDE/OTFS → sys 字段透传正确 + 跑出非 static BER 曲线
- [ ] (用户验) UI static (fd=0) → 与 28a4bc6 baseline 完全等价（回归）

## 已知风险

- **R1**：本次实施不重新推导 SC-FDE N_info（pilot_per_blk 默认 0 → N_data_per_blk = blk_fft → N_info 公式与 V1.0 等价）。若后续启用 V4.0 突破（pilot_per_blk > 0），N_info 需重算（modem_encode_scfde V4.0 内部 L80-86 已自动 pad/截断，但 caller 应优先传对的值避免 padding 噪声）。**缓解**：follow-up spec 处理。
- **R2**：DSSS / FH-MFSK schema 差异。DSSS V1.0 已支持 `fading_type` / `fd_hz` 字段（grep 验证），按现有 schema 透传即可。FH-MFSK 信道层独立处理，本 spec 不动其 schema。
- **R3**：SC-FDE V4.0 突破在当前 UI 默认（blk_cp=blk_fft）下不会自动激活。这是设计耦合，需要 follow-up spec 解耦 blk_cp/blk_fft 控件 + 加 pilot_per_blk 控件。
- **R4**：用户在 UI 选 "slow Jakes" 后 SC-FDE BER 仍可能 ~50%，因为 V4.0 路径未激活——这是 R3 的延伸 limitation，需明确告知用户。

## OUT-OF-SCOPE 备忘

- P3 UI（保持 static-only 参考）
- 14_Streaming P5/P6
- SC-TDE V5.6 HFM signature toggle（14_Streaming 不需要）
- `gen_doppler_channel V1.5` 信道层（已 fork）
- SC-FDE blk_cp/blk_fft 解耦 + V4.0 自动激活（follow-up spec：UI pilot_per_blk 控件 + `blk_cp` 独立控件）
