---
project: uwacomm
type: feature
status: active
created: 2026-04-22
parent: 2026-04-15-streaming-framework-master.md
depends_on: [2026-04-17-p3-demo-ui-refactor.md]
phase: P4-real-doppler
tags: [流式仿真, 14_Streaming, UI, P4, 多普勒, 时变信道]
---

# P4 真实多普勒仿真 — 从 P3 fork 并接入 gen_doppler_channel

## 目标

从重构后的 P3 fork 出 **P4 版本**，将当前"手搓常数 α + 静态 h_tap + 载波位移"的简化多普勒模型替换为 `modules/10_DopplerProc` 提供的 `gen_doppler_channel`（时变 α(t) + 多径延迟/增益 + drift/jitter/random_walk 时变模型），使 demo 能演示真实水声信道的时变多普勒效应。

**P3 保留不动**，作为稳定参考 demo 供对比与回退。

## 非目标

- 不做阵列版（`gen_uwa_channel_array` 先跳过，后续 P4.x 再扩）
- 不改 modem_encode/decode 接口
- 不推翻 P3（p3_*.m 全部冻结）
- 不重写 01-13 模块（仅调用 10_DopplerProc 已有 API）
- 不修 RX 接收端（复用 P3 的 TV 分支；若 RX 不鲁棒则记录为已知限制）

## 背景与动机

### 当前 P3 的"假"多普勒（on_transmit L882-902）

```matlab
% --- 基带信道（对完整帧施加）---
[h_tap, ch_label] = p3_channel_tap(sch, app.sys, app.preset_dd.Value);
frame_ch = conv(frame_bb, h_tap);                       % 静态 h_tap
frame_ch = frame_ch(1:length(frame_bb));

% --- 多普勒注入（单 α 常数）---
dop_hz = app.doppler_edit.Value;
if abs(dop_hz) > 1e-3
    alpha = dop_hz / app.sys.fc;                        % 常量 α
    frame_ch_r = comp_resample_spline(frame_ch, alpha); % 重采样一次
    ...
    frame_ch = frame_ch .* exp(1j * 2*pi * dop_hz * t_vec);  % 载波位移
end
```

**局限性**：
1. α 全程常数 → 无法演示平台运动不稳（漂移 / 抖动 / 非线性轨迹）
2. `h_tap` 静态 → 无时变多径
3. 多径与多普勒解耦（先 conv 再 resample）→ 与 `s((1+α(t))t)` 后再 conv 的物理模型**等价性不严格**
4. RX 端调试时很难从"几乎理想"信道切换到"真实场景"，中间缺渐变

### 模块 10 已有能力（gen_doppler_channel V1.0）

```matlab
function [r, channel_info] = gen_doppler_channel(s, fs, alpha_base, paths, snr_db, time_varying)
% 时变 α(t) 三种模型：
%   'linear_drift'  : α(t) = α_base + drift_rate * t
%   'sinusoidal'    : α(t) = α_base + A*sin(2π*f_mod*t)
%   'random_walk'   : α(t) = α_base + cumsum(jitter*N(0,1))
% paths.delays / paths.gains: 多径延迟与复增益
% 返回 channel_info.alpha_true (1xN) 瞬时 α 序列
```

已在 `modules/10_DopplerProc/test_doppler.m` 及 `13_SourceCode/tests/*` 中广泛使用，稳定。

## 方案

### 文件 fork 清单（Step F）

保留 `ui/p3_*.m` 不动，新建 `ui/p4_*.m`：

| 新文件 | 来源 | 改动 |
|--------|------|------|
| `ui/p4_demo_ui.m` | `ui/p3_demo_ui.m`（重构后版本，≤1000 行） | 函数名改；信道段重写（见 Step S1）；新增 UI 控件（见 Step S2） |
| `ui/p4_render_tabs.m` | `ui/p3_render_tabs.m`（Step A 的产物） | 函数名改；信道 tab 显示 α(t) 轨迹（新增） |
| `ui/p4_apply_scheme_params.m` | `ui/p3_apply_scheme_params.m` | 仅改名，内容不变 |
| `ui/p4_channel_tap.m` | `ui/p3_channel_tap.m` | 改名；返回值扩展为 `[h_tap, paths, label]`（新增 paths 结构给 gen_doppler_channel）|
| `ui/p4_downconv_bw.m` | `ui/p3_downconv_bw.m` | 仅改名 |
| `ui/p4_text_capacity.m` | `ui/p3_text_capacity.m` | 仅改名 |
| `ui/p4_animate_tick.m` | `ui/p3_animate_tick.m` | 仅改名 |
| `ui/p4_channel_tap.m` | `ui/p3_channel_tap.m` | （见上） |
| `ui/p4_metric_card.m` | `ui/p3_metric_card.m` | 仅改名 |
| `ui/p4_pick_font.m` | `ui/p3_pick_font.m` | 仅改名 |
| `ui/p4_plot_channel_stem.m` | `ui/p3_plot_channel_stem.m` | 仅改名 |
| `ui/p4_render_quality.m` | `ui/p3_render_quality.m` | 仅改名 |
| `ui/p4_render_sync.m` | `ui/p3_render_sync.m` | 仅改名 |
| `ui/p4_semantic_color.m` | `ui/p3_semantic_color.m` | 仅改名 |
| `ui/p4_sonar_badge.m` | `ui/p3_sonar_badge.m` | 仅改名 |
| `ui/p4_style.m` | `ui/p3_style.m` | 仅改名 |
| `ui/p4_style_axes.m` | `ui/p3_style_axes.m` | 仅改名 |

