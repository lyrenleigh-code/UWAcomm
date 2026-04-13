%% test_sctde_discrete_doppler.m — SC-TDE 离散Doppler/混合Rician信道对比
% TX: 编码→交织→QPSK→[训练+数据]→09 RRC成形(基带)→帧组装
%     帧组装: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]
% 信道: apply_channel(离散Doppler/Rician混合/Jakes) — 等效基带
% RX: 09下变频 → ①LFM相位粗估多普勒 → ②粗补偿+训练精估 → ③LFM精确定时 →
%     提取数据 → 09 RRC匹配 → 残余CFO补偿(alpha_est*fc) →
%     12 Turbo均衡(GAMP+DFE或BEM+ISI消除) → 译码
% 版本：V1.0.0 — 6种信道模型对比 (对标SC-FDE/OTFS信道配置)
% 基于V5.1.0 SC-TDE时变测试，仅替换信道施加为apply_channel

clc; close all;
fprintf('========================================\n');
fprintf('  SC-TDE 离散Doppler信道对比 V1.0\n');
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
delay_samp = sym_delays * sps;  % 样本级时延 @fs=48kHz

% 每径Doppler频移 (6径)
doppler_per_path = [0, 3, -4, 5, -2, 1];  % Hz

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
N_lfm = length(LFM_bb);
guard_samp = max(sym_delays) * sps + 80;    % 保护间隔(覆盖最大多径+余量)

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
    'static',   'static',   zeros(1,6),  0;
    'disc-5Hz', 'discrete', doppler_per_path, 5;
    'hyb-K20',  'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',0.5, 'K_rice',20), 5;
    'hyb-K10',  'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',0.5, 'K_rice',10), 5;
    'hyb-K5',   'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',1.0, 'K_rice',5),  5;
    'jakes5Hz', 'jakes',    5, 5;
};

fprintf('通带: fs=%dHz, fc=%dHz, HFM/LFM=%.0f~%.0fHz\n', fs, fc, f_lo, f_hi);
fprintf('帧: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data], guard=%d样本(%.1fms)\n', guard_samp, guard_samp/fs*1000);
fprintf('数据: train=%d + data=%d sym\n', train_len, N_data_sym);
fprintf('信道: 6径, delays=[%s] sym, 每径Doppler=[%s]Hz\n', num2str(sym_delays), num2str(doppler_per_path));
fprintf('RX: ①LFM相位→alpha ②训练精估 ③LFM定时 ④BEM+Turbo(%d轮)\n\n', turbo_iter);

ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));
alpha_est_matrix = zeros(size(fading_cfgs,1), length(snr_list));
sync_info_matrix = zeros(size(fading_cfgs,1), 2);

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname=fading_cfgs{fi,1}; ftype=fading_cfgs{fi,2};
    fparams=fading_cfgs{fi,3}; fd_hz=fading_cfgs{fi,4};

    %% ===== TX ===== %%
    rng(100+fi);
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

    % 帧组装：[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]
    frame_bb = [HFM_bb_n, zeros(1,guard_samp), HFM_bb_neg_n, zeros(1,guard_samp), ...
                LFM_bb_n, zeros(1,guard_samp), LFM_bb_n, zeros(1,guard_samp), shaped_bb];
    T_v_lfm = (N_lfm + guard_samp) / fs;  % LFM1头到LFM2头间隔(秒)
    lfm_data_offset = N_lfm + guard_samp;  % LFM2头到data头的距离

    %% ===== 信道（apply_channel替代gen_uwa_channel）===== %%
    rx_bb_frame = apply_channel(frame_bb, delay_samp, gains_raw, ftype, fparams, fs, fc);
    [rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);
    sig_pwr = mean(rx_pb_clean.^2);

    fprintf('%-8s |', fname);

    %% ===== SNR循环：全链路处理（含sync+多普勒估计+信道估计）===== %%
    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300+fi*1000+si*100);
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

        % LFM相位法粗估alpha（窗口搜索，避免HFM互相关和LFM1/LFM2互扰）
        corr_est = filter(mf_lfm, 1, bb_raw);
        corr_est_abs = abs(corr_est);
        p1_lo = max(1, lfm1_peak_nom - lfm_search_margin);
        p1_hi = min(lfm1_peak_nom + lfm_search_margin, length(corr_est_abs));
        [~, p1_rel] = max(corr_est_abs(p1_lo:p1_hi));
        p1_idx = p1_lo + p1_rel - 1;
        T_v_samp = round(T_v_lfm * fs);
        p2_lo = max(1, lfm2_peak_nom - lfm_search_margin);
        p2_hi = min(lfm2_peak_nom + lfm_search_margin, length(corr_est_abs));
        [~, p2_rel] = max(corr_est_abs(p2_lo:p2_hi));
        p2_idx = p2_lo + p2_rel - 1;
        R1 = corr_est(p1_idx); R2 = corr_est(p2_idx);
        alpha_lfm = angle(R2 * conj(R1)) / (2*pi*fc*T_v_lfm);
        sync_peak = abs(R1) / sum(abs(LFM_bb_n).^2);

        % 粗补偿+粗提取（用于训练精估）
        if abs(alpha_lfm) > 1e-10
            bb_comp1 = comp_resample_spline(bb_raw, alpha_lfm, fs, 'fast');
        else
            bb_comp1 = bb_raw;
        end
        corr_c1 = abs(filter(mf_lfm, 1, bb_comp1(1:min(lfm2_search_len,length(bb_comp1)))));
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

        % 训练精估（替代CP精估：训练分两半，计算相位差→残余alpha）
        T_half = floor(train_len / 2);
        R_t1 = sum(rc(1:T_half) .* conj(training(1:T_half)));
        R_t2 = sum(rc(T_half+1:2*T_half) .* conj(training(T_half+1:2*T_half)));
        alpha_train = angle(R_t2 * conj(R_t1)) / (2*pi*fc*T_half/sym_rate);
        alpha_est = alpha_lfm + alpha_train;

        % ===== 阶段2: 精补偿 + LFM精确定时 =====
        if abs(alpha_est) > 1e-10
            bb_comp = comp_resample_spline(bb_raw, alpha_est, fs, 'fast');
        else
            bb_comp = bb_raw;
        end

        corr_lfm_comp = abs(filter(mf_lfm, 1, bb_comp(1:min(lfm2_search_len,length(bb_comp)))));
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

        T = train_len;
        N_dsym = N_tx - T;
        nv_eq = max(noise_var, 1e-10);
        P_paths = length(sym_delays);

        % 残余CFO补偿（用估计alpha，不用oracle dop_rate）
        if abs(alpha_est) > 1e-10
            cfo_res_hz = alpha_est * fc;
            t_sym_vec = (0:length(rx_sym_recv)-1) / sym_rate;
            rx_sym_recv = rx_sym_recv .* exp(-1j*2*pi*cfo_res_hz*t_sym_vec);
        end

        if strcmpi(ftype, 'static')
            %% === 静态：GAMP估计 + 标准Turbo（不变）===
            rx_train = rx_sym_recv(1:train_len);
            L_h = max(sym_delays)+1;
            T_mat = zeros(train_len, L_h);
            for col = 1:L_h
                T_mat(col:train_len, col) = training(1:train_len-col+1).';
            end
            [h_gamp_vec, ~] = ch_est_gamp(rx_train(:), T_mat, L_h, 50, noise_var);
            h_est_gamp = h_gamp_vec(:).';
            [bits_out,~] = turbo_equalizer_sctde(rx_sym_recv, h_est_gamp, training, ...
                turbo_iter, noise_var, eq_params, codec);
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

            if si == 1
                align_corr = abs(sum(rx_sym_recv(1:min(50,train_len)) .* conj(training(1:min(50,train_len))))) / ...
                             (norm(rx_sym_recv(1:min(50,train_len))) * norm(training(1:min(50,train_len))) + 1e-30);
                fprintf('\n  [对齐] corr=%.3f, off=%d | [BEM] Q=%d, obs=%d, cond=%.0f | ', ...
                    align_corr, best_off, bem_info.Q, length(obs_y), bem_info.cond_num);
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

