%% compare_pilot_papr.m — OTFS pilot方案PAPR对比
% 对比A(冲激)/B(ZC序列)/C(叠加) 三种pilot的时域PAPR
% 用法: run('compare_pilot_papr.m')

clc; close all;
fprintf('========================================\n');
fprintf('  OTFS Pilot 方案 PAPR 对比\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));

%% 参数
N = 32; M = 64; cp_len = 32;
fs_bb = 6000;
N_mc = 50;  % Monte Carlo次数
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);

% 三种pilot配置
configs = {
    'A-Impulse',      struct('mode','impulse', 'guard_k',4, 'guard_l',10);
    'B-ZC序列',       struct('mode','sequence', 'seq_type','zc', 'seq_root',1, 'guard_k',4, 'guard_l',10);
    'C-叠加pilot',    struct('mode','superimposed', 'pilot_power',0.2);
};

n_cfg = size(configs, 1);
results = struct();

fprintf('%-12s | %-10s %-10s %-10s %-10s %-10s\n', ...
    'Pilot方案', 'PAPR均值', 'PAPR最大', 'BB Peak', 'BB RMS', '数据槽数');
fprintf('%s\n', repmat('-', 1, 68));

for ci = 1:n_cfg
    cname = configs{ci, 1};
    cfg = configs{ci, 2};

    % 首次调用获取data_indices数量
    [~, ~, ~, data_idx] = otfs_pilot_embed(zeros(1,1), N, M, cfg);
    n_data = length(data_idx);

    % 设置pilot幅度（impulse/sequence用sqrt(n_data)，superimposed用其自身设置）
    if strcmp(cfg.mode, 'impulse') || strcmp(cfg.mode, 'sequence')
        cfg.pilot_value = sqrt(n_data);
    end

    % Monte Carlo
    papr_arr = zeros(1, N_mc);
    peak_arr = zeros(1, N_mc);
    rms_arr = zeros(1, N_mc);

    for trial = 1:N_mc
        rng(trial);
        data = constellation(randi(4, 1, n_data));
        [dd_frame, pinfo, gmask, didx] = otfs_pilot_embed(data, N, M, cfg);
        [sig_bb, ~] = otfs_modulate(dd_frame, N, M, cp_len, 'dft');

        peak_arr(trial) = max(abs(sig_bb));
        rms_arr(trial) = sqrt(mean(abs(sig_bb).^2));
        papr_arr(trial) = 20*log10(peak_arr(trial) / rms_arr(trial));
    end

    results(ci).name = cname;
    results(ci).papr_mean = mean(papr_arr);
    results(ci).papr_max = max(papr_arr);
    results(ci).peak_mean = mean(peak_arr);
    results(ci).rms_mean = mean(rms_arr);
    results(ci).n_data = n_data;

    fprintf('%-12s | %-10.2f %-10.2f %-10.3f %-10.3f %-10d\n', ...
        cname, mean(papr_arr), max(papr_arr), mean(peak_arr), mean(rms_arr), n_data);
end

fprintf('\n');

%% 可视化：时域波形 + 幅值分布
try
    figure('Name', 'Pilot PAPR对比', 'Position', [50 50 1400 700]);
    colors = {'b', 'r', 'g'};
    rng(1);
    data_vis = constellation(randi(4, 1, 2000));  % 足够长
    for ci = 1:n_cfg
        cfg = configs{ci, 2};
        [~, ~, ~, didx] = otfs_pilot_embed(zeros(1,1), N, M, cfg);
        if strcmp(cfg.mode, 'impulse') || strcmp(cfg.mode, 'sequence')
            cfg.pilot_value = sqrt(length(didx));
        end
        data_v = data_vis(1:length(didx));
        [dd_v, ~, ~, ~] = otfs_pilot_embed(data_v, N, M, cfg);
        [sig_v, ~] = otfs_modulate(dd_v, N, M, cp_len, 'dft');

        % 子图1: 时域|amp|波形
        subplot(2, n_cfg, ci);
        plot(abs(sig_v), colors{ci}, 'LineWidth', 0.5);
        xlabel('样本'); ylabel('|amp|');
        title(sprintf('%s: PAPR=%.1fdB', configs{ci,1}, ...
            20*log10(max(abs(sig_v))/sqrt(mean(abs(sig_v).^2)))));
        grid on; ylim([0 max(abs(sig_v))*1.1]);

        % 子图2: 幅值直方图（对数）
        subplot(2, n_cfg, n_cfg+ci);
        histogram(abs(sig_v), 80, 'FaceColor', colors{ci}, 'FaceAlpha', 0.7);
        xlabel('|amp|'); ylabel('count'); set(gca, 'YScale', 'log');
        title(sprintf('%s 幅值分布', configs{ci,1}));
        grid on;
    end

    fprintf('可视化完成\n');
catch e
    fprintf('可视化失败: %s\n', e.message);
end

%% 保存结果
result_file = fullfile(fileparts(mfilename('fullpath')), 'compare_pilot_papr_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'OTFS Pilot PAPR 对比 (N_mc=%d, N=%d, M=%d, QPSK)\n\n', N_mc, N, M);
for ci = 1:n_cfg
    r = results(ci);
    fprintf(fid, '%s: PAPR均值=%.2fdB, 最大=%.2fdB, Peak=%.3f, RMS=%.3f, 数据槽=%d\n', ...
        r.name, r.papr_mean, r.papr_max, r.peak_mean, r.rms_mean, r.n_data);
end
fclose(fid);
fprintf('结果已保存: %s\n', result_file);
