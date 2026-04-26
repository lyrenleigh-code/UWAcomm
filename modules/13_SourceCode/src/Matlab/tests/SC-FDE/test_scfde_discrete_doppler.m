%% test_scfde_discrete_doppler.m — SC-FDE 离散Doppler/混合Rician信道对比
% TX: 编码→交织→QPSK→分块+CP→拼接→09 RRC成形
%     帧组装: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]
% 信道: apply_channel(离散Doppler/Rician混合/Jakes) — 等效基带
% RX: 09下变频 → ①双LFM相位→alpha估计 → ②CP精估 → ③resample补偿 →
%     ④LFM精确定时 → 提取数据 → 09 RRC匹配 → 分块去CP+FFT →
%     BEM(DCT)信道估计 + 跨块Turbo均衡(LMMSE-IC+BCJR+DD)
% 版本: V1.1.0 — 加 benchmark_mode 注入（spec 2026-04-19-e2e-timevarying-baseline）
% 目的: 验证SC-FDE在离散Doppler/Rician混合信道下是否显著优于Jakes连续谱
%
% ⚠ OFFLINE ORACLE BASELINE（2026-04-24 audit 声明 / 2026-04-26 Phase 3b.4 决议）
%   本脚本保留 oracle 参考（sps/GAMP/BEM 观测矩阵均用 all_cp_data），用于离散
%   Doppler/Rician 信道对比基准。非 production path，不在 E2E benchmark 主路径
%   （benchmark_e2e_baseline.m 只调 timevarying runner）。
%   Production 去 oracle 版本: 14_Streaming/rx/modem_decode_scfde.m
%   架构迁移版本: test_scfde_timevarying.m V2.2+ (Phase 1/2/3b.2，commit c8ccb06)
%
%   Phase 3b.4 决议（2026-04-26）：决定**不迁移** discrete_doppler 架构。
%   A1 验证（diag_a1_streaming_decoder_jakes.m）证 14_Streaming production
%   decoder 在 jakes fd=1Hz 也 ~50%（架构 trade-off，非实现 bug）。
%   discrete_doppler 同样单训练块 + 时变信道 → 迁移会重现 50% 灾难，
%   反而失去 oracle baseline 对比基准。
%   后续若需协议层改动（多训练块/导频 superimposed/超训练块）→ 开新 spec。
%   CLAUDE.md §2 白名单允许 benchmark baseline 保留 oracle 作算法对比基准。

%% ========== Benchmark mode 注入（2026-04-19） ========== %%
if ~exist('benchmark_mode','var') || isempty(benchmark_mode)
    benchmark_mode = false;
end
if ~benchmark_mode
    clc; close all;
end
fprintf('========================================\n');
fprintf('  SC-FDE 离散Doppler信道对比 V1.1\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

%% ========== 系统参数 ========== %%
sps = 8; sym_rate = 6000; fs = sym_rate * sps; fc = 12000;
rolloff = 0.35; span = 6;
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7);
n_code = 2; mem = codec.constraint_len - 1;

% 6径信道（同test_scfde_timevarying）
sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));
delay_samp = sym_delays * sps;   % 样本级时延 @fs=48kHz
K_sparse = length(sym_delays);
L_h = max(sym_delays) + 1;

% 每径Doppler频移 (对应6径)
doppler_per_path = [0, 3, -4, 5, -2, 1];  % Hz

%% ========== 帧参数（HFM/LFM前导码）========== %%
bw_lfm = sym_rate * (1 + rolloff);
preamble_dur = 0.05;
f_lo = fc - bw_lfm/2;  f_hi = fc + bw_lfm/2;
[HFM_pb, ~] = gen_hfm(fs, preamble_dur, f_lo, f_hi);
N_preamble = length(HFM_pb);
t_pre = (0:N_preamble-1) / fs;

% HFM基带（正扫频 f_lo→f_hi）
f0 = f_lo; f1 = f_hi; T_pre = preamble_dur;
if abs(f1-f0) < 1e-6, phase_hfm = 2*pi*f0*t_pre;
else, k_hfm = f0*f1*T_pre/(f1-f0); phase_hfm = -2*pi*k_hfm*log(1-(f1-f0)/f1*t_pre/T_pre); end
HFM_bb = exp(1j*(phase_hfm - 2*pi*fc*t_pre));

% HFM-基带（负扫频 f_hi→f_lo）
if abs(f1-f0) < 1e-6, phase_hfm_neg = 2*pi*f1*t_pre;
else, k_neg = f1*f0*T_pre/(f0-f1); phase_hfm_neg = -2*pi*k_neg*log(1-(f0-f1)/f0*t_pre/T_pre); end
HFM_bb_neg = exp(1j*(phase_hfm_neg - 2*pi*fc*t_pre));

% LFM基带
chirp_rate_lfm = (f_hi - f_lo) / preamble_dur;
phase_lfm = 2*pi * (f_lo * t_pre + 0.5 * chirp_rate_lfm * t_pre.^2);
LFM_bb = exp(1j*(phase_lfm - 2*pi*fc*t_pre));
% LFM- 基带版本（down-chirp，激活 est_alpha_dual_chirp）—— 2026-04-20 spec dual-chirp-refinement
chirp_rate_lfm = (f_hi - f_lo) / preamble_dur;
phase_lfm_neg = 2*pi * (f_hi * t_pre - 0.5 * chirp_rate_lfm * t_pre.^2);
LFM_bb_neg = exp(1j*(phase_lfm_neg - 2*pi*fc*t_pre));
N_lfm = length(LFM_bb);
% guard 扩展：容纳 α=3e-2 下 LFM peak 漂移 —— 2026-04-20 dual-chirp 改造
alpha_max_design = 3e-2;
guard_samp = max(sym_delays) * sps + 80 + ceil(alpha_max_design * max(N_preamble, N_lfm));

