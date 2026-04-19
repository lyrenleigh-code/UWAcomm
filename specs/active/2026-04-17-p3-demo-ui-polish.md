---
project: uwacomm
type: enhancement
status: active
created: 2026-04-17
parent: 2026-04-17-p3-demo-ui-refactor.md
phase: P3.x-maintenance
depends_on: [p3-demo-ui-refactor]
tags: [流式仿真, 14_Streaming, UI, 美化, 视觉设计, p3_demo_ui]
---

# p3_demo_ui 视觉美化 — 深色科技风 V2

## 目标

在现有 V3.1.0 深色科技风基础上，从平面 "能看" 升级为 **有层次、有动态、有叙事** 的通信声纳演示界面。五个方向全部覆盖：视觉层次 / 动态反馈 / 字体排版 / 数据可视化 / 布局重构。

**非目标**：
- 不改 modem_encode/decode 接口
- 不改 FIFO / timer / 解码逻辑
- 不动 P1/P2 版本
- 不改变 7 tab 架构与验收点（spec `2026-04-17-p3-demo-ui-refactor.md` 的验收项全部仍须通过）

## 设计语言

### 核心关键词

**声纳 × 示波器 × 科技驾驶舱**

- 主配色延续现有 deep space cyan + amber，但加入 **光晕 (glow)** 与 **半透明层 (surface overlay)**
- 形态延续矩形网格（uigridlayout 约束），但引入 **metric card** 与 **semantic chip** 两种原子单元
- 动态使用既有 100ms timer，不新增调度机制

### 新增设计 token

| Token | 值 | 用途 |
|-------|-----|------|
| `glow_cyan` | RGB(0.20, 0.78, 0.95, α=0.35) | 主色发光描边 |
| `glow_amber` | RGB(0.95, 0.62, 0.20, α=0.35) | 动作色发光（Transmit）|
| `surface_glass` | RGB(0.12, 0.16, 0.22) + α=0.6 | 玻璃层（card 底） |
| `border_subtle` | RGB(0.18, 0.22, 0.29) | 静态描边 |
| `border_active` | RGB(0.20, 0.78, 0.95) | 激活描边 |
| `accent_sonar` | RGB(0.30, 0.90, 0.55) | 声纳脉冲色 |

### 字体阶梯（新）

| 层级 | 字号 | 字重 | 字体 |
|------|------|------|------|
| H1 顶栏标题 | 22 | Bold | Segoe UI Semibold / system |
| H2 面板标题 | 15 | Bold | Segoe UI |
| H3 分组标签 | 12 | Bold | Segoe UI |
| Body | 12 | Regular | Segoe UI |
| Metric 大数 | 28 | Bold | **JetBrains Mono** (fallback: Cascadia Mono / Consolas) |
| Metric 单位 | 10 | Regular | JetBrains Mono |
| Code / 数据 | 11 | Regular | JetBrains Mono |

字体探测：启动时 `listfonts` 检查 JetBrains Mono / Cascadia → 失败 fallback Consolas。

## 五大方向落地

### A. 视觉层次强化

| 项 | 实现 |
|----|------|
| A1 面板发光描边 | `uipanel` 用 `BorderColor=PALETTE.border_subtle` + `BorderWidth=1`；"激活"面板（如 RX ON 时的 RX 面板）切 `border_active` |
| A2 Metric Card | 新建 `p3_metric_card.m`：接收 axes/grid + label + value + unit + tone，输出 3 层嵌套 uigridlayout（label / value 大字 / unit 小字 + 趋势 sparkline 占位） |
| A3 顶栏装饰 | 顶栏左侧加 **声纳波纹 patch**（3 个同心弧 via `uiaxes` + `patch`），标题右侧加 **logo 占位**（系统参数徽标：`fs/fc` 小字灰阶） |
| A4 分组分隔线 | TX/RX 面板内分组前加 1px 青色渐隐分隔 `uilabel` trick（高度 1，BackgroundColor=cyan α=0.3） |

### B. 动态反馈

