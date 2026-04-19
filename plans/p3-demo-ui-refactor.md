---
project: uwacomm
type: plan
status: active
created: 2026-04-17
parent_spec: specs/active/2026-04-17-p3-demo-ui-refactor.md
phase: P3.x-maintenance
tags: [流式仿真, 14_Streaming, UI, 重构, p3_demo_ui]
---

# p3_demo_ui 重构 — 实施计划

## 目标

执行 spec `2026-04-17-p3-demo-ui-refactor.md` 的方案 B。**先做字段映射**（spec 标注的 🔴 高风险项），再按 3 步 commit 实施。

## 非目标

- 不改 `modem_encode/decode` 接口
- 不改 UI 外观/布局
- 不动 p1_demo_ui.m / p2_demo_ui.m

---

## 字段映射（Step 0，实施前必做）

### 1. `p3_text_capacity.m`

**原位置**：`on_scheme_changed` L396-403

**依赖的 app 字段**：无（硬编码数字）

**当前实现中有常量 magic number**：
- `(128*32 - 2) / 8` ← SC-FDE 的 `blk_fft=128 * N_blocks=32 - mem=2`（其中 2 = codec.constraint_len - 1）
- `((256-8)*16 - 2) / 8` ← OFDM 的 `(blk_fft=256 - nulls=8) * N_blocks=16 - mem=2`
- `(2000 - 2) / 8` ← SC-TDE 的 N_data_sym=2000 - mem=2
- `(1200 - 2) / 8` ← DSSS N_info=1200 - mem? 实际 `on_transmit` L561 里 DSSS `N_info = 1200`（无 mem 扣减）
- `2192 / 8` ← FH-MFSK payload_bits=2048 + header=128 + crc=16 = 2192

**新签名**：

```matlab
function nb = p3_text_capacity(sch, sys)
% 输入: sch 体制名, sys 系统参数结构
% 输出: nb 文本最大字节数
    mem = sys.codec.constraint_len - 1;
    switch sch
        case 'SC-FDE'
            blk_fft = 128;  % 默认值，与 on_scheme_changed 当前 switch 一致
            N_blocks = 32;
            nb = floor((blk_fft * (N_blocks - 1) - mem) / 8);  % V2: block 1 训练
        case 'OFDM'
            blk_fft = 256; N_blocks = 16;
            nulls = floor(blk_fft / sys.ofdm.null_spacing);
            N_data_sc = blk_fft - nulls;
            nb = floor((N_data_sc * (N_blocks - 1) - mem) / 8);
        case 'SC-TDE'
            N_data_sym = 2000;
            nb = floor((N_data_sym - mem) / 8);
        case 'DSSS'
            N_info = 1200;
            nb = floor(N_info / 8);
        case 'FH-MFSK'
            nb = floor(sys.frame.body_bits / 8);  % header + payload + crc
        otherwise
            nb = 200;
    end
end
```

**🔴 发现的 bug**：原代码 SC-FDE 公式 `128*32-2` 少了 "block 1 = 训练块" 的扣减，实际 `on_transmit` L541 是 `blk_fft * (N_blocks - 1) - mem`。当前 switch 会**显示容量偏大**（误差 4096 bits ≈ 512 字节）。修复此 bug 是本重构的顺带收益。冒烟测试 `assert(nb_helper == nb_on_transmit)` 会捕获。

---

### 2. `p3_downconv_bw.m`

**原位置**：`downconv_bandwidth` L958-972

**依赖的 app 字段**：
- `app.sys.sym_rate`
- `app.sys.scfde.rolloff`, `.ofdm.rolloff`, `.sctde.rolloff`
- `app.sys.dsss.total_bw`, `.otfs.total_bw`, `.fhmfsk.total_bw`

**新签名**：

