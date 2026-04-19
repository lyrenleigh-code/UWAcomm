---
project: uwacomm
type: enhancement
status: active
created: 2026-04-17
parent: 2026-04-17-p3-demo-ui-polish.md
phase: P3.x-maintenance
depends_on: [p3-demo-ui-polish]
tags: [流式仿真, 14_Streaming, UI, 可视化, 同步, 多普勒, BER历史]
---

# p3_demo_ui 可视化扩展 — 同步/多普勒 + 质量历史

## 目标

三项合一：

1. **P3 真同步切换** — 移除 `frame_start_write` 共享捷径，`try_decode_frame` 走真实 LFM 匹配滤波检测（与 P1/P2 对齐）
2. **Sync tab** — 展示真同步过程：匹配滤波 peak / 符号定时 / 多普勒占位（scheme 分支渲染）
3. **Quality tab** — 最近 N 帧 BER/SNR/iter 演进曲线

**非目标**：
- 不改 modem_encode 接口
- Doppler 链路接入留后续 spec（`doppler_edit` 当前未用）
- 不改 timer tick 机制（100ms）

## 现状分析（关键发现）

### A. 现有 P3 同步路径（作弊式，本 spec Step 0 移除）

`p3_demo_ui.m` `try_decode_frame` L1088：
```matlab
fs_pos = app.tx_meta_pending.frame_start_write;   % TX 推入时已写入，RX 直接读
```

即帧起点来自 TX 状态共享，**无真实前导码匹配滤波**。模块 08 的 `sync_dual_hfm` / `detect_lfm_start` 现在在 P3 demo 里未被调用。

**本 spec Step 0 将切换到真同步**：参考 P2 `frame_detector.m` 的 hybrid 模式，在 FIFO 尾部滑动匹配滤波检测 HFM+ peak，定位 fs_pos 后解码。

### B. Decoder 内符号同步（可暴露）

`rx/modem_decode_scfde.m` L65-71：
```matlab
for off = ... % 小窗口搜索
    c = corr(rx_filt, train_template);
    if c > best_corr, best_corr = c; best_off = off; end
end
rx_sym_all = rx_filt(best_off+1 : sys.sps : end);
```

**数据可用**：`best_off`, `best_corr`, 以及遍历窗口的 corr 曲线。需在 decode 返回 `info` 中新增字段。

### C. Doppler 未接入

`app.doppler_edit` 字段存在（L256）但整个代码**零处读取**。TX 链路 `frame_ch = conv(frame_bb, h_tap)`（L830）**无 Doppler resample**。

因此 Stage 1 的 "多普勒估计轨迹" 若要真实有效，需要**先接入 doppler_edit 到 TX 信道**（见 §4）。

## Stage 1: 同步/多普勒 tab

### 子图布局（2×2 或 1×3）

```
┌─────────────────────┬─────────────────────┐
│ 🎯 帧起点定位       │ 📡 符号定时搜索     │
│ (LFM 匹配滤波峰值)  │ (decoder best_off)  │
├─────────────────────┼─────────────────────┤
│ 🌊 多普勒 α 轨迹     │ 📌 HFM+/HFM- 相关  │
│ (最近 20 帧 α 值)   │ (粗同步双向对比)    │
└─────────────────────┴─────────────────────┘
```

### 数据来源（Step 0 真同步直接提供）

**M1. try_decode_frame 走真同步 — 替代 frame_start_write**

新建 `common/detect_frame_stream.m`（流式帧检测器）：

```matlab
function det = detect_frame_stream(fifo, fifo_write, last_fs, sys, search_win)
% 输入：
%   fifo         — passband FIFO ring（real 向量）
%   fifo_write   — FIFO 写指针（绝对位置）
%   last_fs      — 上次检测到的 fs_pos（用于预测窗口）
%   sys          — 系统参数（fs/fc/preamble 模板信息）
%   search_win   — 搜索窗口（样本数）
% 输出：
%   det.found        — bool
%   det.fs_pos       — 检测到的帧起点
%   det.hfm_pos_corr — HFM+ 匹配滤波曲线（用于 sync tab 可视化）
%   det.hfm_neg_corr — HFM- 匹配滤波曲线
%   det.peak_ratio   — 峰值 / 旁瓣比
%   det.confidence   — 检测置信度
```

