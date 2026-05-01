# Plan: P4 UI 解耦 SC-FDE blk_cp/blk_fft + 加 pilot 控件

> Spec: `specs/active/2026-05-01-p4-ui-decouple-blk-cp-and-pilot-controls.md`
> 分支: `claude-uwacomm-work-20260425`
> Base HEAD: `ced0d9a`
> 影响范围：14_Streaming UI 层 only（不动 modem_encode/decode_scfde）

## 文件清单

### 修改
1. `modules/14_Streaming/src/Matlab/ui/p4_apply_scheme_params.m` (V2.0 → V3.0)
2. `modules/14_Streaming/src/Matlab/ui/p4_demo_ui.m` (UI layout + ui_vals + on_scheme_changed + 校验 + V4.0 预设按钮)

### 新增
3. `modules/14_Streaming/src/Matlab/tests/test_p4_apply_scheme_params_v3.m` (6 case smoke)

## 实施顺序

### Step 1 — `p4_apply_scheme_params V3.0`（最小代码改动，先动算法侧）

**文件**：`p4_apply_scheme_params.m` L44-55

**改动 diff**：
```matlab
    if strcmp(sch, 'SC-FDE')
        sys_out.scfde.blk_fft     = ui_vals.blk_fft;
-        sys_out.scfde.blk_cp      = sys_out.scfde.blk_fft;     % V2.0 强制锁死
+        sys_out.scfde.blk_cp      = local_get_or_default(ui_vals, 'blk_cp', sys_out.scfde.blk_fft);
        sys_out.scfde.N_blocks    = 32;
        sys_out.scfde.turbo_iter  = ui_vals.turbo_iter;
        sys_out.scfde.fading_type = fading_type_val;
        sys_out.scfde.fd_hz       = fd_hz_ui;
        sys_out.scfde.pilot_per_blk  = local_get_or_default(ui_vals, 'pilot_per_blk',  0);
        sys_out.scfde.train_period_K = local_get_or_default(ui_vals, 'train_period_K', sys_out.scfde.N_blocks - 1);
-        % N_info 推导：与 V1.0 保持一致（pilot_per_blk=0 默认 → N_data_per_blk=blk_fft → 等价）
-        N_info = sys_out.scfde.blk_fft * (sys_out.scfde.N_blocks - 1) - mem;
+        % V3.0 N_info 推导（参 modem_encode_scfde V4.0:35,49-60,81）
+        K = sys_out.scfde.train_period_K;
+        N = sys_out.scfde.N_blocks;
+        if K >= N - 1
+            N_train_blocks = 1;
+        else
+            N_train_blocks = floor(N / (K + 1)) + 1;
+            train_idx = round(linspace(1, N, N_train_blocks));
+            N_train_blocks = length(unique(train_idx));
+        end
+        N_data_blocks = N - N_train_blocks;
+        N_data_per_blk = sys_out.scfde.blk_fft - sys_out.scfde.pilot_per_blk;
+        N_info = N_data_per_blk * N_data_blocks - mem;
```

**头注更新**：版本 V2.0 → V3.0，加 V3.0 历史条目

### Step 2 — `p4_demo_ui.m` Layout 扩展（4 新行）

**文件**：`p4_demo_ui.m`

**Layout 改动**（L258-259）：
```matlab
-    tx_grid = uigridlayout(tx_panel, [18 2]);
-    tx_grid.RowHeight = {25, 55, 25, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 25, '1x'};
+    tx_grid = uigridlayout(tx_panel, [22 2]);
+    tx_grid.RowHeight = {25, 55, 25, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 32, 28, 25, '1x'};
```

**新增控件**（在 L312 之后插入 4 块）：
```matlab
    % SC-FDE V3.0 新增（行 15/16/17/18）
    app.lbl_blk_cp = uilabel(tx_grid, 'Text', 'blk_cp:');
    app.lbl_blk_cp.Layout.Row = 15; app.lbl_blk_cp.Layout.Column = 1;
    app.blk_cp_dd = uidropdown(tx_grid, ...
        'Items', {'64', '128 (V4.0 推荐)', '256'}, 'Value', '128 (V4.0 推荐)');
    app.blk_cp_dd.Layout.Row = 15; app.blk_cp_dd.Layout.Column = 2;

    app.lbl_pilot_pb = uilabel(tx_grid, 'Text', 'pilot_per_blk:');
    app.lbl_pilot_pb.Layout.Row = 16; app.lbl_pilot_pb.Layout.Column = 1;
    app.pilot_pb_edit = uieditfield(tx_grid, 'numeric', 'Value', 0, ...
        'Limits', [0 256], 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d');
    app.pilot_pb_edit.Layout.Row = 16; app.pilot_pb_edit.Layout.Column = 2;

    app.lbl_train_K = uilabel(tx_grid, 'Text', 'train_period_K:');
    app.lbl_train_K.Layout.Row = 17; app.lbl_train_K.Layout.Column = 1;
    app.train_K_edit = uieditfield(tx_grid, 'numeric', 'Value', 31, ...
        'Limits', [1 31], 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d');
    app.train_K_edit.Layout.Row = 17; app.train_K_edit.Layout.Column = 2;

    app.preset_v40_btn = uibutton(tx_grid, 'push', 'Text', 'V4.0 Jakes 推荐', ...
        'BackgroundColor', PALETTE.accent, 'FontColor', 'white', ...
        'ButtonPushedFcn', @(~,~) on_apply_v40_preset());
    app.preset_v40_btn.Layout.Row = 18; app.preset_v40_btn.Layout.Column = [1 2];
```