```matlab
function bw = p3_downconv_bw(sch, sys)
    switch sch
        case 'SC-FDE', bw = sys.sym_rate * (1 + sys.scfde.rolloff);
        case 'OFDM',   bw = sys.sym_rate * (1 + sys.ofdm.rolloff);
        case 'SC-TDE', bw = sys.sym_rate * (1 + sys.sctde.rolloff);
        case 'DSSS',   bw = sys.dsss.total_bw;
        case 'OTFS',   bw = sys.otfs.total_bw;
        otherwise,     bw = sys.fhmfsk.total_bw;
    end
end
```

**迁移调用点**：
- `on_transmit` L653（隐式 this-function call） → `p3_downconv_bw(sch, app.sys)`
- `update_tabs_from_entry` L1151, L1319 → 同上

---

### 3. `p3_channel_tap.m`

**原位置**：`build_channel_tap` L974-1033

**依赖的 app 字段**：
- `app.preset_dd.Value` ← **隐式 handle 依赖，必须转成显式参数**
- `app.sys.dsss.chip_delays / gains_raw / sps`
- `app.sys.otfs.sym_delays / gains_raw`
- `app.sys.sps`
- `app.sys.fhmfsk.samples_per_sym`

**新签名**：

```matlab
function [h_tap, label] = p3_channel_tap(sch, sys, preset)
% 输入:
%   sch    体制名
%   sys    系统参数
%   preset 信道预设字符串（来自 UI 下拉，如 '6径 标准水声'）
% 输出:
%   h_tap  信道冲激响应（在 body_bb 的采样率下）
%   label  描述标签，UI 显示用
```

函数体保持原逻辑，仅把 `app.preset_dd.Value` 替换为参数 `preset`，`app.sys.X` 替换为 `sys.X`。

**迁移调用点**：
- `on_transmit` L607 → `[h_tap, ch_label] = p3_channel_tap(sch, app.sys, app.preset_dd.Value);`

---

### 4. `p3_apply_scheme_params.m`

**原位置**：`on_transmit` L533-579，5 个 scheme elseif 块

**依赖的 app 字段**：
- **读**：`app.blk_dd.Value`, `app.iter_edit.Value`, `app.pl_dd.Value`, `app.sys.*`
- **写**（mutate app.sys）：`app.sys.scfde / .ofdm / .sctde / .dsss / .otfs / .frame` 的多字段

**ui_vals 参数设计**：只传当前 scheme 需要的 UI 值（helper 按 scheme 取），避免传 handle：

```matlab
ui_vals = struct( ...
    'blk_fft',    parse_lead_int(app.blk_dd.Value), ... % 数字，非 handle
    'turbo_iter', app.iter_edit.Value, ...
    'payload',    parse_lead_int(app.pl_dd.Value) );
```

**新签名**：

```matlab
function [N_info, sys_out] = p3_apply_scheme_params(sch, sys, ui_vals)
% 输入:
%   sch     体制名
%   sys     输入 sys 参数（将被拷贝修改）
%   ui_vals struct 含 blk_fft, turbo_iter, payload（按 scheme 取用）
% 输出:
%   N_info  信息比特数
%   sys_out 更新后的 sys（caller 写回 app.sys）
```

函数体 = 原 L533-579 的 5 个 elseif 块，`app.sys.X = Y` → `sys.X = Y`，`sys_out = sys`。

**迁移调用点**：

```matlab
% 原 L532-579 整段替换为：
ui_vals = struct( ...
    'blk_fft',    parse_lead_int(app.blk_dd.Value), ...
    'turbo_iter', app.iter_edit.Value, ...
    'payload',    parse_lead_int(app.pl_dd.Value) );
[N_info, app.sys] = p3_apply_scheme_params(sch, app.sys, ui_vals);
```

注意：`parse_lead_int` 是 local helper（L1361），保留在 `p3_demo_ui.m` 内。

---

### 5. `p3_render_tabs.m`

**原位置**：`update_tabs_from_entry` L1095-1354

