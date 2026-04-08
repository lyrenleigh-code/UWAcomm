%% test_sctde_timevarying.m — SC-TDE通带仿真 时变信道测试
% TX: 编码→交织→QPSK→[训练+数据]→09 RRC成形(基带)→09上变频(通带实数)
%     08 gen_lfm(通带实LFM) → 08帧组装: [LFM|guard|data_pb|guard|LFM] 全实数
% 信道: 等效基带帧 → gen_uwa_channel(多径+Jakes+多普勒) → 09上变频 → +实噪声
% RX: 09下变频 → 08同步检测(无噪声,直达径窗口) → 10多普勒估计 →
%     10重采样补偿(-alpha) → 提取数据 → 09 RRC匹配 → 下采样 →
%     12 Turbo均衡(RLS+PLL+BCJR) → 译码
% 版本：V4.0.0 — P3-2: 时变路径改用BEM(DCT)+散布导频+ISI消除(TDE方案)
%   静态路径保持不变(GAMP+turbo_equalizer_sctde)
%   V3→V4: 替换DFE+Kalman为BEM(DCT) per-symbol ISI消除+MMSE Turbo

clc; close all;
fprintf('========================================\n');
fprintf('  SC-TDE 通带仿真 — 时变信道测试\n');
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
turbo_iter = 6;
% DFE(31,90): num_fb覆盖max_delay=90，配合h_est初始化
eq_params = struct('num_ff',31, 'num_fb',90, 'lambda',0.998, ...
    'pll', struct('enable',true,'Kp',0.01,'Ki',0.005));

% 6径水声信道
sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

train_len = 500;
N_data_sym = 2000;
M_coded = 2*N_data_sym;
N_info = M_coded/n_code - mem;

% --- P3-2: 散布导频参数（仅时变路径使用）--- %
% 关键：导频簇长度须 > max_delay，否则多径分量指向未知数据，BEM观测无效
% 导频间隔须保证BEM在整个帧内有足够的时间分辨率
pilot_cluster_len = max(sym_delays) + 50;  % 每簇导频符号数（max_delay+余量）
pilot_spacing = 300;                   % 数据段内导频间隔
N_pilot_clusters = floor(N_data_sym / (pilot_spacing + pilot_cluster_len));
N_total_pilots = N_pilot_clusters * pilot_cluster_len;
N_data_actual = N_data_sym - N_total_pilots;  % 实际数据符号数
M_coded_tv = 2 * N_data_actual;        % 时变情况编码位数
N_info_tv = M_coded_tv / n_code - mem;

h_sym = zeros(1, max(sym_delays)+1);
for p=1:length(sym_delays), h_sym(sym_delays(p)+1)=gains(p); end

%% ========== 帧参数 ========== %%
bw_lfm = sym_rate * (1 + rolloff);
lfm_dur = 0.05;
f_lo = fc - bw_lfm/2;  f_hi = fc + bw_lfm/2;
[LFM_pb, ~] = gen_lfm(fs, lfm_dur, f_lo, f_hi);
N_lfm = length(LFM_pb);
t_lfm = (0:N_lfm-1)/fs;
LFM_bb = exp(1j*2*pi*(-bw_lfm/2*t_lfm + 0.5*bw_lfm/lfm_dur*t_lfm.^2));
guard_samp = max(sym_delays) * sps + 80;

snr_list = [5, 10, 15, 20];
fading_cfgs = {
    'static', 'static', 0,  0;
    'fd=1Hz', 'slow',   1,  1/fc;
    'fd=5Hz', 'slow',   5,  5/fc;
};

