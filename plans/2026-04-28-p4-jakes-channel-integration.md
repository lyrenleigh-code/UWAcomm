# P4 Jakes 信道接入 — 实施计划

参考 spec：`specs/active/2026-04-28-p4-jakes-channel-integration.md`

## 决策记录

**Q1: 用 `gen_uwa_channel` 还是 `apply_channel`？**
**A1**: `gen_uwa_channel`（13/common）。`apply_channel` 的 'jakes' 模式内部就调 `gen_uwa_channel`，且把 `doppler_rate=fd_hz/fc` 绑死，无法独立控制 bulk α（用户的 dop_hz）和 Jakes fd_hz。直接用 `gen_uwa_channel` 可让 doppler_rate=alpha_b（来自 dop_hz）和 fading_fd_hz=jakes_fd_edit 物理独立。

**Q2: tv 模型与 Jakes 组合？**
**A2**: 不组合。`gen_uwa_channel` 不接受 tv struct，改造它超本 spec 范围。Jakes 模式下 tv 控件被忽略 + UI 警告。如需 tv+Jakes 组合，开 follow-up（写 jakes wrapper 接受 tv）。

**Q3: jakes seed？**
**A3**: 每次 transmit `randi([1,1e6])`，模拟真实 random。用户多次测看到不同 realization，符合工程 demo 直觉。reproducibility 留 follow-up（seed UI 控件）。

**Q4: noise_var 在哪加？**
**A4**: `gen_uwa_channel` 调用时 `snr_db=Inf`，噪声在 UI 现有 AWGN 段统一加（与 static 路径一致），避免 jakes 路径双重加噪。

## 步骤

### S1 — `p4_demo_ui.m` channel 段分发改造
- L913-925 现有逻辑包成 `if startsWith(fading_str, 'static') ... else ... end`
- else 分支：构造 ch_params + 调 `gen_uwa_channel` + 长度对齐 + alpha_true 重建
- jakes+tv 时 append_log 警告
- ch_label 显示 jakes fd

### S2 — addpath
`p4_demo_ui` 启动逻辑（约 L40 setup 处）加 13_SourceCode/common 路径，确保 `gen_uwa_channel` 可被 dispatch。

### S3 — Smoke 测试 `tests/test_p4_jakes_channel_smoke.m`
- 不跑 modem，仅验证信道调用 + 输出形态：
  - C1 static fd=0 → gen_doppler_channel 路径，输出非空，长度对齐
  - C2 slow Jakes fd=2 → gen_uwa_channel 路径，h_time(:,1) ≠ h_time(:,end)（时变性确认）
  - C3 fast Jakes fd=10 → 同 C2，时变标准差更大

### S4 — 用户验收
- (用户跑) test_p4_jakes_channel_smoke 3/3 PASS
- (用户跑) UI 'slow Jakes' fd=2Hz SC-FDE 看 BER

### S5 — 文档同步
- `wiki/debug-logs/14_Streaming/流式调试日志.md` 加 2026-04-28 后续章节
- `wiki/log.md` 加条目

## 测试矩阵

| 测试 | 类型 | 期望 |
|---|---|---|
| `test_p4_jakes_channel_smoke.m` | 单元（信道调用） | 3/3 PASS |
| (用户) UI slow Jakes fd=2 SC-FDE static SNR=15 | E2E demo | BER 反映 Jakes（与 runner jakes5Hz 数据 ~50% 类似） |
| (用户) UI static fd=0 (回归) | E2E demo | 与 28a4bc6 等价 |

## 不在范围

- hybrid / discrete 信道模型
- tv + Jakes 组合
- p3 jakes
- jakes seed UI 控件
