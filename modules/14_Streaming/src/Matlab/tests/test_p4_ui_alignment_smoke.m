function test_p4_ui_alignment_smoke()
% TEST_P4_UI_ALIGNMENT_SMOKE  P4 UI ↔ 算法对齐冒烟测试
%
% 验证 p4_apply_scheme_params V2.0：
%   C1 SC-FDE static 默认控件 → V1.0 兼容性（fading_type='static', fd_hz=0,
%      pilot_per_blk=0, train_period_K=N_blocks-1）
%   C2 SC-FDE slow Jakes (fd=1Hz) → fading_type='jakes', fd_hz=1
%   C3 SC-TDE fast Jakes (fd=5Hz) → sys.sctde.fading_type='jakes', fd_hz=5
%   C4 OTFS slow Jakes (fd=2Hz) → sys.otfs.fading_type='jakes', fd_hz=2
%
% 测试范围：仅 sys 字段透传（结构变更测试），不跑 modem encode/decode
%
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm-claude\modules\14_Streaming\src\Matlab\tests');
%   clear functions; clear all;
%   diary('test_p4_ui_alignment_smoke_results.txt');
%   run('test_p4_ui_alignment_smoke.m');
%   diary off;
%
% 参考：specs/active/2026-04-28-p4-ui-algo-alignment.md

%% 0. 路径注册
this_dir       = fileparts(mfilename('fullpath'));      % .../14_Streaming/src/Matlab/tests
streaming_root = fileparts(this_dir);                    % .../14_Streaming/src/Matlab
mod14_root     = fileparts(fileparts(streaming_root));   % .../modules/14_Streaming
modules_root   = fileparts(mod14_root);                  % .../modules
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(modules_root, '13_SourceCode', 'src', 'Matlab', 'common'));

pass = 0; fail = 0;
fprintf('========== P4 UI ↔ 算法对齐冒烟测试 ==========\n');

%% 加载默认 sys
sys = sys_params_default();

%% C1 — SC-FDE static + 默认控件（V1.0 兼容回归）
try
    ui_vals = struct( ...
        'blk_fft',     128, ...
        'turbo_iter',  6, ...
        'payload',     2048, ...
        'fading_type', 'static (恒定)', ...
        'fd_hz',       0 );
    [N_info, sys_out] = p4_apply_scheme_params('SC-FDE', sys, ui_vals);

    assert(strcmp(sys_out.scfde.fading_type, 'static'), ...
        'C1: fading_type expected ''static'', got ''%s''', sys_out.scfde.fading_type);
    assert(sys_out.scfde.fd_hz == 0, ...
        'C1: fd_hz expected 0, got %g', sys_out.scfde.fd_hz);
    assert(sys_out.scfde.pilot_per_blk == 0, ...
        'C1: pilot_per_blk expected 0 (V1.0 default), got %d', sys_out.scfde.pilot_per_blk);
    assert(sys_out.scfde.train_period_K == sys_out.scfde.N_blocks - 1, ...
        'C1: train_period_K expected %d, got %d', ...
        sys_out.scfde.N_blocks - 1, sys_out.scfde.train_period_K);
    % N_info V1.0 兼容
    expected_N_info = 128 * (32 - 1) - (sys.codec.constraint_len - 1);
    assert(N_info == expected_N_info, ...
        'C1: N_info expected %d, got %d', expected_N_info, N_info);

    fprintf('[PASS] C1 SC-FDE static V1.0 兼容（fading=static, fd_hz=0, pilot_per_blk=0, train_K=%d, N_info=%d）\n', ...
        sys_out.scfde.train_period_K, N_info);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C1 SC-FDE static: %s\n', ME.message);
    fail = fail + 1;
end

%% C2 — SC-FDE slow Jakes (fd=1Hz)
try
    ui_vals = struct( ...
        'blk_fft',     128, ...
        'turbo_iter',  6, ...
        'payload',     2048, ...
        'fading_type', 'slow (Jakes 慢衰落)', ...
        'fd_hz',       1 );
    [~, sys_out] = p4_apply_scheme_params('SC-FDE', sys, ui_vals);

    assert(strcmp(sys_out.scfde.fading_type, 'jakes'), ...
        'C2: fading_type expected ''jakes'', got ''%s''', sys_out.scfde.fading_type);
    assert(sys_out.scfde.fd_hz == 1, ...
        'C2: fd_hz expected 1, got %g', sys_out.scfde.fd_hz);

    fprintf('[PASS] C2 SC-FDE slow Jakes 透传（fading=%s, fd_hz=%g）\n', ...
        sys_out.scfde.fading_type, sys_out.scfde.fd_hz);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C2 SC-FDE slow Jakes: %s\n', ME.message);
    fail = fail + 1;
end

%% C3 — SC-TDE fast Jakes (fd=5Hz)
try
    ui_vals = struct( ...
        'blk_fft',     128, ...
        'turbo_iter',  6, ...
        'payload',     2048, ...
        'fading_type', 'fast (Jakes 快衰落)', ...
        'fd_hz',       5 );
    [~, sys_out] = p4_apply_scheme_params('SC-TDE', sys, ui_vals);

    assert(strcmp(sys_out.sctde.fading_type, 'jakes'), ...
        'C3: sctde.fading_type expected ''jakes'', got ''%s''', sys_out.sctde.fading_type);
    assert(sys_out.sctde.fd_hz == 5, ...
        'C3: sctde.fd_hz expected 5, got %g', sys_out.sctde.fd_hz);

    fprintf('[PASS] C3 SC-TDE fast Jakes 透传（fading=%s, fd_hz=%g）\n', ...
        sys_out.sctde.fading_type, sys_out.sctde.fd_hz);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C3 SC-TDE fast Jakes: %s\n', ME.message);
    fail = fail + 1;
end

%% C4 — OTFS slow Jakes (fd=2Hz)
try
    ui_vals = struct( ...
        'blk_fft',     128, ...
        'turbo_iter',  6, ...
        'payload',     2048, ...
        'fading_type', 'slow (Jakes 慢衰落)', ...
        'fd_hz',       2 );
    [~, sys_out] = p4_apply_scheme_params('OTFS', sys, ui_vals);

    assert(strcmp(sys_out.otfs.fading_type, 'jakes'), ...
        'C4: otfs.fading_type expected ''jakes'', got ''%s''', sys_out.otfs.fading_type);
    assert(sys_out.otfs.fd_hz == 2, ...
        'C4: otfs.fd_hz expected 2, got %g', sys_out.otfs.fd_hz);

    fprintf('[PASS] C4 OTFS slow Jakes 透传（fading=%s, fd_hz=%g）\n', ...
        sys_out.otfs.fading_type, sys_out.otfs.fd_hz);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C4 OTFS slow Jakes: %s\n', ME.message);
    fail = fail + 1;
end

%% 汇总
fprintf('\n========== 总结 ==========\n');
fprintf('PASS: %d / %d\n', pass, pass + fail);
fprintf('FAIL: %d\n', fail);
if fail == 0
    fprintf('[ALL PASS] V2.0 字段透传冒烟测试通过\n');
else
    fprintf('[HAS FAIL] %d 个 case 失败，需排查\n', fail);
end
end
