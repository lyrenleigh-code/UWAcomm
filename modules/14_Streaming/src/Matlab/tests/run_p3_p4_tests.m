function run_p3_p4_tests()
% RUN_P3_P4_TESTS  P3 重构 + P4 真实多普勒 冒烟总入口
%
% 跑两个 smoke：
%   1. test_p3_ui_smoke        — P3 Step 2 helper 单元测试
%   2. test_p4_channel_smoke   — P4 channel_tap + gen_doppler_channel V1.1 相位修复验证
%
% 用法（MATLAB 命令行）：
%   cd('D:\Claude\TechReq\UWAcomm\modules\14_Streaming\src\Matlab\tests');
%   clear functions; clear all;
%   run_p3_p4_tests
%
% 输出：
%   diary  → run_p3_p4_tests_results.txt（完整日志）
%   控制台 → P3/P4 分栏总结 + UI 手工回归 checklist

clc;
this_dir       = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
modules_root   = fileparts(fileparts(streaming_root));

% 路径注册（UI helpers / common / 10_DopplerProc）
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(modules_root, '10_DopplerProc', 'src', 'Matlab'));

diary_file = fullfile(this_dir, 'run_p3_p4_tests_results.txt');
if exist(diary_file, 'file'), delete(diary_file); end
diary(diary_file);
diary on;
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('========================================\n');
fprintf('  P3 重构 + P4 真实多普勒 — 冒烟总入口\n');
fprintf('  %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('========================================\n\n');

err_p3 = 0; err_p4 = 0;

%% 1. P3 UI smoke
fprintf('\n>>>>>>>>>> 1. P3 UI Step 2 冒烟 <<<<<<<<<<\n\n');
try
    test_p3_ui_smoke();
catch ME
    fprintf(2, '[P3-ERR] %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf(2, '  @ %s:%d\n', ME.stack(1).name, ME.stack(1).line);
    end
    err_p3 = 1;
end

%% 2. P4 信道 smoke
fprintf('\n\n>>>>>>>>>> 2. P4 Channel + Doppler V1.1 冒烟 <<<<<<<<<<\n\n');
try
    test_p4_channel_smoke();
catch ME
    fprintf(2, '[P4-ERR] %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf(2, '  @ %s:%d\n', ME.stack(1).name, ME.stack(1).line);
    end
    err_p4 = 1;
end

%% 3. UI 手工回归 checklist
fprintf('\n\n>>>>>>>>>> 3. UI 手工回归（MATLAB 命令行）<<<<<<<<<<\n\n');
fprintf('P3 参考 demo（稳定版，不动）:\n');
fprintf('  >> p3_demo_ui\n\n');
fprintf('P4 真实多普勒 demo（本次修复后）:\n');
fprintf('  >> p4_demo_ui\n\n');
fprintf('关键回归点 (SC-FDE + 6径标准 + SNR=15 + tv_enable=false):\n');
fprintf('  [ ] dop=0   → P3/P4 均 BER ≈ 0%%\n');
fprintf('  [ ] dop=6   → P3/P4 均 BER ≈ 0%%\n');
fprintf('  [ ] dop=12  → P3/P4 均 BER ≈ 0.1%%  （本次修复验证点）\n');
fprintf('  [ ] dop=24  → P3/P4 均 BER ≈ 47%%   （已知物理断崖，与 gen_doppler 无关）\n');
fprintf('时变演示 (勾选 "启用时变"):\n');
fprintf('  [ ] dop=12 + random_walk + jitter=0.02µ → 信道 tab 标题显示 α(t) std>0\n');
fprintf('  [ ] dop=12 + linear_drift + drift=0.5µ/s → α(t) 单调线性上升\n\n');
fprintf('背景参考:\n');
fprintf('  - 4-20 诊断基线表：specs/active/2026-04-20-alpha-compensation-pipeline-debug.md L19-24\n');
fprintf('  - E2E 时变基线：    wiki/comparisons/e2e-timevarying-baseline.md §3.2\n');
fprintf('  - V1.0 bug：fs/fc=4 倍相位过快（dop=12 实际为 48 Hz），V1.1 修复\n');

%% 总结
fprintf('\n\n========================================\n');
fprintf('  总结\n');
fprintf('========================================\n');
fprintf('P3 smoke : %s\n', tern(err_p3 == 0));
fprintf('P4 smoke : %s\n', tern(err_p4 == 0));
fprintf('\n日志: %s\n', diary_file);

if err_p3 + err_p4 > 0
    fprintf(2, '\n[!!] 有脚本级抛错，详见 diary\n');
else
    fprintf('\n[OK] 脚本级无抛错（单项 PASS/FAIL 计数见各测试打印）\n');
end

end

% ---------- 局部 ----------
function s = tern(ok)
    if ok, s = 'PASS'; else, s = 'FAIL'; end
end
