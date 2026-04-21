%% diag_otfs_32pct.m
% 功能：OTFS 32% BER 根因诊断
% 版本：V1.0.0 (2026-04-21)
% 对应 spec: specs/active/2026-04-21-otfs-disc-doppler-32pct-debug.md
%
% 目标：在 SNR=10dB 单点上扫描 {pilot_mode × channel × trials}，
%       定位 32% BER 是 pilot_mode regression (H1) 还是
%       非均匀 Doppler + on-grid 估计失败 (H4) 或其他
%
% 矩阵：
%   pilot_mode ∈ {'impulse', 'sequence', 'superimposed'}
%   channel    ∈ {'static', 'disc-5Hz', 'hyb-K20'}
%   trials     = 3
%   SNR        = 10 dB（单点）
%
% 评价：
%   - ber_coded (要求 impulse+static ≤ 5% 为 PASS)
%   - nmse_h_dd (dB)
%   - path_detection_rate
%   - frame_detected
%
% 用法：
%   >> clear functions; clear all; close all;
%   >> cd('D:\Claude\TechReq\UWAcomm\modules\13_SourceCode\src\Matlab\tests\OTFS')
%   >> diag_otfs_32pct

clear functions; clear all; close all; clc;

% 结果目录
diag_dir = fullfile(fileparts(mfilename('fullpath')), 'diag_results');
if ~exist(diag_dir, 'dir'); mkdir(diag_dir); end
log_file = fullfile(diag_dir, 'otfs_32pct_diag_log.txt');
mat_file = fullfile(diag_dir, 'otfs_32pct_diag.mat');
diary(log_file); diary on;

fprintf('========================================\n');
fprintf('  OTFS 32%% BER 根因诊断 (2026-04-21)\n');
fprintf('  spec: 2026-04-21-otfs-disc-doppler-32pct-debug.md\n');
fprintf('========================================\n\n');

%% === 扫描配置 === %%
SNR_DB   = 10;
N_TRIALS = 3;
PILOT_MODES = {'impulse', 'sequence', 'superimposed'};
CHANNELS = {
    'static',     'static',   zeros(1,5);
    'disc-5Hz',   'discrete', [0, 3, -4, 5, -2];
    'hyb-K20',    'hybrid',   struct('doppler_hz',[0,3,-4,5,-2], 'fd_scatter',0.5, 'K_rice',20);
};

N_PM = numel(PILOT_MODES);
N_CH = size(CHANNELS, 1);

%% === 路径依赖 === %%
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

%% === 跑矩阵 === %%
% 存 ber/nmse/path_det/frame_ok，维度 [N_CH, N_PM, N_TRIALS]
ber        = nan(N_CH, N_PM, N_TRIALS);
nmse_db    = nan(N_CH, N_PM, N_TRIALS);
path_det   = nan(N_CH, N_PM, N_TRIALS);   % 检测路径数 / 真实 5 径
frame_ok   = nan(N_CH, N_PM, N_TRIALS);

t_start = tic;
for ch_i = 1:N_CH
    ch_name = CHANNELS{ch_i, 1};
    ch_type = CHANNELS{ch_i, 2};
    ch_par  = CHANNELS{ch_i, 3};

    fprintf('\n--- 信道 %s ---\n', ch_name);
    fprintf('%-14s | %-15s | %-12s | %-10s | %s\n', ...
        'pilot_mode', 'BER (%)', 'NMSE (dB)', 'PathDet', 'FrameOK');
    fprintf('%s\n', repmat('-', 1, 70));

    for pm_i = 1:N_PM
        pm = PILOT_MODES{pm_i};

        ber_row  = nan(1, N_TRIALS);
        nmse_row = nan(1, N_TRIALS);
        pd_row   = nan(1, N_TRIALS);
        fok_row  = nan(1, N_TRIALS);

        for tr_i = 1:N_TRIALS
            seed = 100 * tr_i + pm_i;
            try
                [b, n, pd, fok] = run_otfs_once(ch_type, ch_par, pm, SNR_DB, seed);
                ber_row(tr_i)  = b;
                nmse_row(tr_i) = n;
                pd_row(tr_i)   = pd;
                fok_row(tr_i)  = fok;
            catch e
                fprintf('  [FAIL] ch=%s pm=%s tr=%d : %s\n', ch_name, pm, tr_i, e.message);
            end
        end

        ber(ch_i, pm_i, :)      = ber_row;
        nmse_db(ch_i, pm_i, :)  = nmse_row;
        path_det(ch_i, pm_i, :) = pd_row;
        frame_ok(ch_i, pm_i, :) = fok_row;

        ber_m = 100 * mean(ber_row, 'omitnan');
        ber_s = 100 * std(ber_row, 'omitnan');
        nmse_m = mean(nmse_row, 'omitnan');
        pd_m = mean(pd_row, 'omitnan');
        fok_m = mean(fok_row, 'omitnan');

        fprintf('%-14s | %5.2f ± %-4.2f   | %6.1f        | %.2f       | %.2f\n', ...
            pm, ber_m, ber_s, nmse_m, pd_m, fok_m);
    end
