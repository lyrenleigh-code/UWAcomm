---
project: uwacomm
type: feature
status: active
created: 2026-05-01
parent: 2026-04-28-p4-ui-algo-alignment.md
related: [2026-04-26-scfde-time-varying-pilot-arch.md, 2026-04-22-p4-real-doppler-fork.md]
phase: P4-ui-decouple
tags: [流式仿真, 14_Streaming, UI, P4, SC-FDE, V4.0, blk_cp, pilot]
---

# P4 UI 解耦 SC-FDE blk_cp/blk_fft + 加 pilot 控件

## 目标

让 SC-FDE V4.0 协议层突破（jakes fd=1Hz 47%→3.37%，14× 改善，archive `2026-04-26-scfde-time-varying-pilot-arch.md` 实测）在 P4 demo UI 上**真正可激活**。

**主目标**：UI 加 3 个 SC-FDE 专属控件（`blk_cp` / `pilot_per_blk` / `train_period_K`），把 `p4_apply_scheme_params V2.0` 已通好的字段透传通道用起来。

**次目标**：
- 加 "V4.0 Jakes 推荐预设"按钮，一键设 `blk_fft=256, blk_cp=128, pilot_per_blk=128, train_period_K=8`（runner 验证组合）
- 控件级校验逻辑（`blk_cp ≤ blk_fft`、`pilot_per_blk ≤ blk_cp`、`train_period_K ∈ [1, N_blocks-1]`）
- 校验失败给出明确报错（不让用户跑出 BER=50% 才发现配置错）

**不在本次范围**：
- modem_encode/decode_scfde 算法层改动（V4.0/V4.1 已 PASS）
- 其他体制（OFDM/SC-TDE/DSSS/OTFS/FH-MFSK）不动
- runner ↔ UI 等价性单元测试（独立 follow-up，todo §middle "P4 UI follow-up runner↔UI 等价"）

## 非目标

- 不动 P3 demo UI（已冻结）
- 不引入 oracle toggle 控件（独立 follow-up）
- 不解决 bypass=ON dop=10 SC-FDE 残余 35.9%（独立 follow-up，下一项任务）
- 不动 `streaming_apply_modem_params.m` AMC 路径（P6 阶段事）

## 调研结论 2026-05-01

| 层 | 文件 / 状态 |
|---|---|
| 算法 | `modem_encode_scfde V4.0` + `modem_decode_scfde V4.1` ✅ 支持 cfg.pilot_per_blk / cfg.train_period_K |
| 字段透传 | `p4_apply_scheme_params V2.0` ✅ pilot_per_blk / train_period_K passthrough（默认 V1.0 兼容） |
| 强制赋值 | `p4_apply_scheme_params.m:46` ❌ `sys_out.scfde.blk_cp = sys_out.scfde.blk_fft` 锁死 |
| UI 控件 | `p4_demo_ui.m:308-312` ❌ 仅 `blk_dd` 单一 dropdown（blk_fft），无 blk_cp / pilot_per_blk / train_period_K |
| ui_vals 构造 | `p4_demo_ui.m:868-873` ❌ 不传 pilot_per_blk / train_period_K |
| Codex 进度 | `p4_apply_scheme_params V1.0` ✅ 字段通道；UI 控件 ❌ 同样未做 |

**结论**：双方都卡在 UI 控件这一步。本 spec 把控件做出来 + 解 codex 与 claude 都标记的 follow-up。

## 实施步骤

### S1 — `p4_apply_scheme_params V3.0`（解耦 blk_cp）