**内部引用改名**：`p4_demo_ui.m` 及所有 p4_*.m 内部对 `p3_xxx(...)` 的调用全部改为 `p4_xxx(...)`。

### 核心改动（Step S1）— on_transmit 信道段重写

**替换前**（P3 版本，L882-902）：

```matlab
[h_tap, ch_label] = p3_channel_tap(sch, app.sys, app.preset_dd.Value);
frame_ch = conv(frame_bb, h_tap);
frame_ch = frame_ch(1:length(frame_bb));
dop_hz = app.doppler_edit.Value;
if abs(dop_hz) > 1e-3
    alpha = dop_hz / app.sys.fc;
    frame_ch_r = comp_resample_spline(frame_ch, alpha);
    ...
    frame_ch = frame_ch .* exp(1j*2*pi*dop_hz*t_vec);
end
```

**替换后**（P4 版本）：

```matlab
[~, paths, ch_label] = p4_channel_tap(sch, app.sys, app.preset_dd.Value);
dop_hz   = app.doppler_edit.Value;
alpha_b  = dop_hz / app.sys.fc;
tv = struct( ...
    'enable',     app.tv_enable_cb.Value, ...
    'model',      app.tv_model_dd.Value, ...       % 'linear_drift' / 'sinusoidal' / 'random_walk' / 'constant'
    'drift_rate', app.tv_drift_edit.Value * 1e-6, ...  % µ/s → α/s
    'jitter_std', app.tv_jitter_edit.Value * 1e-6 );

% gen_doppler_channel 内部完成 resample + 多径 + 噪声注入
% 它自己加噪 → snr_db 直接传进去；外层 add_awgn 跳过（见 Step S3）
fs_bb = app.sys.fs;
[frame_ch, ch_info] = gen_doppler_channel( ...
    frame_bb, fs_bb, alpha_b, paths, snr_db, tv);

% ch_info.alpha_true 存起来供 RX 和 UI 用
app.tx_alpha_true = ch_info.alpha_true;
app.tx_h_tap      = tap_from_paths(paths, fs_bb);   % h_tap 仍要给 RX 做 oracle 对比
ch_label = sprintf('%s | α_base=%.2e | model=%s', ch_label, alpha_b, tv.model);
```

**关键设计**：
- **paths 结构**由新签名 `p4_channel_tap` 直接返回，不再依赖 `h_tap` 反推
- **gen_doppler_channel 内部注入噪声**，所以 P3 原本的 `add_awgn` 路径要**跳过或改道**（见 Step S3）
- **α_base 依然来自 `app.doppler_edit.Value / fc`**（单位一致）
- **h_tap 仍构造**（从 paths），因为 P3 的 update_txinfo_panel / update_tabs 现还在用它做 stem 图

### UI 扩展（Step S2）

在 TX 面板 `multi-doppler` 子区新增 4 个控件（占 ~20 行）：

| 控件 | 类型 | 绑定 | 默认值 | 说明 |
|------|------|------|--------|------|
| `tv_enable_cb` | checkbox | `app.tv_enable_cb` | true | "启用时变多普勒" |
| `tv_model_dd` | dropdown | `app.tv_model_dd` | `'random_walk'` | 选 constant/linear_drift/sinusoidal/random_walk |
| `tv_drift_edit` | numeric | `app.tv_drift_edit` | 0.1 | drift_rate 单位 µ/s（即 1e-6 / s）|
| `tv_jitter_edit` | numeric | `app.tv_jitter_edit` | 0.02 | jitter_std 单位 µ（即 1e-6）|

放在现有 `多普勒 (Hz)` 控件下方同一子网格，保持 TX 面板总行数可控。