fprintf('通带: fs=%dHz, fc=%dHz, LFM=%.0f~%.0fHz\n', fs, fc, f_lo, f_hi);
fprintf('帧: [LFM_pb|guard|data_pb(RRC→UC)|guard|LFM_pb] 全实数\n');
fprintf('同步: 无噪声(per fading), 直达径窗口(50样本)\n');
fprintf('均衡: DFE(ff=%d,fb=%d)+GAMP信道估计, Turbo %d次\n\n', ...
    eq_params.num_ff, eq_params.num_fb, turbo_iter);

ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));
sync_info_matrix = zeros(size(fading_cfgs,1), 2);
alpha_est_save = zeros(1, size(fading_cfgs,1));

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname=fading_cfgs{fi,1}; ftype=fading_cfgs{fi,2};
    fd_hz=fading_cfgs{fi,3}; dop_rate=fading_cfgs{fi,4};

    %% ===== TX ===== %%
    rng(100+fi);
    training = constellation(randi(4,1,train_len));
    pilot_sym_ref = constellation(randi(4,1,pilot_cluster_len));  % 导频参考符号

    if strcmpi(ftype, 'static')
        % 静态：原始帧结构（无散布导频）
        info_bits = randi([0 1],1,N_info);
        coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
        coded = coded(1:M_coded);
        [inter_all,~] = random_interleave(coded,codec.interleave_seed);
        data_sym = bits2qpsk(inter_all);
        tx_sym = [training, data_sym];
        known_map = [true(1,train_len), false(1,N_data_sym)];
        pilot_positions = [];
    else
        % 时变：插入散布导频
        info_bits = randi([0 1],1,N_info_tv);
        coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
        coded = coded(1:M_coded_tv);
        [inter_all,~] = random_interleave(coded,codec.interleave_seed);
        data_sym_tv = bits2qpsk(inter_all);

        % 构建混合数据段: [数据... | 导频簇 | 数据... | 导频簇 | ...]
        mixed_seg = zeros(1, N_data_sym);
        known_seg = false(1, N_data_sym);     % 数据段内已知位置标记
        pilot_positions = zeros(1, N_pilot_clusters);
        d_idx = 0;                             % 数据符号游标
        pos = 1;                               % 混合段写入位置
        for kk = 1:N_pilot_clusters
            % 填充数据到下一个导频位置
            pilot_start = (kk-1) * pilot_spacing + 1;
            n_data_fill = pilot_start - pos;
            if n_data_fill > 0 && d_idx + n_data_fill <= N_data_actual
                mixed_seg(pos : pos+n_data_fill-1) = data_sym_tv(d_idx+1 : d_idx+n_data_fill);
                d_idx = d_idx + n_data_fill;
                pos = pos + n_data_fill;
            end
            % 插入导频簇
            if pos + pilot_cluster_len - 1 <= N_data_sym
                mixed_seg(pos : pos+pilot_cluster_len-1) = pilot_sym_ref;
                known_seg(pos : pos+pilot_cluster_len-1) = true;
                pilot_positions(kk) = train_len + pos;  % 帧内1-based位置
                pos = pos + pilot_cluster_len;
            end
        end
        % 填充剩余数据
        n_remain = N_data_actual - d_idx;
        if n_remain > 0 && pos + n_remain - 1 <= N_data_sym
            mixed_seg(pos : pos+n_remain-1) = data_sym_tv(d_idx+1 : d_idx+n_remain);
            pos = pos + n_remain;
        end
        % 截断到实际使用长度
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
    lfm_scale = sqrt(mean(data_pb.^2)) / sqrt(mean(LFM_pb.^2));
    LFM_pb_n = LFM_pb * lfm_scale;
    LFM_bb_n = LFM_bb * lfm_scale;

    % 帧组装（通带实数）
    frame_pb = [LFM_pb_n, zeros(1,guard_samp), data_pb, zeros(1,guard_samp), LFM_pb_n];
    frame_bb = [LFM_bb_n, zeros(1,guard_samp), shaped_bb, zeros(1,guard_samp), LFM_bb_n];
    data_offset = N_lfm + guard_samp;

    %% ===== 信道（固定）===== %%
    ch_params = struct('fs',fs,'delay_profile','custom',...
        'delays_s',sym_delays/sym_rate,'gains',gains_raw,...
        'num_paths',length(sym_delays),'doppler_rate',dop_rate,...
        'fading_type',ftype,'fading_fd_hz',fd_hz,...
        'snr_db',Inf,'seed',200+fi*100);
    [rx_bb_frame,~] = gen_uwa_channel(frame_bb, ch_params);
    [rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);
    sig_pwr = mean(rx_pb_clean.^2);

    %% ===== 无噪声同步（直达径窗口）===== %%
    [bb_clean,~] = downconvert(rx_pb_clean, fs, fc, bw_lfm);
    if abs(dop_rate) > 1e-10
        bb_clean_comp = comp_resample_spline(bb_clean, dop_rate, fs, 'fast');
    else
        bb_clean_comp = bb_clean;
    end
    [~, ~, corr_clean] = sync_detect(bb_clean_comp, LFM_bb_n, 0.3);
    dw = min(50, round(length(corr_clean)/2));
    [max_peak, max_pos] = max(corr_clean(1:dw));
    % 首达径检测：找第一个超过最强峰60%的位置（避免锁定多径回波）
    first_thresh = 0.6 * max_peak;
    first_idx = find(corr_clean(1:dw) > first_thresh, 1, 'first');
    if ~isempty(first_idx)
        sync_pos_fixed = first_idx;
        sync_peak_clean = corr_clean(first_idx);
    else
        sync_pos_fixed = max_pos;
        sync_peak_clean = max_peak;
    end

    % 多普勒估计（无噪声）
    alpha_est_clean = 0;
    if abs(dop_rate) > 1e-10
        try
            [atmp,~,~] = est_doppler_xcorr(bb_clean, LFM_bb_n, ...
                (N_lfm+guard_samp+N_shaped+guard_samp)/fs, fs, fc);
            if ~isempty(atmp) && isfinite(atmp), alpha_est_clean=atmp; else, alpha_est_clean=dop_rate; end
        catch, alpha_est_clean=dop_rate;
        end
    end

    sync_info_matrix(fi,:) = [sync_pos_fixed, sync_peak_clean];
    alpha_est_save(fi) = alpha_est_clean;
    fprintf('%-8s |', fname);

    %% ===== SNR循环 ===== %%
    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300+fi*1000+si*100);
        rx_pb = rx_pb_clean + sqrt(noise_var)*randn(size(rx_pb_clean));

        % 下变频 + 多普勒重采样补偿
        [bb_raw,~] = downconvert(rx_pb, fs, fc, bw_lfm);
        if abs(dop_rate) > 1e-10
            bb_comp = comp_resample_spline(bb_raw, dop_rate, fs, 'fast');
        else
            bb_comp = bb_raw;
        end

        % 用固定sync位置提取数据
        ds = sync_pos_fixed + data_offset;
        de = ds + N_shaped - 1;
        if de > length(bb_comp), rx_data_bb=[bb_comp(ds:end),zeros(1,de-length(bb_comp))];
        else, rx_data_bb=bb_comp(ds:de); end

        % RRC匹配+下采样（原始方案：sps范围内搜索分数偏移即可）
        % 注：sync_pos_fixed已体现在ds的数据提取位置中，无需额外补偿
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
        N_tx = length(tx_sym);
        if length(rx_sym_recv)>N_tx, rx_sym_recv=rx_sym_recv(1:N_tx);
        elseif length(rx_sym_recv)<N_tx, rx_sym_recv=[rx_sym_recv,zeros(1,N_tx-length(rx_sym_recv))]; end

        N_tx = length(tx_sym);
        T = train_len;
        N_dsym = N_tx - T;
        nv_eq = max(noise_var, 1e-10);
        P_paths = length(sym_delays);

        % 残余CFO补偿（符号率，不影响sync）
        % 重采样去时间压缩后，基带仍残留 alpha*fc Hz 频偏
        if abs(dop_rate) > 1e-10
            cfo_res_hz = dop_rate * fc;  % 残余CFO (Hz)
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
            % 训练段观测
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
            % 散布导频观测（跳过每簇前max_delay个ISI保护位置）
            max_d = max(sym_delays);
            for kk = 1:N_pilot_clusters
                pp_pos = pilot_positions(kk);
                if pp_pos == 0, continue; end
                for jj = max_d : pilot_cluster_len-1  % 从max_d开始，确保全部径可解析
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

            if si == 1  % 仅第一个SNR打印诊断
                % 对齐验证：训练段前10符号相关性
                align_corr = abs(sum(rx_sym_recv(1:min(50,train_len)) .* conj(training(1:min(50,train_len))))) / ...
                             (norm(rx_sym_recv(1:min(50,train_len))) * norm(training(1:min(50,train_len))) + 1e-30);
                fprintf('\n  [对齐] corr(rx,train)=%.3f, best_off=%d样本(%.1f符号) | ', ...
                    align_corr, best_off, best_off/sps);
                fprintf('\n  [BEM] Q=%d, obs=%d, cond=%.0f, nmse=%.1fdB | ', ...
                    bem_info.Q, length(obs_y), bem_info.cond_num, bem_info.nmse_residual);
            end

            % --- Turbo迭代 --- %
            [~,perm_turbo_tv] = random_interleave(zeros(1,M_coded_tv), codec.interleave_seed);
            data_only_idx = find(~known_map(T+1:end));  % 数据段内非导频位置
            bits_decoded = [];
            var_x = 1;  % 初始软符号方差

            for titer = 1:turbo_iter

                if titer == 1
                    % --- iter1: 已知位置ISI消除 + MMSE单抽头（ISI建模为噪声）--- %
                    data_eq = zeros(1, N_dsym);
                    for n = 1:N_dsym
                        nn = T + n;
                        % 已知位置ISI消除
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
                                    % 未知位置ISI功率累加（建模为额外噪声）
                                    isi_unknown_pwr = isi_unknown_pwr + abs(h_tv(pp, nn))^2;
                                end
                            end
                        end
                        h0_n = h_tv(1, nn);
                        rx_ic = rx_sym_recv(nn) - isi_known;
                        % MMSE：主径信号 vs (AWGN噪声+残余ISI)
                        nv_total = nv_eq + isi_unknown_pwr;
                        data_eq(n) = conj(h0_n) * rx_ic / (abs(h0_n)^2 + nv_total);
                    end
                    % 从训练段估计post-EQ噪声+残余ISI方差
                    train_eq = data_eq(1:min(T, length(data_eq)));
                    train_ref = training(1:length(train_eq));
                    nv_post = max(var(train_eq - train_ref), nv_eq * 0.1);
                else
                    % --- iter2+: 软符号全ISI消除 + MMSE + BEM重估计 --- %

                    % 软符号 → 全帧重建
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
                    % 数据位置填软符号
                    n_fill = min(length(x_bar_data), length(data_only_idx));
                    full_soft(T + data_only_idx(1:n_fill)) = x_bar_data(1:n_fill);
                    % 导频位置填已知符号
                    pilot_idx_seg = find(known_map(T+1:end));
                    full_soft(T + pilot_idx_seg) = tx_sym(T + pilot_idx_seg);

                    % DD-BEM重估计（用软符号扩展观测）
                    avg_confidence = mean(abs(Lp_coded));
                    if avg_confidence > 0.5  % 置信度门控
                        obs_y2 = []; obs_x2 = []; obs_n2 = [];
                        dd_step = 4;  % 每4个符号采样一个DD观测
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

                    % per-symbol ISI消除 + 单抽头MMSE
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
                        % MMSE单抽头（考虑软符号残余方差）
                        data_eq(n) = conj(h0_n) * rx_ic / ...
                            (abs(h0_n)^2 + nv_eq / max(1 - var_x_avg, 0.01));
                    end
                    % 从训练段估计post-EQ噪声+残余ISI方差（防高SNR时LLR过度自信）
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
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (sync=%d, peak=%.3f)\n', sync_pos_fixed, sync_peak_clean);
end