end
elapsed = toc(t_start);
fprintf('\n[总耗时] %.1f 秒\n', elapsed);

%% === 保存 === %%
meta = struct('snr_db', SNR_DB, 'n_trials', N_TRIALS, ...
              'pilot_modes', {PILOT_MODES}, ...
              'channels', {CHANNELS(:,1).'}, ...
              'timestamp', datestr(now, 'yyyy-mm-ddTHH:MM:SS'));
save(mat_file, 'ber', 'nmse_db', 'path_det', 'frame_ok', 'meta');
fprintf('[保存] %s\n', mat_file);

%% === 决策树 === %%
fprintf('\n========== 决策树分析 ==========\n');
idx_static = strcmp({'static','disc-5Hz','hyb-K20'}, 'static');
idx_imp    = strcmp(PILOT_MODES, 'impulse');
ber_static_impulse = mean(ber(idx_static, idx_imp, :), 'omitnan');
fprintf('static + impulse 均 BER = %.2f%%\n', 100*ber_static_impulse);

if ber_static_impulse <= 0.05
    fprintf('>>> H1 成立：pilot_mode=''sequence'' regression 确认\n');
    % 看 disc-5Hz 下 impulse 是否也恢复
    idx_disc = strcmp({'static','disc-5Hz','hyb-K20'}, 'disc-5Hz');
    ber_disc_impulse = mean(ber(idx_disc, idx_imp, :), 'omitnan');
    fprintf('    disc-5Hz + impulse 均 BER = %.2f%%\n', 100*ber_disc_impulse);
    if ber_disc_impulse <= 0.05
        fprintf('>>> H4 否定：根因完全是 pilot_mode regression，Yang 2026 理论不需要\n');
        fprintf('    建议修复：test_otfs_timevarying.m:20 默认值回滚 ''impulse''\n');
    else
        fprintf('>>> H4 成立：disc-5Hz + impulse 仍 %.1f%%，存在真正非均匀 Doppler 问题\n', ...
                100*ber_disc_impulse);
        fprintf('    建议：升级衍生 spec 2026-04-22-otfs-nonuniform-doppler-ce.md\n');
    end
elseif ber_static_impulse > 0.20
    fprintf('>>> H1 否定：impulse 在 static 下仍 %.1f%%\n', 100*ber_static_impulse);
    fprintf('    进入 Step 2b：需要 oracle 模式对照\n');
    fprintf('    （建议：手工改 use_oracle=true 跑 impulse+static）\n');
else
    fprintf('>>> 边缘状态 (ber=%.2f%%)，建议 N_TRIALS 加大到 10\n', 100*ber_static_impulse);
end

diary off;
fprintf('\n[日志] %s\n', log_file);


%% ========================================================================
%% 单 run 子函数（内联 test_otfs_timevarying 核心段，裁剪为单点）
%% ========================================================================
function [ber_out, nmse_db_out, path_det_out, frame_ok_out] = ...
    run_otfs_once(ftype, fparams, pilot_mode, snr_db, seed)
% 参数复用 test_otfs_timevarying.m V5.1 的设定
    rng(seed);

    %% 参数 (与 test_otfs_timevarying.m 完全一致) %%
    sym_rate = 6000;
    fc = 12000;
    delay_bins = [0, 1, 3, 5, 8];
    gains_raw  = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
    N = 32; M = 64; cp_len = 32;
    num_turbo = 3;
    sps = 6; fs_pb = sym_rate * sps; %#ok<NASGU>
    constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
    bits_per_sym = 2;

    % pilot_config
    switch pilot_mode
        case 'impulse'
            pilot_config = struct('mode','impulse', 'guard_k',4, ...
                'guard_l',max(delay_bins)+2, 'pilot_value',1);
        case 'sequence'
            pilot_config = struct('mode','sequence', 'seq_type','zc', 'seq_root',1, ...
                'guard_k',4, 'guard_l',max(delay_bins)+2, 'pilot_value',1);
        case 'superimposed'
            pilot_config = struct('mode','superimposed', 'pilot_power',0.2);
    end
    [~,~,~,data_indices] = otfs_pilot_embed(zeros(1,1), N, M, pilot_config);
    N_data_slots = length(data_indices);
    if ismember(pilot_mode, {'impulse','sequence'})
        pilot_config.pilot_value = sqrt(N_data_slots);
    end

    codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, ...
                   'decode_mode','max-log');
    n_code = 2; mem = codec.constraint_len - 1;
    M_coded = N_data_slots * bits_per_sym;
    N_info = M_coded / n_code - mem;
    [~, perm] = random_interleave(zeros(1, M_coded), codec.interleave_seed);

    %% TX %%
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_coded);
    [interleaved,~] = random_interleave(coded, codec.interleave_seed);
    data_sym = constellation(bi2de(reshape(interleaved,2,[]).','left-msb')+1);
    [dd_frame, pilot_info, guard_mask, ~] = otfs_pilot_embed(data_sym, N, M, pilot_config); %#ok<ASGLU>
    [otfs_signal, ~] = otfs_modulate(dd_frame, N, M, cp_len, 'dft');

    %% Channel %%
    rx_clean = apply_channel(otfs_signal, delay_bins, gains_raw, ftype, fparams, sym_rate, fc);

    %% 通带帧组装 + frame_parse %%
    frame_p = struct('N',N, 'M',M, 'cp_len',cp_len, ...
                     'sps',sps, 'fs_bb',sym_rate, 'fc',fc, ...
                     'bw',sym_rate*1.3, ...
                     'T_hfm',0.05, 'T_lfm',0.02, 'guard_ms',5, ...
                     'sync_gain',0.7);
    [frame_tx_pb, info] = frame_assemble_otfs(otfs_signal, frame_p); %#ok<ASGLU>
    [frame_rx_pb, ~]    = frame_assemble_otfs(rx_clean, frame_p);
    sig_pwr_pb = mean(frame_rx_pb.^2);

    %% Pilot-only 真实信道基线 (for NMSE) %%
    if ~isempty(pilot_info.positions) && ~strcmp(pilot_mode,'superimposed')
        dd_pilot_only = zeros(N, M);
        dd_pilot_only(pilot_info.positions(1,1), pilot_info.positions(1,2)) = pilot_info.values(1);
        [sig_po, ~] = otfs_modulate(dd_pilot_only, N, M, cp_len, 'dft');
        rx_po = apply_channel(sig_po, delay_bins, gains_raw, ftype, fparams, sym_rate, fc);
        [Y_dd_po, ~] = otfs_demodulate(rx_po, N, M, cp_len, 'dft');
        h_true_dd = Y_dd_po / pilot_info.values(1);
    else
        h_true_dd = [];  % superimposed 不容易单独抽
    end

    %% 加噪 + 反组装 %%
    noise_pwr = sig_pwr_pb * 10^(-snr_db/10);
    frame_rx_noisy = frame_rx_pb + sqrt(noise_pwr) * randn(size(frame_rx_pb));
    [rx_noisy, sync_info] = frame_parse_otfs(frame_rx_noisy, info);
    noise_var = mean(abs(rx_clean).^2) * 10^(-snr_db/10);

    frame_ok_out = (isfield(sync_info, 'sync_success') && sync_info.sync_success);
    if ~frame_ok_out
        frame_ok_out = 1;  % frame_parse 无 fail 字段，默认 ok
    end

    %% OTFS demod %%
    [Y_dd, ~] = otfs_demodulate(rx_noisy, N, M, cp_len, 'dft');
    if ~isempty(pilot_info.positions)
        pk_pos = pilot_info.positions(1,1);
        pl_pos = pilot_info.positions(1,2);
        pv_val = pilot_info.values(1);
    else
        pk_pos = ceil(N/2); pl_pos = ceil(M/2); pv_val = 1;
    end

    %% 信道估计 %%
    switch pilot_mode
        case 'impulse'
            [h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M);
        case 'sequence'
            [h_dd, path_info] = ch_est_otfs_zc(Y_dd, pilot_info, N, M);
        case 'superimposed'
            [h_dd, path_info] = ch_est_otfs_superimposed(Y_dd, pilot_info, N, M, ...
                struct('iter',3, 'guard_k',4, 'guard_l',max(delay_bins)+2));
    end

    %% NMSE %%
    if ~isempty(h_true_dd)
        nmse_db_out = 10*log10(norm(h_dd(:) - h_true_dd(:))^2 / max(norm(h_true_dd(:))^2, 1e-12));
    else
        nmse_db_out = NaN;
    end
    path_det_out = path_info.num_paths / length(delay_bins);  % 真径数 = 5

    %% 噪声方差估计 (与 test_otfs_timevarying 一致) %%
    nv_dd = max(noise_var, 1e-8);
    if strcmp(pilot_mode, 'impulse')
        detected_dl = unique(path_info.delay_idx);
        noise_mask = false(N, M);
        for dk_n = -pilot_config.guard_k:pilot_config.guard_k
            for dl_n = 0:pilot_config.guard_l
                if ~ismember(dl_n, detected_dl)
                    kk_n = mod(pk_pos-1+dk_n, N)+1;
                    ll_n = mod(pl_pos-1+dl_n, M)+1;
                    noise_mask(kk_n, ll_n) = true;
                end
            end
        end
        if any(noise_mask(:))
            nv_dd = max(mean(abs(Y_dd(noise_mask)).^2), 1e-8);
        end
    end

    %% Pilot 贡献去除 %%
    Y_dd_eq = Y_dd;
    switch pilot_mode
        case 'impulse'
            for pp_r = 1:path_info.num_paths
                kk_r = mod(pk_pos-1+path_info.doppler_idx(pp_r), N)+1;
                ll_r = mod(pl_pos-1+path_info.delay_idx(pp_r), M)+1;
                Y_dd_eq(kk_r, ll_r) = Y_dd_eq(kk_r, ll_r) - path_info.gain(pp_r) * pv_val;
            end
        case 'sequence'
            for pp_r = 1:path_info.num_paths
                dl_p = path_info.delay_idx(pp_r);
                dk_p = path_info.doppler_idx(pp_r);
                for pc_i = 1:size(pilot_info.positions, 1)
                    pk_c = pilot_info.positions(pc_i, 1);
                    pl_c = pilot_info.positions(pc_i, 2);
                    pv_c = pilot_info.values(pc_i);
                    kk_r = mod(pk_c-1+dk_p, N)+1;
                    ll_r = mod(pl_c-1+dl_p, M)+1;
                    Y_dd_eq(kk_r, ll_r) = Y_dd_eq(kk_r, ll_r) - path_info.gain(pp_r) * pv_c;
                end
            end
        case 'superimposed'
            h_origin = zeros(N, M);
            for p_idx = 1:path_info.num_paths
                dk_p = path_info.doppler_idx(p_idx);
                dl_p = path_info.delay_idx(p_idx);
                kk_o = mod(dk_p, N) + 1;
                ll_o = mod(dl_p, M) + 1;
                h_origin(kk_o, ll_o) = path_info.gain(p_idx);
            end
            Y_pilot_contrib = ifft2(fft2(pilot_info.pilot_pattern) .* fft2(h_origin));
            Y_dd_eq = Y_dd - Y_pilot_contrib;
    end

    %% Turbo: LMMSE + BCJR (3 轮) %%
    prior_mean = [];
    prior_var = [];
    ber_out = 1.0;
    for turbo_iter = 1:num_turbo
        [x_hat, ~, x_mean, eq_info] = eq_otfs_lmmse(Y_dd_eq, h_dd, path_info, N, M, ...
            nv_dd, 1, constellation, prior_mean, prior_var); %#ok<ASGLU>

        x_data_soft = x_mean(data_indices);
        nv_llr = max(eq_info.nv_post, 1e-8);
        LLR_eq = zeros(1, M_coded);
        for k = 1:N_data_slots
            LLR_eq(2*k-1) = -2*sqrt(2)*real(x_data_soft(k)) / nv_llr;
            LLR_eq(2*k)   = -2*sqrt(2)*imag(x_data_soft(k)) / nv_llr;
        end
        LLR_eq = max(min(LLR_eq, 30), -30);

        LLR_coded = random_deinterleave(LLR_eq, perm);
        [~, Lp_info, Lp_coded] = siso_decode_conv(LLR_coded, [], ...
            codec.gen_polys, codec.constraint_len, codec.decode_mode);
        bits_out = double(Lp_info > 0);
        nc = min(length(bits_out), N_info);
        ber_out = mean(bits_out(1:nc) ~= info_bits(1:nc));

        if turbo_iter < num_turbo
            Lp_coded_inter = random_interleave(Lp_coded, codec.interleave_seed);
            if length(Lp_coded_inter) < M_coded
                Lp_coded_inter = [Lp_coded_inter, zeros(1, M_coded - length(Lp_coded_inter))];
            else
                Lp_coded_inter = Lp_coded_inter(1:M_coded);
            end
            [x_bar, var_x] = soft_mapper(Lp_coded_inter, 'qpsk');
            var_x = max(var_x, nv_dd);
            prior_mean = zeros(N, M);
            prior_var = var_x * ones(N, M);
            n_fill = min(length(x_bar), N_data_slots);
            prior_mean(data_indices(1:n_fill)) = x_bar(1:n_fill);
        end
    end
end
