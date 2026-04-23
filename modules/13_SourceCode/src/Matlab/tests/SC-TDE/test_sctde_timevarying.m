%% test_sctde_timevarying.m — SC-TDE通带仿真 时变信道测试
% TX: 编码→交织→QPSK→[训练+数据]→09 RRC成形(基带)→09上变频(通带实数)
%     帧组装: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]
% 信道: 等效基带帧 → gen_uwa_channel(多径+Jakes+多普勒) → 09上变频 → +实噪声
% RX: 09下变频 → ①LFM相位粗估多普勒 → ②粗补偿+训练精估 → ③LFM精确定时 →
%     提取数据 → 09 RRC匹配 →
%     12 Turbo均衡(GAMP+DFE或BEM+ISI消除) → 译码
% 版本：V5.4.0 — 删 post-CFO 伪补偿（基带 Doppler 模型下是伪操作，α=+1e-3 起 BER 破 50%）
% 变更：V5.1→V5.2 对齐 OFDM V4.3 策略（修复fd=1Hz高SNR反弹）
%   1. 时变信道：alpha_est = alpha_lfm（跳过训练精估，训练相位差被Jakes污染）
%   2. BEM估计后：从训练段实测 nv_post_meas，nv_eq = max(nv_eq, nv_post_meas)
%   静态路径: GAMP+turbo_equalizer_sctde（不变）
%   时变路径: BEM(DCT)+散布导频+ISI消除+MMSE Turbo（nv_eq 兜底后进 Turbo）
%   V5.3: 加 benchmark_mode 注入开关（spec 2026-04-19-e2e-timevarying-baseline）
%   V5.4: 删 post-CFO 伪补偿（含 D6/D7 pre-CFO 插桩），保留 diag_enable_legacy_cfo 反义回溯
%         RCA: specs/archive/2026-04-23-sctde-alpha-1e2-disaster-root-cause
%         fix: specs/archive/2026-04-24-sctde-remove-post-cfo-compensation
%         static 受益：α=+1e-3 50.66%→0%，α=+1e-2 50.36%→0.29%，α=0 1.84%→0.04%
%         时变实测（V3 plan C 证伪）：apply post-CFO 在 fd=1Hz 下反而破坏，全 skip 更优
%         fd=1Hz 非单调 BER vs SNR → specs/active/2026-04-24-sctde-fd1hz-nonmonotonic-investigation

%% ========== Benchmark mode 注入（2026-04-19） ========== %%
if ~exist('benchmark_mode','var') || isempty(benchmark_mode)
    benchmark_mode = false;
end
if ~benchmark_mode
    clc; close all;
