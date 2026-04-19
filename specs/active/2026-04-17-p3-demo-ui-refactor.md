---
project: uwacomm
type: refactor
status: active
created: 2026-04-17
parent: 2026-04-15-streaming-framework-master.md
phase: P3.x-maintenance
depends_on: [P3.1, P3.2, P3.3]
tags: [流式仿真, 14_Streaming, UI, 重构, p3_demo_ui]
---

# p3_demo_ui 重构 — 拆分与模块化

## 目标

将 `modules/14_Streaming/src/Matlab/ui/p3_demo_ui.m` 从单文件 **1378 行** 拆到多个文件，每个文件 **≤ 800 行**（对齐项目 `coding-style` 规范），同时保持 UI 行为完全等价。

**非目标**：
- 不新增功能、不改 UX、不改 modem_encode/decode 接口
- 不改 FIFO / timer / callback 触发机制
- 不动 P1/P2 版本的 `p1_demo_ui.m` `p2_demo_ui.m`

## 现状

### 规模

| 指标 | 当前 | 目标 |
|------|------|------|
| 文件行数 | 1378 | 主文件 ≤ 800 |
| 函数数 | 25 | 各函数 ≤ 80 行 |
| 最大函数 | `update_tabs_from_entry` = **261 行** | ≤ 80 行 |

### 问题

| # | 位置 | 问题 |
|---|------|------|
| 1 | `update_tabs_from_entry` (L1095-1354) | 5 段互斥渲染（TX/RX 对比 / 频谱 / 均衡 / 信道时域 / 频域）硬塞一个函数 |
| 2 | `on_transmit` (L523-672) | 5 个 scheme 参数分支结构同构、可抽策略函数 |
| 3 | 文本容量公式 | `on_scheme_changed` 和 `on_transmit` 各算一遍 → 两处重复 |
| 4 | Axes 样式 | `ax.XColor='k'; ax.YColor='k';` 重复 20+ 次 |
| 5 | 字体常量 | `'FontName','Consolas'` 散落 15+ 次 |
| 6 | 主 setup | L87-374 共 287 行连续拼 UI，难导航 |

## MATLAB 约束（关键）

**嵌套函数** 与父函数共享 workspace（可直接读写 `app`）。
**外部函数** 必须通过参数传递，`struct` 是值拷贝，回写要返回整个结构。

因此：
- **UI 回调、状态变更函数必须保持嵌套**（在 `p3_demo_ui.m` 内），否则失去 `app` 引用。
- **只有纯读/纯函数可外化**（渲染、参数映射、常量计算）。

## 方案 B — 拆 5 个外部 helper + 主文件内重组

### 新建文件（5 个）

| 文件 | 职责 | 预估行数 | 函数签名 |
|------|------|---------|---------|
| `ui/p3_render_tabs.m` | 接收已完成的 entry + axes 句柄，刷新 5 个渲染 tab（compare / spectrum / eq / channel_td / channel_fd） | ~320 | `p3_render_tabs(sch, entry, axes, sys)` |
| `ui/p3_apply_scheme_params.m` | 根据 scheme 名 + UI 值计算 `N_info` 并返回更新后的 `sys` 子结构 | ~80 | `[N_info, sys_out] = p3_apply_scheme_params(sch, sys, ui_vals)` |
| `ui/p3_channel_tap.m` | 按 scheme + preset 构造信道抽头 | ~70 | `[h_tap, label] = p3_channel_tap(sch, sys, preset)` |
| `ui/p3_downconv_bw.m` | scheme → 接收端下变频带宽 | ~25 | `bw = p3_downconv_bw(sch, sys)` |
| `ui/p3_text_capacity.m` | scheme → 最大文本字节数（单一事实源） | ~25 | `nb = p3_text_capacity(sch, sys)` |

### `p3_render_tabs.m` 内部分解

一个文件内 1 个入口 + 5 个 local function（MATLAB local function 不需外置）：

```matlab
function p3_render_tabs(sch, entry, axes, sys)
    render_compare(sch, entry, axes.compare_tx, axes.compare_rx, sys);
    render_spectrum(sch, entry, axes.spectrum, sys);
    render_eq(sch, entry, axes.eq, sys);          % 内部分派 fhmfsk/dsss/turbo
    render_channel(sch, entry, axes.h_td, axes.h_fd, sys);
end

function render_compare(sch, entry, ax_tx, ax_rx, sys) ... end
function render_spectrum(sch, entry, ax, sys) ... end
function render_eq(sch, entry, ax_cells, sys) ... end
function render_channel(sch, entry, ax_td, ax_fd, sys) ... end
function style_axes(ax)                 % 复用 ax.XColor='k'; ax.YColor='k';
    ax.XColor='k'; ax.YColor='k';
end
```

**`axes` 参数设计**：struct，字段为：