%% ========== 同步信息 ========== %%
fprintf('\n--- 同步信息（LFM定时）---\n');
lfm_expected = 2*N_preamble + 3*guard_samp + N_lfm + 1;
for fi=1:size(fading_cfgs,1)
    fprintf('%-8s: lfm_pos=%d (expected~%d), peak=%.3f\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), lfm_expected, sync_info_matrix(fi,2));
end

%% ========== 多普勒估计 ========== %%
fprintf('\n--- 多普勒估计（SNR=%ddB）---\n', snr_list(1));
for fi=1:size(fading_cfgs,1)
    fprintf('%-8s: alpha_est=%.4e\n', fading_cfgs{fi,1}, alpha_est_matrix(fi,1));
end

%% ========== 可视化 ========== %%
figure('Position',[100 400 700 450]);
markers = {'o-','s-','d-','^-','v-','x-'};
colors = [0 .45 .74; .85 .33 .1; .47 .67 .19; .93 .69 .13; .49 .18 .56; .3 .3 .3];
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
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_sctde_discrete_doppler_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'SC-TDE 离散Doppler信道对比 V1.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '帧结构: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]\n');
fprintf(fid, 'fs=%dHz, fc=%dHz, sps=%d\n', fs, fc, sps);
fprintf(fid, '信道: %d径, delays=[%s] sym, 每径Doppler=[%s]Hz\n', ...
    length(sym_delays), num2str(sym_delays), num2str(doppler_per_path));
fprintf(fid, '训练: %d符号, 散布导频: %d簇×%d, 间隔%d\n\n', train_len, N_pilot_clusters, pilot_cluster_len, pilot_spacing);

fprintf(fid, '=== BER ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

fprintf(fid, '\n=== 同步 + 多普勒 ===\n');
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s: lfm_pos=%d, peak=%.3f, alpha_est=%.4e\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), sync_info_matrix(fi,2), alpha_est_matrix(fi,1));
end

fclose(fid);
fprintf('结果已保存: %s\n', result_file);
