%% diag_alpha_pipeline.m — α=2e-3 崩溃根因 pipeline 诊断
% 对应 spec: specs/active/2026-04-20-alpha-compensation-pipeline-debug.md
% 版本：V1.0.0（2026-04-20）

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
runner = fullfile(this_dir, 'test_scfde_timevarying.m');

out_dir = fullfile(this_dir, 'diag_results');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

fprintf('========================================\n');
fprintf('  α=2e-3 Pipeline 诊断 V1.0.0\n');
fprintf('========================================\n');

%% Part 1: α=0 vs α=2e-3 基线 RMS 对比（oracle α）
for ai = [0, 2e-3]
    if ai == 0, tag = 'a0'; else, tag = sprintf('a%.0e', ai); end
    mat_path = fullfile(out_dir, sprintf('diag_%s.mat', tag));
    csv_path = fullfile(out_dir, sprintf('diag_%s.csv', tag));

    fprintf('\n=== Part 1: 跑 α=%.0e (oracle) ===\n', ai);

    % 准备 runner workspace
    benchmark_mode        = true; %#ok<*NASGU>
    bench_oracle_alpha    = true;
    bench_snr_list        = [10];
    bench_fading_cfgs     = { sprintf('a=%g', ai), 'static', 0, ai, 1024, 128, 4 };
    bench_channel_profile = 'custom6';
    bench_seed            = 42;
    bench_stage           = 'diag';
    bench_scheme_name     = 'SC-FDE';
    bench_csv_path        = csv_path;
    bench_diag            = struct('enable', true, 'out_path', mat_path);
    bench_toggles         = struct();  % baseline: 全关

    if exist(csv_path, 'file'), delete(csv_path); end
    if exist(mat_path, 'file'), delete(mat_path); end

    run(runner);

    clearvars -except ai this_dir runner out_dir
end

%% Part 2: 读 MAT 做节点 RMS ratio 对比
d0 = load(fullfile(out_dir, 'diag_a0.mat'));       d0 = d0.diag_rec;
d2 = load(fullfile(out_dir, 'diag_a2e-03.mat'));   d2 = d2.diag_rec;

node_list = {'frame_bb','rx_pb_clean','bb_raw','bb_comp','rx_sym_all','Y_freq_blk1','LLR_all','hard_coded'};
rms_ratios = nan(1, numel(node_list));

fprintf('\n=== Pipeline RMS ratio (α=2e-3 vs α=0) ===\n');
for ni = 1:numel(node_list)
    n = node_list{ni};
    if ~isfield(d0, n) || ~isfield(d2, n)
        fprintf('  [%-14s] <缺失>\n', n);
        continue;
    end
    a = d0.(n); b = d2.(n);
    if iscell(a), a = a{1}; b = b{1}; end
    a = a(:); b = b(:);
    L = min(length(a), length(b));
    rms_ratios(ni) = norm(b(1:L) - a(1:L)) / max(norm(a(1:L)), eps);
    fprintf('  [%-14s] ratio = %.4e\n', n, rms_ratios(ni));
end

fprintf('\n=== 逐块 BER 分布（α=2e-3）===\n');
if isfield(d2, 'ber_per_block_coded')
    fprintf('  ber_head (首 50 coded bits)  = %.4f\n', d2.ber_head);
    fprintf('  ber_per_block_coded          = [%s]\n', sprintf('%.3f ', d2.ber_per_block_coded));
    fprintf('  ber_tail (末 50 coded bits)  = %.4f\n', d2.ber_tail);
    fprintf('  ber_info (final decoded)     = %.4f\n', d2.ber_info);
end
if isfield(d2, 'lfm_pos_obs')
    fprintf('  LFM2 定时：obs=%d  nominal=%d  偏移=%+d\n', ...
        d2.lfm_pos_obs, d2.lfm_pos_nom, d2.lfm_pos_obs - d2.lfm_pos_nom);
end

save(fullfile(out_dir, 'pipeline_rms.mat'), 'rms_ratios', 'node_list', 'd0', 'd2');
fprintf('\n[已存] %s\n', fullfile(out_dir, 'pipeline_rms.mat'));

