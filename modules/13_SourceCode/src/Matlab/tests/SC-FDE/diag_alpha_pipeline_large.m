%% diag_alpha_pipeline_large.m — α=±3e-2 pipeline 不对称诊断
% 对应 spec: specs/active/2026-04-21-alpha-pipeline-large-alpha-debug.md
% 版本：V1.0.0（2026-04-21）
%
% 目的：定位 SC-FDE α=+3e-2 (BER 50%) vs α=-3e-2 (BER 3%) 的 pipeline 不对称根因
% 方法：复用 diag_alpha_pipeline 架构，跑 α ∈ {0, +3e-2, -3e-2} Oracle 三路
%       9 节点 RMS + 逐块 BER + 帧头/尾对比 + 3 关键 toggle (H2/H3/H6)

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
runner = fullfile(this_dir, 'test_scfde_timevarying.m');

out_dir = fullfile(this_dir, 'diag_results_large');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

fprintf('========================================\n');
fprintf('  大 α (±3e-2) Pipeline 不对称诊断 V1.0.0\n');
fprintf('========================================\n');

alpha_list = [0, +3e-2, -3e-2];
alpha_tags = {'zero', 'pos3e2', 'neg3e2'};

%% Part 1: 三路 α oracle 跑（基线）
for ai = 1:numel(alpha_list)
    alpha = alpha_list(ai);
    tag = alpha_tags{ai};
    mat_path = fullfile(out_dir, sprintf('diag_%s.mat', tag));
    csv_path = fullfile(out_dir, sprintf('diag_%s.csv', tag));

    fprintf('\n=== Part 1 [%d/%d]: α=%+.0e (oracle) ===\n', ai, numel(alpha_list), alpha);

    benchmark_mode        = true; %#ok<*NASGU>
    bench_oracle_alpha    = true;
    bench_snr_list        = [10];
    bench_fading_cfgs     = { sprintf('a=%g', alpha), 'static', 0, alpha, 1024, 128, 4 };
    bench_channel_profile = 'custom6';
    bench_seed            = 42;
    bench_stage           = 'diag_large';
    bench_scheme_name     = 'SC-FDE';
    bench_csv_path        = csv_path;
    bench_diag            = struct('enable', true, 'out_path', mat_path);
    bench_toggles         = struct();

    if exist(csv_path, 'file'), delete(csv_path); end
    if exist(mat_path, 'file'), delete(mat_path); end

    run(runner);
    clearvars -except ai alpha_list alpha_tags this_dir runner out_dir
end

%% Part 2: 节点 RMS 三路对比
dz = load(fullfile(out_dir, 'diag_zero.mat'));   dz = dz.diag_rec;
dp = load(fullfile(out_dir, 'diag_pos3e2.mat')); dp = dp.diag_rec;
dn = load(fullfile(out_dir, 'diag_neg3e2.mat')); dn = dn.diag_rec;

node_list = {'frame_bb','rx_pb_clean','bb_raw','bb_comp','rx_sym_all','Y_freq_blk1','LLR_all','hard_coded'};
rms_pos_zero = nan(1, numel(node_list));
rms_neg_zero = nan(1, numel(node_list));
rms_pos_neg  = nan(1, numel(node_list));

fprintf('\n=== Part 2: 节点 RMS ratio 三路 ===\n');
fprintf('%-14s %-12s %-12s %-12s\n', 'node', '(+3e-2)/0', '(-3e-2)/0', 'asym_ratio');
fprintf('%s\n', repmat('-', 1, 60));
for ni = 1:numel(node_list)
    n = node_list{ni};
    if ~isfield(dz, n) || ~isfield(dp, n) || ~isfield(dn, n)
        fprintf('  [%-14s] <缺失>\n', n);
        continue;
    end
    a = dz.(n); b = dp.(n); c = dn.(n);
    if iscell(a), a = a{1}; b = b{1}; c = c{1}; end
    a = a(:); b = b(:); c = c(:);
    L = min([length(a), length(b), length(c)]);
    rms_pos_zero(ni) = norm(b(1:L) - a(1:L)) / max(norm(a(1:L)), eps);
    rms_neg_zero(ni) = norm(c(1:L) - a(1:L)) / max(norm(a(1:L)), eps);
    rms_pos_neg(ni)  = norm(b(1:L) - c(1:L)) / max(norm(c(1:L)), eps);
    asym = rms_pos_zero(ni) / max(rms_neg_zero(ni), eps);
    fprintf('  %-14s %-12.3e %-12.3e %-12.3f\n', n, ...
        rms_pos_zero(ni), rms_neg_zero(ni), asym);
end

%% Part 3: 逐块 BER + 帧头/帧尾对比
fprintf('\n=== Part 3: 逐块 + 帧头/帧尾 BER（帧尾污染判别）===\n');
fprintf('%-12s %-10s %-10s %-35s %-10s %-10s\n', ...
    'α', 'BER_final', 'BER_head', 'BER_per_block', 'BER_tail', 'lfm_pos_err');