end
fprintf('========================================\n');
fprintf('  SC-TDE 通带仿真 — 时变信道测试 V5.2\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

%% ========== 参数 ========== %%
sps = 8; sym_rate = 6000; fs = sym_rate*sps; fc = 12000;
rolloff = 0.35; span_rrc = 6;
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;
turbo_iter = 10;
eq_params = struct('num_ff',31, 'num_fb',90, 'lambda',0.998, ...
    'pll', struct('enable',true,'Kp',0.01,'Ki',0.005));

% 6径水声信道
sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

train_len = 500;
% N_data_sym在帧参数之后根据目标帧长动态计算

% --- 散布导频参数（仅时变路径）--- %
pilot_cluster_len = max(sym_delays) + 50;
pilot_spacing = 300;

h_sym = zeros(1, max(sym_delays)+1);
for p=1:length(sym_delays), h_sym(sym_delays(p)+1)=gains(p); end

%% ========== 帧参数（HFM + LFM前导码）========== %%
bw_lfm = sym_rate * (1 + rolloff);
preamble_dur = 0.05;
f_lo = fc - bw_lfm/2;  f_hi = fc + bw_lfm/2;

% HFM+（正扫频，Doppler不变性用于帧检测）
[HFM_pb, ~] = gen_hfm(fs, preamble_dur, f_lo, f_hi);
N_preamble = length(HFM_pb);
t_pre = (0:N_preamble-1)/fs;

% HFM基带版本
f0 = f_lo; f1 = f_hi; T_pre = preamble_dur;
if abs(f1-f0) < 1e-6
    phase_hfm = 2*pi*f0*t_pre;
else
    k_hfm = f0*f1*T_pre/(f1-f0);
    phase_hfm = -2*pi*k_hfm*log(1 - (f1-f0)/f1*t_pre/T_pre);
end
HFM_bb = exp(1j*(phase_hfm - 2*pi*fc*t_pre));

% HFM-基带版本（负扫频）
if abs(f1-f0) < 1e-6
    phase_hfm_neg = 2*pi*f1*t_pre;
else
    k_neg = f1*f0*T_pre/(f0-f1);
    phase_hfm_neg = -2*pi*k_neg*log(1 - (f0-f1)/f0*t_pre/T_pre);
end
HFM_bb_neg = exp(1j*(phase_hfm_neg - 2*pi*fc*t_pre));

% LFM基带版本（线性调频）
chirp_rate_lfm = (f_hi - f_lo) / preamble_dur;
phase_lfm = 2*pi * (f_lo * t_pre + 0.5 * chirp_rate_lfm * t_pre.^2);
LFM_bb = exp(1j*(phase_lfm - 2*pi*fc*t_pre));
% 【P1 2026-04-21】LFM- 基带版本（down-chirp，激活 est_alpha_dual_chirp）
phase_lfm_neg = 2*pi * (f_hi * t_pre - 0.5 * chirp_rate_lfm * t_pre.^2);
LFM_bb_neg = exp(1j*(phase_lfm_neg - 2*pi*fc*t_pre));
N_lfm = length(LFM_bb);
% 【P2 2026-04-21】guard 扩展容纳 α=3e-2 下 LFM peak 漂移
alpha_max_design = 3e-2;
guard_samp = max(sym_delays) * sps + 80 + ceil(alpha_max_design * max(N_preamble, N_lfm));

% 恢复原始数据长度参数
N_data_sym = 2000;
M_coded = 2*N_data_sym;
N_info = M_coded/n_code - mem;

% 散布导频计算（依赖N_data_sym）
N_pilot_clusters = floor(N_data_sym / (pilot_spacing + pilot_cluster_len));
N_total_pilots = N_pilot_clusters * pilot_cluster_len;
N_data_actual = N_data_sym - N_total_pilots;
M_coded_tv = 2 * N_data_actual;
N_info_tv = M_coded_tv / n_code - mem;

snr_list = [5, 10, 15, 20];
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
        bench_scheme_name = 'SC-TDE';
    end
    fprintf('[BENCHMARK] snr_list=%s, fading rows=%d, profile=%s, seed=%d, stage=%s\n', ...
            mat2str(snr_list), size(fading_cfgs,1), ...
            bench_channel_profile, bench_seed, bench_stage);
end

%% bench_seed 兜底（2026-04-23 E2E C 阶段）
if ~exist('bench_seed','var') || isempty(bench_seed)
    bench_seed = 42;
end

fprintf('通带: fs=%dHz, fc=%dHz, HFM/LFM=%.0f~%.0fHz\n', fs, fc, f_lo, f_hi);
fprintf('帧: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data], guard=%d样本(%.1fms)\n', guard_samp, guard_samp/fs*1000);
fprintf('数据: train=%d + data=%d sym\n', train_len, N_data_sym);
fprintf('RX: ①LFM相位→alpha ②训练精估 ③LFM定时 ④BEM+Turbo(%d轮)\n\n', turbo_iter);

ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));
alpha_est_matrix = zeros(size(fading_cfgs,1), length(snr_list));
sync_info_matrix = zeros(size(fading_cfgs,1), 2);

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname=fading_cfgs{fi,1}; ftype=fading_cfgs{fi,2};
    fd_hz=fading_cfgs{fi,3}; dop_rate=fading_cfgs{fi,4};

    %% ===== TX ===== %%
    % bench_seed 注入（2026-04-23 E2E C 阶段）
    rng(uint32(mod(100 + fi + (bench_seed - 42) * 100000, 4294967296)));
    training = constellation(randi(4,1,train_len));
    pilot_sym_ref = constellation(randi(4,1,pilot_cluster_len));

    if strcmpi(ftype, 'static')
        info_bits = randi([0 1],1,N_info);
        coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
        coded = coded(1:M_coded);
        [inter_all,~] = random_interleave(coded,codec.interleave_seed);
        data_sym = bits2qpsk(inter_all);
        tx_sym = [training, data_sym];
        known_map = [true(1,train_len), false(1,N_data_sym)];
        pilot_positions = [];
    else
        info_bits = randi([0 1],1,N_info_tv);
        coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
        coded = coded(1:M_coded_tv);
        [inter_all,~] = random_interleave(coded,codec.interleave_seed);
        data_sym_tv = bits2qpsk(inter_all);

        mixed_seg = zeros(1, N_data_sym);
        known_seg = false(1, N_data_sym);
        pilot_positions = zeros(1, N_pilot_clusters);
        d_idx = 0; pos = 1;
        for kk = 1:N_pilot_clusters
            pilot_start = (kk-1) * pilot_spacing + 1;
            n_data_fill = pilot_start - pos;
            if n_data_fill > 0 && d_idx + n_data_fill <= N_data_actual
                mixed_seg(pos : pos+n_data_fill-1) = data_sym_tv(d_idx+1 : d_idx+n_data_fill);
                d_idx = d_idx + n_data_fill;
                pos = pos + n_data_fill;
            end
            if pos + pilot_cluster_len - 1 <= N_data_sym
                mixed_seg(pos : pos+pilot_cluster_len-1) = pilot_sym_ref;
                known_seg(pos : pos+pilot_cluster_len-1) = true;
                pilot_positions(kk) = train_len + pos;
                pos = pos + pilot_cluster_len;
            end
        end
        n_remain = N_data_actual - d_idx;
        if n_remain > 0 && pos + n_remain - 1 <= N_data_sym
            mixed_seg(pos : pos+n_remain-1) = data_sym_tv(d_idx+1 : d_idx+n_remain);
            pos = pos + n_remain;
        end
        mixed_seg = mixed_seg(1:pos-1);
        known_seg = known_seg(1:pos-1);

        tx_sym = [training, mixed_seg];
        known_map = [true(1,train_len), known_seg];
    end

    % 09-RRC成形 + 上变频
    [shaped_bb,~,~] = pulse_shape(tx_sym, sps, 'rrc', rolloff, span_rrc);
    N_shaped = length(shaped_bb);
    [data_pb,~] = upconvert(shaped_bb, fs, fc);

    % 功率归一化
    data_rms = sqrt(mean(data_pb.^2));
    lfm_scale = data_rms / sqrt(mean(HFM_pb.^2));
    HFM_bb_n = HFM_bb * lfm_scale;
    HFM_bb_neg_n = HFM_bb_neg * lfm_scale;
    LFM_bb_n = LFM_bb * lfm_scale;
    LFM_bb_neg_n = LFM_bb_neg * lfm_scale;  % 【P3 2026-04-21】

    % 帧组装：[HFM+|g|HFM-|g|LFM_up|g|LFM_dn|g|data]（P3：LFM2→down）
    frame_bb = [HFM_bb_n, zeros(1,guard_samp), HFM_bb_neg_n, zeros(1,guard_samp), ...
                LFM_bb_n, zeros(1,guard_samp), LFM_bb_neg_n, zeros(1,guard_samp), shaped_bb];
    % 【P6 2026-04-21】TX 默认 tail padding
    default_tail_pad = ceil(alpha_max_design * length(frame_bb) * 1.5);
    frame_bb = [frame_bb, zeros(1, default_tail_pad)];
    T_v_lfm = (N_lfm + guard_samp) / fs;  % LFM1头到LFM2头间隔(秒)
    lfm_data_offset = N_lfm + guard_samp;  % LFM2头到data头的距离

    %% ===== 信道（固定，不随SNR变）===== %%
    ch_params = struct('fs',fs,'delay_profile','custom',...
        'delays_s',sym_delays/sym_rate,'gains',gains_raw,...
        'num_paths',length(sym_delays),'doppler_rate',dop_rate,...
        'fading_type',ftype,'fading_fd_hz',fd_hz,...
        'snr_db',Inf,'seed',200+fi*100);
    [rx_bb_frame,~] = gen_uwa_channel(frame_bb, ch_params);
    [rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);
    sig_pwr = mean(rx_pb_clean.^2);

    fprintf('%-8s |', fname);

    %% ===== SNR循环：全链路处理（含sync+多普勒估计+信道估计）===== %%
    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        % bench_seed 注入（2026-04-23 E2E C 阶段）
        rng(uint32(mod(300 + fi*1000 + si*100 + (bench_seed - 42) * 100000, 4294967296)));
        rx_pb = rx_pb_clean + sqrt(noise_var)*randn(size(rx_pb_clean));

        % 1. 下变频（有噪声信号）
        [bb_raw,~] = downconvert(rx_pb, fs, fc, bw_lfm);

        % ===== 阶段1: LFM相位粗估 + 训练精估 =====
        mf_lfm = conj(fliplr(LFM_bb_n));
        lfm2_search_len = min(3*N_preamble + 4*guard_samp + 2*N_lfm, length(bb_raw));
        % 匹配滤波标称峰值位置（基于帧结构，filter输出在信号尾部达峰）
        lfm1_peak_nom = 2*N_preamble + 2*guard_samp + N_lfm;   % LFM1峰 = 8800
        lfm2_peak_nom = 2*N_preamble + 3*guard_samp + 2*N_lfm; % LFM2峰 = 12000
        lfm_search_margin = max(sym_delays)*sps + 200;           % 搜索半径(覆盖多径+Doppler)

        % 【P4 2026-04-21】双 LFM 时延差法 α 估计 + 迭代 refinement
        if isempty(which('est_alpha_dual_chirp'))
            dop_dir = fullfile(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))), ...
                                '10_DopplerProc','src','Matlab');
            addpath(dop_dir);
        end
        cfg_alpha = struct();
        cfg_alpha.up_start = max(1, lfm1_peak_nom - lfm_search_margin);
        cfg_alpha.up_end   = min(lfm1_peak_nom + lfm_search_margin, length(bb_raw));
        cfg_alpha.dn_start = max(1, lfm2_peak_nom - lfm_search_margin);
        cfg_alpha.dn_end   = min(lfm2_peak_nom + lfm_search_margin, length(bb_raw));
        cfg_alpha.nominal_delta_samples = N_lfm + guard_samp;
        cfg_alpha.use_subsample = true;
        cfg_alpha.sign_convention = 'uwa-channel';   % V1.1: 内部取反号
        k_chirp = chirp_rate_lfm;
        [alpha_lfm, alpha_diag] = est_alpha_dual_chirp(bb_raw, LFM_bb_n, LFM_bb_neg_n, ...
                                                      fs, fc, k_chirp, cfg_alpha);
        % 迭代 refinement（默认 2 次）
        if ~exist('bench_alpha_iter','var') || isempty(bench_alpha_iter)
            bench_alpha_iter = 2;
        end
        if bench_alpha_iter > 0 && abs(alpha_lfm) > 1e-10
            for iter_a = 1:bench_alpha_iter
                bb_iter = comp_resample_spline(bb_raw, alpha_lfm, fs, 'fast');
                [delta_signed, ~] = est_alpha_dual_chirp(bb_iter, LFM_bb_n, LFM_bb_neg_n, ...
                                                        fs, fc, k_chirp, cfg_alpha);
                alpha_lfm = alpha_lfm + delta_signed;
            end
        end
        % 【P8 2026-04-21】正向大 α 精扫
        if alpha_lfm > 1.5e-2
            mf_up_tmp = conj(fliplr(LFM_bb_n));
            mf_dn_tmp = conj(fliplr(LFM_bb_neg_n));
            a_candidates = alpha_lfm + (-2e-3 : 2e-4 : 2e-3);
            best_metric = -inf; best_a = alpha_lfm;
            for ac = a_candidates
                bb_try = comp_resample_spline(bb_raw, ac, fs, 'fast');
                up_end_t = min(cfg_alpha.up_end, length(bb_try));
                dn_end_t = min(cfg_alpha.dn_end, length(bb_try));
                c_up = abs(filter(mf_up_tmp, 1, bb_try(cfg_alpha.up_start:up_end_t)));
                c_dn = abs(filter(mf_dn_tmp, 1, bb_try(cfg_alpha.dn_start:dn_end_t)));
                m = max(c_up) + max(c_dn);
                if m > best_metric, best_metric = m; best_a = ac; end
            end
            alpha_lfm = best_a;
        end
        % === diag D1: Oracle α（spec 2026-04-23-sctde-alpha-1e2-disaster-rca） === %
        if exist('diag_oracle_alpha','var') && diag_oracle_alpha
            alpha_lfm = dop_rate;
            if si == 1 && fi == 1
                fprintf('  [DIAG-D1] oracle alpha=%+.2e injected (override LFM est)\n', alpha_lfm);
            end
        end
        % R1/p1_idx/p2_idx 保留变量
        corr_est = filter(mf_lfm, 1, bb_raw);
        corr_est_abs = abs(corr_est);
        p1_idx = alpha_diag.tau_up;
        p2_idx = alpha_diag.tau_dn;
        R1 = corr_est(p1_idx);
        R2 = NaN;
        T_v_samp = round(T_v_lfm * fs);
        sync_peak = abs(R1) / sum(abs(LFM_bb_n).^2);

        % 粗补偿+粗提取（用于训练精估）
        if abs(alpha_lfm) > 1e-10
            bb_comp1 = comp_resample_spline(bb_raw, alpha_lfm, fs, 'fast');
        else
            bb_comp1 = bb_raw;
        end
        % 【P5 2026-04-21】round-1 定时改用 down-chirp 模板（LFM2 已改）
        mf_lfm_neg_r1 = conj(fliplr(LFM_bb_neg_n));
        corr_c1 = abs(filter(mf_lfm_neg_r1, 1, bb_comp1(1:min(lfm2_search_len,length(bb_comp1)))));
        c1_lo = max(1, lfm2_peak_nom - lfm_search_margin);
        c1_hi = min(lfm2_peak_nom + lfm_search_margin, length(corr_c1));
        [~, c1_rel] = max(corr_c1(c1_lo:c1_hi));
        lp1 = c1_lo + c1_rel - 1 - N_lfm + 1;
        d1 = lp1 + lfm_data_offset; e1 = d1 + N_shaped - 1;
        if e1 > length(bb_comp1), rd1=[bb_comp1(d1:end),zeros(1,e1-length(bb_comp1))];
        else, rd1=bb_comp1(d1:e1); end
        [rf1,~] = match_filter(rd1, sps, 'rrc', rolloff, span_rrc);
        b1=0; bp1=0;
        for off=0:sps-1
            st=rf1(off+1:sps:end);
            n_check = min(length(st), train_len);
            if n_check >= 10, c=abs(sum(st(1:n_check).*conj(training(1:n_check))));
                if c>bp1, bp1=c; b1=off; end, end, end
        rc = rf1(b1+1:sps:end);
        N_tx = length(tx_sym);
        if length(rc)>N_tx, rc=rc(1:N_tx);
        elseif length(rc)<N_tx, rc=[rc,zeros(1,N_tx-length(rc))]; end

        % 【P7 2026-04-21】SC-TDE 保留训练精估（对 static 分支 + 小 α 有效），加阈值门禁避免大 α 下 wrap
        % === diag D1: oracle α 开启时跳过训练精估（保持 alpha_est == dop_rate 干净）===
        if strcmpi(ftype, 'static') && ~(exist('diag_oracle_alpha','var') && diag_oracle_alpha)
            T_half = floor(train_len / 2);
            R_t1 = sum(rc(1:T_half) .* conj(training(1:T_half)));
            R_t2 = sum(rc(T_half+1:2*T_half) .* conj(training(T_half+1:2*T_half)));
            alpha_train = angle(R_t2 * conj(R_t1)) / (2*pi*fc*T_half/sym_rate);
            % 门禁：大 α 下 alpha_train 可能 wrap
            train_threshold = 1 / (2*fc*T_half/sym_rate);
            if abs(alpha_lfm) > 1.5e-2 || abs(alpha_train) > 0.7 * train_threshold
                alpha_est = alpha_lfm;
            else
                alpha_est = alpha_lfm + alpha_train;
            end
        else
            alpha_train = 0;
            alpha_est = alpha_lfm;
        end

        % ===== 阶段2: 精补偿 + LFM精确定时 =====
        if abs(alpha_est) > 1e-10
            bb_comp = comp_resample_spline(bb_raw, alpha_est, fs, 'fast');
        else
            bb_comp = bb_raw;
        end

        % 【P5 2026-04-21】LFM2 定时改用 down-chirp 模板
        mf_lfm_neg = conj(fliplr(LFM_bb_neg_n));
        corr_lfm_comp = abs(filter(mf_lfm_neg, 1, bb_comp(1:min(lfm2_search_len,length(bb_comp)))));
        c2_lo = max(1, lfm2_peak_nom - lfm_search_margin);
        c2_hi = min(lfm2_peak_nom + lfm_search_margin, length(corr_lfm_comp));
        [~, lfm2_local] = max(corr_lfm_comp(c2_lo:c2_hi));
        lfm2_peak_idx = c2_lo + lfm2_local - 1;
        lfm_pos = lfm2_peak_idx - N_lfm + 1;

        if si == 1
            sync_info_matrix(fi,:) = [lfm_pos, sync_peak];
        end

        % 数据段提取
        ds = lfm_pos + lfm_data_offset;
        de = ds + N_shaped - 1;
        if de > length(bb_comp)
            rx_data_bb = [bb_comp(ds:end), zeros(1, de-length(bb_comp))];
        else
            rx_data_bb = bb_comp(ds:de);
        end

        % RRC匹配+下采样+训练对齐
        [rx_filt,~] = match_filter(rx_data_bb, sps, 'rrc', rolloff, span_rrc);
        best_off = 0; best_pwr = 0;
        for off = 0:sps-1
            idx = off+1 : sps : length(rx_filt);
            n_check = min(length(idx), train_len);
            if n_check >= 10
                c = abs(sum(rx_filt(idx(1:n_check)) .* conj(tx_sym(1:n_check))));
                if c > best_pwr, best_pwr = c; best_off = off; end
            end
        end
        rx_sym_recv = rx_filt(best_off+1:sps:end);
        if length(rx_sym_recv)>N_tx, rx_sym_recv=rx_sym_recv(1:N_tx);
        elseif length(rx_sym_recv)<N_tx, rx_sym_recv=[rx_sym_recv,zeros(1,N_tx-length(rx_sym_recv))]; end

        % === diag D9: dump rx_filt 前 48 + rx_sym_recv 前 10 + 扫描 8 sps 相位对齐 === %
        if si == 1 && fi == 1 && exist('diag_dump_rxfilt','var') && diag_dump_rxfilt
            fprintf('  [DIAG-D9] group_delay=span_rrc*sps/2=%d samples, sps=%d, best_off=%d\n', ...
                span_rrc*sps/2, sps, best_off);
            fprintf('  [DIAG-D9] rx_filt(1:48) abs:  '); fprintf('%.3f ', abs(rx_filt(1:48))); fprintf('\n');
            fprintf('  [DIAG-D9] rx_filt(1:48) arg°: '); fprintf('%+5.0f ', angle(rx_filt(1:48))*180/pi); fprintf('\n');
            fprintf('  [DIAG-D9] training(1:6) abs:  '); fprintf('%.3f ', abs(training(1:6))); fprintf('\n');
            fprintf('  [DIAG-D9] training(1:6) arg°: '); fprintf('%+5.0f ', angle(training(1:6))*180/pi); fprintf('\n');
            fprintf('  [DIAG-D9] rx_sym_recv(1:10) abs:  '); fprintf('%.3f ', abs(rx_sym_recv(1:10))); fprintf('\n');
            fprintf('  [DIAG-D9] rx_sym_recv(1:10) arg°: '); fprintf('%+5.0f ', angle(rx_sym_recv(1:10))*180/pi); fprintf('\n');
            % 全 8 sps 相位扫描（找最好对齐）
            fprintf('  [DIAG-D9] sps phase scan (corr with training(1:50)):\n');
            for off_p = 0:sps-1
                idx_p = off_p+1 : sps : length(rx_filt);
                n_p = min(length(idx_p), 50);
                sym_p = rx_filt(idx_p(1:n_p));
                c_p = sum(sym_p .* conj(training(1:n_p))) / (norm(sym_p)*norm(training(1:n_p))+1e-30);
                fprintf('    off=%d: |corr(1:50)|=%.3f arg=%+6.1f°\n', off_p, abs(c_p), angle(c_p)*180/pi);
            end
            % 尝试"跳过 group_delay" 的 sps 对齐（理论上 rx_filt(gd+1) 对应第 1 符号）
            gd = span_rrc*sps/2;
            fprintf('  [DIAG-D9] 跳过 group_delay=%d sample 后对齐:\n', gd);
            for off_p = 0:sps-1
                start_p = gd + off_p + 1;
                if start_p <= length(rx_filt)
                    idx_p = start_p : sps : length(rx_filt);
                    n_p = min(length(idx_p), 50);
                    if n_p >= 10
                        sym_p = rx_filt(idx_p(1:n_p));
                        c_p = sum(sym_p .* conj(training(1:n_p))) / (norm(sym_p)*norm(training(1:n_p))+1e-30);
                        fprintf('    off=%d (start=%d): |corr|=%.3f arg=%+6.1f°\n', ...
                            off_p, start_p, abs(c_p), angle(c_p)*180/pi);
                    end
                end
            end
        end

        T = train_len;
        N_dsym = N_tx - T;
        nv_eq = max(noise_var, 1e-10);
        P_paths = length(sym_delays);

        % === 历史 post-CFO 补偿已删除（RCA: specs/archive/2026-04-23-sctde-alpha-1e2-disaster-root-cause）===
        % fix: specs/archive/2026-04-24-sctde-remove-post-cfo-compensation
        % 根因：gen_uwa_channel 基带模型仅做时间伸缩 s_bb((1+α)t) + 多径，无载波频偏；
        %       comp_resample_spline 补偿时间伸缩后，bb_comp 已无 CFO。
        %       原 rx_sym_recv .* exp(-j·2π·α·fc·t) 在 static 下 α=+1e-3 起注入 α·fc 频偏破 50% BER。
        % D10 验证（static）：skip 后 α=+1e-3 50.66%→0%，α=+1e-2 50.36%→0.29%，α=0 1.84%→0.04%。
        % V3 验证（时变）：apply post-CFO（plan C 实验）反而使 fd=1Hz SNR=20 0%→37%，
        %       证明时变路径也不需 post-CFO；历史 V5.2 "fd=1Hz 0.76%" 不可复现（代码演化累积差异）。
        % fd=1Hz 的非单调 BER vs SNR（SNR=15 27.96% / SNR=20 0%）属 Turbo+BEM 在时变信道下
        %       的稀有触发，已 known limitation，独立 spec 调研：
        %       specs/active/2026-04-24-sctde-fd1hz-nonmonotonic-investigation
        % 未来若切 passband Doppler 信道（gen_uwa_channel 输出含真 CFO），需重新评估。
        % 反义 toggle 保留供历史行为回溯/对照实验：
        if abs(alpha_est) > 1e-10 && ...
           exist('diag_enable_legacy_cfo','var') && diag_enable_legacy_cfo
            cfo_res_hz = alpha_est * fc;
            t_sym_vec = (0:length(rx_sym_recv)-1) / sym_rate;
            rx_sym_recv = rx_sym_recv .* exp(-1j*2*pi*cfo_res_hz*t_sym_vec);
            if si == 1 && fi == 1
                fprintf('  [LEGACY-CFO] 启用历史 post-CFO 补偿：α·fc=%+.1f Hz\n', cfo_res_hz);
            end
        end

        if strcmpi(ftype, 'static')
            %% === 静态：GAMP估计 + 标准Turbo（不变）===
            rx_train = rx_sym_recv(1:train_len);
            L_h = max(sym_delays)+1;
            T_mat = zeros(train_len, L_h);
            for col = 1:L_h
                T_mat(col:train_len, col) = training(1:train_len-col+1).';
            end

            % === diag D2/D4: Oracle h / LS fallback（spec 2026-04-23-sctde-alpha-1e2-rca） === %
            if exist('diag_oracle_h','var') && diag_oracle_h
                h_est_gamp = h_sym;   % 名义冲激响应（gains 归一化后）
                if si == 1 && fi == 1
                    fprintf('  [DIAG-D2] oracle h injected (= h_sym, L=%d)\n', L_h);
                end
            elseif exist('diag_use_ls','var') && diag_use_ls
                h_ls = (T_mat' * T_mat + 1e-3*eye(L_h)) \ (T_mat' * rx_train(:));
                h_est_gamp = h_ls(:).';
                if si == 1 && fi == 1
                    fprintf('  [DIAG-D4] LS (ridge=1e-3) instead of GAMP\n');
                end
            else
                [h_gamp_vec, ~] = ch_est_gamp(rx_train(:), T_mat, L_h, 50, noise_var);
                h_est_gamp = h_gamp_vec(:).';
            end

            % === diag: dump h 对比（oracle vs estimated） === %
            if si == 1 && fi == 1 && exist('diag_dump_h','var') && diag_dump_h
                fprintf('  [DIAG-H] tap | |h_est|   arg°   | |h_true|  arg°\n');
                for p_ = 1:length(sym_delays)
                    idx_tap = sym_delays(p_)+1;
                    fprintf('  [DIAG-H] %3d | %.4f  %+7.2f | %.4f  %+7.2f\n', ...
                        idx_tap, abs(h_est_gamp(idx_tap)), angle(h_est_gamp(idx_tap))*180/pi, ...
                        abs(h_sym(idx_tap)), angle(h_sym(idx_tap))*180/pi);
                end
                fprintf('  [DIAG-H] NMSE(h_est vs h_sym) = %.4f (norm²)\n', ...
                    sum(abs(h_est_gamp - h_sym).^2) / sum(abs(h_sym).^2));
            end

            % === diag D5: 信号层对齐诊断（Turbo 之前） === %
            if si == 1 && fi == 1 && exist('diag_dump_signal','var') && diag_dump_signal
                lfm_expected_theory = 2*N_preamble + 3*guard_samp + N_lfm + 1;
                fprintf('  [DIAG-S] lfm_pos=%d, theory≈%d, err=%d\n', ...
                    lfm_pos, lfm_expected_theory, lfm_pos - lfm_expected_theory);
                fprintf('  [DIAG-S] alpha_est=%+.4e, dop_rate=%+.4e, err=%+.2e\n', ...
                    alpha_est, dop_rate, alpha_est - dop_rate);
                fprintf('  [DIAG-S] best_off (sps phase)=%d / %d\n', best_off, sps);
                % 前 50 符号对齐
                c50 = sum(rx_sym_recv(1:50) .* conj(training(1:50))) / ...
                      (norm(rx_sym_recv(1:50)) * norm(training(1:50)) + 1e-30);
                fprintf('  [DIAG-S] corr(1:50)   |=%.3f, arg=%+7.1f°\n', abs(c50), angle(c50)*180/pi);
                % 中段对齐（250-300）
                c_mid = sum(rx_sym_recv(251:300) .* conj(training(251:300))) / ...
                        (norm(rx_sym_recv(251:300)) * norm(training(251:300)) + 1e-30);
                fprintf('  [DIAG-S] corr(251:300)|=%.3f, arg=%+7.1f°\n', abs(c_mid), angle(c_mid)*180/pi);
                % 尾段对齐（450-500）
                c_tail = sum(rx_sym_recv(451:500) .* conj(training(451:500))) / ...
                         (norm(rx_sym_recv(451:500)) * norm(training(451:500)) + 1e-30);
                fprintf('  [DIAG-S] corr(451:500)|=%.3f, arg=%+7.1f°\n', abs(c_tail), angle(c_tail)*180/pi);
                % 模型拟合残差（用 h_sym 做 oracle 信道）
                y_model = conv(training(1:train_len), h_sym);
                y_model = y_model(1:train_len);
                resid   = rx_sym_recv(1:train_len) - y_model;
                pwr_sig   = mean(abs(y_model).^2);
                pwr_resid = mean(abs(resid).^2);
                fprintf('  [DIAG-S] P_sig=%.3e, P_resid=%.3e, SNR_emp=%.1f dB, noise_var=%.3e\n', ...
                    pwr_sig, pwr_resid, 10*log10(pwr_sig/pwr_resid), noise_var);
            end

            % === diag D3: Turbo iter override === %
            if exist('diag_turbo_iter','var') && ~isempty(diag_turbo_iter)
                turbo_iter_use = diag_turbo_iter;
            else
                turbo_iter_use = turbo_iter;
            end
            [bits_out,~] = turbo_equalizer_sctde(rx_sym_recv, h_est_gamp, training, ...
                turbo_iter_use, noise_var, eq_params, codec);
        else
            %% === 时变：BEM(DCT) + per-symbol ISI消除 + MMSE Turbo ===

            % --- 构建BEM观测矩阵（训练 + 散布导频）--- %
            obs_y = []; obs_x = []; obs_n = [];
            for n = max(sym_delays)+1 : train_len
                x_vec = zeros(1, P_paths);
                for pp = 1:P_paths
                    idx = n - sym_delays(pp);
                    if idx >= 1, x_vec(pp) = training(idx); end
                end
                if any(x_vec ~= 0)
                    obs_y(end+1) = rx_sym_recv(n);
                    obs_x = [obs_x; x_vec];
                    obs_n(end+1) = n;
                end
            end
            max_d = max(sym_delays);
            for kk = 1:N_pilot_clusters
                pp_pos = pilot_positions(kk);
                if pp_pos == 0, continue; end
                for jj = max_d : pilot_cluster_len-1
                    n = pp_pos + jj;
                    if n > N_tx, break; end
                    x_vec = zeros(1, P_paths);
                    all_known = true;
                    for pp = 1:P_paths
                        idx = n - sym_delays(pp);
                        if idx >= 1 && idx <= N_tx && known_map(idx)
                            x_vec(pp) = tx_sym(idx);
                        else
                            all_known = false;
                        end
                    end
                    if all_known && any(x_vec ~= 0)
                        obs_y(end+1) = rx_sym_recv(n);
                        obs_x = [obs_x; x_vec];
                        obs_n(end+1) = n;
                    end
                end
            end

            % BEM(DCT)信道估计
            bem_opts = struct('Q_mode', 'auto', 'lambda_scale', 1.0);
            [h_tv, ~, bem_info] = ch_est_bem(obs_y(:), obs_x, obs_n(:), N_tx, ...
                sym_delays, fd_hz, sym_rate, nv_eq, 'dct', bem_opts);

            % V5.2：从训练段实测 nv_post 并兜底 nv_eq
            % 原因：高SNR时BEM+散布导频有残余模型误差，名义 nv_eq 远小于实际残差噪声，
            % MMSE公式 (|h0|² + nv_eq) 过度去噪 → LLR 过度自信 → 20dB反弹
            nv_post_sum = 0; nv_post_cnt = 0;
            for n = max(sym_delays)+1 : train_len
                y_pred = 0;
                for pp = 1:P_paths
                    idx = n - sym_delays(pp);
                    if idx >= 1
                        y_pred = y_pred + h_tv(pp, n) * training(idx);
                    end
                end
                nv_post_sum = nv_post_sum + abs(rx_sym_recv(n) - y_pred)^2;
                nv_post_cnt = nv_post_cnt + 1;
            end
            nv_post_meas = nv_post_sum / max(nv_post_cnt, 1);
            nv_eq_orig = nv_eq;
            nv_eq = max(nv_eq, nv_post_meas);

            if si == 1
                align_corr = abs(sum(rx_sym_recv(1:min(50,train_len)) .* conj(training(1:min(50,train_len))))) / ...
                             (norm(rx_sym_recv(1:min(50,train_len))) * norm(training(1:min(50,train_len))) + 1e-30);
                fprintf('\n  [对齐] corr=%.3f, off=%d | [BEM] Q=%d, obs=%d, cond=%.0f | nv_post=%.2e/nv_eq_orig=%.2e\n', ...
                    align_corr, best_off, bem_info.Q, length(obs_y), bem_info.cond_num, nv_post_meas, nv_eq_orig);
            end

            % --- Turbo迭代 --- %
            [~,perm_turbo_tv] = random_interleave(zeros(1,M_coded_tv), codec.interleave_seed);
            data_only_idx = find(~known_map(T+1:end));
            bits_decoded = [];
            var_x = 1;

            for titer = 1:turbo_iter

                if titer == 1
                    % iter1: 已知位置ISI消除 + MMSE单抽头
                    data_eq = zeros(1, N_dsym);
                    for n = 1:N_dsym
                        nn = T + n;
                        isi_known = 0;
                        isi_unknown_pwr = 0;
                        for pp = 1:P_paths
                            d = sym_delays(pp);
                            if d == 0, continue; end
                            idx = nn - d;
                            if idx >= 1 && idx <= N_tx
                                if known_map(idx)
                                    isi_known = isi_known + h_tv(pp, nn) * tx_sym(idx);
                                else
                                    isi_unknown_pwr = isi_unknown_pwr + abs(h_tv(pp, nn))^2;
                                end
                            end
                        end
                        h0_n = h_tv(1, nn);
                        rx_ic = rx_sym_recv(nn) - isi_known;
                        nv_total = nv_eq + isi_unknown_pwr;
                        data_eq(n) = conj(h0_n) * rx_ic / (abs(h0_n)^2 + nv_total);
                    end
                    train_eq = data_eq(1:min(T, length(data_eq)));
                    train_ref = training(1:length(train_eq));
                    nv_post = max(var(train_eq - train_ref), nv_eq * 0.1);
                else
                    % iter2+: 软符号全ISI消除 + MMSE + DD-BEM重估计
                    Lp_inter = random_interleave(Lp_coded, codec.interleave_seed);
                    if length(Lp_inter) < M_coded_tv
                        Lp_inter = [Lp_inter, zeros(1, M_coded_tv-length(Lp_inter))];
                    else
                        Lp_inter = Lp_inter(1:M_coded_tv);
                    end
                    [x_bar_data, var_x] = soft_mapper(Lp_inter, 'qpsk');
                    var_x_avg = mean(var_x);

                    full_soft = zeros(1, N_tx);
                    full_soft(1:T) = training;
                    n_fill = min(length(x_bar_data), length(data_only_idx));
                    full_soft(T + data_only_idx(1:n_fill)) = x_bar_data(1:n_fill);
                    pilot_idx_seg = find(known_map(T+1:end));
                    full_soft(T + pilot_idx_seg) = tx_sym(T + pilot_idx_seg);

                    % DD-BEM重估计
                    avg_confidence = mean(abs(Lp_coded));
                    if avg_confidence > 0.5
                        obs_y2 = []; obs_x2 = []; obs_n2 = [];
                        dd_step = 4;
                        for n = max(sym_delays)+1 : N_tx
                            if n <= T || known_map(n)
                                use = true;
                            elseif mod(n - T, dd_step) == 0
                                use = true;
                            else
                                use = false;
                            end
                            if use
                                x_vec = zeros(1, P_paths);
                                for pp = 1:P_paths
                                    idx = n - sym_delays(pp);
                                    if idx >= 1 && idx <= N_tx
                                        x_vec(pp) = full_soft(idx);
                                    end
                                end
                                if any(x_vec ~= 0)
                                    obs_y2(end+1) = rx_sym_recv(n);
                                    obs_x2 = [obs_x2; x_vec];
                                    obs_n2(end+1) = n;
                                end
                            end
                        end
                        [h_tv, ~, ~] = ch_est_bem(obs_y2(:), obs_x2, obs_n2(:), N_tx, ...
                            sym_delays, fd_hz, sym_rate, nv_eq, 'dct', bem_opts);
                    end

                    % per-symbol 全ISI消除 + 单抽头MMSE
                    data_eq = zeros(1, N_dsym);
                    for n = 1:N_dsym
                        nn = T + n;
                        isi = 0;
                        for pp = 1:P_paths
                            d = sym_delays(pp);
                            if d == 0, continue; end
                            idx = nn - d;
                            if idx >= 1 && idx <= N_tx
                                isi = isi + h_tv(pp, nn) * full_soft(idx);
                            end
                        end
                        h0_n = h_tv(1, nn);
                        rx_ic = rx_sym_recv(nn) - isi;
                        data_eq(n) = conj(h0_n) * rx_ic / ...
                            (abs(h0_n)^2 + nv_eq / max(1 - var_x_avg, 0.01));
                    end
                    train_eq = data_eq(1:min(T, length(data_eq)));
                    train_ref = training(1:length(train_eq));
                    nv_post = max(var(train_eq - train_ref), nv_eq * 0.1);
                end

                % 提取数据位置LLR（排除导频）
                data_eq_clean = data_eq(data_only_idx);
                LLR_eq = zeros(1, 2*length(data_eq_clean));
                LLR_eq(1:2:end) = -2*sqrt(2) * real(data_eq_clean) / nv_post;
                LLR_eq(2:2:end) = -2*sqrt(2) * imag(data_eq_clean) / nv_post;

                % BCJR译码
                LLR_trunc = LLR_eq(1:min(length(LLR_eq), M_coded_tv));
                if length(LLR_trunc) < M_coded_tv
                    LLR_trunc = [LLR_trunc, zeros(1, M_coded_tv - length(LLR_trunc))];
                end
                Le_deint = random_deinterleave(LLR_trunc, perm_turbo_tv);
                Le_deint = max(min(Le_deint, 30), -30);
                [~, Lp_info, Lp_coded] = siso_decode_conv(Le_deint, [], codec.gen_polys, ...
                    codec.constraint_len, codec.decode_mode);
                bits_decoded = double(Lp_info > 0);
            end
            bits_out = bits_decoded;
        end

        if strcmpi(ftype, 'static')
            nc = min(length(bits_out), N_info);
        else
            nc = min(length(bits_out), N_info_tv);
        end
        ber = mean(bits_out(1:nc) ~= info_bits(1:nc));
        ber_matrix(fi,si) = ber;
        alpha_est_matrix(fi,si) = alpha_est;
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (lfm=%d, peak=%.3f)\n', sync_info_matrix(fi,1), sync_info_matrix(fi,2));
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
            row.ber_uncoded      = NaN;
            row.nmse_db          = NaN;
            row.sync_tau_err     = NaN;
            row.frame_detected   = 1;
            row.turbo_final_iter = 10;
            row.runtime_s        = NaN;
            row.alpha_est        = alpha_est_matrix(fi_b, si_b);  % 2026-04-24 verify 用
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
for fi=1:size(fading_cfgs,1)
    fprintf('%-8s: lfm_pos=%d (expected~%d), peak=%.3f\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), lfm_expected, sync_info_matrix(fi,2));
end

%% ========== 多普勒估计 ========== %%
fprintf('\n--- 多普勒估计（有噪声, SNR=%ddB）---\n', snr_list(1));
for fi=1:size(fading_cfgs,1)
    alpha_true = fading_cfgs{fi,4};
    if abs(alpha_true) < 1e-10
        fprintf('%-8s: -\n', fading_cfgs{fi,1});
    else
        fprintf('%-8s: est=%.2e, true=%.2e\n', fading_cfgs{fi,1}, alpha_est_matrix(fi,1), alpha_true);
    end
end

%% ========== 可视化 ========== %%
figure('Position',[100 400 700 450]);
markers = {'o-','s-','d-'};
colors = [0 0.45 0.74; 0.85 0.33 0.1; 0.47 0.67 0.19];
for fi=1:size(fading_cfgs,1)
    semilogy(snr_list, max(ber_matrix(fi,:),1e-5), markers{fi}, ...
        'Color',colors(fi,:), 'LineWidth',1.8, 'MarkerSize',7, ...
        'DisplayName', fading_cfgs{fi,1});
    hold on;
end
snr_lin=10.^(snr_list/10);
semilogy(snr_list,max(0.5*erfc(sqrt(snr_lin)),1e-5),'k--','LineWidth',1,'DisplayName','QPSK uncoded');
grid on; xlabel('SNR (dB)'); ylabel('BER');
title('SC-TDE 通带时变信道 BER vs SNR（6径, max\_delay=15ms）');
legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);

