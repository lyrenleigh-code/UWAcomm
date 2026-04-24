---
project: uwacomm
type: plan
status: active
created: 2026-04-22
parent_spec: specs/active/2026-04-22-p4-real-doppler-fork.md
depends_on: [plans/p3-demo-ui-refactor.md]
tags: [流式仿真, 14_Streaming, UI, P4, 多普勒]
---

# P4 真实多普勒仿真 — 实施计划

## 前置依赖

**必须先完成** `plans/p3-demo-ui-refactor.md` 的 Step 2 + Step 3。P4 的 fork 起点是重构完的 P3，避免把 1832 行的乱文件直接复制。

## 目标

执行 spec `2026-04-22-p4-real-doppler-fork.md` 的 3 个步骤：Step F（fork）→ Step S1（接入 gen_doppler_channel）→ Step S2（UI 扩展）。

---

## Step F — Fork 文件（低风险）

### F.1 批量复制

```bash
cd modules/14_Streaming/src/Matlab/ui
for f in p3_*.m; do
    cp "$f" "p4_${f#p3_}"
done
```

预期产出（17 个文件）：
```
p4_animate_tick.m      p4_channel_tap.m       p4_demo_ui.m
p4_downconv_bw.m       p4_metric_card.m       p4_pick_font.m
p4_plot_channel_stem.m p4_render_quality.m    p4_render_sync.m
p4_render_tabs.m       p4_apply_scheme_params.m
p4_semantic_color.m    p4_sonar_badge.m       p4_style.m
p4_style_axes.m        p4_text_capacity.m
```

（注：`p4_render_tabs.m` 和 `p4_apply_scheme_params.m` 依赖 P3 refactor Step 2 产物；Step F 只在 P3 refactor 完成后执行）

### F.2 内部函数名 + 调用点重命名

**MATLAB 约束**：函数名必须 = 文件名，漏改会报错。

每个 p4_*.m 内：
1. 把 `function xxx = p3_yyy(...)` → `function xxx = p4_yyy(...)`（第 1 行）
2. 把文件内所有 `p3_xxx(` 调用 → `p4_xxx(`
3. 函数注释头内的 `p3_xxx` 若用于描述签名需同步；若只是历史注释（如"对齐 p3_channel_tap V2.0"）可保留

建议用 MATLAB 脚本一次性批处理：

```matlab
% scripts/rename_p3_to_p4.m
files = dir('modules/14_Streaming/src/Matlab/ui/p4_*.m');
for i = 1:length(files)
    fp = fullfile(files(i).folder, files(i).name);
    txt = fileread(fp);
    txt = regexprep(txt, 'function\s+([^\n=]*=\s*)?p3_', 'function $1p4_');
    txt = regexprep(txt, 'p3_(\w+)\s*\(', 'p4_$1(');
    fid = fopen(fp, 'w'); fwrite(fid, txt); fclose(fid);
end
```

脚本跑完后 grep 校验：
```bash
grep -n "p3_" modules/14_Streaming/src/Matlab/ui/p4_*.m
# 命中结果必须全部是描述性注释（非调用），否则漏改
```

### F.3 验收

1. **启动**：`p4_demo_ui()` 无报错弹出窗口，UI 布局与 P3 完全一致
2. **5 scheme 发射**：切换 SC-FDE / OFDM / SC-TDE / DSSS / FH-MFSK，TX → RX 监听 → Transmit 都能解码成功（static 6径 SNR=15dB）
3. **P3 不动**：`git diff modules/14_Streaming/src/Matlab/ui/p3_*.m` 必须为空
4. **timer 共存**：P3 和 P4 可同时启动两个窗口各自独立运行

### F.4 commit

```
feat: 14_Streaming fork P4 from refactored P3

从重构后的 p3_*.m 派生 p4_*.m (17 个文件)，仅函数名/调用点重命名，
行为完全等价。为后续接入 gen_doppler_channel 做准备。

P3 保持不动作为稳定参考 demo。
```