%% ========== 信道配置（6种，对标OTFS V2.0）========== %%
% {名称, 信道类型, 参数, blk_fft, blk_cp, N_blocks, fd_hz_bem}
fading_cfgs = {
    'static',   'static',   zeros(1,6), ...
                            1024, 128,  4,  0;
    'disc-5Hz', 'discrete', doppler_per_path, ...
                            128,  128, 32,  5;
    'hyb-K20',  'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',0.5, 'K_rice',20), ...
                            128,  128, 32,  5;
    'hyb-K10',  'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',0.5, 'K_rice',10), ...
                            128,  128, 32,  5;
    'hyb-K5',   'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',1.0, 'K_rice',5), ...
                            128,  128, 32,  5;
    'jakes5Hz', 'jakes',    5, ...
                            128,  128, 32,  5;
};

snr_list = [0, 5, 10, 15, 20];

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
        bench_stage = 'B';
    end
    if ~exist('bench_scheme_name','var') || isempty(bench_scheme_name)
        bench_scheme_name = 'SC-FDE';
    end
    fprintf('[BENCHMARK] snr_list=%s, fading rows=%d, stage=%s\n', ...
            mat2str(snr_list), size(fading_cfgs,1), bench_stage);
end

fprintf('通带: fs=%dHz, fc=%dHz, sps=%d, HFM/LFM=%.0f~%.0fHz\n', fs, fc, sps, f_lo, f_hi);
fprintf('帧: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]\n');
fprintf('信道: 6径, delays=[%s] sym, max=%.1fms\n', num2str(sym_delays), max(sym_delays)/sym_rate*1000);
fprintf('每径Doppler: [%s] Hz\n', num2str(doppler_per_path));
fprintf('RX: ①LFM相位→alpha ②CP精估 ③resample ④LFM定时 ⑤BEM+Turbo\n\n');

%% ========== 主循环 ========== %%
N_fading = size(fading_cfgs, 1);
ber_matrix = zeros(N_fading, length(snr_list));
alpha_est_matrix = zeros(N_fading, length(snr_list));
sync_info_matrix = zeros(N_fading, 2);
H_est_blocks_save = cell(1, N_fading);
info_rate_save = zeros(1, N_fading);
% 可视化保存
snr_vis_idx = find(snr_list == 10, 1);
if isempty(snr_vis_idx), snr_vis_idx = 3; end
frame_bb_save = [];       % TX基带帧（代表性config）
frame_pb_save = [];       % TX通带帧
rx_pb_save = [];          % RX通带信号
rx_bb_save = [];          % RX基带信号
eq_sym_save = cell(N_fading, 1);  % 均衡后星座
tx_sym_save = [];         % TX符号（参考）
vis_fi = 2;               % 可视化用的fading index (disc-5Hz)

fprintf('%-8s |', '');
for si = 1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-', 1, 8+8*length(snr_list)));