**依赖的 entry 字段**（已稳定，来自 `try_decode_frame`）：
- `entry.scheme` (char)
- `entry.info` (struct，来自 modem_decode 输出)
- `entry.h_tap` (vector)
- `entry.meta` (struct)
- `entry.tx_body_bb_clean` (vector)
- `entry.pb_seg` (vector)
- `entry.bypass_rf` (logical)
- `entry.ber` (scalar)

**依赖的 app 字段**：
- `app.sys.fs / fc / sym_rate`
- `app.sys.dsss.sps`
- `app.tabs.{compare_tx, compare_rx, spectrum, pre_eq, eq_it1, eq_mid, post_eq, h_td, h_fd}`

**依赖的外部函数**：
- `upconvert`（已在 addpath 中，09_Waveform）
- `p3_downconv_bw`（本次外化）

**axes 参数打包**（spec 已定）：

```matlab
axes_struct = struct( ...
    'compare_tx', app.tabs.compare_tx, ...
    'compare_rx', app.tabs.compare_rx, ...
    'spectrum',   app.tabs.spectrum, ...
    'eq',         {{app.tabs.pre_eq, app.tabs.eq_it1, app.tabs.eq_mid, app.tabs.post_eq}}, ...
    'h_td',       app.tabs.h_td, ...
    'h_fd',       app.tabs.h_fd );
% 注意 cell 要双层 {{...}} 避免 struct 按 cell 列扩成 struct array
```

**新签名**：

```matlab
function p3_render_tabs(sch, entry, axes_struct, sys)
% 输入:
%   sch          体制名
%   entry        历史条目 struct（字段如上）
%   axes_struct  UI axes 句柄打包
%   sys          系统参数（只读）
```

**文件内部结构**（MATLAB local function，不需外置）：

```matlab
function p3_render_tabs(sch, entry, ax, sys)
    render_compare(sch, entry, ax.compare_tx, ax.compare_rx, sys);
    render_spectrum(sch, entry, ax.spectrum, sys);
    render_eq(sch, entry, ax.eq, sys);
    render_channel(sch, entry, ax.h_td, ax.h_fd, sys);
end

function render_compare(...) end                % ~35 行（原 L1103-1138）
function render_spectrum(...) end               % ~20 行（原 L1140-1155）
function render_eq(sch, entry, ax_cells, sys)
    if strcmp(sch, 'FH-MFSK'), render_eq_fhmfsk(entry, ax_cells);
    elseif strcmp(sch, 'DSSS'), render_eq_dsss(entry, ax_cells);
    else, render_eq_turbo(entry, ax_cells); end
end
function render_eq_fhmfsk(...) end              % ~27 行（原 L1164-1190）
function render_eq_dsss(...) end                % ~30 行（原 L1192-1220）
function render_eq_turbo(...) end               % ~50 行（原 L1222-1270）
function render_channel(...) end                % ~85 行（原 L1272-1353）
function style_axes(ax)                         % 辅助
    ax.XColor='k'; ax.YColor='k';
end
```

**迁移调用点**：

```matlab
% try_decode_frame (L850-935) 末尾新增 entry 入栈后，调用：
axes_struct = pack_axes();  % helper 函数（嵌套，见下）
p3_render_tabs(sch, entry, axes_struct, app.sys);

% on_history_select 同上
```

`pack_axes` 作为嵌套函数（保持在主文件）：

```matlab
function ax = pack_axes()
    ax = struct( ...
        'compare_tx', app.tabs.compare_tx, ...
        'compare_rx', app.tabs.compare_rx, ...
        'spectrum',   app.tabs.spectrum, ...
        'eq',         {{app.tabs.pre_eq, app.tabs.eq_it1, app.tabs.eq_mid, app.tabs.post_eq}}, ...
        'h_td',       app.tabs.h_td, ...
        'h_fd',       app.tabs.h_fd );
end
```

---

## 实施步骤

### Step 1 — 纯函数外化（低风险）

**目标**：3 个小 helper 建好，最小替换验证。