**顺移**（L314-336 全段 +4 行）：
- `lbl_iter`/`iter_edit`: Row 15 → Row 19
- `lbl_pl`/`pl_dd`: Row 14 → Row 14（不动，FH-MFSK 与 SC-FDE blk_fft 共享 Row 14）
- `lbl_pilot`/`pilot_dd` (OTFS): Row 16 → Row 20
- txinfo_panel: Row [17 18] → Row [21 22]

**on_scheme_changed**（L702-707）加 4 控件可见性：
```matlab
    is_scfde = strcmp(sch, 'SC-FDE');
    show(app.lbl_blk_cp,    is_scfde); show(app.blk_cp_dd,    is_scfde);
    show(app.lbl_pilot_pb,  is_scfde); show(app.pilot_pb_edit, is_scfde);
    show(app.lbl_train_K,   is_scfde); show(app.train_K_edit,  is_scfde);
    show(app.preset_v40_btn, is_scfde);
```

**ui_vals 构造**（L868-873）加 3 字段：
```matlab
        ui_vals = struct( ...
            'blk_fft',        parse_lead_int(app.blk_dd.Value), ...
            'blk_cp',         parse_lead_int(app.blk_cp_dd.Value), ...
            'pilot_per_blk',  app.pilot_pb_edit.Value, ...
            'train_period_K', app.train_K_edit.Value, ...
            'turbo_iter',     app.iter_edit.Value, ...
            'payload',        parse_lead_int(app.pl_dd.Value), ...
            'fading_type',    app.fading_dd.Value, ...
            'fd_hz',          app.jakes_fd_edit.Value );
```

**校验逻辑**（在 ui_vals 构造之前）：
```matlab
        if strcmp(sch, 'SC-FDE')
            blk_fft_v = parse_lead_int(app.blk_dd.Value);
            blk_cp_v  = parse_lead_int(app.blk_cp_dd.Value);
            pilot_v   = app.pilot_pb_edit.Value;
            if blk_cp_v > blk_fft_v
                set_status(sprintf('blk_cp (%d) > blk_fft (%d)', blk_cp_v, blk_fft_v), 'error');
                return;
            end
            if pilot_v >= blk_fft_v
                set_status(sprintf('pilot_per_blk (%d) >= blk_fft (%d)', pilot_v, blk_fft_v), 'error');
                return;
            end
            if pilot_v > 0 && pilot_v ~= blk_cp_v
                append_log(sprintf('[!] V4.0 干净 BEM 物理条件偏离：pilot_per_blk=%d != blk_cp=%d，BER 可能差', pilot_v, blk_cp_v));
            end
        end
```

**新回调函数**（在 on_pilot_mode_changed 后）：
```matlab
function on_apply_v40_preset()
    app.blk_dd.Value = '256';
    app.blk_cp_dd.Value = '128 (V4.0 推荐)';
    app.pilot_pb_edit.Value = 128;
    app.train_K_edit.Value = 8;
    append_log('[预设] V4.0 Jakes：blk_fft=256, blk_cp=128, pilot=128, K=8');
    append_log('       jakes fd=1Hz runner BER 3.37%（吞吐损失 ~50%）');
end
```

### Step 3 — Smoke 测试 `test_p4_apply_scheme_params_v3.m`

参考 `tests/test_p4_ui_alignment_smoke.m` 风格（如果存在）：