```matlab
axes.compare_tx = app.tabs.compare_tx;
axes.compare_rx = app.tabs.compare_rx;
axes.spectrum   = app.tabs.spectrum;
axes.eq         = {app.tabs.pre_eq, app.tabs.eq_it1, app.tabs.eq_mid, app.tabs.post_eq};
axes.h_td       = app.tabs.h_td;
axes.h_fd       = app.tabs.h_fd;
```

### 主文件内部重组（不外化，只抽嵌套函数）

保持在 `p3_demo_ui.m` 内部，但把 setup 段的 287 行拆成 4 个嵌套函数：

```matlab
function p3_demo_ui()
    %% 状态初始化
    ...
    %% UI 构建
    app.fig = uifigure(...);
    main = uigridlayout(...);
    build_topbar(main);       % 原 L98-158
    build_middle_panels(main); % 原 L160-307
    build_bottom_tabs(main);   % 原 L309-363
    start_timer_and_init();    % 原 L365-374
    %% 内部函数
    function build_topbar(main) ... end    % 嵌套，读写 app
    function build_middle_panels(main) ... end
    function build_bottom_tabs(main) ... end
    function start_timer_and_init() ... end
    % 其他 callback 嵌套函数...
end
```

### 改动点映射

| 原位置 | 改动 |
|--------|------|
| L396-405 (`on_scheme_changed` 文本容量 switch) | → `nb = p3_text_capacity(sch, app.sys)` |
| L533-579 (`on_transmit` scheme 分支) | → `[N_info, app.sys] = p3_apply_scheme_params(sch, app.sys, ui_vals)` |
| L653 (`downconv_bandwidth` call) | → `p3_downconv_bw(sch, app.sys)` |
| L974-1033 (`build_channel_tap` 嵌套函数体) | → 外化为 `p3_channel_tap.m`，签名带 `sys, preset_name` |
| L1095-1354 (`update_tabs_from_entry`) | → `p3_render_tabs(sch, entry, axes_struct, app.sys)` |

### 预计行数分布（refactor 后）

| 文件 | 行数 |
|------|------|
| `p3_demo_ui.m`（主） | ~780（原 1378 - 抽出 ~600 + 少量新增 boilerplate） |
| `p3_render_tabs.m` | ~320 |
| `p3_apply_scheme_params.m` | ~80 |
| `p3_channel_tap.m` | ~70 |
| `p3_downconv_bw.m` | ~25 |
| `p3_text_capacity.m` | ~25 |
| **合计** | ~1300（净 -80 = 样板/重复消除） |

全部文件 ≤ 800 行 ✓

## 不做的事（Rejected alternatives）

### 方案 A（仅同文件嵌套拆分）
- 可读性提升，但主文件仍 1100+ 行 → 不达标。
- 可做为方案 B 不通过时的最小方案。

### 方案 C（只外化 `update_tabs_from_entry`）
- 收益 -260 行 → 主文件 ~1120 行，仍超标。
- 放弃。

### 不抽 `p3_style.m`
- MATLAB 没有真·跨文件常量。可用 function 返回字符串但对可读性负收益。**由 `style_axes` local function 在 `p3_render_tabs.m` 内部覆盖**即可。

## 文件清单

### 新建（5 个 + 1 plan + 1 test）

| 文件 | 用途 |
|------|------|
| `ui/p3_render_tabs.m` | 外化渲染 |
| `ui/p3_apply_scheme_params.m` | 外化 scheme 参数映射 |
| `ui/p3_channel_tap.m` | 外化信道构造 |
| `ui/p3_downconv_bw.m` | 外化带宽查表 |
| `ui/p3_text_capacity.m` | 外化文本容量 |
| `plans/p3-demo-ui-refactor.md` | 实施计划 |
| `tests/test_p3_ui_smoke.m` | UI 冒烟测试（见验收） |

### 修改（1）

| 文件 | 修改 |
|------|------|
| `ui/p3_demo_ui.m` | 抽取上述 5 处 → 调外化函数；setup 段内部拆 4 个嵌套函数；文件总行降到 ≤ 800 |

### 不动

- `p1_demo_ui.m`、`p2_demo_ui.m`（不同版本独立演进）
- `modem_*`、`common/`、`tx/`、`rx/` 所有现有函数
- 01-13 模块

## 验收标准

### 功能等价（必测）

- [ ] 启动 `p3_demo_ui()` 无报错，3 秒内主窗口可见
- [ ] 5 个 scheme 切换（SC-FDE / OFDM / SC-TDE / DSSS / FH-MFSK）：
  - [ ] 文本容量提示随 scheme 变化（对比 refactor 前数值）
  - [ ] SC-FDE / OFDM / SC-TDE 显示 `blk_fft` + `Turbo 迭代`
  - [ ] DSSS 隐藏调制参数
  - [ ] FH-MFSK 显示 `payload bits`