for fi = 1:N_fading
    fname   = fading_cfgs{fi,1};
    ftype   = fading_cfgs{fi,2};
    fparams = fading_cfgs{fi,3};
    blk_fft = fading_cfgs{fi,4};
    blk_cp  = fading_cfgs{fi,5};
    N_blocks = fading_cfgs{fi,6};
    fd_hz   = fading_cfgs{fi,7};
    sym_per_block = blk_cp + blk_fft;

    M_per_blk = 2 * blk_fft;
    M_total = M_per_blk * N_blocks;
    N_info = M_total / n_code - mem;
    N_total_sym = N_blocks * sym_per_block;

    %% ===== TX（固定，不随SNR变）===== %%
    rng(100 + fi);
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_total);
    [inter_all, perm_all] = random_interleave(coded, codec.interleave_seed);
    sym_all = bits2qpsk(inter_all);

    all_cp_data = zeros(1, N_total_sym);
    for bi = 1:N_blocks
        data_sym = sym_all((bi-1)*blk_fft+1 : bi*blk_fft);
        x_cp = [data_sym(end-blk_cp+1:end), data_sym];
        all_cp_data((bi-1)*sym_per_block+1 : bi*sym_per_block) = x_cp;
    end

    [shaped_bb, ~, ~] = pulse_shape(all_cp_data, sps, 'rrc', rolloff, span);
    N_shaped = length(shaped_bb);
    [data_pb, ~] = upconvert(shaped_bb, fs, fc);

    % 功率归一化（HFM/LFM匹配数据段RMS）
    data_rms = sqrt(mean(data_pb.^2));
    lfm_scale = data_rms / sqrt(mean(HFM_pb.^2));
    HFM_bb_n = HFM_bb * lfm_scale;
    HFM_bb_neg_n = HFM_bb_neg * lfm_scale;
    LFM_bb_n = LFM_bb * lfm_scale;
    LFM_bb_neg_n = LFM_bb_neg * lfm_scale;

    % 帧组装: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]
    % 2026-04-20：LFM2 改 down-chirp
    frame_bb = [HFM_bb_n, zeros(1,guard_samp), HFM_bb_neg_n, zeros(1,guard_samp), ...
                LFM_bb_n, zeros(1,guard_samp), LFM_bb_neg_n, zeros(1,guard_samp), shaped_bb];
    T_v_lfm = (N_lfm + guard_samp) / fs;  % LFM1头→LFM2头间隔(秒)
    lfm_data_offset = N_lfm + guard_samp;  % LFM2头→data头

    % 通信速率
    T_frame_s = length(frame_bb) / fs;
    info_rate_bps = N_info / T_frame_s;
    info_rate_save(fi) = info_rate_bps;

    % 保存帧数据（用于可视化）
    if fi == vis_fi
        frame_bb_save = frame_bb;
        [frame_pb_save, ~] = upconvert(frame_bb, fs, fc);
        tx_sym_save = sym_all;
    end

    %% ===== 信道（固定，不随SNR变）===== %%
    rx_bb_frame = apply_channel(frame_bb, delay_samp, gains_raw, ftype, fparams, fs, fc);

    [rx_pb_clean, ~] = upconvert(rx_bb_frame, fs, fc);
    sig_pwr = mean(rx_pb_clean.^2);

    fprintf('%-8s |', fname);

    %% ===== SNR循环 ===== %%
    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300 + fi*1000 + si*100);
        rx_pb = rx_pb_clean + sqrt(noise_var) * randn(size(rx_pb_clean));

        % 保存RX通带（可视化用）
        if fi == vis_fi && si == snr_vis_idx
            rx_pb_save = rx_pb;
        end

        % 1. 下变频
        [bb_raw, ~] = downconvert(rx_pb, fs, fc, bw_lfm);

        % 2. 双 LFM（up+down）时延差法 α 估计 —— 2026-04-20 dual-chirp 改造
        mf_lfm = conj(fliplr(LFM_bb_n));
        lfm2_search_len = min(3*N_preamble + 4*guard_samp + 2*N_lfm, length(bb_raw));
        lfm2_start = 2*N_preamble + 2*guard_samp + N_lfm + 1;
        lfm1_search_start = 2*N_preamble + 2*guard_samp + 1;
        lfm1_end = 2*N_preamble + 2*guard_samp + N_lfm + guard_samp;
        if isempty(which('est_alpha_dual_chirp'))
            dop_dir = fullfile(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))), ...
                                '10_DopplerProc','src','Matlab');
            addpath(dop_dir);
        end
        cfg_alpha = struct();
        cfg_alpha.up_start = lfm1_search_start;
        cfg_alpha.up_end   = lfm1_end;
        cfg_alpha.dn_start = lfm2_start;
        cfg_alpha.dn_end   = min(lfm2_search_len, length(bb_raw));
        cfg_alpha.nominal_delta_samples = N_lfm + guard_samp;
        cfg_alpha.use_subsample = true;
        cfg_alpha.sign_convention = 'uwa-channel';   % V1.1: 内部取反号
        k_chirp = chirp_rate_lfm;
        [alpha_lfm, alpha_diag] = est_alpha_dual_chirp(bb_raw, LFM_bb_n, LFM_bb_neg_n, ...
                                                      fs, fc, k_chirp, cfg_alpha);
        % R1/p1_idx/p2_idx 保留旧变量名（下游 sync/BEM 使用）
        corr_est = filter(mf_lfm, 1, bb_raw);
        corr_est_abs = abs(corr_est);
        p1_idx = alpha_diag.tau_up;
        p2_idx = alpha_diag.tau_dn;
        R1 = corr_est(p1_idx);
        R2 = NaN;
        T_v_samp = round(T_v_lfm * fs);
        sync_peak = abs(R1) / sum(abs(LFM_bb_n).^2);

        % 3. 粗补偿+CP精估
        if abs(alpha_lfm) > 1e-10
            bb_comp1 = comp_resample_spline(bb_raw, alpha_lfm, fs, 'fast');
        else
            bb_comp1 = bb_raw;
        end
        % LFM2 是 down-chirp，用 mf_lfm_neg 找 peak
        mf_lfm_neg = conj(fliplr(LFM_bb_neg_n));
        corr_c1 = abs(filter(mf_lfm_neg, 1, bb_comp1(1:min(lfm2_search_len,length(bb_comp1)))));
        [~, l1] = max(corr_c1(lfm2_start:end));
        lp1 = lfm2_start + l1 - 1 - N_lfm + 1;
        d1 = lp1 + lfm_data_offset; e1 = d1 + N_shaped - 1;
        if e1 > length(bb_comp1), rd1 = [bb_comp1(d1:end), zeros(1,e1-length(bb_comp1))];
        else, rd1 = bb_comp1(d1:e1); end
        [rf1, ~] = match_filter(rd1, sps, 'rrc', rolloff, span);
        b1 = 0; bp1 = 0;
        for off = 0:sps-1
            st = rf1(off+1:sps:end);
            if length(st) >= 10, c = abs(sum(st(1:10).*conj(all_cp_data(1:10))));
                if c > bp1, bp1 = c; b1 = off; end, end
        end
        rc = rf1(b1+1:sps:end);
        if length(rc) > N_total_sym, rc = rc(1:N_total_sym);
        elseif length(rc) < N_total_sym, rc = [rc, zeros(1,N_total_sym-length(rc))]; end
        Rcp = 0;
        for bi2 = 1:N_blocks
            bs2 = (bi2-1)*sym_per_block;
            Rcp = Rcp + sum(rc(bs2+1:bs2+blk_cp) .* conj(rc(bs2+blk_fft+1:bi2*sym_per_block)));
        end
        alpha_cp = angle(Rcp) / (2*pi*fc*blk_fft/sym_rate);
        alpha_est = alpha_lfm + alpha_cp;

        % 4. 精补偿 + LFM精确定时
        if abs(alpha_est) > 1e-10
            bb_comp = comp_resample_spline(bb_raw, alpha_est, fs, 'fast');
        else
            bb_comp = bb_raw;
        end
        corr_lfm_comp = abs(filter(mf_lfm, 1, bb_comp(1:min(lfm2_search_len,length(bb_comp)))));
        [~, lfm2_local] = max(corr_lfm_comp(lfm2_start:end));
        lfm2_peak_idx = lfm2_start + lfm2_local - 1;
        lfm_pos = lfm2_peak_idx - N_lfm + 1;
        sync_offset_sym = 0;
        phase_ramp_frac = ones(1, blk_fft);

        if si == 1, sync_info_matrix(fi,:) = [lfm_pos, sync_peak]; end

        % 5. 数据提取 + 匹配滤波
        ds = lfm_pos + lfm_data_offset;
        de = ds + N_shaped - 1;
        if de > length(bb_comp), rx_data_bb = [bb_comp(ds:end), zeros(1,de-length(bb_comp))];
        else, rx_data_bb = bb_comp(ds:de); end
        [rx_filt, ~] = match_filter(rx_data_bb, sps, 'rrc', rolloff, span);
        best_off = 0; best_pwr = 0;
        for off = 0:sps-1
            st = rx_filt(off+1:sps:end);
            if length(st) >= 10, c = abs(sum(st(1:10).*conj(all_cp_data(1:10))));
                if c > best_pwr, best_pwr = c; best_off = off; end, end
        end
        rx_sym_all = rx_filt(best_off+1:sps:end);
        if length(rx_sym_all) > N_total_sym, rx_sym_all = rx_sym_all(1:N_total_sym);
        elseif length(rx_sym_all) < N_total_sym, rx_sym_all = [rx_sym_all, zeros(1,N_total_sym-length(rx_sym_all))]; end

        % 6. 信道估计
        nv_eq = max(noise_var, 1e-10);
        eff_delays = mod(sym_delays - sync_offset_sym, blk_fft);

        if strcmpi(ftype, 'static')
            % 静态: GAMP（用第1块CP段）
            usable = blk_cp;
            T_mat = zeros(usable, L_h);
            tx_blk1 = all_cp_data(1:sym_per_block);
            for col = 1:L_h
                for row = col:usable, T_mat(row, col) = tx_blk1(row - col + 1); end
            end
            y_train = rx_sym_all(1:usable).';
            [h_gamp_vec, ~] = ch_est_gamp(y_train, T_mat, L_h, 50, nv_eq);
            h_td_est = zeros(1, blk_fft);
            for p = 1:K_sparse
                if sym_delays(p)+1 <= L_h
                    h_td_est(eff_delays(p)+1) = h_gamp_vec(sym_delays(p)+1);
                end
            end
            H_est_blocks = cell(1, N_blocks);
            for bi = 1:N_blocks
                H_est_blocks{bi} = fft(h_td_est) .* phase_ramp_frac;
            end
        else
            % 时变: BEM(DCT)跨块估计（每块CP段作导频）
            obs_y = []; obs_x = []; obs_n = [];
            for bi = 1:N_blocks
                blk_start = (bi-1) * sym_per_block;
                for kk = max(sym_delays)+1 : blk_cp
                    n = blk_start + kk;
                    x_vec = zeros(1, K_sparse);
                    for pp = 1:K_sparse
                        idx = n - sym_delays(pp);
                        if idx >= 1 && idx <= N_total_sym
                            x_vec(pp) = all_cp_data(idx);
                        end
                    end
                    if any(x_vec ~= 0) && n <= length(rx_sym_all)
                        obs_y(end+1) = rx_sym_all(n);
                        obs_x = [obs_x; x_vec];
                        obs_n(end+1) = n;
                    end
                end
            end
            bem_opts = struct('Q_mode', 'auto', 'lambda_scale', 1.0);
            [h_tv_bem, ~, bem_info] = ch_est_bem(obs_y(:), obs_x, obs_n(:), N_total_sym, ...
                sym_delays, fd_hz, sym_rate, nv_eq, 'dct', bem_opts);
            H_est_blocks = cell(1, N_blocks);
            for bi = 1:N_blocks
                blk_mid = (bi-1)*sym_per_block + round(sym_per_block/2);
                blk_mid = max(1, min(blk_mid, N_total_sym));
                h_td_est = zeros(1, blk_fft);
                for p = 1:K_sparse
                    h_td_est(eff_delays(p)+1) = h_tv_bem(p, blk_mid);
                end
                H_est_blocks{bi} = fft(h_td_est) .* phase_ramp_frac;
            end
        end
        if si == 1, H_est_blocks_save{fi} = H_est_blocks{1}; end

        % 保存BEM时变输出（用于ICI-aware均衡）
        if exist('h_tv_bem', 'var') && fd_hz > 0
            h_tv_cur = h_tv_bem;  % P×N_total_sym
        else
            h_tv_cur = [];  % 静态信道不需要
        end

        % 6b. nv_post: 从CP导频段实测残差方差（防高SNR过度自信）
        nv_post_sum = 0; nv_post_cnt = 0;
        for bi_nv = 1:N_blocks
            blk_start_nv = (bi_nv-1) * sym_per_block;
            h_td_blk = ifft(H_est_blocks{bi_nv});
            for kk = max(sym_delays)+1 : blk_cp
                n_nv = blk_start_nv + kk;
                if n_nv > length(rx_sym_all), break; end
                y_pred = 0;
                for pp = 1:K_sparse
                    idx_nv = n_nv - sym_delays(pp);
                    if idx_nv >= 1 && idx_nv <= N_total_sym
                        y_pred = y_pred + h_td_blk(eff_delays(pp)+1) * all_cp_data(idx_nv);
                    end
                end
                nv_post_sum = nv_post_sum + abs(rx_sym_all(n_nv) - y_pred)^2;
                nv_post_cnt = nv_post_cnt + 1;
            end
        end
        nv_post = nv_post_sum / max(nv_post_cnt, 1);
        nv_eq = max(nv_eq, nv_post);  % 兜底：实测残差 >= 理论噪声

        % 7. 分块去CP + FFT
        Y_freq_blocks = cell(1, N_blocks);
        for bi = 1:N_blocks
            blk_sym = rx_sym_all((bi-1)*sym_per_block+1 : bi*sym_per_block);
            rx_nocp = blk_sym(blk_cp+1:end);
            Y_freq_blocks{bi} = fft(rx_nocp);
        end

        % 8. 跨块Turbo均衡: LMMSE-IC + BCJR + DD信道重估计
        turbo_iter = 6;
        x_bar_blks = cell(1, N_blocks);
        var_x_blks = ones(1, N_blocks);
        H_cur_blocks = H_est_blocks;
        for bi = 1:N_blocks, x_bar_blks{bi} = zeros(1, blk_fft); end
        La_dec_info = [];
        bits_decoded = [];

        % 提取per-block BEM时变信道 (P×blk_fft)
        h_tv_blocks = cell(1, N_blocks);
        if ~isempty(h_tv_cur)
            for bi = 1:N_blocks
                data_start = (bi-1)*sym_per_block + blk_cp + 1;
                data_end = bi * sym_per_block;
                data_end = min(data_end, size(h_tv_cur, 2));
                h_blk = h_tv_cur(:, data_start:data_end);
                % 补齐（防止边界不足）
                if size(h_blk, 2) < blk_fft
                    h_blk = [h_blk, repmat(h_blk(:,end), 1, blk_fft-size(h_blk,2))];
                end
                h_tv_blocks{bi} = h_blk;
            end
        end

        use_ici_eq = ~isempty(h_tv_cur);  % 时变信道用ICI-aware均衡

        for titer = 1:turbo_iter
            LLR_all = zeros(1, M_total);
            for bi = 1:N_blocks
                if use_ici_eq
                    [x_tilde, mu, nv_tilde] = eq_mmse_ic_tv_fde(Y_freq_blocks{bi}, ...
                        h_tv_blocks{bi}, eff_delays, x_bar_blks{bi}, var_x_blks(bi), nv_eq);
                else
                    [x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq_blocks{bi}, ...
                        H_cur_blocks{bi}, x_bar_blks{bi}, var_x_blks(bi), nv_eq);
                end
                Le_eq_blk = soft_demapper(x_tilde, mu, nv_tilde, zeros(1,M_per_blk), 'qpsk');
                LLR_all((bi-1)*M_per_blk+1 : bi*M_per_blk) = Le_eq_blk;
            end
            Le_eq_deint = random_deinterleave(LLR_all, perm_all);
            Le_eq_deint = max(min(Le_eq_deint, 30), -30);
            [~, Lpost_info, Lpost_coded] = siso_decode_conv(...
                Le_eq_deint, La_dec_info, codec.gen_polys, codec.constraint_len);
            bits_decoded = double(Lpost_info > 0);

            if titer < turbo_iter
                Lpost_inter = random_interleave(Lpost_coded, codec.interleave_seed);
                if length(Lpost_inter) < M_total
                    Lpost_inter = [Lpost_inter, zeros(1, M_total-length(Lpost_inter))];
                else
                    Lpost_inter = Lpost_inter(1:M_total);
                end
                % 软符号反馈
                x_bar_td_all = zeros(1, N_total_sym);
                var_x_avg = 0;
                for bi = 1:N_blocks
                    coded_blk = Lpost_inter((bi-1)*M_per_blk+1 : bi*M_per_blk);
                    [x_bar_blks{bi}, var_x_raw] = soft_mapper(coded_blk, 'qpsk');
                    var_x_blks(bi) = max(var_x_raw, nv_eq);
                    var_x_avg = var_x_avg + var_x_blks(bi);
                    blk_s = (bi-1)*sym_per_block;
                    x_bar_td_all(blk_s+blk_cp+1 : bi*sym_per_block) = x_bar_blks{bi};
                    x_bar_td_all(blk_s+1 : blk_s+blk_cp) = x_bar_blks{bi}(end-blk_cp+1:end);
                end
                var_x_avg = var_x_avg / N_blocks;

                % DD-BEM信道重估计 (替代per-block DD-LS，保留时变跟踪能力)
                if titer >= 2 && var_x_avg < 0.4 && fd_hz > 0
                    dd_y = obs_y(:); dd_x = obs_x; dd_n = obs_n(:);  % CP(已知)
                    % 追加置信度高的数据段软符号
                    for bi = 1:N_blocks
                        blk_s = (bi-1)*sym_per_block;
                        if var_x_blks(bi) >= 0.4, continue; end  % 跳过低置信度块
                        for kk = blk_cp+max(sym_delays)+1 : sym_per_block
                            n_dd = blk_s + kk;
                            if n_dd > length(rx_sym_all), break; end
                            xv = zeros(1, K_sparse);
                            for pp = 1:K_sparse
                                idx_dd = n_dd - sym_delays(pp);
                                if idx_dd >= 1 && idx_dd <= N_total_sym
                                    xv(pp) = x_bar_td_all(idx_dd);
                                end
                            end
                            if any(xv ~= 0)
                                dd_y(end+1,1) = rx_sym_all(n_dd);
                                dd_x = [dd_x; xv];
                                dd_n(end+1,1) = n_dd;
                            end
                        end
                    end
                    [h_tv_dd, ~, ~] = ch_est_bem(dd_y, dd_x, dd_n, N_total_sym, ...
                        sym_delays, fd_hz, sym_rate, nv_eq, 'dct', bem_opts);
                    for bi = 1:N_blocks
                        bm = (bi-1)*sym_per_block + round(sym_per_block/2);
                        bm = max(1, min(bm, N_total_sym));
                        h_td_dd = zeros(1, blk_fft);
                        for p = 1:K_sparse
                            h_td_dd(eff_delays(p)+1) = h_tv_dd(p, bm);
                        end
                        H_cur_blocks{bi} = fft(h_td_dd) .* phase_ramp_frac;
                        % 同步刷新ICI-aware per-block信道
                        if use_ici_eq
                            ds_dd = (bi-1)*sym_per_block + blk_cp + 1;
                            de_dd = min(bi*sym_per_block, size(h_tv_dd,2));
                            hb_dd = h_tv_dd(:, ds_dd:de_dd);
                            if size(hb_dd,2) < blk_fft
                                hb_dd = [hb_dd, repmat(hb_dd(:,end),1,blk_fft-size(hb_dd,2))];
                            end
                            h_tv_blocks{bi} = hb_dd;
                        end
                    end
                end
            end
        end

        % 保存均衡后星座（最终Turbo迭代, 可视化用）
        if si == snr_vis_idx
            eq_syms_vis = zeros(1, blk_fft * N_blocks);
            for bi_v = 1:N_blocks
                if use_ici_eq
                    [x_t_v, ~, ~] = eq_mmse_ic_tv_fde(Y_freq_blocks{bi_v}, ...
                        h_tv_blocks{bi_v}, eff_delays, x_bar_blks{bi_v}, var_x_blks(bi_v), nv_eq);
                else
                    [x_t_v, ~, ~] = eq_mmse_ic_fde(Y_freq_blocks{bi_v}, ...
                        H_cur_blocks{bi_v}, x_bar_blks{bi_v}, var_x_blks(bi_v), nv_eq);
                end
                eq_syms_vis((bi_v-1)*blk_fft+1 : bi_v*blk_fft) = x_t_v;
            end
            eq_sym_save{fi} = eq_syms_vis;
        end

        nc = min(length(bits_decoded), N_info);
        ber = mean(bits_decoded(1:nc) ~= info_bits(1:nc));
        ber_matrix(fi, si) = ber;
        alpha_est_matrix(fi, si) = alpha_est;
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (blk=%d, rate=%.0fbps)\n', blk_fft, info_rate_bps);
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
            % profile 记录 "custom6|static/disc-5Hz/..."
            row.profile          = sprintf('%s|%s', bench_channel_profile, fading_cfgs{fi_b,1});
            ch_type = fading_cfgs{fi_b,2};
            if strcmp(ch_type,'jakes') && isnumeric(fading_cfgs{fi_b,3})
                row.fd_hz = fading_cfgs{fi_b,3};
            else
                row.fd_hz = NaN;
            end
            row.doppler_rate     = 0;
            row.snr_db           = snr_list(si_b);
            row.seed             = bench_seed;
            row.ber_coded        = ber_matrix(fi_b, si_b);
            row.ber_uncoded      = NaN;
            row.nmse_db          = NaN;
            row.sync_tau_err     = NaN;
            row.frame_detected   = 1;
            row.turbo_final_iter = 6;
            row.runtime_s        = NaN;
            bench_append_csv(bench_csv_path, row);
        end
    end
    fprintf('[BENCHMARK] CSV 写入: %s (%d 行)\n', bench_csv_path, ...
            size(fading_cfgs,1) * length(snr_list));
    return;
