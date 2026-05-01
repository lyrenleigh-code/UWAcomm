---
project: uwacomm
type: feature
status: active
created: 2026-04-28
parent: 2026-04-15-streaming-framework-master.md
related: [2026-04-22-p4-real-doppler-fork.md, 2026-04-28-p4-ui-algo-alignment.md]
phase: P4-jakes-channel
tags: [流式仿真, 14_Streaming, UI, P4, Jakes, 信道层]
---

# P4 Jakes 信道接入 — 让 fading_dd 控件真正起作用

## 目标

复活 `p4_demo_ui.m` L287 的 `app.fading_dd` 死链。当前用户在 UI 选 "slow Jakes 慢衰落" / "fast Jakes 快衰落" 时**完全无效**——根因是 `gen_doppler_channel V1.5` 不支持 Jakes 衰落多径，`p4_channel_tap` 只生成静态多径。

本 spec 接入 13_SourceCode 的 `gen_uwa_channel`（已含 Jakes 多径衰落实现，13 runner 一直在用），让 P4 UI 选 jakes 时走真 Jakes 路径，匹配 `wiki/modules/13_SourceCode/离散Doppler全体制对比.md` runner 数据上界。

## 非目标

- **不动 'static' 路径**（保持 `gen_doppler_channel` + `p4_channel_tap` 现状，含 tv 模型）
- **不接 hybrid Rician 模型**（apply_channel 的 K-factor 模式，留 follow-up）
- **不接 discrete 多径离散 Doppler**（13 disc-5Hz 数据，留 follow-up）
- **tv 模型与 Jakes 暂不组合**（gen_uwa_channel 不接受 tv struct；选 jakes 时 tv 被忽略，UI 提示用户）

## 不一致清单（调研 2026-04-28）

| 控件 | 现状 |
|---|---|
| `app.fading_dd` (static/slow Jakes/fast Jakes) | ❌ V2.0 透传到 `sys.{scheme}.fading_type`，但 channel 不读 |
| `app.jakes_fd_edit` (fd_hz) | ❌ V2.0 透传到 `sys.{scheme}.fd_hz`，但 channel 不读 |
| `gen_doppler_channel` | 只做 α(t) + 静态多径，**不含 Jakes** |
| `p4_channel_tap` | 只返静态多径 paths（不带时变 tap） |
| `gen_uwa_channel` (13/common) | ✅ 已实现 Jakes 多径 + bulk Doppler，13 runner 用（含 6 体制 disc/jakes 完整数据） |

## 物理模型对照

| 选项 | 接入 | bulk α 来源 | 多径时变 |
|---|---|---|---|
| 'static (恒定)' | `p4_channel_tap` + `gen_doppler_channel`（现状） | `dop_hz/fc` | ❌ 静态多径 |
| 'slow (Jakes 慢衰落)' | `gen_uwa_channel`（新接） | `dop_hz/fc` | ✅ Jakes，`fading_type='slow'`, `fading_fd_hz=jakes_fd_edit` |
| 'fast (Jakes 快衰落)' | 同上 | 同上 | ✅ Jakes，`fading_type='fast'` |

**bulk α 与 Jakes fd_hz 物理独立**：dop_hz 是 TX/RX 相对运动 Doppler；jakes_fd_hz 是散射体多径多普勒扩展。`gen_uwa_channel` 的 `doppler_rate` 和 `fading_fd_hz` 是两个独立参数，可同时设。

## 实施步骤

### S1 — `p4_demo_ui.m` channel 段加分支
`on_transmit()` L913-925 改为按 `app.fading_dd.Value` 选路径：