改 `try_decode_frame`：
```matlab
function try_decode_frame()
    if ~app.tx_pending, return; end
    % 真同步：滑动窗口扫 FIFO 尾部
    det = detect_frame_stream(app.fifo, app.fifo_write, app.last_decode_at, app.sys, search_win);
    if ~det.found, return; end
    if app.last_decode_at >= det.fs_pos, return; end
    fs_pos = det.fs_pos;
    fn = app.tx_meta_pending.frame_pb_samples;
    if app.fifo_write < fs_pos + fn - 1, return; end  % 等够样本
    rx_seg = app.fifo(fs_pos : fs_pos + fn - 1);
    ...
    % 同步结果保存到 entry（供 sync tab 用）
    entry.sync_det = det;
end
```

**关键**：`frame_start_write` 可仍写入 `app.tx_meta_pending` 作为 ground truth（sync tab 里叠加显示 "真值 vs 检测值"），但不再用于驱动解码。

**M2. modem_decode_* 暴露符号定时**

在 `rx/modem_decode_scfde.m` 的 info 里新增：
```matlab
info.sym_off_best = best_off;
info.sym_off_corr = corr_curve;  % 遍历窗口的 corr 值
info.sym_off_search_window = search_range;
```

同理 `modem_decode_ofdm` / `modem_decode_sctde` 修改。`modem_decode_fhmfsk` / `modem_decode_dsss` 的同步机制不同，输出相应字段即可（跳频能量峰 / Rake 合并点）。

**M3. Doppler 接入 — 策略 B（本 spec 不做）**

`app.doppler_edit` 字段 UI 有但 TX 链路未用。本 spec **不接入** Doppler 注入/估计路径。

多普勒子图内容：
- 若能从 `sync_dual_hfm` 副产物读出（HFM+ vs HFM- 峰值偏差推算 α），直接展示
- 否则占位图 + 标注 "Doppler 链路未接入，见 doppler-integration spec"
- α 轨迹从 `app.history` 的 `info.sync_det.peak_ratio` 等采集（若无则留空）

### 渲染 helper — `ui/p3_render_sync.m`

```matlab
function p3_render_sync(entry, axes_struct, sys, PALETTE, FONTS)
% 输入：
%   entry        — history 条目（需含 sync_viz / info.sym_off_*）
%   axes_struct  — 4 uiaxes 句柄
%   sys          — 系统参数
%   PALETTE/FONTS — 样式（来自 p3_style）
%
% 渲染 4 子图：
%   1. 帧起点（LFM 匹配滤波）
%   2. 符号定时（corr 曲线 + best_off 标记）
%   3. 多普勒轨迹（从 app.history 聚合，可外部传入）
%   4. HFM+/HFM- 相关
end
```

### 视觉规范

- 匹配滤波峰值用 **amber 高亮线** + **cyan 次峰圈选**（标注旁瓣）
- 符号定时 corr 曲线：青色填充，best_off 位置 amber 垂线
- α 轨迹：多帧连线 + 点标记，偏差用 ±3σ 误差条
- 所有 axes 用 `p3_style_axes` 统一深色

## Stage 2: 质量历史 tab

### 子图布局（2×1）

```
┌─────────────────────────────────────┐
│ 📊 BER 历史曲线                     │
│ (最近 20 帧，scheme 分色)           │
├─────────────────────────────────────┤
│ 📈 SNR 估计 + turbo_iter            │
│ (双 Y 轴：左 SNR 右 iter)            │
└─────────────────────────────────────┘
```

### 数据来源

直接读 `app.history`（已存在的 cell array，最多 20 帧）：

```matlab
for k = 1:length(app.history)
    e = app.history{k};
    ber(k)    = e.ber;
    est_snr(k) = e.info.estimated_snr;
    iter(k)   = e.iter;
    scheme{k} = e.scheme;
end
```

### 渲染 helper — `ui/p3_render_quality.m`

```matlab
function p3_render_quality(history, axes_struct, PALETTE, FONTS)
% 输入：
%   history      — cell array of entry
%   axes_struct  — 2 uiaxes 句柄（ax_ber / ax_snr）
%   PALETTE/FONTS
%
% 渲染：
%   ax_ber: semilogy，BER 散点+连线，scheme 分色（legend）
%   ax_snr: plot SNR 实线 + iter 柱状图叠加（双 Y 轴）
end
```

