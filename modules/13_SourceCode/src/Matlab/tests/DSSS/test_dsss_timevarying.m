%% test_dsss_timevarying.m — DSSS通带仿真 时变信道测试
% TX: 编码→BPSK(±1)→dsss_spread(Gold31)→RRC成形(码片率)→上变频→帧组装
%     帧: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|train_chips|data_chips]
% 信道: 等效基带帧→gen_uwa_channel(5径+Jakes+多普勒)→上变频→+实噪声
% RX: 下变频→LFM粗估α→精补偿→LFM定时→RRC匹配→训练估信道→Rake(MRC)→译码
% 版本：V1.1.0 — 加 benchmark_mode 注入（spec 2026-04-19-e2e-timevarying-baseline）

%% ========== Benchmark mode 注入（2026-04-19） ========== %%
if ~exist('benchmark_mode','var') || isempty(benchmark_mode)
    benchmark_mode = false;
end
if ~benchmark_mode
    clc; close all;
end
fprintf('========================================\n');
fprintf('  DSSS 通带仿真 — 时变信道测试 V1.1\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

%% ========== 参数 ========== %%
chip_rate = 6000; sps = 8; fs = chip_rate*sps; fc = 12000;
rolloff = 0.35; span_rrc = 6;

% 扩频
L = 31;
spread_code = gen_gold_code(5, 0);
spread_code_pm = 2*spread_code - 1;
dsss_sym_rate = chip_rate / L;

% 编解码
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;

% 数据
N_info = 500;
M_coded = n_code * (N_info + mem);
N_dsss_sym = M_coded + 1;             % DBPSK: +1参考符号
N_data_chips = N_dsss_sym * L;
train_sym = 100;
train_chips = train_sym * L;

% 5径信道 (max_delay=8 < L=31, 无ISI)
chip_delays = [0, 1, 3, 5, 8];
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

% 通信速率
code_rate = 1/n_code;
info_rate_bps = dsss_sym_rate * 1 * code_rate;

%% ========== 帧参数 ========== %%
bw = chip_rate * (1 + rolloff);
preamble_dur = 0.05;
f_lo = fc - bw/2; f_hi = fc + bw/2;

[HFM_pb, ~] = gen_hfm(fs, preamble_dur, f_lo, f_hi);
N_preamble = length(HFM_pb);
t_pre = (0:N_preamble-1)/fs;

f0=f_lo; f1=f_hi; T_pre=preamble_dur;
if abs(f1-f0)<1e-6, phase_hfm=2*pi*f0*t_pre;
else, k_hfm=f0*f1*T_pre/(f1-f0); phase_hfm=-2*pi*k_hfm*log(1-(f1-f0)/f1*t_pre/T_pre); end
HFM_bb = exp(1j*(phase_hfm - 2*pi*fc*t_pre));

if abs(f1-f0)<1e-6, phase_hfm_neg=2*pi*f1*t_pre;
else, k_neg=f1*f0*T_pre/(f0-f1); phase_hfm_neg=-2*pi*k_neg*log(1-(f0-f1)/f0*t_pre/T_pre); end
HFM_bb_neg = exp(1j*(phase_hfm_neg - 2*pi*fc*t_pre));

chirp_rate_lfm = (f_hi-f_lo)/preamble_dur;
phase_lfm = 2*pi*(f_lo*t_pre + 0.5*chirp_rate_lfm*t_pre.^2);
LFM_bb = exp(1j*(phase_lfm - 2*pi*fc*t_pre));
% 【P1 2026-04-21】LFM- 基带版本（down-chirp，激活 est_alpha_dual_chirp）
phase_lfm_neg = 2*pi*(f_hi*t_pre - 0.5*chirp_rate_lfm*t_pre.^2);
LFM_bb_neg = exp(1j*(phase_lfm_neg - 2*pi*fc*t_pre));
N_lfm = length(LFM_bb);
% 【P2 2026-04-21】guard 扩展
alpha_max_design = 3e-2;
guard_samp = max(chip_delays)*sps + 80 + ceil(alpha_max_design * max(N_preamble, N_lfm));

% LFM检测标称位置
lfm1_peak_nom = 2*N_preamble + 2*guard_samp + N_lfm;
lfm2_peak_nom = 2*N_preamble + 3*guard_samp + 2*N_lfm;
lfm_search_margin = max(chip_delays)*sps + 200;
T_v_lfm = (N_lfm + guard_samp) / fs;
lfm_data_offset = N_lfm + guard_samp;

snr_list = [-15, -10, -5, 0, 5, 10];
fading_cfgs = {
    'static', 'static', 0,  0;
    'fd=1Hz', 'slow',   1,  1/fc;
    'fd=5Hz', 'slow',   5,  5/fc;
};

%% ========== Benchmark 覆盖（benchmark_mode=true 时生效） ========== %%
if benchmark_mode
    if exist('bench_snr_list','var') && ~isempty(bench_snr_list)
        snr_list = bench_snr_list;
    end
    if exist('bench_fading_cfgs','var') && ~isempty(bench_fading_cfgs)
        fading_cfgs = bench_fading_cfgs;
    end
    if ~exist('bench_channel_profile','var') || isempty(bench_channel_profile)
        bench_channel_profile = 'custom6';
    end
    if ~exist('bench_seed','var') || isempty(bench_seed)
        bench_seed = 42;
    end
    if ~exist('bench_stage','var') || isempty(bench_stage)
        bench_stage = 'A1';
    end
    if ~exist('bench_scheme_name','var') || isempty(bench_scheme_name)
        bench_scheme_name = 'DSSS';
    end
    fprintf('[BENCHMARK] snr_list=%s, fading rows=%d, profile=%s, seed=%d, stage=%s\n', ...
            mat2str(snr_list), size(fading_cfgs,1), ...
            bench_channel_profile, bench_seed, bench_stage);
end

fprintf('通带: fs=%dHz, fc=%dHz, 带宽=%.0fHz\n', fs, fc, bw);
fprintf('DSSS: Gold(%d), L=%d, 码片率=%d, 符号率=%.1f sym/s\n', 5, L, chip_rate, dsss_sym_rate);
fprintf('通信速率: %.1f bps (BPSK, R=1/%d, L=%d)\n', info_rate_bps, n_code, L);
fprintf('信道: %d径, delays=[%s] chips\n', length(chip_delays), num2str(chip_delays));
fprintf('处理增益: %.1f dB\n\n', 10*log10(L));

ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));
ber_unc_matrix = zeros(size(fading_cfgs,1), length(snr_list));
alpha_est_matrix = zeros(size(fading_cfgs,1), length(snr_list));
sync_info_matrix = zeros(size(fading_cfgs,1), 2);

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname=fading_cfgs{fi,1}; ftype=fading_cfgs{fi,2};
    fd_hz=fading_cfgs{fi,3}; dop_rate=fading_cfgs{fi,4};

    %% ===== TX ===== %%
    rng(100+fi);
    training = 2*randi([0,1],1,train_sym) - 1;
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_coded);
    [interleaved, ~] = random_interleave(coded, codec.interleave_seed);

    % DBPSK差分编码: d(k) = b(k) XOR d(k-1), 参考符号d(0)=1
    diff_encoded = zeros(1, M_coded + 1);  % +1 for reference
    diff_encoded(1) = 1;  % reference bit
    for k = 1:M_coded
        diff_encoded(k+1) = xor(interleaved(k), diff_encoded(k));
    end
    data_sym = 2*diff_encoded - 1;  % BPSK: 0→-1, 1→+1

    train_spread = dsss_spread(training, spread_code);
    data_spread = dsss_spread(data_sym, spread_code);
    all_chips = [train_spread, data_spread];
    N_total_chips = length(all_chips);

    [shaped_bb,~,~] = pulse_shape(all_chips, sps, 'rrc', rolloff, span_rrc);
    N_shaped = length(shaped_bb);
    [data_pb,~] = upconvert(shaped_bb, fs, fc);
    data_rms = sqrt(mean(data_pb.^2));
    lfm_scale = data_rms / sqrt(mean(HFM_pb.^2));
    HFM_bb_n = HFM_bb*lfm_scale; HFM_bb_neg_n = HFM_bb_neg*lfm_scale;
    LFM_bb_n = LFM_bb*lfm_scale; LFM_bb_neg_n = LFM_bb_neg*lfm_scale;  % 【P3】

    % 【P3 2026-04-21】帧 LFM2→down
    frame_bb = [HFM_bb_n, zeros(1,guard_samp), HFM_bb_neg_n, zeros(1,guard_samp), ...
                LFM_bb_n, zeros(1,guard_samp), LFM_bb_neg_n, zeros(1,guard_samp), shaped_bb];
    % 【P6 2026-04-21】TX 默认 tail padding
    default_tail_pad = ceil(alpha_max_design * length(frame_bb) * 1.5);
    frame_bb = [frame_bb, zeros(1, default_tail_pad)];

    %% ===== 信道（固定per fading config）===== %%
    ch_params = struct('fs',fs, 'delay_profile','custom', ...
        'delays_s',chip_delays/chip_rate, 'gains',gains_raw, ...
        'num_paths',length(chip_delays), 'doppler_rate',dop_rate, ...
        'fading_type',ftype, 'fading_fd_hz',fd_hz, ...
        'snr_db',Inf, 'seed',200+fi*100);
    [rx_bb_frame,~] = gen_uwa_channel(frame_bb, ch_params);
    [rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);
    sig_pwr = mean(rx_pb_clean.^2);

    mf_lfm = conj(fliplr(LFM_bb_n));
    lfm2_search_len = min(3*N_preamble + 4*guard_samp + 2*N_lfm, length(rx_bb_frame));

    % ===== 无噪声sync+doppler估计（per fading config, 复用给所有SNR）=====
    [bb_clean,~] = downconvert(rx_pb_clean, fs, fc, bw);
    % 【P4 2026-04-21】双 LFM 时延差法 α 估计 + 迭代 refinement
    if isempty(which('est_alpha_dual_chirp'))
        dop_dir = fullfile(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))), ...
                            '10_DopplerProc','src','Matlab');
        addpath(dop_dir);
    end
    cfg_alpha = struct();
    cfg_alpha.up_start = max(1, lfm1_peak_nom - lfm_search_margin);
    cfg_alpha.up_end   = min(lfm1_peak_nom + lfm_search_margin, length(bb_clean));
    cfg_alpha.dn_start = max(1, lfm2_peak_nom - lfm_search_margin);
    cfg_alpha.dn_end   = min(lfm2_peak_nom + lfm_search_margin, length(bb_clean));
    cfg_alpha.nominal_delta_samples = N_lfm + guard_samp;
    cfg_alpha.use_subsample = true;
    k_chirp = chirp_rate_lfm;
    [alpha_raw, alpha_diag] = est_alpha_dual_chirp(bb_clean, LFM_bb_n, LFM_bb_neg_n, ...
                                                    fs, fc, k_chirp, cfg_alpha);
    alpha_est = -alpha_raw;
    % 迭代 refinement
    if ~exist('bench_alpha_iter','var') || isempty(bench_alpha_iter)
        bench_alpha_iter = 2;
    end
    if bench_alpha_iter > 0 && abs(alpha_est) > 1e-10
        for iter_a = 1:bench_alpha_iter
            bb_iter = comp_resample_spline(bb_clean, alpha_est, fs, 'fast');
            [delta_raw, ~] = est_alpha_dual_chirp(bb_iter, LFM_bb_n, LFM_bb_neg_n, ...
                                                  fs, fc, k_chirp, cfg_alpha);
            alpha_est = alpha_est + (-delta_raw);
        end
    end
    % 【P8】正向大 α 精扫
    if alpha_est > 1.5e-2
        mf_up_tmp = conj(fliplr(LFM_bb_n));
        mf_dn_tmp = conj(fliplr(LFM_bb_neg_n));
        a_candidates = alpha_est + (-2e-3 : 2e-4 : 2e-3);
        best_metric = -inf; best_a = alpha_est;
        for ac = a_candidates
            bb_try = comp_resample_spline(bb_clean, ac, fs, 'fast');
            up_end_t = min(cfg_alpha.up_end, length(bb_try));
            dn_end_t = min(cfg_alpha.dn_end, length(bb_try));
            c_up = abs(filter(mf_up_tmp, 1, bb_try(cfg_alpha.up_start:up_end_t)));
            c_dn = abs(filter(mf_dn_tmp, 1, bb_try(cfg_alpha.dn_start:dn_end_t)));
            m = max(c_up) + max(c_dn);
            if m > best_metric, best_metric = m; best_a = ac; end
        end
        alpha_est = best_a;
    end

    % 【2026-04-22】可选 symbol-level α 跟踪（Sun-2020）
    % 通过 `doppler_track_mode = 'symbol_per_sym'` 启用；默认 'block'（向后兼容）
    if ~exist('doppler_track_mode','var') || isempty(doppler_track_mode)
        doppler_track_mode = 'symbol';   % 默认 'symbol' (均值 resample, 最优)；可切 'block'/'symbol_per_sym'
    end
    alpha_est_block = alpha_est;  % 保留块估计
    alpha_track_sym = [];  % 逐符号 α 序列（symbol mode 下填充）
    if strcmpi(doppler_track_mode, 'symbol') || strcmpi(doppler_track_mode, 'symbol_per_sym')
        if isempty(which('est_alpha_dsss_symbol'))
            addpath(dop_dir);
        end
        % Data 段起始 sample（frame_bb 里从 shaped_bb 开始）
        data_start_sym = 2*N_preamble + 2*N_lfm + 4*guard_samp + 1;
        n_symbols_total = length(all_chips) / L;  % 总 DSSS symbols（含 training）
        frame_cfg_sym = struct('data_start_samples', data_start_sym, 'n_symbols', n_symbols_total);
        track_cfg_sym = struct('alpha_block', alpha_est_block, 'alpha_max', 3e-2, ...
                               'iir_beta', 0.7, 'iir_warmup', 5, 'use_subsample', true);
        [alpha_track_sym, alpha_sym_avg, sym_diag] = est_alpha_dsss_symbol( ...
            bb_clean, spread_code, sps, fs, fc, frame_cfg_sym, track_cfg_sym);
        alpha_est = alpha_sym_avg;  % 用均值 resample (uniform mode)
    end

    corr_clean = filter(mf_lfm, 1, bb_clean);
    p1_idx = alpha_diag.tau_up;
    p2_idx = alpha_diag.tau_dn;
    R1 = corr_clean(p1_idx); R2 = NaN;
    sync_peak = abs(R1) / sum(abs(LFM_bb_n).^2);

    % 精补偿 + LFM精确定时（无噪声）
    if abs(alpha_est) > 1e-10
        bb_comp_clean = comp_resample_spline(bb_clean, alpha_est, fs, 'fast');
    else
        bb_comp_clean = bb_clean;
    end
    % 【P5 2026-04-21】LFM2 定时改用 down-chirp 模板
    mf_lfm_neg = conj(fliplr(LFM_bb_neg_n));
    corr_comp_clean = abs(filter(mf_lfm_neg, 1, bb_comp_clean(1:min(lfm2_search_len,length(bb_comp_clean)))));
    c2_lo = max(1, lfm2_peak_nom - lfm_search_margin);
    c2_hi = min(lfm2_peak_nom + lfm_search_margin, length(corr_comp_clean));
    [~, lfm2_local] = max(corr_comp_clean(c2_lo:c2_hi));
    lfm2_peak_idx = c2_lo + lfm2_local - 1;
    lfm_pos = lfm2_peak_idx - N_lfm + 1;
    sync_info_matrix(fi,:) = [lfm_pos, sync_peak];

    fprintf('%-8s |', fname);

    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300+fi*1000+si*100);
        rx_pb = rx_pb_clean + sqrt(noise_var)*randn(size(rx_pb_clean));

        % 1. 下变频
        [bb_raw,~] = downconvert(rx_pb, fs, fc, bw);

        % 2. 多普勒补偿（复用无噪声估计的alpha_est）
        if abs(alpha_est) > 1e-10
            if strcmpi(doppler_track_mode, 'symbol_per_sym') && ~isempty(alpha_track_sym)
                % 逐符号 resample（Sun-2020 Phase 2）
                bb_comp = comp_resample_piecewise(bb_raw, alpha_est, alpha_track_sym, ...
                    2*N_preamble + 2*N_lfm + 4*guard_samp + 1, L*sps);
            else
                bb_comp = comp_resample_spline(bb_raw, alpha_est, fs, 'fast');
            end
        else
            bb_comp = bb_raw;
        end

        % 5. 数据段提取 + RRC匹配 + 下采样
        ds = lfm_pos + lfm_data_offset;
        de = ds + N_shaped - 1;
        if de > length(bb_comp)
            rx_data_bb = [bb_comp(ds:end), zeros(1, de-length(bb_comp))];
        else
            rx_data_bb = bb_comp(ds:de);
        end
        [rx_filt,~] = match_filter(rx_data_bb, sps, 'rrc', rolloff, span_rrc);

        best_off=0; best_pwr=0;
        for off=0:sps-1
            idx=off+1:sps:length(rx_filt);
            n_check=min(length(idx),train_chips);
            if n_check>=L
                c=abs(sum(rx_filt(idx(1:n_check)).*conj(train_spread(1:n_check))));
                if c>best_pwr, best_pwr=c; best_off=off; end
            end
        end
        rx_chips = rx_filt(best_off+1:sps:end);
        if length(rx_chips)>N_total_chips, rx_chips=rx_chips(1:N_total_chips);
        elseif length(rx_chips)<N_total_chips, rx_chips=[rx_chips,zeros(1,N_total_chips-length(rx_chips))]; end

        % 残余CFO补偿
        if abs(alpha_est) > 1e-10
            cfo_res = alpha_est * fc;
            t_chip = (0:length(rx_chips)-1) / chip_rate;
            rx_chips = rx_chips .* exp(-1j*2*pi*cfo_res*t_chip);
        end

        % 6. 训练段信道估计（Rake finger增益）
        h_est = zeros(1, length(chip_delays));
        for p = 1:length(chip_delays)
            d = chip_delays(p);
            acc = 0;
            for k = 1:train_sym
                cs = (k-1)*L + d + 1; ce = cs + L - 1;
                if ce <= train_chips
                    acc = acc + (sum(rx_chips(cs:ce).*spread_code_pm)/L) * conj(training(k));
                end
            end
            h_est(p) = acc / train_sym;
        end

        % 7. Rake接收（数据段，含参考符号）
        [rake_out,~] = eq_rake(rx_chips, spread_code, chip_delays, h_est, N_dsss_sym, struct('combine','mrc','offset',train_chips));

        % 8. DCD差分检测（不依赖载波相位，抗时变）
        % rake_out: 1x(M_coded+1), 含参考符号
        [dcd_decisions, dcd_diff] = det_dcd(rake_out);
        % dcd_decisions: 1xM_coded, +1/-1
        % +1 = 同相 = bit0, -1 = 反相 = bit1
        bits_dcd = double(dcd_decisions < 0);  % -1→bit1, +1→bit0
        ber_unc = mean(bits_dcd ~= interleaved);

        % 软LLR: 用差分相关实部作为软信息
        nv_diff = max(var(real(dcd_diff)) * 0.5, 1e-6);  % 粗估差分噪声
        LLR_inter = max(min(-real(dcd_diff) / nv_diff, 30), -30);  % 负实部→bit1更可能
        [~,perm] = random_interleave(zeros(1,M_coded), codec.interleave_seed);
        LLR_coded = random_deinterleave(LLR_inter, perm);
        [~,Lp_info,~] = siso_decode_conv(LLR_coded, [], codec.gen_polys, codec.constraint_len, codec.decode_mode);
        bits_out = double(Lp_info > 0);

        nc = min(length(bits_out), N_info);
        ber = mean(bits_out(1:nc) ~= info_bits(1:nc));
        ber_matrix(fi,si) = ber;
        ber_unc_matrix(fi,si) = ber_unc;
        alpha_est_matrix(fi,1) = alpha_est;  % 同一fading config共用
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (lfm=%d, pk=%.3f)\n', sync_info_matrix(fi,1), sync_info_matrix(fi,2));
end