---

## Step S1 — 信道段替换（中风险，核心步骤）

### S1.1 改 `p4_channel_tap.m` 签名

**原（沿袭 P3）**：`[h_tap, label] = p4_channel_tap(sch, sys, preset)`

**新**：`[h_tap, paths, label] = p4_channel_tap(sch, sys, preset)`

在原函数体内，构造 `h_tap` 之前先构造 `paths` 结构：

```matlab
paths = struct( ...
    'delays', delays_samp / fs_effective, ...   % 秒
    'gains',  gains );
```

其中 `fs_effective` 按体制分支取值：
- DSSS: `sys.dsss.chip_rate * sys.dsss.sps`
- 其他: `sys.sym_rate * sys.sps` 或 `sys.fs`

**⚠️ 关键**：paths.delays 的单位是**秒**（gen_doppler_channel 要求），不是样本数。原 `delays_samp` 是在 frame_bb 的采样率下的样本数，需除以对应 fs。

实现：

```matlab
function [h_tap, paths, label] = p4_channel_tap(sch, sys, preset)
    % ... 前面 AWGN / preset 分支保持 ...

    % 构造离散 h_tap（原逻辑）
    delays_samp = round(sym_d * sps_use);
    h_tap = zeros(1, max(delays_samp) + 1);
    for p = 1:length(delays_samp)
        h_tap(delays_samp(p)+1) = h_tap(delays_samp(p)+1) + gains(p);
    end
    h_tap = h_tap / norm(h_tap);

    % 新增 paths 结构（给 gen_doppler_channel）
    fs_bb = sys.fs;  % frame_bb 的实际采样率
    paths = struct( ...
        'delays', delays_samp / fs_bb, ...  % 样本→秒
        'gains',  gains / norm(gains) );    % 归一化与 h_tap 一致

    label = sprintf('%s, %d 抽头', preset, length(h_tap));
end
```

**AWGN 分支**：`paths = struct('delays', 0, 'gains', 1)`。

### S1.2 改 `p4_demo_ui.m` 的 `on_transmit` 信道段

定位：原 P3 L882-902（fork 后的 p4 版本同行号区间）。

**替换前**（13 行）：

```matlab
[h_tap, ch_label] = p4_channel_tap(sch, app.sys, app.preset_dd.Value);
frame_ch = conv(frame_bb, h_tap);
frame_ch = frame_ch(1:length(frame_bb));
dop_hz = app.doppler_edit.Value;
if abs(dop_hz) > 1e-3
    alpha = dop_hz / app.sys.fc;
    frame_ch_r = comp_resample_spline(frame_ch, alpha);
    if length(frame_ch_r) > length(frame_ch)
        frame_ch = frame_ch_r(1:length(frame_ch));
    else
        frame_ch = [frame_ch_r, zeros(1, length(frame_ch)-length(frame_ch_r))];
    end
    t_vec = (0:length(frame_ch)-1) / app.sys.fs;
    frame_ch = frame_ch .* exp(1j * 2*pi * dop_hz * t_vec);
    ch_label = sprintf('%s + Doppler %+gHz (α=%.2e)', ch_label, dop_hz, alpha);
end
```

**替换后**（~15 行）：

```matlab
[h_tap, paths, ch_label] = p4_channel_tap(sch, app.sys, app.preset_dd.Value);
dop_hz  = app.doppler_edit.Value;
alpha_b = dop_hz / app.sys.fc;
tv = struct( ...
    'enable',     logical(app.tv_enable_cb.Value), ...
    'model',      app.tv_model_dd.Value, ...
    'drift_rate', app.tv_drift_edit.Value * 1e-6, ...
    'jitter_std', app.tv_jitter_edit.Value * 1e-6 );

% gen_doppler_channel 内部 = 多径卷积 + α(t) 重采样 + 载波位移 + AWGN
[frame_ch, ch_info] = gen_doppler_channel( ...
    frame_bb, app.sys.fs, alpha_b, paths, snr_db, tv);

app.tx_alpha_true = ch_info.alpha_true;
app.tx_h_tap      = h_tap;
ch_label = sprintf('%s | α_base=%.2e %s', ch_label, alpha_b, ...
    ternary(tv.enable, ['| ' tv.model], '| constant'));
```