### 视觉规范

- BER ≥ 1e-1 **红色**，1e-2 ≤ BER < 1e-1 **黄色**，< 1e-2 **青色**（用点颜色，按值染色）
- BER=0 用特殊标记（向下三角 + "✓"）
- SNR 曲线青色实线，iter 柱状图半透 amber
- 空 history 显示 "(暂无解码数据，Transmit 至少 1 次)"

## 文件清单

### 新建（3 helper + 1 真同步检测器）

| 文件 | 职责 | 行数估计 |
|------|------|---------|
| `14_Streaming/src/Matlab/common/detect_frame_stream.m` | **流式帧检测器**（P3 真同步核心，从 FIFO 做 HFM 匹配滤波） | ~120 |
| `14_Streaming/src/Matlab/ui/p3_render_sync.m` | 同步 tab 4 子图 scheme 分支渲染 | ~180 |
| `14_Streaming/src/Matlab/ui/p3_render_quality.m` | 质量 tab 2 子图渲染 | ~90 |

### 修改

| 文件 | 修改 |
|------|------|
| `ui/p3_demo_ui.m` | **try_decode_frame 换真同步**；底部 tab 6→8；`update_tabs_from_entry` 尾部调 `p3_render_sync` + `p3_render_quality` |
| `rx/modem_decode_scfde.m` | info 新增 `sym_off_best` / `sym_off_corr` |
| `rx/modem_decode_ofdm.m` | 同上 |
| `rx/modem_decode_sctde.m` | 同上 |
| `rx/modem_decode_fhmfsk.m` | info 新增 `hop_energy_peaks`（跳频 peak 位置/能量） |
| `rx/modem_decode_dsss.m` | info 新增 `rake_merge_delays`（Rake 选中径时延） |
| `rx/modem_decode_otfs.m` | info 新增 `dd_path_info`（DD 域路径） |

### 不动

- modem_encode_*
- 01-13 模块（仅读 `08_Sync/` 的 `detect_lfm_start` / `sync_dual_hfm` 作依赖）
- Doppler 注入链路

## 验收标准

### 功能验收

#### Step 0 真同步
- [ ] `detect_frame_stream` 单元测试：对合成前导码 + 噪声，检测位置偏差 ≤ 2 样本
- [ ] UI 下 Transmit 5 次，全部成功解码（BER 分布与旧 cheat 路径一致）
- [ ] log 显示 "sync_det fs_pos=X (gt=Y, diff=Z)"，|diff| ≤ 4 样本
- [ ] SNR=15dB / static 6 径下 detect rate = 100%（5/5）
- [ ] 关闭 RX 开关后立即停检测（无 false trigger）

#### Step 2/3 可视化
- [ ] 启动 UI 无报错，8 个底部 tab 全部可见
- [ ] Transmit 1 次后 "🎯 同步/多普勒" tab 4 子图全部渲染
  - [ ] 帧起点峰值可见且接近真实位置
  - [ ] 符号定时 corr 曲线有明确 best_off 标记
  - [ ] 多普勒轨迹占位或首点
  - [ ] HFM+/HFM- 对比图可见
- [ ] Transmit 3+ 次后 "📊 质量历史" tab 显示
  - [ ] BER 散点按值染色
  - [ ] SNR 曲线平滑
  - [ ] iter 柱状图叠加
- [ ] 5 个 scheme 切换时 sync_viz 字段仍有效（FH-MFSK / DSSS 用不同图层）
- [ ] 空 history 状态下两 tab 显示友好占位文字

### 回归验收（前序 polish spec 的所有项必须仍通过）

- [ ] 原 6 个 tab 功能完整
- [ ] SC-FDE/OFDM/SC-TDE 解码成功（BER=0 @ default params）
- [ ] FH-MFSK 解码成功
- [ ] RX 监听呼吸灯 / 解码闪烁动效正常
- [ ] Clear 按钮清空 sync/quality tab

### 代码指标

