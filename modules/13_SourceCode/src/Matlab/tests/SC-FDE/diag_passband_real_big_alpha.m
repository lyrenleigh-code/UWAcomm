%% diag_passband_real_big_alpha.m
% 目的：诊断真实 Doppler 下 oracle_passband 在 |α|≥1e-2 的反转断崖
%
% 数据回顾（diag_passband_real_doppler 的 oracle_passband 列）：
%   α=+1e-2: 1.51%      | α=-1e-2: 45.63%  ← 负向崩
%   α=+3e-2: 50.32%     | α=-3e-2:  2.17%  ← 正向崩（方向反了）
%
% 本脚本跑这 4 点（oracle_passband + real_doppler），保存 diag mat，
% 后处理比较：
%   - rx_pb_clean 频谱中心（应为 ±fc(1+α)）  → 验证 gen_doppler_channel 正确
%   - 通带 resample 后 rx_pb 频谱中心      → 应拉回 ±fc
%   - bb_raw 频谱中心                      → 应接近 DC
%   - LFM peak 位置 vs 名义值
%   - alpha_lfm / alpha_cp（estimator 自然运行的输出）
%   - ber_head vs ber_tail（帧头 vs 帧尾误码分布）
%
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_results_real_big_alpha');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

fprintf('========================================\n');
fprintf('  真实 Doppler × oracle_passband 大 α 断崖诊断 V1.0\n');
fprintf('========================================\n\n');

%% Part 1：跑 4 α 点，保存 diag mat
h_alpha_list = [1e-2, -1e-2, 3e-2, -3e-2];
h_n = length(h_alpha_list);
h_mat_paths = cell(1, h_n);
h_csv_paths = cell(1, h_n);

for h_ai = 1:h_n
    a_val = h_alpha_list(h_ai);
    h_tag = sprintf('a%+g', a_val);
    h_mat_paths{h_ai} = fullfile(h_out_dir, sprintf('diag_%s.mat', h_tag));
    h_csv_paths{h_ai} = fullfile(h_out_dir, sprintf('bench_%s.csv', h_tag));
    if exist(h_mat_paths{h_ai}, 'file'), delete(h_mat_paths{h_ai}); end
    if exist(h_csv_paths{h_ai}, 'file'), delete(h_csv_paths{h_ai}); end

    fprintf('[%d/%d] 跑 α=%+g（real Doppler + oracle_passband + diag）\n', h_ai, h_n, a_val);

    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = [10];
    bench_fading_cfgs              = { sprintf('a=%g', a_val), 'static', 0, a_val, 1024, 128, 4 };
    bench_channel_profile          = 'custom6';
    bench_seed                     = 42;
    bench_stage                    = 'diag';
    bench_scheme_name              = 'SC-FDE';
    bench_csv_path                 = h_csv_paths{h_ai};
    bench_diag                     = struct('enable', true, 'out_path', h_mat_paths{h_ai});
    bench_toggles                  = struct();
    bench_oracle_alpha             = false;
    bench_oracle_passband_resample = true;   % ★ 通带 oracle
    bench_use_real_doppler         = true;   % ★ 真实 Doppler

    try
        run(h_runner);
    catch ME
        fprintf('  [ERROR] %s\n', ME.message);
    end

    clearvars -except h_ai h_n h_alpha_list h_mat_paths h_csv_paths ...
                      h_this_dir h_runner h_out_dir
end

%% Part 2：后处理节点对比
fprintf('\n========================================\n');
fprintf('  Part 2：节点对比分析\n');
fprintf('========================================\n');

% 加载
h_diag_all = cell(1, h_n);
for h_ai = 1:h_n
    if exist(h_mat_paths{h_ai}, 'file')
        S = load(h_mat_paths{h_ai});
        h_diag_all{h_ai} = S.diag_rec;
    else
        fprintf('[WARN] 缺 %s\n', h_mat_paths{h_ai});
    end
end

% 固定参数（从 runner 一致）
h_fs = 48000;
h_fc = 12000;

%% 表 1：主要标量对比
fprintf('\n--- 表 1：BER / α_lfm / α_cp / α_est / LFM peak ---\n');
fprintf('%-10s | %-9s | %-9s | %-10s | %-10s | %-10s | %-10s | %-10s\n', ...
        'α_true','BER','head','tail','α_lfm','α_cp','α_est','peak-nom');