其中 `ternary` 是 local helper（在 p4_demo_ui.m 内部加 3 行）。

### S1.3 删除外层 add_awgn

原 P3 代码中（约 L920+）对 `frame_ch` 还会做：
```matlab
frame_ch = add_awgn(frame_ch, snr_db);  % 或类似
```

**P4 必须删掉**（`gen_doppler_channel` 已加噪）。删除前用 grep 定位：

```bash
grep -n "add_awgn\|awgn\|randn.*noise" p4_demo_ui.m
```

### S1.4 验证

1. **等价性回归**（constant 模式）：
   ```
   P4 启动 → tv_enable=false → SC-FDE + 6径标准 + SNR=15 + doppler=0
   Transmit → BER 记录
   ```
   对比 P3 同参数 BER，差 ≤ 0.001。

2. **等价性回归**（有多普勒 constant）：
   ```
   P4 tv_enable=false → doppler=10 Hz
   ```
   对比 P3 同参数 BER，差 ≤ 0.05（内部 resample 实现方式不同，允许小差异）。

3. **时变生效**：
   ```
   P4 tv_enable=true, model='random_walk', jitter=0.02, doppler=0
   ```
   检查 `app.tx_alpha_true` 非常量（std > 0）。

### S1.5 commit

```
feat: 14_Streaming P4 接入 gen_doppler_channel 真实多普勒模型

替换 on_transmit 信道段：
- 原：conv(h_tap) + comp_resample_spline(α) + exp(j2π·dop·t) + add_awgn
- 新：gen_doppler_channel(paths, α_base, snr_db, time_varying)

p4_channel_tap 返回 paths 结构（delays 单位：秒）。
外层 add_awgn 删除（gen_doppler_channel 内部加噪）。
```

---

## Step S2 — UI 控件 + α(t) 可视化（低风险）

### S2.1 TX 面板新增 4 控件

定位到 TX 面板 `tx_grid` 当前 `doppler_edit` 创建处（P3 L259）：

```matlab
[~, app.doppler_edit] = mk_row(tx_grid, 5, '多普勒 (Hz):', 'numeric', 0, [-50 50]);
```

在其下方新增 4 行（假设 tx_grid 目前行数为 N，延后 N+4）：

```matlab
% 时变多普勒参数
[~, app.tv_enable_cb]   = mk_row(tx_grid, 6, '启用时变:',   'checkbox', true, []);
[~, app.tv_model_dd]    = mk_row(tx_grid, 7, '时变模型:',   'dropdown', ...
    'random_walk', {'constant','linear_drift','sinusoidal','random_walk'});
[~, app.tv_drift_edit]  = mk_row(tx_grid, 8, 'drift(µ/s):',  'numeric', 0.1,  [0 10]);
[~, app.tv_jitter_edit] = mk_row(tx_grid, 9, 'jitter(µ):',   'numeric', 0.02, [0 1]);
```

**`mk_row` 扩展**：当前 `mk_row` 只支持 `'numeric'`，需添加 `'checkbox'` 和 `'dropdown'` 分支（~10 行）。

### S2.2 回调

```matlab
function on_tv_model_changed()
    is_const = strcmp(app.tv_model_dd.Value, 'constant') || ...
               ~logical(app.tv_enable_cb.Value);
    app.tv_drift_edit.Enable  = ~is_const;
    app.tv_jitter_edit.Enable = ~is_const;
end
```

绑定到 `tv_model_dd.ValueChangedFcn` 和 `tv_enable_cb.ValueChangedFcn`。