1. 新建 `ui/p3_text_capacity.m` （如上签名）
2. 新建 `ui/p3_downconv_bw.m`
3. 新建 `ui/p3_channel_tap.m`
4. 替换调用点（共 4 处）：
   - `on_scheme_changed` L395-403 switch → `p3_text_capacity(sch, app.sys)`
   - `on_transmit` L653（bw 计算） → 保留原 `downconv_bandwidth` 嵌套函数暂时（Step 2 再删）或同时替换
   - `on_transmit` L607 → `p3_channel_tap(sch, app.sys, app.preset_dd.Value)`
   - `update_tabs_from_entry` L1151/L1319 → `p3_downconv_bw(sch, app.sys)`
5. **删除原嵌套函数** `downconv_bandwidth` 和 `build_channel_tap` （L958-1033）
6. **手工验证**：
   - [ ] 启动 UI，切换 5 个 scheme 文本容量提示正确（对比 refactor 前截图）
   - [ ] 发一帧 SC-FDE static SNR=15dB → 解码成功
   - [ ] 信道预设切换 `AWGN / 6径 标准 / 6径 深衰减 / 3径 短时延` 都能 Transmit
7. **commit**：`refactor: 14_Streaming P3 UI 抽出 3 个纯函数 helper`

**文件行数预期**：1378 → ~1290（-88）

---

### Step 2 — 复杂函数外化（中风险）

**目标**：两个最大函数外化。

1. 新建 `ui/p3_apply_scheme_params.m`（签名见字段映射 #4）
2. 新建 `ui/p3_render_tabs.m`（签名 + local functions 见字段映射 #5）
3. 替换调用点：
   - `on_transmit` L532-579 scheme 分支 → `[N_info, app.sys] = p3_apply_scheme_params(...)`
   - `try_decode_frame` 和 `on_history_select` 里调用 `update_tabs_from_entry(entry)` → `p3_render_tabs(sch, entry, pack_axes(), app.sys)`
4. **删除原嵌套函数** `update_tabs_from_entry` （L1095-1354）
5. **冒烟测试脚本** `tests/test_p3_ui_smoke.m`（spec 已规划）：
   ```matlab
   % 调 helper 验证字段齐全 + 单一事实源一致
   sys = sys_params_default();
   for sch = {'SC-FDE','OFDM','SC-TDE','DSSS','FH-MFSK'}
       ui = default_ui_vals(sch{1});
       [Ni, ~] = p3_apply_scheme_params(sch{1}, sys, ui);
       assert(Ni > 0);
       nb_a = floor(Ni / 8);
       nb_b = p3_text_capacity(sch{1}, sys);
       assert(abs(nb_a - nb_b) <= 1, ...
           sprintf('%s: params=%d capacity=%d', sch{1}, nb_a, nb_b));
       bw = p3_downconv_bw(sch{1}, sys); assert(bw > 0);
       [h,~] = p3_channel_tap(sch{1}, sys, 'AWGN (无多径)');
       assert(~isempty(h));
   end
   ```
6. **手工验证**：
   - [ ] 所有 5 scheme Transmit+解码成功（静态 SNR=15）
   - [ ] 均衡 tab 显示正常（Turbo 4 列星座 / FH-MFSK 能量矩阵 / DSSS Rake）
   - [ ] 信道 tab 时域 CIR + 频域响应（`6径 标准` 显示估计 vs 真实）
   - [ ] TX/RX 对比 tab 正常（bypass + 非 bypass 都测）
   - [ ] 解码历史下拉 → 切换历史条目重渲染
7. **commit**：`refactor: 14_Streaming P3 UI 外化 render_tabs 和 scheme_params`

**文件行数预期**：1290 → ~800

---

### Step 3 — 主文件内部重组（低风险，最后做）

**目标**：主文件 setup 段拆嵌套函数，最终 ≤ 800 行。

1. 在主函数体内把 L87-374（287 行）拆为 4 个嵌套函数：
   - `build_topbar(main)` — 原 L98-158
   - `build_middle_panels(main)` — 原 L160-307
   - `build_bottom_tabs(main)` — 原 L309-363
   - `start_timer_and_init()` — 原 L365-374