targets = {'zero', 'pos3e2', 'neg3e2'};
dats = {dz, dp, dn};
for i = 1:3
    d = dats{i};
    if isfield(d, 'ber_per_block_coded')
        blk_str = sprintf('[%.2f %.2f %.2f %.2f]', d.ber_per_block_coded);
    else
        blk_str = '<missing>';
    end
    bh = '';
    if isfield(d, 'ber_head'), bh = sprintf('%.4f', d.ber_head); end
    bt = '';
    if isfield(d, 'ber_tail'), bt = sprintf('%.4f', d.ber_tail); end
    bi = '';
    if isfield(d, 'ber_info'), bi = sprintf('%.4f', d.ber_info); end
    lfmerr = '';
    if isfield(d, 'lfm_pos_obs')
        lfmerr = sprintf('%+d', d.lfm_pos_obs - d.lfm_pos_nom);
    end
    fprintf('  %-12s %-10s %-10s %-35s %-10s %-10s\n', targets{i}, bi, bh, blk_str, bt, lfmerr);
end

%% Part 4: +3e-2 下关键 toggle 测试（H2 skip_lpf, H3 force_best_off, H6 pad_tail）
toggle_list = {
    'baseline',      struct();
    'H2_skip_lpf',   struct('skip_downconvert_lpf', true);
    'H3_best_off0',  struct('force_best_off', true);
    'H4_oracle_h',   struct('oracle_h', true);
    'H5_force_lfm',  struct('force_lfm_pos', true);
    'H6_pad_tail',   struct('pad_tx_tail', true);
    'H7_skip_cp',    struct('skip_alpha_cp', true);
};

fprintf('\n=== Part 4: α=+3e-2 下 toggle BER 测试 ===\n');
n_tog = size(toggle_list, 1);
ber_by_toggle = nan(1, n_tog);
blk_by_toggle = cell(1, n_tog);

for ti = 1:n_tog
    tname = toggle_list{ti, 1};
    tcfg  = toggle_list{ti, 2};

    benchmark_mode        = true;
    bench_oracle_alpha    = true;
    bench_snr_list        = [10];
    bench_fading_cfgs     = { 'a=+3e-2', 'static', 0, +3e-2, 1024, 128, 4 };
    bench_channel_profile = 'custom6';
    bench_seed            = 42;
    bench_stage           = 'diag_large';
    bench_scheme_name     = 'SC-FDE';
    bench_csv_path        = fullfile(out_dir, sprintf('toggle_%s.csv', tname));
    bench_diag            = struct('enable', true, ...
                                    'out_path', fullfile(out_dir, sprintf('toggle_%s.mat', tname)));
    bench_toggles         = tcfg;

    if exist(bench_csv_path, 'file'), delete(bench_csv_path); end
    if exist(bench_diag.out_path, 'file'), delete(bench_diag.out_path); end

    run(runner);

    try
        tmp = load(bench_diag.out_path);
        ber_by_toggle(ti) = tmp.diag_rec.ber_info;
        if isfield(tmp.diag_rec, 'ber_per_block_coded')
            blk_by_toggle{ti} = tmp.diag_rec.ber_per_block_coded;
        end
    catch ME
        fprintf('  [!] 读 diag 失败：%s\n', ME.message);
    end

    clearvars -except ti n_tog toggle_list ber_by_toggle blk_by_toggle ...
                      out_dir this_dir runner alpha_list alpha_tags
end

%% Part 5: Toggle ranking
fprintf('\n============================================\n');
fprintf('  Toggle Ranking (α=+3e-2 oracle @ SNR=10)\n');
fprintf('============================================\n');
baseline_ber = ber_by_toggle(1);
fprintf('%-20s %-10s %-10s %s\n', 'Toggle', 'BER', 'Δ', 'blocks');
fprintf('%s\n', repmat('-', 1, 70));
for ti = 1:n_tog
    blk_str = '';
    if ~isempty(blk_by_toggle{ti})
        blk_str = sprintf('[%s]', sprintf('%.2f ', blk_by_toggle{ti}));
    end
    delta = ber_by_toggle(ti) - baseline_ber;
    fprintf('%-20s %-10.4f %+10.4f  %s\n', toggle_list{ti,1}, ...
        ber_by_toggle(ti), delta, blk_str);
end

save(fullfile(out_dir, 'large_alpha_summary.mat'), ...
     'rms_pos_zero', 'rms_neg_zero', 'rms_pos_neg', 'node_list', ...
     'toggle_list', 'ber_by_toggle', 'blk_by_toggle', 'dz', 'dp', 'dn');
fprintf('\n[已存] %s\n', fullfile(out_dir, 'large_alpha_summary.mat'));
fprintf('\n=== 诊断完成 ===\n');