fprintf('%s\n', repmat('-', 1, 110));
for h_ai = 1:h_n
    a_true = h_alpha_list(h_ai);
    if isempty(h_diag_all{h_ai})
        fprintf('%-+10.1e | <缺失>\n', a_true); continue;
    end
    D = h_diag_all{h_ai};
    ber_coded = NaN;
    if isfield(D, 'ber_info'), ber_coded = D.ber_info; end
    head = NaN; tail = NaN;
    if isfield(D, 'ber_head'), head = D.ber_head; end
    if isfield(D, 'ber_tail'), tail = D.ber_tail; end
    al = get_field_or_nan(D, 'alpha_lfm');
    ac = get_field_or_nan(D, 'alpha_cp');
    ae = get_field_or_nan(D, 'alpha_est');
    lfm_obs = get_field_or_nan(D, 'lfm_pos_obs');
    lfm_nom = get_field_or_nan(D, 'lfm_pos_nom');
    peak_diff = NaN;
    if ~isnan(lfm_obs) && ~isnan(lfm_nom), peak_diff = lfm_obs - lfm_nom; end
    fprintf('%-+10.1e | %-9.4f | %-9.4f | %-10.4f | %-+10.3e | %-+10.3e | %-+10.3e | %-+10d\n', ...
            a_true, ber_coded, head, tail, al, ac, ae, round(peak_diff));
end

%% 表 2：各节点 RMS
fprintf('\n--- 表 2：节点 RMS（复信号用 abs） ---\n');
h_nodes = {'frame_bb','rx_pb_clean','bb_raw','bb_comp','rx_sym_all'};
fprintf('%-10s', 'α_true');
for nn = 1:length(h_nodes), fprintf(' | %-14s', h_nodes{nn}); end
fprintf('\n%s\n', repmat('-', 1, 10 + length(h_nodes)*17));
for h_ai = 1:h_n
    a_true = h_alpha_list(h_ai);
    fprintf('%-+10.1e', a_true);
    if isempty(h_diag_all{h_ai})
        fprintf(' | <缺失>\n'); continue;
    end
    D = h_diag_all{h_ai};
    for nn = 1:length(h_nodes)
        v = NaN;
        if isfield(D, h_nodes{nn})
            x = D.(h_nodes{nn});
            if ~isempty(x), v = sqrt(mean(abs(x(:)).^2)); end
        end
        if isnan(v), fprintf(' | %-14s', '--');
        else, fprintf(' | %-14.4e', v); end
    end
    fprintf('\n');
end

%% 表 3：频谱峰位（rx_pb_clean 应在 ±fc(1+α)，bb_raw 应在 DC 附近）
fprintf('\n--- 表 3：频谱主峰频率（Hz） ---\n');
fprintf('%-10s | %-18s | %-18s | %-18s\n', 'α_true', 'rx_pb_clean peak', 'expected fc(1+α)', 'bb_raw peak');
fprintf('%s\n', repmat('-', 1, 75));
for h_ai = 1:h_n
    a_true = h_alpha_list(h_ai);
    if isempty(h_diag_all{h_ai})
        fprintf('%-+10.1e | <缺失>\n', a_true); continue;
    end
    D = h_diag_all{h_ai};

    pb_peak_hz = peak_freq_abs(D.rx_pb_clean, h_fs);
    bb_peak_hz = peak_freq_signed(D.bb_raw, h_fs);
    expected_fc = h_fc * (1 + a_true);

    fprintf('%-+10.1e | %-18.2f | %-18.2f | %-+18.2f\n', ...
            a_true, pb_peak_hz, expected_fc, bb_peak_hz);
end