| 项 | 实现 |
|----|------|
| B1 status 呼吸灯 | on_tick 中取 `sin(2π t / 2s)` 映射到 FontColor 的 α（Matlab 不支持 alpha，用亮度插值 text↔primary），RX ON 时触发 |
| B2 Transmit hover/press | `ButtonDownFcn` + `ButtonPushedFcn` 做 BackgroundColor 瞬变；press 时边框用 `glow_amber` |
| B3 检测闪烁 | `det_status` 由 "空闲"→"检测中" 时，切换 status 底色 3 次（100ms × 3）后回稳，通过 on_tick 跑计数器 |
| B4 progress 条 | RX 面板顶部加 1px 进度条（FIFO 占用率），用 `uilabel` 设 Width 百分比，青色；FIFO > 80% 时变 amber |
| B5 解码成功 flash | 每次成功解码 `text_out` 边框闪 primary 色 2 次（on_tick 驱动） |

### C. 字体与排版

| 项 | 实现 |
|----|------|
| C1 字体探测函数 | 新建 `p3_pick_font.m`：输入候选列表 → 返回第一个 `listfonts` 命中 |
| C2 字号阶梯 | 常量写入 `p3_style.m`（MATLAB 没有真常量，导出一个 `FONTS` / `SIZES` struct） |
| C3 语义着色 | 新建 `p3_semantic_color.m`：输入关键词（"收敛"/"未收敛"/"进行中"/"失败"）→ 返回 `struct('fg', rgb, 'bg', rgb)`，在 `update_info_panel` 调用 |
| C4 数字等宽 | 所有 BER / SNR / FIFO / noise_var 显示一律 FontName=JetBrains Mono |

### D. 数据可视化

| 项 | 实现 |
|----|------|
| D1 axes 深色化 | `style_dark_axes` 已有，扩展：grid `LineStyle=':'`、`GridAlpha=0.25`、`MinorGridVisible='on'` |
| D2 信道 stem 幅度梯度 | 新建 `p3_plot_channel_stem.m`：按 `abs(h)` 映射到 cyan→amber 渐变（colormap interp），深色底 + 白色 marker |
| D3 频谱填充 | 频谱图用 `area(...)` 替代 `plot(...)`，FaceColor=cyan α=0.3，EdgeColor=cyan α=0.9 |
| D4 scope 双色 | 示波器 "TX 干净基带" 浅青、"RX 实测" 亮青 + 半透叠加 |
| D5 星座图网格 | pre_eq / eq_it1 / eq_mid / post_eq 加 unit circle + (±1/√2,±1/√2) 参考点 + 暗青网格 |

### E. 布局重构

| 项 | 实现 |
|----|------|
| E1 TX/RX 头像区 | 面板顶加 1 行 `uigridlayout([1 3])`：图标（▲/▼ Unicode，16px）/ 中文主标题 / 英文副标题（小字灰） |
| E2 Bento 信息卡 | 现 `info_panel`（4×4 label 网格）改为 8 个 **metric card**（A2 的组件）排成 4×2 bento |
| E3 Tab 标题符号 | 底部 tab 加 Unicode 前缀：`⟡ Scope` / `≋ Spectrum` / `▨ 均衡` / `⇄ TX/RX` / `☲ 信道` / `☰ 日志`（测 Windows 渲染兼容性） |
| E4 顶栏紧凑化 | 顶栏重排成：`[标题 + 声纳] [scheme + bypass] [RX 开关] [status 灯] [Transmit 按钮 + Mon]`，高度 110→96，视觉密度降低 |

## 文件清单

### 新建（7 个）

| 文件 | 用途 | 预估行数 |
|------|------|---------|
| `ui/p3_style.m` | 返回 `PALETTE` + `FONTS` + `SIZES` + `GLOW` 四个 struct 的单一事实源 | ~90 |
| `ui/p3_pick_font.m` | 字体探测，fallback 链 | ~30 |
| `ui/p3_semantic_color.m` | 关键词→语义色（fg/bg） | ~50 |
| `ui/p3_metric_card.m` | 构造指标卡（label/value/unit/tone），返回 handles | ~80 |
| `ui/p3_plot_channel_stem.m` | 彩色 stem 绘信道抽头 | ~40 |
| `ui/p3_sonar_badge.m` | 顶栏声纳波纹装饰 patch | ~50 |
| `ui/p3_animate_tick.m` | on_tick 内被调用的动效更新（呼吸灯 / flash / progress） | ~80 |

### 修改（1 + 现有 refactor 产物）