%% ========== Benchmark CSV 写入（benchmark_mode=true 时生效） ========== %%
if benchmark_mode
    bench_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'bench_common');
    addpath(bench_dir);
    if ~exist('bench_csv_path','var') || isempty(bench_csv_path)
        bench_csv_path = fullfile(bench_dir, 'e2e_baseline_unspecified.csv');
    end
    for fi_b = 1:size(fading_cfgs,1)
        for si_b = 1:length(snr_list)
            row = bench_init_row(bench_stage, bench_scheme_name);
            row.profile          = bench_channel_profile;
            row.fd_hz            = fading_cfgs{fi_b, 3};
            row.doppler_rate     = fading_cfgs{fi_b, 4};
            row.snr_db           = snr_list(si_b);
            row.seed             = bench_seed;
            row.ber_coded        = ber_matrix(fi_b, si_b);
            row.ber_uncoded      = ber_unc_matrix(fi_b, si_b);
            row.nmse_db          = NaN;
            row.sync_tau_err     = NaN;
            row.frame_detected   = 1;
            row.turbo_final_iter = NaN;  % DSSS 无 turbo
            row.runtime_s        = NaN;
            bench_append_csv(bench_csv_path, row);
        end
    end
    fprintf('[BENCHMARK] CSV 写入: %s (%d 行)\n', bench_csv_path, ...
            size(fading_cfgs,1) * length(snr_list));
    return;
