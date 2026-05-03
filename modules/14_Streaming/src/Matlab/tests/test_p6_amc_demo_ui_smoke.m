%% test_p6_amc_demo_ui_smoke.m - Streaming P6 AMC dashboard smoke test
% Acceptance:
%   1. Headless model path produces frame decisions and artifact rows.
%   2. Hidden uifigure path initializes without callback/runtime errors.

clear functions; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));

streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(streaming_root);
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'ui'));
streaming_addpaths();

diary_path = fullfile(this_dir, 'test_p6_amc_demo_ui_smoke_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('======================================\n');
fprintf(' Streaming P6 - AMC dashboard smoke\n');
fprintf('======================================\n\n');

pass_count = 0;
total_checks = 0;

app_model = p6_amc_demo_ui(struct('headless', true));
[pass_count, total_checks] = record_check(pass_count, total_checks, ...
    isfield(app_model, 'detail') && height(app_model.detail) > 0 && ...
    isfield(app_model, 'summary') && app_model.summary.mean_utility >= 0, ...
    'headless dashboard model produced decision rows', ...
    'headless dashboard model missing decision rows');

[pass_count, total_checks] = record_check(pass_count, total_checks, ...
    isfield(app_model, 'artifact_table') && height(app_model.artifact_table) > 0, ...
    'dashboard loaded P6 regression artifact summary rows', ...
    'dashboard did not load regression artifact summary rows');

alpha_csv = fullfile(this_dir, 'p6_ui_phy_alpha_refine_raw.csv');
if exist(alpha_csv, 'file') == 2
    metrics = table_text_col(app_model.artifact_table, 'metric');
    [pass_count, total_checks] = record_check(pass_count, total_checks, ...
        any(strcmp(metrics, 'UI alpha avg/max BER')), ...
        'dashboard loaded UI alpha refine artifact rows', ...
        'dashboard did not load UI alpha refine artifact rows');
end

scenarios = {'Business frame', 'Stateful 32-frame', 'High-Doppler DSSS scan'};
policies = {'AMC default', 'AMC profile-aware', 'AMC safe fastDSSS', ...
    'Fixed OFDM', 'Fixed DSSS-sps3'};
all_combo_ok = true;
for sidx = 1:numel(scenarios)
    for pidx = 1:numel(policies)
        app_combo = p6_amc_demo_ui(struct('headless', true, ...
            'scenario', scenarios{sidx}, 'policy', policies{pidx}));
        all_combo_ok = all_combo_ok && height(app_combo.detail) > 0 && ...
            isfinite(app_combo.summary.mean_goodput);
    end
end
[pass_count, total_checks] = record_check(pass_count, total_checks, ...
    all_combo_ok, ...
    'all dashboard scenario/policy headless combinations ran', ...
    'one or more scenario/policy headless combinations failed');

app_ui = p6_amc_demo_ui(struct('visible', 'off'));
cleanup_obj = onCleanup(@() close_if_valid(app_ui));
drawnow;

[pass_count, total_checks] = record_check(pass_count, total_checks, ...
    isfield(app_ui, 'fig') && isvalid(app_ui.fig) && ...
    isfield(app_ui, 'detail') && height(app_ui.detail) > 0, ...
    'hidden uifigure initialized and ran the default preview', ...
    'hidden uifigure failed to initialize');

fprintf('\nResult: %d/%d checks passed\n', pass_count, total_checks);
if pass_count == total_checks
    fprintf('[PASS] Streaming P6 AMC dashboard smoke passed\n');
else
    error('test_p6_amc_demo_ui_smoke: %d/%d checks failed', ...
        total_checks - pass_count, total_checks);
end

diary off;
fprintf('Log written: %s\n', diary_path);

% -------------------------------------------------------------------------
function [pass_count, total_checks] = record_check(pass_count, total_checks, ...
    condition, pass_msg, fail_msg)

total_checks = total_checks + 1;
if condition
    pass_count = pass_count + 1;
    fprintf('[PASS] %s\n', pass_msg);
else
    fprintf('[FAIL] %s\n', fail_msg);
end

end

% -------------------------------------------------------------------------
function close_if_valid(app)

if isfield(app, 'fig') && isvalid(app.fig)
    close(app.fig);
end

end

% -------------------------------------------------------------------------
function c = table_text_col(tbl, name)

var_name = find_table_var(tbl, name);
v = tbl.(var_name);
if isstring(v)
    c = cellstr(v);
elseif iscell(v)
    c = v;
elseif iscategorical(v)
    c = cellstr(v);
else
    c = cellstr(string(v));
end

end

% -------------------------------------------------------------------------
function var_name = find_table_var(tbl, name)

vars = tbl.Properties.VariableNames;
idx = strcmp(vars, name);
if ~any(idx)
    idx = strcmpi(vars, name);
end
if ~any(idx)
    error('test_p6_amc_demo_ui_smoke: missing table variable "%s"', name);
end
var_name = vars{find(idx, 1, 'first')};

end