%% ========== 同步信息 ========== %%
fprintf('\n--- 同步信息（无噪声）---\n');
for fi=1:size(fading_cfgs,1)
    fprintf('%-8s: sync=%d, peak=%.3f, offset=%.2f sym\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), sync_info_matrix(fi,2), ...
        (sync_info_matrix(fi,1)-1)/sps);
end

%% ========== 多普勒估计 ========== %%
fprintf('\n--- 多普勒估计（无噪声）---\n');
for fi=1:size(fading_cfgs,1)
    alpha_true = fading_cfgs{fi,4};
    if abs(alpha_true) < 1e-10
        fprintf('%-8s: -\n', fading_cfgs{fi,1});
    else
        fprintf('%-8s: est=%.2e, true=%.2e\n', fading_cfgs{fi,1}, alpha_est_save(fi), alpha_true);
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

% 通带发射帧时域波形（最后一个fading config的帧）
figure('Position',[100 350 900 250]);
t_frame = (0:length(frame_pb)-1)/fs*1000;
plot(t_frame, frame_pb, 'b', 'LineWidth',0.3); hold on;
xline(N_lfm/fs*1000, 'r--');
xline((N_lfm+guard_samp)/fs*1000, 'r--');
xline((N_lfm+guard_samp+N_shaped)/fs*1000, 'r--');
xline((N_lfm+guard_samp+N_shaped+guard_samp)/fs*1000, 'r--');
xlabel('时间 (ms)'); ylabel('幅度'); grid on;
title(sprintf('通带发射帧（实信号, fc=%dHz, 全长%.1fms）', fc, length(frame_pb)/fs*1000));
text(N_lfm/2/fs*1000, max(frame_pb)*0.8, 'LFM1', 'FontSize',10, 'Color','r', 'HorizontalAlignment','center');
text((N_lfm+guard_samp+N_shaped/2)/fs*1000, max(frame_pb)*0.8, 'Train+Data', 'FontSize',10, 'Color','r', 'HorizontalAlignment','center');
text((2*N_lfm+2*guard_samp+N_shaped-N_lfm/2)/fs*1000, max(frame_pb)*0.8, 'LFM2', 'FontSize',10, 'Color','r', 'HorizontalAlignment','center');