end

%% ========== 可视化 ========== %%

% --- Figure 1: BER曲线 ---
figure('Position',[50 500 700 450]);
markers = {'o-','s-','d-'}; colors = [0 0.45 0.74; 0.85 0.33 0.1; 0.47 0.67 0.19];
for fi=1:size(fading_cfgs,1)
    semilogy(snr_list, max(ber_matrix(fi,:),1e-5), markers{fi}, ...
        'Color',colors(fi,:), 'LineWidth',1.8, 'MarkerSize',7, ...
        'DisplayName', fading_cfgs{fi,1});
    hold on;
end
snr_lin=10.^(snr_list/10);
semilogy(snr_list,max(0.5*erfc(sqrt(snr_lin)),1e-5),'k--','LineWidth',1,'DisplayName','BPSK AWGN');
semilogy(snr_list,max(0.5*erfc(sqrt(snr_lin*L)),1e-5),'g-.','LineWidth',1,...
    'DisplayName',sprintf('BPSK+PG(%ddB)', round(10*log10(L))));
grid on; xlabel('SNR (dB)'); ylabel('BER');
title(sprintf('DSSS Gold(%d) Rake(MRC) — %.1f bps (BPSK, R=1/%d, L=%d)', L, info_rate_bps, n_code, L));
legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);