| 文件 | 修改 |
|------|------|
| `ui/p3_demo_ui.m` | 引入 p3_style / p3_pick_font；顶栏 E4 重排；TX/RX 头像 E1；info_panel 改 bento E2；on_tick 调 p3_animate_tick；并行：把 A/B/C/D/E 所涉的样式/动效调用点接入 |
| `ui/p3_render_tabs.m` | (若 refactor 已拆) 接入 D1-D5 的深色 axes + 彩色 stem + 频谱填充 + 星座网格 |

### 不动

- `p1_demo_ui.m`、`p2_demo_ui.m`
- `modem_*`、`common/`、`tx/`、`rx/`
- 01-13 模块

## 与 refactor spec 的关系

`2026-04-17-p3-demo-ui-refactor.md` 中 **Step C 主文件内部重组** 如果未完成（当前主文件仍 1461 行），polish 实施前必须先收口 Step C，否则主文件会继续膨胀。

**执行顺序建议**：

```
refactor Step C 收口 → polish Step 1~4
```

若 Step C 继续拖，polish 也可执行，但要求每次 polish 变更**净增 ≤ +80 行**（样式抽取、动效嵌套函数都要压缩）。

## 验收标准

### 视觉验收（手动截图对比）

- [ ] 启动后 3 秒内主窗口可见，无报错
- [ ] 所有面板有边框（A1），RX ON 时 RX 面板边框切青色
- [ ] BER / SNR / FIFO / turbo_iter 显示为 metric card（A2）
- [ ] 顶栏有声纳波纹装饰（A3）
- [ ] RX ON 状态灯有**呼吸效果**（肉眼可见亮度周期变化，B1）
- [ ] Transmit 按钮 press 时边框短暂发光（B2）
- [ ] 检测到帧瞬间 status 闪烁（B3）
- [ ] RX 面板 FIFO 进度条随 TX 变化（B4）
- [ ] 成功解码后 text_out 边框闪 2 次（B5）
- [ ] Metric 区使用等宽字体（C4）
- [ ] `convergence` 字段显示有语义色（"收敛"绿 / "未收敛"红）（C3）
- [ ] 信道 tab 抽头为**彩色 stem**（D2）
- [ ] 频谱有**填充**（D3）
- [ ] TX/RX 对比双色叠加（D4）
- [ ] 星座图有单位圆 + 参考点（D5）
- [ ] TX/RX 面板顶部有**图标 + 中/英双标题**（E1）
- [ ] info 区是 **8 张 bento card** 布局（E2）
- [ ] 底部 tab 标题有 Unicode 符号前缀（E3）
- [ ] 顶栏高度 ≤ 96px（E4）

### 功能回归（refactor spec 的全部验收项）

- [ ] 5 个 scheme 切换正常
- [ ] RX 监听 ON + Transmit 至少一次解码成功
- [ ] 7 个底部 tab 全部渲染
- [ ] 解码历史下拉切换正常
- [ ] Bypass RF 正常
- [ ] Clear 按钮正常
- [ ] 关闭无 timer 泄漏

### 代码指标

- [ ] `p3_demo_ui.m` **≤ 900 行**（polish 若配合 Step C 收口则 ≤ 800）
- [ ] 新建 7 个 helper 各 ≤ 100 行
- [ ] `p3_style.m` 是 **唯一** 色板 / 字体 / 字号出处（旧的内联 PALETTE 拆出）
- [ ] 所有样式相关魔法值都落在 `p3_style.m`
- [ ] Code Analyzer 无新增警告

### 性能

- [ ] 100ms timer 在 `p3_animate_tick` 介入后仍不丢 tick（`BusyMode='drop'` 仍兜底）
- [ ] GUI 启动时间 ≤ 3 秒（等同原）
- [ ] 呼吸灯/进度条更新 CPU 可忽略（<2% 增量）

## 风险