% 通带接收信号（最后一个fading config, 最高SNR）
figure('Position',[100 650 900 250]);
t_rx = (0:length(rx_pb)-1)/fs*1000;
plot(t_rx, rx_pb, 'b', 'LineWidth',0.3);
xlabel('时间 (ms)'); ylabel('幅度'); grid on;
title(sprintf('通带接收信号（%s, SNR=%ddB）', fname, snr_list(end)));

% 通带频谱（发射 vs 接收）
figure('Position',[700 400 500 350]);
N_spec = length(frame_pb);
f_spec = (-N_spec/2:N_spec/2-1)*fs/N_spec/1000;
spec_tx = 20*log10(abs(fftshift(fft(frame_pb)))/N_spec + 1e-10);
plot(f_spec, spec_tx, 'b', 'LineWidth',0.5); hold on;
N_spec_rx = length(rx_pb);
f_spec_rx = (-N_spec_rx/2:N_spec_rx/2-1)*fs/N_spec_rx/1000;
spec_rx = 20*log10(abs(fftshift(fft(rx_pb)))/N_spec_rx + 1e-10);
plot(f_spec_rx, spec_rx, 'r', 'LineWidth',0.5);
xlabel('频率 (kHz)'); ylabel('dB'); grid on;
title('通带频谱'); legend('TX','RX','Location','best');
xlim([0 fs/1000/2]);

fprintf('\n完成\n');