- [ ] 3 个新 helper 各 ≤ 150 行
- [ ] `p3_demo_ui.m` 净增 ≤ +80 行（tab 构建 + 路由）
- [ ] modem_decode_* 每个修改点 ≤ 5 行（只加字段）
- [ ] mlint 无新增警告

## 风险

| 风险 | 等级 | 应对 |
|------|------|------|
| **detect_frame_stream 漏检/误检导致解码失败** | 🔴 高 | Step 0 commit 前必须跑 5 次 Transmit 全部成功；漏检时 log 显示 "未检测到帧，FIFO 长度 X"；用 `ground_truth vs 估值` 偏差量化精度 |
| 流式检测 FIFO 尾部窗口不够引起 peak 截断 | 🟡 中 | 搜索窗口 = `2 × preamble_len`，先等 FIFO 积累足够再触发检测 |
| 前导码模板需要和 TX 一致 | 🟡 中 | 复用 `assemble_physical_frame` / `gen_hfm` / `gen_lfm`，不要重新实现 |
| SC-FDE decoder `best_off` 搜索窗口小 → corr 曲线点少 | 🟡 中 | sync tab 里拓宽展示（仅 viz），decoder 内部不改 |
| FH-MFSK / DSSS 没有 `sym_off_best` 概念 | 🟡 中 | scheme 分支渲染：Turbo 画 corr，FH-MFSK 画 hop peaks，DSSS 画 rake delays |
| 多普勒 α 轨迹空（因未接入） | 🟡 中 | 占位文字 "Doppler 链路未接入（见 doppler-integration spec）" |
| Quality tab SNR 曲线 y 轴自适应不稳 | 🟢 低 | `ylim auto` + 下限 clip 到 -20dB |
| 新 tab 超出 figure 底部高度 | 🟡 中 | tab_h 320 不变，tabgroup 内部滚动 |
| 真同步切换破坏单帧 Transmit UI 响应性 | 🟡 中 | 每 tick 的滑动检测限制最大搜索长度，保证 < 5ms CPU |

## 实施策略（4 步，每步独立 commit）

### Step 0 — P3 真同步切换（中高风险，优先）
- 新建 `common/detect_frame_stream.m`：流式 HFM+ 匹配滤波，返回 `fs_pos` + 双 HFM corr 曲线
- 修改 `try_decode_frame`：
  - 用 `detect_frame_stream` 替代 `frame_start_write` 读
  - 保留 `app.tx_meta_pending.frame_start_write` 作 **ground truth** 给 sync tab 用（叠加显示真值 vs 估值）
- 冒烟：Transmit 5 次，验证全部成功解码；加 log 输出检测到的 fs_pos 与 ground truth 差值
- 回归：test_p3_unified_modem 2/2 PASS（该测试不走 UI，不受影响）
- commit

### Step 1 — 5 个 decoder info 字段扩展（低风险）
- 修改 6 个 `modem_decode_*.m`，info 字段新增 scheme 特定同步数据（每个 ≤ 5 行）
- 不改 UI / TX
- 回归跑 `test_p3_unified_modem.m`：2/2 PASS
- commit

### Step 2 — Quality tab（低风险，只读 history）
- 新建 `ui/p3_render_quality.m`
- `p3_demo_ui.m` 新增第 7 个 tab "📊 质量历史" + axes_struct
- `update_tabs_from_entry` 调 `p3_render_quality(app.history, ...)`
- UI 冒烟：Transmit 5 次看 BER/SNR/iter 曲线
- commit

### Step 3 — Sync tab（中风险，scheme 分支渲染）
- 新建 `ui/p3_render_sync.m`（scheme 分支路由）
- `p3_demo_ui.m` 新增第 8 个 tab "🎯 同步/多普勒"
- `update_tabs_from_entry` 调 `p3_render_sync(entry, ...)`
- UI 冒烟：5 个 scheme 分别 Transmit 一次，验证 sync tab 子图各有合理内容
- commit

每步独立 commit，失败 `git revert` 回退。

## 后续 spec（本 spec 外，独立规划）

- `2026-04-18-p3-doppler-integration.md`（预占位）: 接入 `doppler_edit` 到 TX 信道（resample 注入 α 漂移 + RX `sync_dual_hfm` 估 α 反补），让多普勒 tab 真实有效

## Log

- 2026-04-17: Spec 创建

## Result

_待填写_
