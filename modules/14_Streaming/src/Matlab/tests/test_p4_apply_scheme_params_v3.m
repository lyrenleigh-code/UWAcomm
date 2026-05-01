function test_p4_apply_scheme_params_v3()
% TEST_P4_APPLY_SCHEME_PARAMS_V3  P4 UI 解耦 blk_cp/blk_fft + pilot 控件 V3.0 冒烟
%
% 验证 p4_apply_scheme_params V3.0：
%   C1 SC-FDE 默认（V2.0 兼容）→ blk_cp=blk_fft, pilot=0, K=31, N_info V2.0 等价
%   C2 SC-FDE V4.0 推荐预设（256/128/128/8）→ 字段透传 + N_info=128*28-mem
%   C3 SC-FDE 自定义（256/64/64/4）→ N_train_blocks 推导正确
%   C4 OFDM 不受影响（blk_cp = round(blk_fft/2)）
%   C5 SC-TDE/DSSS/OTFS 不读 SC-FDE 字段（不污染）
%   C6 fading 透传（fast Jakes fd=5Hz）
%
% 测试范围：仅 sys 字段透传 + N_info 推导，不跑 modem encode/decode
%
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm-claude\modules\14_Streaming\src\Matlab\tests');
%   clear functions; clear all;
%   diary('test_p4_apply_scheme_params_v3_results.txt');
%   run('test_p4_apply_scheme_params_v3.m');
%   diary off;
%
% 参考：specs/active/2026-05-01-p4-ui-decouple-blk-cp-and-pilot-controls.md

%% 0. 路径注册
this_dir       = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
mod14_root     = fileparts(fileparts(streaming_root));
modules_root   = fileparts(mod14_root);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(modules_root, '13_SourceCode', 'src', 'Matlab', 'common'));

pass = 0; fail = 0;
fprintf('========== p4_apply_scheme_params V3.0 冒烟 ==========\n');

%% 加载默认 sys
sys = sys_params_default();
mem = sys.codec.constraint_len - 1;

%% C1 — SC-FDE 默认（V2.0 兼容回归）
try
    ui_vals = struct( ...
        'blk_fft',        128, ...
        'turbo_iter',     6, ...
        'payload',        2048, ...
        'fading_type',    'static (恒定)', ...
        'fd_hz',          0 );
    [N_info, sys_out] = p4_apply_scheme_params('SC-FDE', sys, ui_vals);

    assert(sys_out.scfde.blk_fft == 128, 'C1: blk_fft');
    assert(sys_out.scfde.blk_cp == 128, ...
        'C1: blk_cp 缺省 fallback 应 = blk_fft (128), got %d', sys_out.scfde.blk_cp);
    assert(sys_out.scfde.pilot_per_blk == 0, ...
        'C1: pilot_per_blk 默认 0, got %d', sys_out.scfde.pilot_per_blk);
    assert(sys_out.scfde.train_period_K == 31, ...
        'C1: train_period_K 默认 N_blocks-1=31, got %d', sys_out.scfde.train_period_K);
    expected_N = 128 * 31 - mem;
    assert(N_info == expected_N, 'C1: N_info expected %d, got %d', expected_N, N_info);

    fprintf('[PASS] C1 SC-FDE 默认 V2.0 兼容（blk_cp=blk_fft=%d, pilot=0, K=31, N_info=%d）\n', ...
        sys_out.scfde.blk_cp, N_info);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C1 SC-FDE 默认: %s\n', ME.message);
    fail = fail + 1;
end

%% C2 — SC-FDE V4.0 推荐预设
try
    ui_vals = struct( ...
        'blk_fft',        256, ...
        'blk_cp',         128, ...
        'pilot_per_blk',  128, ...
        'train_period_K', 8, ...
        'turbo_iter',     6, ...
        'payload',        2048, ...
        'fading_type',    'slow (Jakes 慢衰落)', ...
        'fd_hz',          1 );
    [N_info, sys_out] = p4_apply_scheme_params('SC-FDE', sys, ui_vals);

    assert(sys_out.scfde.blk_fft == 256, 'C2: blk_fft');
    assert(sys_out.scfde.blk_cp == 128, ...
        'C2: blk_cp 应解耦 = 128, got %d', sys_out.scfde.blk_cp);
    assert(sys_out.scfde.pilot_per_blk == 128, ...
        'C2: pilot_per_blk 应透传 = 128, got %d', sys_out.scfde.pilot_per_blk);
    assert(sys_out.scfde.train_period_K == 8, ...
        'C2: train_period_K 应透传 = 8, got %d', sys_out.scfde.train_period_K);
    assert(strcmp(sys_out.scfde.fading_type, 'jakes'), ...
        'C2: fading_type 应 = jakes');
    % V4.0 推荐：N_train_blocks = floor(32/9)+1 = 4, N_data_blocks = 28
    %   N_info = (256-128) * 28 - mem = 3584 - mem
    expected_N = 128 * 28 - mem;
    assert(N_info == expected_N, ...
        'C2: V4.0 N_info expected %d, got %d', expected_N, N_info);

    fprintf('[PASS] C2 V4.0 推荐预设（blk_fft=256, blk_cp=128, pilot=128, K=8, N_info=%d）\n', N_info);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C2 V4.0 推荐: %s\n', ME.message);
    fail = fail + 1;