%% Part 3: H1-H8 toggle 逐条测试（α=2e-3 oracle）
toggle_list = {
    'baseline',         struct();
    'H1_skip_resample', struct('skip_resample', true);
    'H2_skip_lpf',      struct('skip_downconvert_lpf', true);
    'H3_best_off0',     struct('force_best_off', true);
    'H4_oracle_h',      struct('oracle_h', true);
    'H5_force_lfm',     struct('force_lfm_pos', true);
    'H6_pad_tail',      struct('pad_tx_tail', true);
    'H7_skip_cp',       struct('skip_alpha_cp', true);
    'H8_bem_q0',        struct('force_bem_q', 0);
    'H8_bem_q4',        struct('force_bem_q', 4);
};

n_tog = size(toggle_list, 1);
ber_by_toggle = nan(1, n_tog);
ber_blocks_by_toggle = cell(1, n_tog);

fprintf('\n=== Part 3: H1-H8 toggle 测试（α=2e-3 oracle, SNR=10）===\n');

for ti = 1:n_tog
    tname = toggle_list{ti, 1};
    tcfg  = toggle_list{ti, 2};
    fprintf('\n--- Toggle [%d/%d] %s ---\n', ti, n_tog, tname);

    benchmark_mode        = true;
    bench_oracle_alpha    = true;
    bench_snr_list        = [10];
    bench_fading_cfgs     = { 'a=2e-3', 'static', 0, 2e-3, 1024, 128, 4 };
    bench_channel_profile = 'custom6';
    bench_seed            = 42;
    bench_stage           = 'diag';
    bench_scheme_name     = 'SC-FDE';
    bench_csv_path        = fullfile(out_dir, sprintf('toggle_%s.csv', tname));
    bench_diag            = struct('enable', true, ...
                                    'out_path', fullfile(out_dir, sprintf('toggle_%s.mat', tname)));
    bench_toggles         = tcfg;

    if exist(bench_csv_path, 'file'), delete(bench_csv_path); end
    if exist(bench_diag.out_path, 'file'), delete(bench_diag.out_path); end

    run(runner);

    % 读回 diag MAT 获取 BER
    try
        tmp = load(bench_diag.out_path);
        ber_by_toggle(ti) = tmp.diag_rec.ber_info;
        if isfield(tmp.diag_rec, 'ber_per_block_coded')
            ber_blocks_by_toggle{ti} = tmp.diag_rec.ber_per_block_coded;
        end
    catch ME
        fprintf('  [!] 读 diag 失败：%s\n', ME.message);
    end

    clearvars -except ti n_tog toggle_list ber_by_toggle ber_blocks_by_toggle ...
                      out_dir this_dir runner
end

%% Part 4: Toggle Ranking
fprintf('\n============================================\n');
fprintf('  Toggle BER Ranking (α=2e-3 oracle @ SNR=10)\n');
fprintf('============================================\n');
baseline_ber = ber_by_toggle(1);
fprintf('%-20s %-10s %-10s %s\n', 'Toggle', 'BER', 'Δ', 'blocks');
fprintf('%s\n', repmat('-', 1, 70));
for ti = 1:n_tog
    blk_str = '';
    if ~isempty(ber_blocks_by_toggle{ti})
        blk_str = sprintf('[%s]', sprintf('%.2f ', ber_blocks_by_toggle{ti}));
    end
    delta = ber_by_toggle(ti) - baseline_ber;
    fprintf('%-20s %-10.4f %+10.4f  %s\n', toggle_list{ti,1}, ...
        ber_by_toggle(ti), delta, blk_str);
end

save(fullfile(out_dir, 'toggle_results.mat'), ...
     'toggle_list', 'ber_by_toggle', 'ber_blocks_by_toggle');
fprintf('\n[已存] %s\n', fullfile(out_dir, 'toggle_results.mat'));
fprintf('\n=== 诊断完成。用 plot_alpha_pipeline_diag.m 生成图 ===\n');