- [ ] RX 监听 ON + Transmit：至少一次解码成功（默认参数 SC-FDE static 6 径 SNR=15dB）
- [ ] 7 个底部 tab 均渲染：scope / spectrum / 均衡分析 / TX-RX 对比 / 信道 / 日志 （+下拉历史）
- [ ] 解码历史：至少 2 次 Transmit 后下拉可切换显示
- [ ] Bypass RF 模式：勾选+Transmit 仍然能渲染 tab
- [ ] Clear 按钮：FIFO、info、BER、历史、所有 axes 清空
- [ ] 关闭窗口无 timer 泄漏（`timerfindall` 后为空）

### 代码指标

- [ ] `p3_demo_ui.m` ≤ 800 行
- [ ] 5 个外化 helper 文件各自 ≤ 350 行
- [ ] 所有函数（含 local）≤ 80 行
- [ ] `mlint`（或 Code Analyzer）无新增警告

### 回归对比

- [ ] 相同输入（SC-FDE static SNR=15dB "Hello UWAcomm"）下 BER 与 refactor 前一致（±0%）
- [ ] 相同输入（FH-MFSK fd=2Hz SNR=10dB）下解码成功率一致
- [ ] `update_tabs_from_entry` 渲染出的图形与 refactor 前视觉等价（手动截图对比）

### 冒烟测试脚本 `tests/test_p3_ui_smoke.m`

自动化覆盖（不依赖人工点按钮）：

```matlab
% 直接调 helper 验证参数映射 + 信道构造正确
sys = sys_params_default();
[N_scfde, sys2] = p3_apply_scheme_params('SC-FDE', sys, struct('blk_fft',128,'iter',6));
assert(N_scfde > 0 && isfield(sys2.scfde, 'turbo_iter'));

% 验证所有 scheme 都能映射
for sch = {'SC-FDE','OFDM','SC-TDE','DSSS','FH-MFSK'}
    [Ni, ~] = p3_apply_scheme_params(sch{1}, sys, default_ui_vals(sch{1}));
    assert(Ni > 0);
    bw = p3_downconv_bw(sch{1}, sys); assert(bw > 0);
    nb = p3_text_capacity(sch{1}, sys); assert(nb > 10);
end

% 验证文本容量与 on_transmit 计算一致（单一事实源校验）
for sch = {'SC-FDE','OFDM','SC-TDE','DSSS','FH-MFSK'}
    nb_from_helper = p3_text_capacity(sch{1}, sys);
    [Ni, ~] = p3_apply_scheme_params(sch{1}, sys, default_ui_vals(sch{1}));
    nb_from_params = floor(Ni / 8);
    assert(abs(nb_from_helper - nb_from_params) <= 1, ...
        sprintf('文本容量不一致: %s helper=%d params=%d', sch{1}, nb_from_helper, nb_from_params));
end
```

（`p3_render_tabs` 无法脱离真实 axes 测，只能手动验收。）

## 风险

| 风险 | 等级 | 应对 |
|------|------|------|
| 抽出的 helper 参数签名遗漏字段 | 🔴 高 | 实施前逐个函数列出**实际读到的 app 字段**，转成显式参数。Plan 阶段做这份映射。 |
| 嵌套函数改成 local function 破坏 closure | 🟡 中 | setup 段 4 个嵌套函数**保持嵌套**（不外化），只是物理上分段 |
| MATLAB R2025b 的静态分析陷阱（见 `conclusions.md` #22） | 🟡 中 | 禁止链式赋值 `uilabel(...).Layout.Row = X`，一律 `lbl = uilabel(...); lbl.Layout.Row = X` |
| 信道构造 `build_channel_tap` 依赖 `app.preset_dd.Value` | 🟡 中 | helper 签名改为 `p3_channel_tap(sch, sys, preset_name)`，preset_name 由调用方传 |
| `p3_render_tabs` 依赖的 `info` 字段与 modem_decode 输出耦合 | 🟢 低 | 只读 `info`，不改接口；已被 P3.1-3.3 稳定 |
| P1/P2 版本被误改 | 🟢 低 | 明确 Scope：只改 p3_ |

## 实施策略

分两步：

1. **Step A — 纯函数外化**（低风险）
   - 新建 `p3_text_capacity.m` / `p3_downconv_bw.m` / `p3_channel_tap.m`
   - 先把 `on_scheme_changed` 的 switch 换成 `p3_text_capacity`
   - 运行 UI 手动验证 5 个 scheme 切换
   - commit

2. **Step B — 复杂函数外化**（中风险）
   - 新建 `p3_apply_scheme_params.m` / `p3_render_tabs.m`
   - 替换 `on_transmit` 参数段和 `update_tabs_from_entry`
   - 运行 UI + 冒烟测试
   - commit

3. **Step C — 主文件内部重组**（低风险，最后做）
   - 把 setup 段拆 4 个嵌套函数
   - 验证 UI 启动无异常
   - commit

每 step 独立 commit，失败可回退。

## Log

- 2026-04-17: Spec 创建

## Result

_待填写_