| 风险 | 等级 | 应对 |
|------|------|------|
| 字体不存在时 fallback 链失效 | 🟡 中 | `p3_pick_font` 最终 fallback 为 `'monospaced'`（MATLAB 保证可用） |
| Unicode 符号（⟡ ≋ ▨）在 Windows MATLAB 渲染缺字形 | 🟡 中 | 实施前先写一个 `test_p3_unicode_render.m` 在 `p3_demo_ui` 启动时临时绘制 20 个候选字符，肉眼确认；不渲染的回退 ASCII（`> Scope` 等） |
| `uipanel` 的 `BorderColor` 在老 MATLAB（<R2023a）不支持 | 🟡 中 | 用 `matlab.ui.container.Panel` 的属性探测：`isprop(p, 'BorderColor')`，不支持时静默跳过 A1 |
| 呼吸灯 100ms 更新肉眼闪烁 | 🟢 低 | 用 1Hz 正弦，tick 只更新，不 redraw 冗余；亮度变化范围 ±15% |
| bento 改造破坏既有数值绑定（`app.lbl_ber` 等句柄） | 🔴 高 | metric card 构造器返回 handles struct，**句柄字段名保持不变** (`app.lbl_ber` 仍指向 value label)，回调零改动 |
| 顶栏 E4 重排破坏 Layout.Column 赋值 | 🟡 中 | 重排后逐个控件 assert `app.tx_btn.Layout.Column == N`（冒烟测试） |
| p3_render_tabs 已外化 → D1-D5 改动需跨文件 | 🟢 低 | D 系列改动集中在 `p3_render_tabs.m`，主文件零侵入 |
| MATLAB R2025b 静态分析链式赋值（见 conclusions.md #22） | 🟡 中 | 新建 helper 严禁 `uilabel(...).Layout.Row = X` 写法 |

## 实施策略（4 步，每步独立 commit）

### Step 1 — 样式基础设施（低风险，解耦先行）
- 新建 `p3_style.m` / `p3_pick_font.m` / `p3_semantic_color.m`
- 把现有 `PALETTE` struct 从 p3_demo_ui.m 抽到 `p3_style.m`
- 字体替换（C1/C2/C4）
- 运行 UI，视觉应与之前 100% 等价（仅字体变化）
- commit

### Step 2 — 数据可视化升级（中风险，只动 render 层）
- 新建 `p3_plot_channel_stem.m`
- 修改 `p3_render_tabs.m` 的 `render_channel` / `render_spectrum` / `render_compare` / `render_eq`
- 实施 D1/D2/D3/D4/D5
- 运行 UI 对比截图
- commit

### Step 3 — 布局重构（中风险，动主文件结构）
- 新建 `p3_metric_card.m` / `p3_sonar_badge.m`
- 顶栏 E4 重排 + 声纳 badge（A3）
- TX/RX 面板头像（E1）
- info 区 bento（E2），**句柄名保持不变**
- tab 标题符号（E3）
- 所有面板边框（A1）
- 分组分隔线（A4）
- 冒烟测试：5 个 scheme 切换 + 至少一次解码成功
- commit

### Step 4 — 动态反馈（低风险，纯嵌套函数）
- 新建 `p3_animate_tick.m`
- 语义色接入 C3
- on_tick 尾部调 p3_animate_tick
- 呼吸灯 B1 / hover B2 / 检测闪烁 B3 / progress 条 B4 / 解码 flash B5
- 运行 UI 验证所有动效
- commit

每 step 独立 commit，失败可回退。

## 冒烟测试脚本 `tests/test_p3_ui_polish_smoke.m`

```matlab
% 1. 样式基础设施
S = p3_style();
assert(isfield(S, 'PALETTE') && isfield(S, 'FONTS') && isfield(S, 'SIZES'));
assert(isfield(S.PALETTE, 'glow_cyan'));

% 2. 字体探测
f = p3_pick_font({'NotExistFont', 'Consolas', 'monospaced'});
assert(~isempty(f));

% 3. 语义色
c = p3_semantic_color('收敛');
assert(all(size(c.fg) == [1 3]) && c.fg(2) > c.fg(1)); % 绿

c2 = p3_semantic_color('未收敛');
assert(c2.fg(1) > c2.fg(2)); % 红

% 4. metric card handles 返回齐全
fig = uifigure('Visible','off');
grid = uigridlayout(fig, [1 1]);
h = p3_metric_card(grid, 'BER', '1.2e-3', '', 'primary');
assert(isfield(h, 'value') && isgraphics(h.value));
close(fig);

% 5. Unicode tab 标题字形可渲染（肉眼辅助）
% 这步无法自动化 → 手动验收
```

## Log

- 2026-04-17: Spec 创建

## Result

_待填写_