end

%% C3 — SC-FDE 自定义（256/64/64/4）
try
    ui_vals = struct( ...
        'blk_fft',        256, ...
        'blk_cp',         64, ...
        'pilot_per_blk',  64, ...
        'train_period_K', 4, ...
        'turbo_iter',     6, ...
        'payload',        2048, ...
        'fading_type',    'static (恒定)', ...
        'fd_hz',          0 );
    [N_info, sys_out] = p4_apply_scheme_params('SC-FDE', sys, ui_vals);

    assert(sys_out.scfde.blk_cp == 64, 'C3: blk_cp 应 = 64');
    assert(sys_out.scfde.pilot_per_blk == 64, 'C3: pilot_per_blk 应 = 64');
    % K=4, N=32: N_train_blocks = floor(32/5)+1 = 7
    %   N_data_blocks = 25
    %   N_info = (256-64)*25 - mem = 4800 - mem
    expected_N = 192 * 25 - mem;
    assert(N_info == expected_N, ...
        'C3: 自定义 N_info expected %d, got %d', expected_N, N_info);

    fprintf('[PASS] C3 自定义 (256/64/64/4) → N_data_blocks=25, N_info=%d\n', N_info);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C3 自定义: %s\n', ME.message);
    fail = fail + 1;
end

%% C4 — OFDM 不受 SC-FDE 字段影响
try
    ui_vals = struct( ...
        'blk_fft',        128, ...
        'blk_cp',         64, ...
        'pilot_per_blk',  32, ...
        'train_period_K', 4, ...
        'turbo_iter',     6, ...
        'payload',        2048, ...
        'fading_type',    'static (恒定)', ...
        'fd_hz',          0 );
    [~, sys_out] = p4_apply_scheme_params('OFDM', sys, ui_vals);

    % OFDM 自己算 blk_cp = round(blk_fft/2)，不读 ui_vals.blk_cp
    assert(sys_out.ofdm.blk_cp == 64, ...
        'C4: OFDM blk_cp 应 = round(128/2)=64, got %d', sys_out.ofdm.blk_cp);

    fprintf('[PASS] C4 OFDM 不受 SC-FDE 字段污染（blk_cp=64 来自 round(blk_fft/2)）\n');
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C4 OFDM: %s\n', ME.message);
    fail = fail + 1;
end

%% C5 — SC-TDE 不污染（仅自己 schema 字段被改）
try
    ui_vals = struct( ...
        'blk_fft',        128, ...
        'blk_cp',         64, ...
        'pilot_per_blk',  32, ...
        'train_period_K', 4, ...
        'turbo_iter',     6, ...
        'payload',        2048, ...
        'fading_type',    'static (恒定)', ...
        'fd_hz',          0 );
    [~, sys_out_sctde] = p4_apply_scheme_params('SC-TDE', sys, ui_vals);

    % SC-TDE 走自己分支：不读 blk_cp/pilot_per_blk/train_period_K
    % sys.scfde 由 sys_params_default 给的 baseline 应保持不变
    assert(sys_out_sctde.scfde.blk_fft == sys.scfde.blk_fft, ...
        'C5: SC-TDE 调用不应修改 sys.scfde.blk_fft');
    assert(sys_out_sctde.scfde.blk_cp == sys.scfde.blk_cp, ...
        'C5: SC-TDE 调用不应修改 sys.scfde.blk_cp');

    fprintf('[PASS] C5 SC-TDE 调用不污染 sys.scfde\n');
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C5 SC-TDE: %s\n', ME.message);
    fail = fail + 1;
end

%% C6 — fading 透传（fast Jakes fd=5Hz）
try
    ui_vals = struct( ...
        'blk_fft',        128, ...
        'blk_cp',         128, ...
        'pilot_per_blk',  0, ...
        'train_period_K', 31, ...
        'turbo_iter',     6, ...
        'payload',        2048, ...
        'fading_type',    'fast (Jakes 快衰落)', ...
        'fd_hz',          5 );
    [~, sys_out] = p4_apply_scheme_params('SC-FDE', sys, ui_vals);

    assert(strcmp(sys_out.scfde.fading_type, 'jakes'), ...
        'C6: fast Jakes fading_type 应 = jakes');
    assert(sys_out.scfde.fd_hz == 5, 'C6: fd_hz 应 = 5');

    fprintf('[PASS] C6 fading 透传（fast Jakes fd_hz=5）\n');
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C6 fading: %s\n', ME.message);
    fail = fail + 1;
end

%% 汇总
fprintf('\n========== 总结 ==========\n');
fprintf('PASS: %d / %d\n', pass, pass + fail);
fprintf('FAIL: %d\n', fail);
if fail == 0
    fprintf('[ALL PASS] V3.0 解耦 + N_info 推导冒烟通过\n');
else
    fprintf('[HAS FAIL] %d 个 case 失败，需排查\n', fail);
end
end