end

%% ========== 同步信息 ========== %%
fprintf('\n--- 同步信息（LFM定时）---\n');
lfm_expected = 2*N_preamble + 3*guard_samp + N_lfm + 1;
for fi = 1:N_fading
    fprintf('%-8s: lfm_pos=%d (expected~%d), peak=%.3f\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), lfm_expected, sync_info_matrix(fi,2));
end

%% ========== 多普勒估计 ========== %%
fprintf('\n--- 多普勒估计 (SNR=%ddB) ---\n', snr_list(1));
for fi = 1:N_fading
    fprintf('%-8s: alpha_est=%.4e (应≈0: 离散Doppler无bulk压缩', ...
        fading_cfgs{fi,1}, alpha_est_matrix(fi,1));
    if strcmpi(fading_cfgs{fi,2}, 'jakes')
        fprintf(', jakes: alpha_true≈%.2e', fading_cfgs{fi,3}/fc);
    end
    fprintf(')\n');
end

%% ========== 信道估计（block1各径）========== %%
fprintf('\n--- H_est block1 各径增益 ---\n');
for fi = 1:N_fading
    blk_fft_fi = fading_cfgs{fi,4};
    eff_d = mod(sym_delays, blk_fft_fi);
    h_td1 = ifft(H_est_blocks_save{fi});
    fprintf('%-8s:', fading_cfgs{fi,1});
    for p = 1:length(sym_delays)
        fprintf(' %.3f<%.0f°', abs(h_td1(eff_d(p)+1)), angle(h_td1(eff_d(p)+1))*180/pi);
    end
    fprintf('\n');
end
fprintf('静态参考:');
for p = 1:length(sym_delays), fprintf(' %.3f', abs(gains(p))); end
fprintf('\n');

%% ========== 可视化 ========== %%
% Figure 1: BER vs SNR（主结果）
figure('Position', [100 400 800 500]);
markers = {'o-','s-','d-','^-','v-','p-'};
colors = lines(N_fading);
for fi = 1:N_fading
    mi = mod(fi-1, length(markers)) + 1;
    semilogy(snr_list, max(ber_matrix(fi,:), 1e-5), markers{mi}, ...
        'Color', colors(fi,:), 'LineWidth', 1.8, 'MarkerSize', 7, ...
        'DisplayName', sprintf('%s(blk=%d)', fading_cfgs{fi,1}, fading_cfgs{fi,4}));
    hold on;
end
snr_lin = 10.^(snr_list/10);
semilogy(snr_list, max(0.5*erfc(sqrt(snr_lin)),1e-5), 'k--', 'LineWidth',1, 'DisplayName','QPSK uncoded');
grid on; xlabel('SNR (dB)'); ylabel('BER');
title(sprintf('SC-FDE 离散Doppler信道对比 (6径, max\\_delay=%.0fms, Turbo=%d轮)', ...
    max(sym_delays)/sym_rate*1000, 6));
legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);
% 通信速率标注
text(snr_list(end)-1, 5e-5, sprintf('info rate: %.0f~%.0f bps', min(info_rate_save), max(info_rate_save)), ...
    'FontSize',10, 'HorizontalAlignment','right');

