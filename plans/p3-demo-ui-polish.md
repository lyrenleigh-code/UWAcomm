---
spec: 2026-04-17-p3-demo-ui-polish.md
project: uwacomm
status: active
created: 2026-04-17
---

# p3_demo_ui 美化 — 实施计划

## 执行顺序

```
Step 1 样式基础设施 → Step 2 数据可视化 → Step 3 布局重构 → Step 4 动态反馈
```

每 step 单独 commit，失败独立回退。

## Step 1 — 样式基础设施（本 commit 内完成）

### 任务清单

- [ ] 新建 `p3_style.m`
  - 返回 struct 含 `PALETTE` / `FONTS` / `SIZES` / `GLOW` 四字段
  - 把主文件 L88-108 的 PALETTE struct 搬过来
  - 新增 glow_cyan / glow_amber / surface_glass / border_subtle / border_active / accent_sonar
  - 新增 FONTS.h1/h2/h3/body/metric_value/metric_unit/code 字号和族
  - 新增 SIZES.padding/spacing/row_h/title_h 通用尺寸
  - 新增 GLOW.border_width / GLOW.alpha

- [ ] 新建 `p3_pick_font.m`
  - `function name = p3_pick_font(candidates)`
  - 遍历 `candidates` cell array，首个 `listfonts` 命中的返回
  - 最终 fallback `'monospaced'`

- [ ] 新建 `p3_semantic_color.m`
  - `function c = p3_semantic_color(keyword)`
  - 支持关键词：`'收敛'|'converged'` → 绿；`'未收敛'|'diverged'` → 红；`'进行中'|'busy'` → 黄；`'失败'|'error'` → 深红；`'空闲'|'idle'` → 灰
  - 返回 `struct('fg', rgb, 'bg', rgb)`
  - 未知关键词返回中性灰

- [ ] 修改 `p3_demo_ui.m`
  - 删除 L88-108 内联 PALETTE
  - 开头加 `S = p3_style(); PALETTE = S.PALETTE;`
  - 所有 `'FontName','Consolas'` 替换为 `'FontName', S.FONTS.code`（等宽字体探测）
  - 标题 H1 字号 20→22，副标题提升对比度
  - 主文件净增应 ≤ +5 行（主要是删 PALETTE 换一行调用）

### 验收

- [ ] `p3_demo_ui()` 启动无报错
- [ ] 5 个 scheme 可切换
- [ ] 视觉与 Step 1 前 99% 等价（仅字体/字号差异）
- [ ] `test_p3_ui_polish_smoke.m` 中前 3 项通过

## Step 2 — 数据可视化升级

### 任务清单

- [ ] 新建 `p3_plot_channel_stem.m`
  - 接收 axes + h_tap + sys → 按 |h| 映射 cyan→amber 渐变 marker
  - 返回句柄 cell

- [ ] 修改 `p3_render_tabs.m`（若存在）/ `p3_demo_ui.m` 中 `update_tabs_from_entry` 对应段
  - render_channel_td 改用 `p3_plot_channel_stem`
  - render_spectrum 用 `area(...)` 替代 `plot(...)`，半透填充
  - render_compare TX/RX 双色叠加
  - render_eq 星座 tab 加 unit circle + (±1/√2,±1/√2) 参考
  - axes 样式调 `p3_style_dark_axes_v2`（grid ':' 线 + alpha 0.25）

### 验收

- [ ] 信道 stem 有彩色梯度
- [ ] 频谱有填充
- [ ] 星座有单位圆 + 参考点
- [ ] TX/RX 对比双色

## Step 3 — 布局重构

### 任务清单

- [ ] 新建 `p3_metric_card.m`
  - 输入：parent grid + label + value_text + unit + tone
  - 输出：`struct('label', h, 'value', h, 'unit', h, 'panel', h)`
  - 内部 3 行：label / value（大等宽）/ unit（小）

- [ ] 新建 `p3_sonar_badge.m`
  - 输入 parent → 画 3 道同心弧 + 中心点，青色半透
  - 占位 80×80 px

- [ ] 修改 `p3_demo_ui.m`
  - 顶栏重排 E4：高 110→96，列权重重分
  - TX 面板头：▲ + "TX 发射端" + "Transmitter" 副标
  - RX 面板头：▼ + "RX 接收端" + "Receiver" 副标
  - info_panel 从 4×4 label 改为 **2×4 bento**（8 张 metric card）
    - BER / 错误比 / FIFO / 检测状态
    - estimated_snr / estimated_ber / turbo_iter / convergence
  - **关键：`app.lbl_ber / app.lbl_esnr / ...` 句柄字段名保持不变**，指向 metric card 的 `.value` handle
  - tab 标题加 Unicode 前缀（先测字形）
  - 面板统一加 `BorderColor` + `BorderWidth=1`（探测属性支持性）

### 验收

- [ ] 顶栏高 ≤ 96
- [ ] 所有 `app.lbl_*` 回调不变仍能更新
- [ ] 至少一次解码成功且 metric 卡显示正确
- [ ] tab 标题 Unicode 渲染成功（否则回退 ASCII）

## Step 4 — 动态反馈

### 任务清单

- [ ] 新建 `p3_animate_tick.m`
  - 输入 `app` + `elapsed_s`
  - 内部：
    - 呼吸灯：RX ON 时 status_lbl FontColor 亮度调 sin(2π·t/2) × 0.15
    - 检测闪烁：`app.flash_det_count > 0` 时切底色
    - 解码 flash：`app.flash_decode_count > 0` 时 text_out 边框切换
    - FIFO 进度条更新：FIFO 占用率 → width 百分比
  - 返回更新后的 app

- [ ] 修改 `p3_demo_ui.m`
  - on_tick 尾部调 `app = p3_animate_tick(app, tic_elapsed)`
  - on_decode_complete 设 `app.flash_decode_count = 4`
  - on_detection_start 设 `app.flash_det_count = 3`
  - Transmit 按钮 `ButtonPushedFcn` 前后做 glow 瞬变
  - RX ON 面板 BorderColor 切 active，OFF 切 subtle

- [ ] C3 语义色接入
  - `update_info_panel` 里 convergence 字段用 `p3_semantic_color` 染色
  - 检测状态同理

### 验收

- [ ] 呼吸灯肉眼可见
- [ ] Transmit 有 press feedback
- [ ] 成功解码后 text_out 闪 2 次
- [ ] 检测开始瞬间 status 闪
- [ ] FIFO 进度条正确反映占用率
- [ ] convergence "收敛"绿 / "未收敛"红

## 风险清单（来自 spec，执行时监控）

1. 🔴 bento 改造破坏 `app.lbl_*` 句柄绑定 → 保持字段名
2. 🟡 字体不存在 → fallback 链
3. 🟡 Unicode 字形缺失 → `test_p3_unicode_render` 先测
4. 🟡 `uipanel.BorderColor` 老版本不支持 → isprop 探测
5. 🟡 R2025b 链式赋值陷阱 → 新 helper 禁用

## 冒烟测试

贯穿 Step 1-4 的 `tests/test_p3_ui_polish_smoke.m` 增量补全。Step 1 完成后先跑前 3 项。

## 回退策略

每 step 单独 commit → 失败 `git revert HEAD` 即可。若某 step 中途发现方向错误，**不合并** 当前 step，回退到上一 step 末尾重新设计。

## Log

- 2026-04-17: Plan 创建，准备开始 Step 1
