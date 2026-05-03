%% test_p4_alpha_gate.m - P4 shared alpha gate regression
% Acceptance:
%   1. A plausible fixed-Doppler alpha is accepted.
%   2. A Jakes false large alpha is rejected before compensation.
%   3. Low confidence, tiny, and non-finite estimates are rejected safely.

clear functions; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));

streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(fullfile(streaming_root, 'common'));

diary_path = fullfile(this_dir, 'test_p4_alpha_gate_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('========================================\n');
fprintf(' P4 shared alpha gate regression\n');
fprintf('========================================\n\n');

sys = sys_params_default();
opts = struct('alpha_abs_max', 1e-2, 'alpha_abs_min', 1e-6, ...
    'alpha_conf_min', 0.30);

pass_count = 0;
total_checks = 0;

fixed_alpha = 5 / sys.fc;
gate = streaming_alpha_gate(fixed_alpha, 0.80, sys, opts);
total_checks = total_checks + 1;
ok = gate.accepted && abs(gate.alpha - fixed_alpha) < 1e-12 && ...
    strcmp(gate.reason, 'accepted');
pass_count = report_check(ok, 'plausible fixed-Doppler alpha accepted', pass_count);

jakes_false_alpha = 3.667e-2;
gate = streaming_alpha_gate(jakes_false_alpha, 0.50, sys, opts);
total_checks = total_checks + 1;
ok = ~gate.accepted && gate.alpha == 0 && strcmp(gate.reason, 'outside_abs_max');
pass_count = report_check(ok, 'Jakes false large alpha rejected', pass_count);

gate = streaming_alpha_gate(fixed_alpha, 0.10, sys, opts);
total_checks = total_checks + 1;
ok = ~gate.accepted && gate.alpha == 0 && strcmp(gate.reason, 'low_confidence');
pass_count = report_check(ok, 'low-confidence alpha rejected', pass_count);

gate = streaming_alpha_gate(1e-8, 1.00, sys, opts);
total_checks = total_checks + 1;
ok = ~gate.accepted && gate.alpha == 0 && strcmp(gate.reason, 'below_min');
pass_count = report_check(ok, 'tiny alpha treated as no compensation', pass_count);

gate = streaming_alpha_gate(NaN, 1.00, sys, opts);
total_checks = total_checks + 1;
ok = ~gate.accepted && gate.alpha == 0 && strcmp(gate.reason, 'nonfinite');
pass_count = report_check(ok, 'non-finite alpha rejected', pass_count);

fprintf('\nResult: %d/%d checks passed\n', pass_count, total_checks);
if pass_count == total_checks
    fprintf('[PASS] P4 shared alpha gate regression passed\n');
else
    error('test_p4_alpha_gate: %d/%d checks failed', ...
        total_checks - pass_count, total_checks);
end

diary off;
fprintf('Log written: %s\n', diary_path);

function pass_count = report_check(ok, label, pass_count)
if ok
    pass_count = pass_count + 1;
    fprintf('[PASS] %s\n', label);
else
    fprintf('[FAIL] %s\n', label);
end
end