```matlab
fading_str = app.fading_dd.Value;
if startsWith(fading_str, 'static')
    % 现有路径（多径 conv + gen_doppler_channel）
    ...
else
    % Jakes 路径
    if strcmp(fading_str, 'slow (Jakes 慢衰落)')
        fading_type = 'slow';
    else
        fading_type = 'fast';
    end
    fd_jakes = app.jakes_fd_edit.Value;
    ch_params = struct( ...
        'fs',           app.sys.fs, ...
        'num_paths',    length(paths.delays), ...
        'delay_profile','custom', ...
        'delays_s',     paths.delays, ...
        'gains',        paths.gains, ...
        'doppler_rate', alpha_b, ...
        'fading_type',  fading_type, ...
        'fading_fd_hz', fd_jakes, ...
        'snr_db',       Inf, ...     % 噪声在 UI 端单独加
        'seed',         randi([1, 1e6]) );
    [frame_ch_raw, ch_info_jakes] = gen_uwa_channel(frame_bb, ch_params);
    % 长度对齐 + alpha_true 序列重建（gen_uwa_channel 不返 alpha_true）
    L_bb = length(frame_bb);
    if length(frame_ch_raw) >= L_bb
        frame_ch = frame_ch_raw(1:L_bb);
    else
        frame_ch = [frame_ch_raw, zeros(1, L_bb - length(frame_ch_raw))];
    end
    app.tx_alpha_true = alpha_b * ones(1, L_bb);  % bulk α 常数（Jakes fd 单独显示）
    ch_label = sprintf('%s | Jakes %s fd=%.1f Hz | α=%.2e', ch_label, fading_type, fd_jakes, alpha_b);
    if tv.enable
        append_log('[!] tv 模型在 Jakes 模式下被忽略（gen_uwa_channel 不支持组合）');
    end
end
```

### S2 — addpath 13_SourceCode/common
`p4_demo_ui` 启动处或 `on_transmit` 内首次调用前加 `addpath` 13_SourceCode/common（gen_uwa_channel 所在）

### S3 — Smoke 测试 `tests/test_p4_jakes_channel_smoke.m`
3 case 验证 channel 调用路径正确，**不跑 modem encode/decode**：
- C1 'static (恒定)' fd=0 → 调 `gen_doppler_channel`，frame_ch 长度 == frame_bb 长度
- C2 'slow (Jakes 慢衰落)' fd=2Hz → 调 `gen_uwa_channel`，输出非全零，多径 tap 确实时变（h_time 列间差异 ≠ 0）
- C3 'fast (Jakes 快衰落)' fd=10Hz → 同 C2，h_time 时变性更高

### S4 — 用户验收
- 4/4 smoke PASS（C1+C2+C3+ V2.0 兼容回归）
- (用户跑) UI 选 'slow Jakes' fd=2Hz SC-FDE static `dop_hz=0` SNR=15 → BER 进入 jakes 区间（不再与 static 0% 等价）
- (用户跑) UI 选 'static' 任意配置 → 与 28a4bc6 baseline 等价（回归）

### S5 — wiki + log
- 调试日志 `wiki/debug-logs/14_Streaming/流式调试日志.md` 加 2026-04-28 后续章节
- log.md 加条目

## 接受准则

- [ ] `p4_demo_ui` channel 段按 fading_dd 分发到 `gen_doppler_channel` (static) 或 `gen_uwa_channel` (jakes)
- [ ] `gen_uwa_channel` addpath 正确，不报 undefined function
- [ ] smoke 测试 3/3 PASS
- [ ] (用户) UI 'slow Jakes' BER 反映真 Jakes 衰落
- [ ] (用户) UI 'static' 与 28a4bc6 baseline 等价

## 已知风险

- **R1**：tv 模型（drift/jitter/random_walk/sinusoidal）在 Jakes 模式下被忽略，用户可能困惑。**缓解**：on_transmit 在 jakes+tv.enable 时打 append_log 警告 + UI 标签提示。
- **R2**：`gen_uwa_channel` 用固定 seed 还是 random？目前 UI 每次 transmit 应该 reproducibility 重要 vs 真实 random 模拟。**决策**：`seed=randi([1,1e6])` 每次 transmit 不同（真实模拟），用户测多次会看到不同 jakes realization。如需 reproducibility 改 seed=42 或暴露 seed UI 控件（follow-up）。
- **R3**：`gen_uwa_channel` 输出长度可能 < frame_bb（α 时间扩展时），UI 已有长度对齐逻辑兼容。
- **R4**：Jakes 衰落 + bulk Doppler 同时启用时，13 runner 数据是否覆盖此场景？多数 runner 测试是 dop_rate=0 + 纯 jakes，UI 允许两者组合可能进入未充分验证的物理空间。**缓解**：用户验收时建议先测 dop_hz=0 + jakes 单独路径，再测组合。

## OUT-OF-SCOPE 备忘

- hybrid Rician（K-factor）信道模型
- discrete 多径离散 Doppler 信道模型
- tv 模型 + Jakes 组合（需新写 jakes wrapper 接受 tv struct）
- p3_demo_ui Jakes 接入（P3 已冻结）
- jakes seed UI 控件（reproducibility）