### S2.3 p4_render_tabs 信道 tab 扩展

`render_channel` 的 ax_td 标题追加 tv 模型信息；在 ax_fd 之下或旁边绘 α(t)：

```matlab
% 在 render_channel 末尾
if isfield(entry, 'alpha_true') && ~isempty(entry.alpha_true)
    % 复用 ax_fd 的一部分空间：在 ax_fd 下方绘 α(t) 子图（需要额外 axes 句柄）
    % 或：直接 plot(ax_fd_right_side)，但空间有限
    % 简化方案：在 ax_td 标题中追加 α(t) 统计
    tv_info = sprintf('α_true: mean=%.2e std=%.2e', ...
        mean(entry.alpha_true), std(entry.alpha_true));
    xlabel(ax_td, tv_info);
end
```

**完整方案**（如果空间够）：在 `p4_demo_ui.m` 信道 tab 构建处多加一个 axes：

```matlab
app.tabs.alpha_t = uiaxes(ch_grid);
app.tabs.alpha_t.Layout.Row = 3; app.tabs.alpha_t.Layout.Column = [1 2];
```

然后 `pack_axes()` 中多传一个 `ax.alpha_t = app.tabs.alpha_t`，`render_channel` 多一个 `plot(ax.alpha_t, entry.alpha_true)`。

**取舍**：S2 内先用简化方案（标题统计），若后续觉得不够再加 axes（可作为 P4.1 小改）。

### S2.4 entry 扩展

`try_decode_frame` 打包 entry 时新增字段：

```matlab
entry.alpha_true = app.tx_alpha_true;
```

### S2.5 验证

- [ ] UI 启动：4 个新控件可见、排版不破
- [ ] tv_enable=false → drift/jitter 控件灰
- [ ] 4 种 model 切换：单次 Transmit 能跑完
- [ ] 信道 tab 标题（或 α(t) 子图）显示合理统计
- [ ] 冒烟脚本 `tests/test_p4_channel_smoke.m` 通过

### S2.6 commit

```
feat: 14_Streaming P4 UI 扩展时变多普勒参数 + α(t) 可视化

TX 面板新增：
- 启用时变 checkbox
- 时变模型下拉（constant/linear_drift/sinusoidal/random_walk）
- drift_rate 输入（单位 µ/s）
- jitter_std 输入（单位 µ）

mk_row 支持 checkbox/dropdown 类型。
信道 tab 标题显示 α(t) 均值/标准差。
```

---

## 回归测试对照表

| 场景 | P3 BER | P4 tv=false BER | P4 random_walk BER |
|------|--------|-----------------|--------------------|
| SC-FDE 6径 SNR=15 静态 | X | == X ±0 | ≤ 5× X |
| OFDM 6径 SNR=15 dop=0 | Y | == Y ±0 | ≤ 10× Y（RX 未 TV 升级） |
| DSSS 5径 SNR=10 | Z | == Z ±0 | ≤ 10× Z |

实测时补具体数字到 spec Result 章节。

## 风险回看（spec → plan 应对）

| spec 风险 | 本计划应对 |
|-----------|-----------|
| 🔴 采样率假设不匹配 | S1.1 显式 `fs_bb = sys.fs`，paths.delays 转秒 |
| 🔴 噪声双重注入 | S1.3 明确删除外层 add_awgn 并 grep 验证 |
| 🟡 RX random_walk 崩溃 | 验收只要求"不崩"（BER < 0.5），BER 退化是已知限制 |
| 🟡 p3 污染 | F.3 `git diff p3_*.m` 为空 |
| 🟢 tv_* 控件失能 | S2.2 `on_tv_model_changed` |

## 归档

3 commit + 冒烟通过 + 回归对比填表 → spec Result 写数据 → spec 挪 archive，plan 挪 plans/archive/。

## Log

- 2026-04-22: Plan 创建，前置 P3 refactor Step 2+3