- 删 L46 强制赋值 `sys_out.scfde.blk_cp = sys_out.scfde.blk_fft`
- 改读 `local_get_or_default(ui_vals, 'blk_cp', sys_out.scfde.blk_fft)`（缺省 fallback = blk_fft，向后兼容）
- N_info 推导按 V4.0 公式（参 `modem_encode_scfde.m:35,49-60,81`）：
  - **公式**：`N_info = (blk_fft - pilot_per_blk) * N_data_blocks - mem`
  - `N_data_blocks` 取决于 `train_period_K`：
    - `K >= N_blocks - 1` → `N_data_blocks = N_blocks - 1 = 31`（单训练块，V1.0 兼容）
    - `K < N_blocks - 1` → `N_train_blocks = floor(N_blocks/(K+1)) + 1`，`N_data_blocks = N_blocks - N_train_blocks`
  - 默认（pilot=0, K=31）：`N_info = blk_fft * 31 - mem`（V2.0 等价 ✓）
  - V4.0 推荐（blk_fft=256, pilot=128, K=8）：`N_train_blocks = floor(32/9)+1 = 4`，`N_data_blocks = 28`，`N_info = 128 * 28 - mem = 3584 - mem`
  - **注意**：`blk_cp` 不进 N_info 公式（仅影响 sym_per_block=blk_cp+blk_fft 的信道时延裕度）；用户应让 `pilot_per_blk == blk_cp` 才能激活 V4.0 干净 BEM 物理条件（spec 实测："CP 段是 pilot 副本 → ~1178 干净 BEM obs/帧"）

### S2 — `p4_demo_ui.m` UI 控件加 3 个

**新增控件**（仅 SC-FDE 时显示）：
- `app.blk_cp_dd` dropdown：`{'64', '128 (V4.0 推荐)', '256'}`，默认 `'128 (V4.0 推荐)'`
- `app.pilot_edit` numeric edit：limits `[0 256]`，默认 `0`（V1.0 兼容）
- `app.train_K_edit` numeric edit：limits `[1 31]`，默认 `31`（V1.0 兼容 = N_blocks-1）

**Layout**：tx_grid Row 14 已被 blk_fft 占，需重排：
- Row 14: blk_fft (existing)
- Row 15: blk_cp (new)
- Row 16: pilot_per_blk (new)
- Row 17: train_period_K (new)
- Row 18: turbo_iter (从 15 往下顺移)
- Row 19+: FH-MFSK / OTFS / TX info 顺移
- 注意 txinfo_panel `Row = [17 18]` 也要往下顺移到 [20 21]

**可见性**（在 `on_scheme_changed`）：
- `blk_cp_dd`, `pilot_edit`, `train_K_edit` 仅 SC-FDE 显示（不和 OFDM/SC-TDE 共用，因 OFDM 有自己的 blk_cp 计算公式 `round(blk_fft/2)`）

**校验**（在 `on_transmit` 入口前 / on_apply_button）：
- 解析 blk_cp，若 > blk_fft → 弹错并 return
- 解析 pilot_per_blk，若 ≥ blk_fft → 弹错并 return（modem_encode L36 assert 条件）
- 提示：若 `pilot_per_blk != blk_cp` → 弹 warning（V4.0 干净 BEM 物理条件偏离，BER 会差）
- 解析 train_period_K，若不在 [1, 31] → uieditfield Limits 已自动卡

**ui_vals 构造**（L868-873）：
- 加 3 字段：`blk_cp` / `pilot_per_blk` / `train_period_K`
- SC-FDE 之外的体制传值无害（apply_scheme_params 只读 SC-FDE 分支）

### S3 — V4.0 推荐预设按钮

新增 `app.preset_v40_btn`（仅 SC-FDE 显示）：
- Text: 'V4.0 Jakes 推荐'
- Callback: 一键设 `blk_fft=256, blk_cp=128, pilot_per_blk=128, train_period_K=8`
- 同时弹消息提示："已应用 V4.0 推荐：BEM obs ~1178/帧，jakes fd=1Hz 实测 BER 3.37%（runner 数据）；吞吐损失 ~50%"

Layout: 放 Row 18（turbo_iter 之后，仅 SC-FDE 可见）

### S4 — Smoke 测试