"constant" 模式下 drift=jitter=0，退化为 P3 行为（作为对照模式）。

### Step S3 — 噪声注入路径调整

P3 在 `frame_ch` 之后走统一 `add_awgn(frame_ch, snr_db)`。`gen_doppler_channel` 内部已加噪，P4 需二选一：

**选 A（推荐）**：P4 跳过外层 `add_awgn`，由 `gen_doppler_channel` 负责噪声。需改 `on_transmit` 把 `snr_db` 直接传给 gen_doppler_channel，删掉后续 add_awgn 调用。

**选 B**：`gen_doppler_channel` 调用时传 `snr_db = Inf`（无噪），外层继续 add_awgn。但 `gen_doppler_channel` 对 `Inf` 的处理路径需验证。

Spec 先锁 **选 A**。

### Step S4 — 信道 tab 扩展（p4_render_tabs）

`render_channel` local 函数追加：
- 新增子图或覆盖图：α(t) 时域曲线（`app.tx_alpha_true` 相对 α_base 的偏差 × 1e6，单位 ppm）
- 标题附加 tv 模型名

（若当前信道 tab 只有 TD+FD 两 axes，则在 FD 下方用一个小 subplot 绘 α(t)；若空间不够则打印到 TD 标题）

### Step S5 — Session 产物 fork

新建 `modules/14_Streaming/sessions/p4_*`（仅在跑测试时产生，不预先建空目录）。P3 的历史 session 不动。

## 验收标准

### 功能

- [ ] `p4_demo_ui()` 启动无报错，5 个 scheme 全能发射
- [ ] tv 模型切换（constant / linear_drift / sinusoidal / random_walk）都能跑完一帧
- [ ] constant + drift=0 + jitter=0 → BER 与 P3 同参数 ±0%（等价性回归）
- [ ] random_walk + drift=0 + jitter=0.02 µ + α_base=0 → α(t) 曲线非常量，可见游走
- [ ] linear_drift + drift=0.5 µ/s → α(t) 严格线性增长
- [ ] 信道 tab 显示 α(t) 曲线与 tv 模型一致
- [ ] P3 (`p3_demo_ui()`) **完全不受影响**，可同时启动两个窗口

### 代码指标

- [ ] 所有新建 p4_*.m 总行数 ≤ P3 版本 + 60 行（UI 新增 + paths 返回）
- [ ] `p4_demo_ui.m` ≤ 1050 行（P3 重构后 ~1000 + P4 UI 新增 ~20 + 信道段调整 ~10）
- [ ] 无 p3_xxx → p4_xxx 漏改（grep `p3_` 于 `ui/p4_*.m` 应为 0 命中，排除注释中提 P3 对照的情况）

### 回归对比（必测）

- [ ] 同参数下 P3 vs P4 constant 模式 BER 差 ≤ 0.001（浮点误差容限）
- [ ] SC-FDE static 6 径 SNR=15 dB：P4 constant vs P4 random_walk(jitter=0.02 µ) BER 变化应 ≤ 5×
- [ ] 冒烟脚本 `tests/test_p4_channel_smoke.m`（见下）通过

### 冒烟测试 `tests/test_p4_channel_smoke.m`

```matlab
% 1. p4_channel_tap 返回 paths 结构完整
sys = sys_params_default();
for sch = {'SC-FDE','OFDM','SC-TDE','DSSS','FH-MFSK'}
    [h, paths, lbl] = p4_channel_tap(sch{1}, sys, '6径 标准水声');
    assert(isfield(paths, 'delays') && isfield(paths, 'gains'));
    assert(length(paths.delays) == length(paths.gains));
    assert(~isempty(h) && ~isempty(lbl));
end

% 2. gen_doppler_channel 对 p4_channel_tap 的 paths 可用
s = randn(1, 4096) + 1j*randn(1, 4096);
[~, paths] = p4_channel_tap('SC-FDE', sys, '6径 标准水声');
tv = struct('enable', true, 'model', 'random_walk', ...
            'drift_rate', 1e-7, 'jitter_std', 2e-8);
[r, info] = gen_doppler_channel(s, sys.fs, 1e-5, paths, 20, tv);
assert(length(info.alpha_true) == length(s));
assert(abs(mean(info.alpha_true) - 1e-5) < 5e-7);  % 均值接近 α_base
assert(std(info.alpha_true) > 0);                   % 非常量

% 3. constant 模式退化等价
tv0 = struct('enable', false, 'model', 'constant', ...
             'drift_rate', 0, 'jitter_std', 0);
[r0, info0] = gen_doppler_channel(s, sys.fs, 1e-5, paths, 100, tv0);  % 高 SNR
assert(all(info0.alpha_true == 1e-5));
```