% 信道CIR + 频响
figure('Position',[100 50 800 300]);
subplot(1,2,1);
delays_ms=sym_delays/sym_rate*1000;
stem(delays_ms,abs(gains),'filled','LineWidth',1.5);
xlabel('时延(ms)');ylabel('|h|');title(sprintf('信道CIR（%d径）',length(sym_delays)));grid on;
subplot(1,2,2);
h_show=zeros(1,1024);
for p=1:length(sym_delays),if sym_delays(p)+1<=1024,h_show(sym_delays(p)+1)=gains(p);end,end
f_khz=(0:1023)*sym_rate/1024/1000;
plot(f_khz,20*log10(abs(fft(h_show))+1e-10),'b','LineWidth',1);
xlabel('频率(kHz)');ylabel('|H|(dB)');title('信道频响');grid on;

% 通带帧波形（构造用于可视化）
[frame_pb_vis,~] = upconvert(frame_bb, fs, fc);
figure('Position',[100 350 900 250]);
t_frame = (0:length(frame_pb_vis)-1)/fs*1000;
plot(t_frame, frame_pb_vis, 'b', 'LineWidth',0.3);
xlabel('时间 (ms)'); ylabel('幅度'); grid on;
title(sprintf('通带发射帧（实信号, fc=%dHz, 全长%.1fms）', fc, length(frame_pb_vis)/fs*1000));
% 标注各段
xline(N_preamble/fs*1000, 'r--');
xline((N_preamble+guard_samp)/fs*1000, 'r--');
xline((2*N_preamble+guard_samp)/fs*1000, 'r--');
xline((2*N_preamble+2*guard_samp)/fs*1000, 'r--');
text(N_preamble/2/fs*1000, max(frame_pb_vis)*0.8, 'HFM+', 'FontSize',9, 'Color','r', 'HorizontalAlignment','center');
text((2*N_preamble+3*guard_samp+N_lfm/2)/fs*1000, max(frame_pb_vis)*0.8, 'LFM1+2', 'FontSize',9, 'Color','r', 'HorizontalAlignment','center');