% Figure 2: 估计信道CIR对比
figure('Position', [100 50 1000 600]);
for fi = 1:N_fading
    blk_fft_fi = fading_cfgs{fi,4};
    eff_d = mod(sym_delays, blk_fft_fi);
    h_td1 = ifft(H_est_blocks_save{fi});
    subplot(2, 3, fi);
    stem((0:blk_fft_fi-1)/sym_rate*1000, abs(h_td1), 'b', 'MarkerSize',2, 'LineWidth',0.6);
    hold on;
    for p = 1:length(eff_d)
        stem(eff_d(p)/sym_rate*1000, abs(h_td1(eff_d(p)+1)), 'r', 'filled', 'MarkerSize',5, 'LineWidth',1.2);
    end
    xlabel('时延(ms)'); ylabel('|h|');
    title(sprintf('%s', fading_cfgs{fi,1}));
    grid on; xlim([0 blk_fft_fi/sym_rate*1000]);
end
sgtitle('信道估计CIR (block1, SNR=0dB)', 'FontSize', 13);

% Figure 3: TX通带帧结构 + 时域波形
try
if ~isempty(frame_pb_save)
    figure('Position', [50 600 1200 450]);

    % 3a: 通带时域波形 + 帧段标注
    subplot(2,1,1);
    t_frame_ms = (0:length(frame_pb_save)-1) / fs * 1000;
    plot(t_frame_ms, frame_pb_save, 'b', 'LineWidth', 0.3);
    xlabel('时间 (ms)'); ylabel('幅度');
    title(sprintf('TX通带帧 (fc=%dHz, fs=%dHz) — %s', fc, fs, fading_cfgs{vis_fi,1}));
    grid on; set(gca, 'FontSize', 10);
    % 帧段标注
    seg_starts = [0, N_preamble, N_preamble+guard_samp, ...
                  2*N_preamble+guard_samp, 2*N_preamble+2*guard_samp, ...
                  2*N_preamble+2*guard_samp+N_lfm, 2*N_preamble+3*guard_samp+N_lfm, ...
                  2*N_preamble+3*guard_samp+2*N_lfm, 2*N_preamble+4*guard_samp+2*N_lfm];
    seg_names = {'HFM+','guard','HFM-','guard','LFM1','guard','LFM2','guard','data'};
    yl = ylim;
    for k = 1:min(length(seg_starts), length(seg_names))
        x_ms = seg_starts(k) / fs * 1000;
        line([x_ms x_ms], yl, 'Color',[0.7 0 0], 'LineStyle','--', 'LineWidth',0.8);
        text(x_ms+0.5, yl(2)*0.85, seg_names{k}, 'FontSize',8, 'Color',[0.7 0 0], 'Rotation',0);
    end

    % 3b: TX基带包络
    subplot(2,1,2);
    plot(t_frame_ms, abs(frame_bb_save), 'b', 'LineWidth', 0.5);
    xlabel('时间 (ms)'); ylabel('|基带|');
    title('TX基带包络');
    grid on; set(gca, 'FontSize', 10);
    for k = 1:min(length(seg_starts), length(seg_names))
        x_ms = seg_starts(k) / fs * 1000;
        line([x_ms x_ms], ylim, 'Color',[0.7 0 0], 'LineStyle','--', 'LineWidth',0.8);
    end