% --- Figure 2: TX通带帧波形 + 频谱 ---
[frame_pb_vis,~] = upconvert(frame_bb, fs, fc);
figure('Position',[50 350 900 500]);
subplot(2,1,1);
t_frame=(0:length(frame_pb_vis)-1)/fs*1000;
plot(t_frame, frame_pb_vis, 'b', 'LineWidth',0.3);
xlabel('时间 (ms)'); ylabel('幅度'); grid on;
title(sprintf('TX通带帧 (fc=%dHz, %.1fms, %.1f bps)', fc, t_frame(end), info_rate_bps));
subplot(2,1,2);
Nfft_v=2^nextpow2(length(frame_pb_vis));
F_tx=fft(frame_pb_vis,Nfft_v);
f_ax=(0:Nfft_v-1)*fs/Nfft_v/1000;
plot(f_ax(1:Nfft_v/2),20*log10(abs(F_tx(1:Nfft_v/2))+1e-10),'b','LineWidth',0.8);
xlabel('频率 (kHz)'); ylabel('幅度 (dB)'); grid on; title('TX通带频谱');
xlim([0 fs/2/1000]); xline(fc/1000,'r--'); xline((fc-bw/2)/1000,'m--'); xline((fc+bw/2)/1000,'m--');

% --- Figure 3: RX波形 + 频谱 (最后SNR) ---
figure('Position',[50 50 900 500]);
subplot(2,1,1); t_rx=(0:length(rx_pb)-1)/fs*1000;
plot(t_rx, rx_pb, 'b', 'LineWidth',0.3);
xlabel('时间 (ms)'); ylabel('幅度'); grid on;
title(sprintf('RX通带 (SNR=%ddB, %s)', snr_list(end), fading_cfgs{end,1}));
subplot(2,1,2);
Nfft_r=2^nextpow2(length(rx_pb)); F_rx=fft(rx_pb,Nfft_r);
f_rx=(0:Nfft_r-1)*fs/Nfft_r/1000;
plot(f_rx(1:Nfft_r/2),20*log10(abs(F_rx(1:Nfft_r/2))+1e-10),'b','LineWidth',0.8);
xlabel('频率 (kHz)'); ylabel('幅度 (dB)'); grid on; title('RX通带频谱');
xlim([0 fs/2/1000]); xline(fc/1000,'r--'); xline((fc-bw/2)/1000,'m--'); xline((fc+bw/2)/1000,'m--');