```matlab
function test_p4_apply_scheme_params_v3()
    % 6 case：V3.0 字段透传 + N_info 推导
    addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'ui'));
    addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

    sys = local_default_sys();
    pass = 0; fail = 0;

    % C1: SC-FDE 默认（V1.0 兼容）
    ui = struct('blk_fft', 128, 'turbo_iter', 6, 'payload', 2048, ...
        'fading_type', 'static (恒定)', 'fd_hz', 0);
    [N, sysO] = p4_apply_scheme_params('SC-FDE', sys, ui);
    expected_N = 128 * 31 - (sys.codec.constraint_len - 1);
    [pass, fail] = local_assert(N == expected_N && sysO.scfde.blk_cp == 128 && ...
        sysO.scfde.pilot_per_blk == 0 && sysO.scfde.train_period_K == 31, 'C1 默认', pass, fail);

    % C2: V4.0 推荐
    ui = struct('blk_fft', 256, 'blk_cp', 128, 'pilot_per_blk', 128, 'train_period_K', 8, ...
        'turbo_iter', 6, 'payload', 2048, 'fading_type', 'slow (Jakes 慢衰落)', 'fd_hz', 1);
    [N, sysO] = p4_apply_scheme_params('SC-FDE', sys, ui);
    expected_N = 128 * 28 - (sys.codec.constraint_len - 1);
    [pass, fail] = local_assert(N == expected_N && sysO.scfde.blk_cp == 128 && ...
        sysO.scfde.pilot_per_blk == 128 && strcmp(sysO.scfde.fading_type, 'jakes'), 'C2 V4.0 推荐', pass, fail);

    % C3: 自定义 (blk_fft=256, blk_cp=64, pilot_per_blk=64, train_period_K=4)
    ui = struct('blk_fft', 256, 'blk_cp', 64, 'pilot_per_blk', 64, 'train_period_K', 4, ...
        'turbo_iter', 6, 'payload', 2048, 'fading_type', 'static (恒定)', 'fd_hz', 0);
    [N, sysO] = p4_apply_scheme_params('SC-FDE', sys, ui);
    expected_N = (256 - 64) * 25 - (sys.codec.constraint_len - 1);  % 25 = 32 - 7 train blocks
    [pass, fail] = local_assert(N == expected_N, sprintf('C3 自定义 (N=%d expected=%d)', N, expected_N), pass, fail);

    % C4: OFDM 不受影响
    ui = struct('blk_fft', 128, 'turbo_iter', 6, 'payload', 2048, ...
        'fading_type', 'static (恒定)', 'fd_hz', 0);
    [N, sysO] = p4_apply_scheme_params('OFDM', sys, ui);
    [pass, fail] = local_assert(sysO.ofdm.blk_cp == 64, 'C4 OFDM 不受影响', pass, fail);

    % C5: SC-TDE 不读 blk_cp
    [N, sysO] = p4_apply_scheme_params('SC-TDE', sys, ui);
    [pass, fail] = local_assert(~isfield(sysO, 'scfde') || ...
        ~isfield(sysO.scfde, 'pilot_per_blk') || sysO.scfde.pilot_per_blk == 0, ...
        'C5 SC-TDE 不污染 scfde', pass, fail);

    % C6: 字段透传 fading
    ui = struct('blk_fft', 128, 'blk_cp', 128, 'pilot_per_blk', 0, 'train_period_K', 31, ...
        'turbo_iter', 6, 'payload', 2048, ...
        'fading_type', 'fast (Jakes 快衰落)', 'fd_hz', 5);
    [N, sysO] = p4_apply_scheme_params('SC-FDE', sys, ui);
    [pass, fail] = local_assert(strcmp(sysO.scfde.fading_type, 'jakes') && ...
        sysO.scfde.fd_hz == 5, 'C6 fading 透传', pass, fail);

    fprintf('\n[smoke] %d PASS / %d FAIL\n', pass, fail);
    if fail > 0, error('test_p4_apply_scheme_params_v3 FAILED'); end
end
```

需要 helper：
- `local_default_sys()` — minimal sys struct（codec, scfde, ofdm, sctde, dsss, otfs, frame）
- `local_assert(cond, name, p, f)` — count + print

### Step 4 — 用户验收

1. 启动 P4 UI：`run modules/14_Streaming/src/Matlab/ui/p4_demo_ui.m`
2. 选 SC-FDE
3. 验回归：默认 + static AWGN → BER 0%（与 ced0d9a 等价）
4. 验默认 + slow Jakes fd=1Hz → 重现 ~50% 灾难（V1.0 兼容路径）
5. 点 "V4.0 Jakes 推荐" 按钮 → 检查 4 控件值正确联动
6. 跑 V4.0 推荐 + slow Jakes fd=1Hz → 期望 BER 3-10%
7. 边界：blk_cp > blk_fft → status 报错且 return

### Step 5 — wiki 更新 + commit

- `wiki/debug-logs/14_Streaming/流式调试日志.md` 加 2026-05-01 章节
- `todo.md` 把 "P4 UI follow-up：解耦 SC-FDE blk_cp/blk_fft + 加 pilot 控件" 移到里程碑
- `wiki/log.md` + `wiki/index.md` 同步（hooks 强制）
- `git commit -m "feat(p4-ui): 解耦 SC-FDE blk_cp/blk_fft + pilot 控件 + V4.0 预设"`

## 风险与回滚

| 风险 | 缓解 |
|---|---|
| Layout 行号顺移漏改 | grep `Layout.Row = 1[5-8]` 全 hit 列表后逐一改 |
| N_info 推导 off-by-one | C2/C3 单测精确数值断言；如失败查 modem_encode L49-60 |
| FH-MFSK pl_dd 共用 Row 14 | 不动 Row 14，新增控件起 Row 15 |
| ValueChangedFcn 事件循环 | 预设按钮直接赋值 .Value 不绑定 ValueChangedFcn |

回滚：`git revert <commit-hash>` — 改动隔离在 P4 UI，无算法层副作用

## 验收清单（checkpoint）

- [ ] Step 1 完成 — 函数级编辑 + 头注 V3.0
- [ ] Step 2 完成 — UI layout + 控件 + 校验 + ui_vals
- [ ] Step 3 完成 — 单测脚本写好
- [ ] Step 4 用户验 — 等用户确认 4 BER 行为符合预期
- [ ] Step 5 commit + wiki