end
catch me_vis3, fprintf('Figure 3 可视化跳过: %s\n', me_vis3.message); end

% Figure 4: TX/RX通带频谱对比
try
if ~isempty(frame_pb_save) && ~isempty(rx_pb_save)
    figure('Position', [50 100 1000 450]);

    % 4a: TX频谱
    subplot(2,1,1);
    N_fft_spec = 2^nextpow2(length(frame_pb_save));
    f_axis_khz = (0:N_fft_spec-1) * fs / N_fft_spec / 1000;
    TX_spec = 20*log10(abs(fft(frame_pb_save, N_fft_spec)) / N_fft_spec + 1e-10);
    plot(f_axis_khz(1:N_fft_spec/2), TX_spec(1:N_fft_spec/2), 'b', 'LineWidth', 0.5);
    xlabel('频率 (kHz)'); ylabel('幅度 (dB)');
    title(sprintf('TX通带频谱 (fc=%.0fkHz, BW=%.1fkHz)', fc/1000, bw_lfm/1000));
    grid on; xlim([0 fs/2/1000]); set(gca, 'FontSize', 10);
    % 标注通带范围
    line([f_lo f_lo]/1000, ylim, 'Color','r', 'LineStyle','--');
    line([f_hi f_hi]/1000, ylim, 'Color','r', 'LineStyle','--');

    % 4b: RX频谱（有噪声）
    subplot(2,1,2);
    N_fft_rx = 2^nextpow2(length(rx_pb_save));
    f_axis_rx = (0:N_fft_rx-1) * fs / N_fft_rx / 1000;
    RX_spec = 20*log10(abs(fft(rx_pb_save, N_fft_rx)) / N_fft_rx + 1e-10);
    plot(f_axis_rx(1:N_fft_rx/2), RX_spec(1:N_fft_rx/2), 'Color',[0.8 0.2 0.2], 'LineWidth', 0.5);
    xlabel('频率 (kHz)'); ylabel('幅度 (dB)');
    title(sprintf('RX通带频谱 (%s, SNR=%ddB)', fading_cfgs{vis_fi,1}, snr_list(snr_vis_idx)));
    grid on; xlim([0 fs/2/1000]); set(gca, 'FontSize', 10);
    line([f_lo f_lo]/1000, ylim, 'Color','r', 'LineStyle','--');
    line([f_hi f_hi]/1000, ylim, 'Color','r', 'LineStyle','--');