2. 主函数体变为：
   ```matlab
   function p3_demo_ui()
       %% 状态/路径
       ... L18-85 保持
       %% UI
       app.fig = uifigure(...);  % L87-95
       main = uigridlayout(...);
       build_topbar(main);
       build_middle_panels(main);
       build_bottom_tabs(main);
       start_timer_and_init();
       %% 内部函数
       function build_topbar(main) ... end
       function build_middle_panels(main) ... end
       function build_bottom_tabs(main) ... end
       function start_timer_and_init() ... end
       % 其他回调嵌套...
   end
   ```
3. **验证**：
   - [ ] UI 启动外观完全一致（对比截图）
   - [ ] 所有回调响应正常
4. **commit**：`refactor: 14_Streaming P3 UI 主文件 setup 拆嵌套函数`

**文件行数预期**：800 → 780（少量净降，因减少注释分隔符）

---

## 新文件骨架示例

### `ui/p3_text_capacity.m`

```matlab
function nb = p3_text_capacity(sch, sys)
% 功能：按体制返回最大文本字节数（TX 面板容量提示用）
% 用法：nb = p3_text_capacity(sch, sys)
% 输入：
%   sch  体制名：'SC-FDE'|'OFDM'|'SC-TDE'|'DSSS'|'FH-MFSK'|'OTFS'
%   sys  系统参数（需 sys.codec.constraint_len, sys.ofdm.null_spacing,
%                     sys.frame.body_bits）
% 输出：
%   nb   最大文本字节数（与 on_transmit 算出的 N_info 对齐）

    mem = sys.codec.constraint_len - 1;
    switch sch
        case 'SC-FDE'
            nb = floor((128 * (32-1) - mem) / 8);
        case 'OFDM'
            nulls = floor(256 / sys.ofdm.null_spacing);
            nb = floor(((256 - nulls) * (16-1) - mem) / 8);
        case 'SC-TDE'
            nb = floor((2000 - mem) / 8);
        case 'DSSS'
            nb = floor(1200 / 8);
        case 'FH-MFSK'
            nb = floor(sys.frame.body_bits / 8);
        otherwise
            nb = 200;
    end
end
```

（其他 4 个 helper 骨架在 Step 实施时直接写，不在本计划列出）

---

## 测试 / 验证总览

| 测试 | Step 1 | Step 2 | Step 3 |
|------|--------|--------|--------|
| UI 启动无报错 | ✅ | ✅ | ✅ |
| 5 scheme 切换 | ✅ | ✅ | ✅ |
| 文本容量正确（bug fix） | ✅ | ✅ | ✅ |
| 解码成功（SC-FDE static） | ✅ | ✅ | ✅ |
| 7 tab 渲染 | — | ✅ | ✅ |
| Bypass + 非 Bypass | — | ✅ | ✅ |
| 解码历史切换 | — | ✅ | ✅ |
| 冒烟测试 test_p3_ui_smoke.m | — | ✅ | ✅ |
| 关闭窗口 timer 清理 | — | — | ✅ |

## 风险回看（spec 风险 → 本计划应对）

| spec 风险 | 本计划应对 |
|-----------|-----------|
| 🔴 helper 签名遗漏字段 | Step 0 字段映射章节已完整列出 5 个 helper 的所有输入字段 |
| 🟡 嵌套函数 closure 破坏 | Step 3 明确 "保持嵌套"，只内部分段 |
| 🟡 MATLAB 链式赋值陷阱 | 编码时避免，已在 conclusions.md #22 |
| 🟡 preset_dd 隐式依赖 | Step 1 显式化为 `p3_channel_tap(sch, sys, preset)` 参数 |

## 归档时机

全部 3 step commit 完成 + 冒烟测试通过 + 手工验收通过 → 补 `Result` 章节 → spec 移 `specs/archive/`。

## Log

- 2026-04-17: Plan 创建，完成 5 个 helper 字段映射