% --- Figure 4: 信道CIR ---
figure('Position',[770 400 400 300]);
stem(chip_delays, abs(gains), 'filled', 'LineWidth',1.5);
xlabel('延迟 (chips)'); ylabel('|h|');
title(sprintf('信道CIR (%d径)', length(chip_delays))); grid on;

fprintf('\n--- 同步信息 ---\n');
lfm_expected = lfm2_peak_nom - N_lfm + 1;
for fi=1:size(fading_cfgs,1)
    fprintf('%-8s: lfm_pos=%d (expected~%d), peak=%.3f\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), lfm_expected, sync_info_matrix(fi,2));
end

fprintf('\n--- 多普勒估计 (SNR=%ddB) ---\n', snr_list(1));
for fi=1:size(fading_cfgs,1)
    at = fading_cfgs{fi,4};
    if abs(at)<1e-10, fprintf('%-8s: -\n', fading_cfgs{fi,1});
    else, fprintf('%-8s: est=%.2e, true=%.2e, err=%.1f%%\n', fading_cfgs{fi,1}, ...
        alpha_est_matrix(fi,1), at, abs(alpha_est_matrix(fi,1)-at)/abs(at)*100); end
end

fprintf('\n完成\n');

%% ========== 保存结果 ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_dsss_timevarying_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'DSSS 时变信道测试结果 V1.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'DSSS: Gold(%d), L=%d, chip_rate=%d, sym_rate=%.1f\n', 5, L, chip_rate, dsss_sym_rate);
fprintf(fid, '通信速率: %.1f bps (BPSK, R=1/%d, L=%d)\n', info_rate_bps, n_code, L);
fprintf(fid, '信道: %d径, delays=[%s], max_delay=%d\n', length(chip_delays), num2str(chip_delays), max(chip_delays));
fprintf(fid, '处理增益: %.1f dB, Rake: %d fingers MRC\n\n', 10*log10(L), length(chip_delays));

fprintf(fid, '=== BER (coded) ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

fprintf(fid, '\n=== BER (uncoded) ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_unc_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

fprintf(fid, '\n=== 同步 + 多普勒 ===\n');
for fi=1:size(fading_cfgs,1)
    at = fading_cfgs{fi,4};
    fprintf(fid, '%-8s: lfm_pos=%d, alpha_est=%.4e, alpha_true=%.4e\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), alpha_est_matrix(fi,1), at);
end
fclose(fid);
fprintf('结果已保存: %s\n', result_file);