end
catch me_vis4, fprintf('Figure 4 可视化跳过: %s\n', me_vis4.message); end

% Figure 5: 接收星座图（各信道, SNR=%ddB）
try
figure('Position', [100 50 1200 500]);
for fi = 1:N_fading
    subplot(2, 3, fi);
    if ~isempty(eq_sym_save{fi})
        eq_s = eq_sym_save{fi};
        plot(real(eq_s), imag(eq_s), '.', 'MarkerSize', 2, 'Color', [0.3 0.3 0.8]);
        hold on;
        plot(real(constellation), imag(constellation), 'r+', 'MarkerSize', 12, 'LineWidth', 2);
    end
    axis equal; grid on;
    xlim([-2 2]); ylim([-2 2]);
    title(sprintf('%s (BER=%.2f%%)', fading_cfgs{fi,1}, ber_matrix(fi,snr_vis_idx)*100));
    xlabel('I'); ylabel('Q');
    set(gca, 'FontSize', 9);
end
sgtitle(sprintf('均衡后星座图 (SNR=%ddB, Turbo=%d轮)', snr_list(snr_vis_idx), 6), 'FontSize', 13);
catch me_vis5, fprintf('Figure 5 可视化跳过: %s\n', me_vis5.message); end

% Figure 6: TX/RX时域波形对比（通带局部放大）
try
if ~isempty(frame_pb_save) && ~isempty(rx_pb_save)
    figure('Position', [200 300 900 400]);
    % 显示data段前2ms
    data_start = 2*N_preamble + 4*guard_samp + 2*N_lfm + 1;
    show_len = min(round(2e-3*fs), length(frame_pb_save)-data_start+1);
    t_show = (0:show_len-1) / fs * 1000;
    subplot(2,1,1);
    plot(t_show, frame_pb_save(data_start:data_start+show_len-1), 'b', 'LineWidth', 0.5);
    xlabel('时间 (ms)'); ylabel('幅度'); title('TX通带 — data段前2ms');
    grid on; set(gca, 'FontSize', 10);
    subplot(2,1,2);
    rx_data_start = min(data_start, length(rx_pb_save)-show_len+1);
    plot(t_show, rx_pb_save(rx_data_start:rx_data_start+show_len-1), 'Color',[0.8 0.2 0.2], 'LineWidth', 0.5);
    xlabel('时间 (ms)'); ylabel('幅度');
    title(sprintf('RX通带 — data段前2ms (%s, SNR=%ddB)', fading_cfgs{vis_fi,1}, snr_list(snr_vis_idx)));
    grid on; set(gca, 'FontSize', 10);