`tests/test_p4_apply_scheme_params_v3.m`：6 case
- C1 SC-FDE 默认（pilot=0，blk_cp 缺省）→ blk_cp=blk_fft=128，pilot_per_blk=0，N_info 与 V2.0 等价
- C2 SC-FDE V4.0 推荐（blk_fft=256, blk_cp=128, pilot_per_blk=128, train_period_K=8）→ 字段正确透传
- C3 SC-FDE 自定义（blk_fft=256, blk_cp=64, pilot_per_blk=64, train_period_K=4）→ N_info 推导正确（N_train_blocks=floor(32/5)+1=7，N_data_blocks=25，N_info=(256-64)*25-mem=4800-mem）
- C4 OFDM 默认 → blk_cp=round(blk_fft/2)（不受影响）
- C5 SC-TDE 默认 → 不读 blk_cp（不受影响）
- C6 边界 — pilot_per_blk > blk_cp → apply_scheme_params 应该如何？（**决策**：函数级不校验，让 modem_encode 自己 fail；UI 层做控件校验）

不跑 modem_encode/decode（仅 assert sys 字段透传）

### S5 — 用户验收

- 在 P4 demo UI：
  - 选 SC-FDE + 默认参数（pilot=0）+ slow Jakes fd=1Hz → 重现 ~50% BER（V1.0 兼容路径）
  - 点 "V4.0 Jakes 推荐" + slow Jakes fd=1Hz → BER 应进入 3-10% 区间（runner 数据 3.37%，UI 路径可能略高因 sync/CFO 抖动）
  - 选 SC-FDE + 默认 + static → BER 0%（回归保护）
- 记录到 `wiki/debug-logs/14_Streaming/流式调试日志.md` 2026-05-01 章节

## 接受准则

- [ ] `p4_apply_scheme_params V3.0` 删除 L46 强制赋值，改读 ui_vals.blk_cp（缺省 fallback = blk_fft）
- [ ] UI 加 blk_cp / pilot_per_blk / train_period_K 3 控件 + V4.0 推荐预设按钮
- [ ] 控件可见性：仅 SC-FDE 显示（OFDM/SC-TDE/DSSS/OTFS/FH-MFSK 隐藏）
- [ ] ui_vals 加 3 字段透传到 apply_scheme_params
- [ ] smoke 测试 6/6 PASS
- [ ] (用户验) UI 默认 + static SC-FDE → 与 ced0d9a baseline 等价（回归）
- [ ] (用户验) UI V4.0 推荐 + jakes fd=1Hz SC-FDE → BER 显著低于默认路径（接近 runner 3.37%）

## 已知风险

- **R1**：N_info 推导公式需精确匹配 `modem_encode_scfde V4.0` 内部逻辑。若推导偏差 → 编码字节数错位 / padding 噪声。**缓解**：S4 C2/C3 单测覆盖；用户验收时检查 TX info 面板的 N_info 数字是否合理。
- **R2**：layout 行号顺移影响多处。**缓解**：检查所有 `Layout.Row = N` 赋值，列出依赖文件后批量改。
- **R3**：`p4_apply_scheme_params V3.0` 的 N_info 推导若 pilot_per_blk > 0 时与 modem_encode 内部 padding 有 off-by-one → 编码 0 比特或 N_info 异常大。**缓解**：参考 `modem_encode_scfde V4.0:80-86` 实际逻辑写推导；C3 单测精确数值断言。
- **R4**：UI 校验只在 on_transmit 触发，控件值已经写入 sys 后才发现错。**缓解**：校验放 on_transmit 最前面，未通过直接 return；考虑 ValueChangedFcn 即时校验（次优）。
- **R5**：本 spec 不做 runner ↔ UI 等价性测试（独立 follow-up），用户可能验收时发现 V4.0 BER 与 runner 偏差大但难定位。**缓解**：用户验收只要"显著低于默认路径"即接受，精确等价归 follow-up。

## OUT-OF-SCOPE 备忘

- bypass=ON dop=10 SC-FDE 残余 35.9%（独立 follow-up，下一项任务）
- runner ↔ UI 等价性单元测试（独立 follow-up，第三项任务）
- oracle toggle 暴露（todo §middle）
- tv 模型 + Jakes 组合（todo §middle，需 jakes wrapper / 扩展 gen_uwa_channel）
- AMC 移植 codex（待 P5 完成）