%% 图 1：4 α 各节点对比图
try
    figure('Name','rx_pb_clean FFT','Position',[100 100 1100 700]);
    for h_ai = 1:h_n
        subplot(2,2,h_ai);
        if ~isempty(h_diag_all{h_ai})
            x = h_diag_all{h_ai}.rx_pb_clean;
            N = length(x);
            f_ax = (0:N-1)*h_fs/N;
            f_ax(f_ax > h_fs/2) = f_ax(f_ax > h_fs/2) - h_fs;
            f_ax = fftshift(f_ax);
            X = fftshift(abs(fft(x)));
            plot(f_ax, 20*log10(max(X,1e-10)), 'b-');
            hold on;
            expected_fc = h_fc * (1 + h_alpha_list(h_ai));
            xline(expected_fc, 'r--', sprintf('fc(1+α)=%.1f Hz', expected_fc));
            xline(-expected_fc, 'r--');
            xline(h_fc, 'k:', 'fc');
            xline(-h_fc, 'k:');
            grid on;
            xlim([-h_fs/2, h_fs/2]);
            xlabel('Hz'); ylabel('dB');
            title(sprintf('α=%+g rx_{pb,clean} FFT', h_alpha_list(h_ai)));
        end
    end
    saveas(gcf, fullfile(h_out_dir, 'fft_rx_pb_clean.png'));

    figure('Name','bb_raw FFT','Position',[120 120 1100 700]);
    for h_ai = 1:h_n
        subplot(2,2,h_ai);
        if ~isempty(h_diag_all{h_ai})
            x = h_diag_all{h_ai}.bb_raw;
            N = length(x);
            f_ax = (0:N-1)*h_fs/N;
            f_ax(f_ax > h_fs/2) = f_ax(f_ax > h_fs/2) - h_fs;
            f_ax = fftshift(f_ax);
            X = fftshift(abs(fft(x)));
            plot(f_ax, 20*log10(max(X,1e-10)), 'b-');
            hold on;
            expected_cfo = -h_fc * h_alpha_list(h_ai) / (1 + h_alpha_list(h_ai));
            xline(0, 'k:', 'DC');
            xline(expected_cfo, 'r--', sprintf('-fc·α/(1+α)=%.1f Hz', expected_cfo));
            grid on;
            xlim([-4000, 4000]);
            xlabel('Hz'); ylabel('dB');
            title(sprintf('α=%+g bb_{raw} FFT（下变频后）', h_alpha_list(h_ai)));
        end
    end
    saveas(gcf, fullfile(h_out_dir, 'fft_bb_raw.png'));

    % 时域头尾 RMS（看信号是否失真）
    figure('Name','bb_raw time domain','Position',[140 140 1100 700]);
    for h_ai = 1:h_n
        subplot(2,2,h_ai);
        if ~isempty(h_diag_all{h_ai})
            x = h_diag_all{h_ai}.bb_raw;
            plot(real(x(1:min(end,2000))), 'b'); hold on;
            plot(imag(x(1:min(end,2000))), 'r');
            grid on;
            xlabel('sample'); ylabel('amp');
            title(sprintf('α=%+g bb_{raw} 前 2000 样本', h_alpha_list(h_ai)));
            legend('I','Q');
        end
    end
    saveas(gcf, fullfile(h_out_dir, 'time_bb_raw_head.png'));

    fprintf('\n图已保存：\n  %s/fft_rx_pb_clean.png\n  %s/fft_bb_raw.png\n  %s/time_bb_raw_head.png\n', ...
            h_out_dir, h_out_dir, h_out_dir);
catch ME
    fprintf('\n[WARN] 绘图失败：%s\n', ME.message);
end

fprintf('\n========================================\n');
fprintf('  完成。关键观察点：\n');
fprintf('  - 表 1：BER 头/尾分布 + estimator 输出（通带 oracle 模式下自然运行）\n');
fprintf('  - 表 3：rx_pb_clean 频谱峰应在 fc(1+α)，bb_raw 应接近 DC（oracle_passband 成功补偿）\n');
fprintf('  - 图 fft_bb_raw：若 bb_raw 频谱中心偏离 DC，说明通带 resample 未完全消除 CFO\n');
fprintf('========================================\n');

%% helpers
function v = get_field_or_nan(S, name)
    if isfield(S, name) && ~isempty(S.(name))
        v = S.(name)(1);
    else
        v = NaN;
    end
end

function f_hz = peak_freq_abs(x, fs)
    % 返回 |FFT| 最大值对应的正频率（实信号两侧对称，取正半）
    N = length(x);
    X = abs(fft(x));
    X = X(1:floor(N/2));
    [~, idx] = max(X);
    f_hz = (idx-1) * fs / N;
end

function f_hz = peak_freq_signed(x, fs)
    % 返回 |FFT| 最大值对应的频率（有符号，复信号用）
    N = length(x);
    X = abs(fft(x));
    [~, idx] = max(X);
    if idx <= N/2
        f_hz = (idx-1) * fs / N;
    else
        f_hz = (idx-1-N) * fs / N;
    end
end