end
catch me_vis6, fprintf('Figure 6 可视化跳过: %s\n', me_vis6.message); end

fprintf('\n完成\n');

%% ========== 保存结果 ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_scfde_discrete_doppler_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'SC-FDE 离散Doppler信道对比 V1.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '帧结构: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]\n');
fprintf(fid, 'fs=%dHz, fc=%dHz, sps=%d, rolloff=%.2f\n', fs, fc, sps, rolloff);
fprintf(fid, '信道: 6径, delays=[%s] sym, gains=[%s]\n', ...
    num2str(sym_delays), num2str(abs(gains_raw), '%.2f '));
fprintf(fid, '每径Doppler: [%s] Hz\n\n', num2str(doppler_per_path));

fprintf(fid, '=== BER ===\n');
fprintf(fid, '%-8s |', '');
for si = 1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, ' | blk  | rate(bps)\n');
fprintf(fid, '%s\n', repmat('-', 1, 8+8*length(snr_list)+20));
for fi = 1:N_fading
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si = 1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_matrix(fi,si)*100); end
    fprintf(fid, ' | %4d | %.0f\n', fading_cfgs{fi,4}, info_rate_save(fi));
end

fprintf(fid, '\n=== 同步信息 ===\n');
for fi = 1:N_fading
    fprintf(fid, '%-8s: lfm_pos=%d (expected~%d), peak=%.3f, alpha_est=%.4e\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), lfm_expected, sync_info_matrix(fi,2), ...
        alpha_est_matrix(fi,1));
end

fprintf(fid, '\n=== H_est block1 ===\n');
for fi = 1:N_fading
    blk_fft_fi = fading_cfgs{fi,4};
    eff_d = mod(sym_delays, blk_fft_fi);
    h_td1 = ifft(H_est_blocks_save{fi});
    fprintf(fid, '%-8s:', fading_cfgs{fi,1});
    for p = 1:length(sym_delays)
        fprintf(fid, ' %.3f<%.0f°', abs(h_td1(eff_d(p)+1)), angle(h_td1(eff_d(p)+1))*180/pi);
    end
    fprintf(fid, '\n');
end
fprintf(fid, '参考(归一化):');
for p = 1:length(sym_delays), fprintf(fid, ' %.3f', abs(gains(p))); end
fprintf(fid, '\n');

fclose(fid);
fprintf('结果已保存: %s\n', result_file);

%% ========== 辅助函数: apply_channel ========== %%
function rx = apply_channel(tx, delay_bins, gains_raw, ftype, fparams, fs, fc)
% 等效基带信道施加，支持4种模型:
%   static:   静态多径 h_p*x(n-d_p)
%   discrete: 离散Doppler h_p*exp(j2πν_p*n/fs)*x(n-d_p)
%   hybrid:   Rician混合 = 离散Doppler(强) + Jakes散射(弱)
%   jakes:    Jakes连续Doppler谱 (via gen_uwa_channel)
% 输入:
%   tx         - 发射基带信号 (1×N复数)
%   delay_bins - 各径时延 (样本, @fs)
%   gains_raw  - 各径复增益
%   ftype      - 'static'/'discrete'/'hybrid'/'jakes'
%   fparams    - 信道参数 (类型相关)
%   fs         - 采样率 (Hz)
%   fc         - 载波频率 (Hz, jakes需要)

    tx = tx(:).';
    rx = zeros(size(tx));
    N_tx = length(tx);

    switch ftype
        case 'static'
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                if d < N_tx
                    rx(d+1:end) = rx(d+1:end) + gains_raw(p) * tx(1:end-d);
                end
            end

        case 'discrete'
            % fparams = [ν_1, ν_2, ..., ν_P] Hz
            doppler_hz = fparams;
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                n_range = (d+1):N_tx;
                phase = exp(1j * 2*pi * doppler_hz(p) * (n_range-1) / fs);
                rx(n_range) = rx(n_range) + gains_raw(p) * phase .* tx(n_range-d);
            end

        case 'hybrid'
            % Rician: h_p(t) = h_p * exp(j2πν_p*t) * [√(K/(K+1)) + √(1/(K+1))*g(t)]
            doppler_hz = fparams.doppler_hz;
            fd_sc = fparams.fd_scatter;
            K = fparams.K_rice;
            spec_amp = sqrt(K / (K+1));
            scat_amp = sqrt(1 / (K+1));
            t = (0:N_tx-1) / fs;
            N_osc = 8;
            rng_state = rng;
            rng(43);
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                n_range = (d+1):N_tx;
                t_r = t(n_range);
                phase_disc = exp(1j * 2*pi * doppler_hz(p) * t_r);
                g_scat = zeros(1, length(n_range));
                for n_osc = 1:N_osc
                    theta = 2*pi * rand;
                    beta = pi * n_osc / N_osc;
                    g_scat = g_scat + exp(1j*(2*pi*fd_sc*cos(beta)*t_r + theta));
                end
                g_scat = g_scat / sqrt(N_osc);
                h_tv = gains_raw(p) * phase_disc .* (spec_amp + scat_amp * g_scat);
                rx(n_range) = rx(n_range) + h_tv .* tx(n_range-d);
            end
            rng(rng_state);

        case 'jakes'
            % Jakes衰落 via gen_uwa_channel (含bulk Doppler)
            fd_hz = fparams;
            delays_s = delay_bins / fs;
            ch_params = struct('fs',fs, 'delay_profile','custom', ...
                'delays_s',delays_s, 'gains',gains_raw, ...
                'num_paths',length(delay_bins), 'doppler_rate',fd_hz/fc, ...
                'fading_type','slow', 'fading_fd_hz',fd_hz, ...
                'snr_db',Inf, 'seed',42);
            [rx, ~] = gen_uwa_channel(tx, ch_params);

        otherwise
            error('不支持的信道类型: %s', ftype);
    end
end