fprintf('\n完成\n');

%% ========== 保存结果到txt ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_sctde_timevarying_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'SC-TDE 通带时变信道测试结果 V5.2 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '帧结构: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]\n');
fprintf(fid, 'fs=%dHz, fc=%dHz, HFM/LFM=%.0f~%.0fHz, sps=%d\n', fs, fc, f_lo, f_hi, sps);
fprintf(fid, '信道: %d径, delays=[%s], guard=%d\n', length(sym_delays), num2str(sym_delays), guard_samp);
fprintf(fid, '训练: %d符号, 散布导频: %d簇×%d, 间隔%d\n\n', train_len, N_pilot_clusters, pilot_cluster_len, pilot_spacing);

% BER表格
fprintf(fid, '=== BER ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

% 同步信息
fprintf(fid, '\n=== 同步信息（LFM定时）===\n');
lfm_expected_f = 2*N_preamble + 3*guard_samp + N_lfm + 1;
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s: lfm_pos=%d (expected~%d), peak=%.3f\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), lfm_expected_f, sync_info_matrix(fi,2));
end

% 多普勒估计
fprintf(fid, '\n=== 多普勒估计 (SNR=%ddB) ===\n', snr_list(1));
for fi=1:size(fading_cfgs,1)
    alpha_true = fading_cfgs{fi,4};
    fprintf(fid, '%-8s: alpha_est=%.4e, alpha_true=%.4e', fading_cfgs{fi,1}, alpha_est_matrix(fi,1), alpha_true);
    if abs(alpha_true) > 1e-10
        fprintf(fid, ', err=%.1f%%\n', abs(alpha_est_matrix(fi,1)-alpha_true)/abs(alpha_true)*100);
    else
        fprintf(fid, '\n');
    end
end

fclose(fid);
fprintf('结果已保存: %s\n', result_file);