## 风险

| 风险 | 等级 | 应对 |
|------|------|------|
| `gen_doppler_channel` 内部采样率假设与 `frame_bb` 不匹配（fs vs sym_rate） | 🔴 高 | Step S1 明确传 `fs_bb = app.sys.fs`；`p4_channel_tap` 返回 paths.delays 已按 fs 换算 |
| 噪声双重注入（外 add_awgn + 内 gen_doppler_channel） | 🔴 高 | Step S3 选 A：跳过外层 add_awgn |
| RX 解码在 random_walk 模式大概率失败（BER 崩溃） | 🟡 中 | 验收允许 BER 降低，但不崩溃（< 0.5）；崩溃则记为 P4 已知限制，后续 P4.1 再做 RX 升级 |
| `paths.delays` 连续值 vs `h_tap` 离散 stem 图不兼容 | 🟡 中 | `h_tap` 仍从 paths 离散化生成给 TD 显示；α(t) 用新子图 |
| 错误引入 P3 污染（意外修改 p3_*.m） | 🟡 中 | Step F 单独 commit 验证 `git diff p3_*.m` 为空；hooks `lint_wiki.py --quick` 会跑 |
| `app.tv_*` 控件在 constant 模式下需 disable 避免误读 | 🟢 低 | UI 回调 `on_tv_model_changed` 切 enable 状态 |

## 实施分步（3 commit）

### 步骤 F — Fork 文件（低风险）

1. `cp ui/p3_*.m ui/p4_*.m`（注意：必须在 P3 refactor 完成后）
2. 批量内部重命名：`sed` 替换 `function p3_xxx` → `function p4_xxx`，调用点 `p3_xxx(` → `p4_xxx(`
3. **手工验证**：`p4_demo_ui()` 能启动、外观与 P3 一致、5 scheme 均能发射解码
4. commit：`feat: 14_Streaming fork P4 from refactored P3`

### 步骤 S1 — 信道段替换（中风险）

1. 改 `p4_channel_tap.m` 签名为 `[h_tap, paths, label] = ...`
2. 替换 `on_transmit` 信道段为 `gen_doppler_channel` 调用
3. 跳过外层 `add_awgn`
4. **验证**：constant 模式 BER 与 P3 同参数一致（±0%）
5. commit：`feat: 14_Streaming P4 接入 gen_doppler_channel 真实多普勒模型`

### 步骤 S2 — UI 控件 + tab 扩展（低风险）

1. TX 面板新增 4 控件（tv_enable / tv_model / tv_drift / tv_jitter）
2. `p4_render_tabs.m` 的 `render_channel` 追加 α(t) 曲线
3. **验证**：四种 tv 模型切换都能跑，α(t) 曲线与模型一致
4. 冒烟脚本 `tests/test_p4_channel_smoke.m` 通过
5. commit：`feat: 14_Streaming P4 UI 扩展时变多普勒参数 + α(t) 可视化`

## 归档时机

Step F + S1 + S2 全通过 + 冒烟 + 手工验收 → 填 Result → 挪到 archive。后续 P4.1 RX 升级另起 spec。

## Log

- 2026-04-22: Spec 创建
- 2026-04-22: 发现并修复 gen_doppler_channel 的基带相位旋转 bug（V1.0 用 `α·fs·t` 而非 `fc·∫α dτ`，fs/fc=4 倍率偏差导致 P4 在 dop_hz=12Hz 时等价于 P3 dop=48Hz → RX 崩）。修复：
  - `gen_doppler_channel.m` → V1.1：新增可选 `fc` 参数，传入后用物理正确公式 `phase_shift = 2π·fc·cumsum(α_t)/fs`，同时修正 t_stretched 起点从 0 开始（α=0 时与 t_orig 对齐）；未传 fc 时发 warning 并回退 V1.0（向后兼容）
  - `p4_demo_ui.m` → on_transmit 调用改为 `gen_doppler_channel(…, app.sys.fc)`
  - `test_p4_channel_smoke.m` → 新增 case 6 验证 V1.1 相位频率 = fc·α 而 V1.0 = fs·α
  - 依据：固定 α 历史基线 `wiki/comparisons/e2e-timevarying-baseline.md` A2 阶段 + `specs/active/2026-04-20-alpha-compensation-pipeline-debug.md` L19-24
- 2026-04-22: **遗留**：`gen_uwa_channel_array.m` / `modules/11_ArrayProc/gen_doppler_channel_array.m` 没传 fc，仍会看到 warning。阵列仿真用到时要跟进传入 fc。
