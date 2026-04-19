%% test_scfde_timevarying.m — SC-FDE通带仿真 时变信道测试
% TX: 编码→交织→QPSK→分块+CP→拼接→09 RRC成形
%     帧组装: [HFM+|guard|HFM-|guard|LFM|guard|data]
% 信道: 等效基带帧 → gen_uwa_channel(多径+Jakes+多普勒) → 09上变频 → +实噪声
% RX: 09下变频 → ①双HFM多普勒估计 → ②重采样补偿 → ③LFM精确定时 →
%     提取数据 → 09 RRC匹配 → 分块去CP+FFT → 信道估计+MMSE → 跨块BCJR
% 版本：V4.0.0 — 两级分离架构：双HFM多普勒+LFM精确定时
% 变更：V3→V4 帧结构[HFM+|HFM-|LFM|data]，解耦多普勒估计与定时同步

clc; close all;
fprintf('========================================\n');
fprintf('  SC-FDE 通带仿真 — 时变信道测试\n');
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

%% ========== 参数 ========== %%
sps = 8; sym_rate = 6000; fs = sym_rate*sps; fc = 12000;
rolloff = 0.35; span = 6;
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7);
n_code = 2; mem = codec.constraint_len - 1;

sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

%% ========== 帧参数 ========== %%
bw_lfm = sym_rate * (1 + rolloff);
preamble_dur = 0.05;
f_lo = fc - bw_lfm/2;  f_hi = fc + bw_lfm/2;
% 使用HFM前导码（Doppler不变性：时间压缩仅引起频移，匹配滤波峰值鲁棒）
[HFM_pb, ~] = gen_hfm(fs, preamble_dur, f_lo, f_hi);
N_preamble = length(HFM_pb);
t_pre = (0:N_preamble-1)/fs;
% HFM基带版本：从通带相位中减去载频
f0 = f_lo; f1 = f_hi; T_pre = preamble_dur;
if abs(f1-f0) < 1e-6
    phase_hfm = 2*pi*f0*t_pre;
else
    k_hfm = f0*f1*T_pre/(f1-f0);
    phase_hfm = -2*pi*k_hfm*log(1 - (f1-f0)/f1*t_pre/T_pre);
end
HFM_bb = exp(1j*(phase_hfm - 2*pi*fc*t_pre));
% HFM-基带版本（负扫频 f_hi → f_lo，后导码）
if abs(f1-f0) < 1e-6
    phase_hfm_neg = 2*pi*f1*t_pre;
else
    k_neg = f1*f0*T_pre/(f0-f1);
    phase_hfm_neg = -2*pi*k_neg*log(1 - (f0-f1)/f0*t_pre/T_pre);
end
HFM_bb_neg = exp(1j*(phase_hfm_neg - 2*pi*fc*t_pre));
% LFM基带版本（线性调频，多普勒补偿后精确定时用）
chirp_rate_lfm = (f_hi - f_lo) / preamble_dur;
phase_lfm = 2*pi * (f_lo * t_pre + 0.5 * chirp_rate_lfm * t_pre.^2);
LFM_bb = exp(1j*(phase_lfm - 2*pi*fc*t_pre));
N_lfm = length(LFM_bb);
guard_samp = max(sym_delays) * sps + 80;

snr_list = [5, 10, 15, 20];
fading_cfgs = {
    'static', 'static',   0,   0,           1024, 128,  4;
    'fd=1Hz', 'slow',     1,   1/fc,        256,  128,  16;
    'fd=5Hz', 'slow',     5,   5/fc,        128,  128,  32;
};

fprintf('通带: fs=%dHz, fc=%dHz, HFM/LFM=%.0f~%.0fHz\n', fs, fc, f_lo, f_hi);
fprintf('帧: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]\n');
fprintf('RX: ①dual-HFM→alpha ②补偿 ③LFM精确定时 ④数据提取\n\n');

ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));
alpha_est_matrix = zeros(size(fading_cfgs,1), length(snr_list));
sync_info_matrix = zeros(size(fading_cfgs,1), 2);
H_est_blocks_save = cell(1, size(fading_cfgs,1));
ch_info_save = cell(1, size(fading_cfgs,1));

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname=fading_cfgs{fi,1}; ftype=fading_cfgs{fi,2};
    fd_hz=fading_cfgs{fi,3}; dop_rate=fading_cfgs{fi,4};
    blk_fft=fading_cfgs{fi,5}; blk_cp=fading_cfgs{fi,6}; N_blocks=fading_cfgs{fi,7};
    sym_per_block = blk_cp + blk_fft;

    M_per_blk = 2*blk_fft;
    M_total = M_per_blk * N_blocks;
    N_info = M_total/n_code - mem;

    %% ===== TX（固定，不随SNR变）===== %%
    rng(100 + fi);
    info_bits = randi([0 1],1,N_info);
    coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
    coded = coded(1:M_total);
    [inter_all,perm_all] = random_interleave(coded,codec.interleave_seed);
    sym_all = bits2qpsk(inter_all);

    all_cp_data = zeros(1, N_blocks * sym_per_block);
    for bi=1:N_blocks
        data_sym = sym_all((bi-1)*blk_fft+1:bi*blk_fft);
        x_cp = [data_sym(end-blk_cp+1:end), data_sym];
        all_cp_data((bi-1)*sym_per_block+1:bi*sym_per_block) = x_cp;
    end

    [shaped_bb,~,~] = pulse_shape(all_cp_data, sps, 'rrc', rolloff, span);
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

    %% ===== 信道（固定，不随SNR变）===== %%
    ch_params = struct('fs',fs,'delay_profile','custom',...
        'delays_s',sym_delays/sym_rate,'gains',gains_raw,...
        'num_paths',length(sym_delays),'doppler_rate',dop_rate,...
        'fading_type',ftype,'fading_fd_hz',fd_hz,...
        'snr_db',Inf,'seed',200+fi*100);
    [rx_bb_frame,ch_info] = gen_uwa_channel(frame_bb, ch_params);
    ch_info_save{fi} = ch_info;  % 保存用于CIR可视化
    [rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);
    sig_pwr = mean(rx_pb_clean.^2);

    L_h = max(sym_delays) + 1;
    K_sparse = length(sym_delays);
    N_total_sym = N_blocks * sym_per_block;

    fprintf('%-8s |', fname);

    %% ===== SNR循环：全链路处理（含sync+多普勒估计+信道估计）===== %%
    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300+fi*1000+si*100);
        rx_pb = rx_pb_clean + sqrt(noise_var)*randn(size(rx_pb_clean));

        % 1. 下变频（有噪声信号）
        [bb_raw,~] = downconvert(rx_pb, fs, fc, bw_lfm);

        % ===== LFM相位粗估 + CP精估 =====
        mf_lfm = conj(fliplr(LFM_bb_n));
        lfm2_search_len = min(3*N_preamble + 4*guard_samp + 2*N_lfm, length(bb_raw));
        lfm2_start = 2*N_preamble + 2*guard_samp + N_lfm + 1;

        % LFM相位法粗估（搜索范围跳过HFM区域，防HFM-LFM互相关干扰）
        corr_est = filter(mf_lfm, 1, bb_raw);
        corr_est_abs = abs(corr_est);
        lfm1_end = 2*N_preamble + 2*guard_samp + N_lfm + guard_samp;
        lfm1_search_start = 2*N_preamble + 2*guard_samp + 1;  % 跳过HFM+/-区域
        [~, p1_rel] = max(corr_est_abs(lfm1_search_start:min(lfm1_end, length(corr_est_abs))));
        p1_idx = lfm1_search_start + p1_rel - 1;
        T_v_samp = round(T_v_lfm * fs);
        [~, p2_rel] = max(corr_est_abs(lfm2_start:min(lfm2_search_len, length(corr_est_abs))));
        p2_idx = lfm2_start + p2_rel - 1;
        R1 = corr_est(p1_idx); R2 = corr_est(p2_idx);
        alpha_lfm = angle(R2 * conj(R1)) / (2*pi*fc*T_v_lfm);
        sync_peak = abs(R1) / sum(abs(LFM_bb_n).^2);

        % 粗补偿+粗提取（仅用于CP估计）
        if abs(alpha_lfm) > 1e-10
            bb_comp1 = comp_resample_spline(bb_raw, alpha_lfm, fs, 'fast');
        else
            bb_comp1 = bb_raw;
        end
        corr_c1 = abs(filter(mf_lfm, 1, bb_comp1(1:min(lfm2_search_len,length(bb_comp1)))));
        [~, l1] = max(corr_c1(lfm2_start:end));
        lp1 = lfm2_start + l1 - 1 - N_lfm + 1;
        d1 = lp1 + lfm_data_offset; e1 = d1 + N_shaped - 1;
        if e1 > length(bb_comp1), rd1=[bb_comp1(d1:end),zeros(1,e1-length(bb_comp1))];
        else, rd1=bb_comp1(d1:e1); end
        [rf1,~] = match_filter(rd1, sps, 'rrc', rolloff, span);
        b1=0; bp1=0;
        for off=0:sps-1
            st=rf1(off+1:sps:end);
            if length(st)>=10, c=abs(sum(st(1:10).*conj(all_cp_data(1:10))));
                if c>bp1, bp1=c; b1=off; end, end, end
        rc = rf1(b1+1:sps:end);
        if length(rc)>N_total_sym, rc=rc(1:N_total_sym);
        elseif length(rc)<N_total_sym, rc=[rc,zeros(1,N_total_sym-length(rc))]; end

        % CP精估
        Rcp = 0;
        for bi2 = 1:N_blocks
            bs2 = (bi2-1)*sym_per_block;
            Rcp = Rcp + sum(rc(bs2+1:bs2+blk_cp) .* conj(rc(bs2+blk_fft+1:bi2*sym_per_block)));
        end
        alpha_cp = angle(Rcp) / (2*pi*fc*blk_fft/sym_rate);
        alpha_est = alpha_lfm + alpha_cp;
        sync_peak = abs(R1) / sum(abs(LFM_bb_n).^2);

        % ---- Round 2: 精补偿 + 最终提取 ----
        if abs(alpha_est) > 1e-10
            bb_comp = comp_resample_spline(bb_raw, alpha_est, fs, 'fast');
        else
            bb_comp = bb_raw;
        end

        corr_lfm_comp = abs(filter(mf_lfm, 1, bb_comp(1:min(lfm2_search_len,length(bb_comp)))));
        [~, lfm2_local] = max(corr_lfm_comp(lfm2_start:end));
        lfm2_peak_idx = lfm2_start + lfm2_local - 1;
        lfm_pos = lfm2_peak_idx - N_lfm + 1;

        sync_offset_samp = 0;
        sync_offset_sym = 0;
        phase_ramp_frac = ones(1, blk_fft);

        if si == 1
            sync_info_matrix(fi,:) = [lfm_pos, sync_peak];
        end

        ds = lfm_pos + lfm_data_offset;
        de = ds + N_shaped - 1;
        if de > length(bb_comp)
            rx_data_bb = [bb_comp(ds:end), zeros(1, de-length(bb_comp))];
        else
            rx_data_bb = bb_comp(ds:de);
        end

        [rx_filt,~] = match_filter(rx_data_bb, sps, 'rrc', rolloff, span);
        best_off=0; best_pwr=0;
        for off=0:sps-1
            st=rx_filt(off+1:sps:end);
            if length(st)>=10, c=abs(sum(st(1:10).*conj(all_cp_data(1:10))));
                if c>best_pwr, best_pwr=c; best_off=off; end
            end
        end
        rx_sym_all = rx_filt(best_off+1:sps:end);
        N_total_sym = N_blocks * sym_per_block;
        if length(rx_sym_all)>N_total_sym, rx_sym_all=rx_sym_all(1:N_total_sym);
        elseif length(rx_sym_all)<N_total_sym, rx_sym_all=[rx_sym_all,zeros(1,N_total_sym-length(rx_sym_all))]; end

        % 6. 信道估计（有噪声信号，每个SNR独立估计）
        nv_eq = max(noise_var, 1e-10);
        eff_delays = mod(sym_delays - sync_offset_sym, blk_fft);

        if strcmpi(ftype, 'static')
            % GAMP估计（用第1块CP段）
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
            % BEM(DCT)跨块估计（每块CP段作为导频）
            obs_y = []; obs_x = []; obs_n = [];
            for bi = 1:N_blocks
                blk_start = (bi-1)*sym_per_block;
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

        % 7. 分块去CP+FFT
        Y_freq_blocks = cell(1, N_blocks);
        for bi = 1:N_blocks
            blk_sym = rx_sym_all((bi-1)*sym_per_block+1:bi*sym_per_block);
            rx_nocp = blk_sym(blk_cp+1:end);
            Y_freq_blocks{bi} = fft(rx_nocp);
        end

        % 8. 跨块Turbo均衡: LMMSE-IC ⇌ BCJR + DD信道重估计
        turbo_iter = 6;
        x_bar_blks = cell(1,N_blocks);
        var_x_blks = ones(1,N_blocks);
        H_cur_blocks = H_est_blocks;
        for bi=1:N_blocks, x_bar_blks{bi}=zeros(1,blk_fft); end
        La_dec_info = [];
        bits_decoded = [];

        for titer = 1:turbo_iter
            % 1. Per-block LMMSE-IC → LLR
            LLR_all = zeros(1, M_total);
            for bi = 1:N_blocks
                [x_tilde,mu,nv_tilde] = eq_mmse_ic_fde(Y_freq_blocks{bi}, ...
                    H_cur_blocks{bi}, x_bar_blks{bi}, var_x_blks(bi), nv_eq);
                Le_eq_blk = soft_demapper(x_tilde, mu, nv_tilde, zeros(1,M_per_blk), 'qpsk');
                LLR_all((bi-1)*M_per_blk+1:bi*M_per_blk) = Le_eq_blk;
            end

            % 2. 跨块解交织 + BCJR
            Le_eq_deint = random_deinterleave(LLR_all, perm_all);
            Le_eq_deint = max(min(Le_eq_deint,30),-30);
            [~, Lpost_info, Lpost_coded] = siso_decode_conv(...
                Le_eq_deint, La_dec_info, codec.gen_polys, codec.constraint_len);
            bits_decoded = double(Lpost_info > 0);

            % 3. 反馈 + DD信道重估计
            if titer < turbo_iter
                Lpost_inter = random_interleave(Lpost_coded, codec.interleave_seed);
                if length(Lpost_inter)<M_total
                    Lpost_inter=[Lpost_inter,zeros(1,M_total-length(Lpost_inter))];
                else
                    Lpost_inter=Lpost_inter(1:M_total);
                end
                for bi = 1:N_blocks
                    coded_blk = Lpost_inter((bi-1)*M_per_blk+1:bi*M_per_blk);
                    [x_bar_blks{bi}, var_x_raw] = soft_mapper(coded_blk, 'qpsk');
                    var_x_blks(bi) = max(var_x_raw, nv_eq);

                    % DD信道重估计: H_dd = Y·X̄*/(|X̄|²+ε)
                    % 用软符号估计（比硬判决更鲁棒）
                    if titer >= 2 && var_x_blks(bi) < 0.5  % 置信度足够时才更新
                        X_bar = fft(x_bar_blks{bi});
                        H_dd_raw = Y_freq_blocks{bi} .* conj(X_bar) ./ (abs(X_bar).^2 + nv_eq);
                        % 稀疏平滑：只保留有效时延位置的抽头
                        h_dd = ifft(H_dd_raw);
                        h_dd_sparse = zeros(1, blk_fft);
                        eff_d = mod(sym_delays - sync_offset_sym, blk_fft);
                        for p=1:length(eff_d), h_dd_sparse(eff_d(p)+1) = h_dd(eff_d(p)+1); end
                        H_cur_blocks{bi} = fft(h_dd_sparse) .* phase_ramp_frac;
                    end
                end
            end
        end

        nc = min(length(bits_decoded),N_info);
        ber = mean(bits_decoded(1:nc)~=info_bits(1:nc));
        ber_matrix(fi,si) = ber;
        alpha_est_matrix(fi,si) = alpha_est;
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (blk=%d, lfm=%d, peak=%.3f)\n', blk_fft, sync_info_matrix(fi,1), sync_info_matrix(fi,2));
end

%% ========== 同步信息 ========== %%
fprintf('\n--- 同步信息（LFM定时）---\n');
lfm_expected = 2*N_preamble + 3*guard_samp + N_lfm + 1;  % LFM2在帧中的标称位置
for fi=1:size(fading_cfgs,1)
    fprintf('%-8s: lfm_pos=%d (expected~%d), peak=%.3f\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), lfm_expected, sync_info_matrix(fi,2));
end

%% ========== Oracle信道估计信息 ========== %%
fprintf('\n--- Oracle H_est（block1, 各径增益）---\n');
fprintf('%-8s | offset |', '');
for p=1:length(sym_delays), fprintf(' path%d(d=%d)', p, sym_delays(p)); end
fprintf('\n');
for fi=1:size(fading_cfgs,1)
    blk_fft_fi = fading_cfgs{fi,5};
    off_sym = 0;  % LFM精确定时后offset=0
    eff_d = mod(sym_delays - off_sym, blk_fft_fi);
    fprintf('%-8s | %2dsym  |', fading_cfgs{fi,1}, off_sym);
    % 取block1的H_est
    h_blk1 = H_est_blocks_save{fi};
    h_td1 = ifft(h_blk1);
    for p=1:length(sym_delays)
        val = h_td1(eff_d(p)+1);
        fprintf(' %.3f<%.0f°', abs(val), angle(val)*180/pi);
    end
    fprintf('\n');
end
fprintf('静态参考: ');
for p=1:length(sym_delays), fprintf(' %.3f', abs(gains(p))); end
fprintf('\n');

%% ========== 多普勒估计 ========== %%
fprintf('\n--- 多普勒估计（有噪声, SNR1）---\n');
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
all_markers = {'o-','s-','d-','^-','v-'};
all_colors = lines(size(fading_cfgs,1));
for fi=1:size(fading_cfgs,1)
    mi = mod(fi-1, length(all_markers))+1;
    semilogy(snr_list, max(ber_matrix(fi,:),1e-5), all_markers{mi}, ...
        'Color',all_colors(fi,:), 'LineWidth',1.8, 'MarkerSize',7, ...
        'DisplayName',sprintf('%s(blk=%d)', fading_cfgs{fi,1}, fading_cfgs{fi,5}));
    hold on;
end
snr_lin=10.^(snr_list/10);
semilogy(snr_list,max(0.5*erfc(sqrt(snr_lin)),1e-5),'k--','LineWidth',1,'DisplayName','QPSK uncoded');
grid on;xlabel('SNR (dB)');ylabel('BER');
title('SC-FDE 通带时变信道 BER vs SNR（6径, max\_delay=15ms）');
legend('Location','southwest');ylim([1e-5 1]);set(gca,'FontSize',12);

% 信道CIR + 频响（静态参考）
figure('Position',[100 50 800 300]);
subplot(1,2,1);
delays_ms=sym_delays/sym_rate*1000;
stem(delays_ms,abs(gains),'filled','LineWidth',1.5);
xlabel('时延(ms)');ylabel('|h|');title(sprintf('信道CIR（%d径, 静态参考）',length(sym_delays)));grid on;
subplot(1,2,2);
h_show=zeros(1,1024);
for p=1:length(sym_delays),if sym_delays(p)+1<=1024,h_show(sym_delays(p)+1)=gains(p);end,end
f_khz=(0:1023)*sym_rate/1024/1000;
plot(f_khz,20*log10(abs(fft(h_show))+1e-10),'b','LineWidth',1);
xlabel('频率(kHz)');ylabel('|H|(dB)');title('信道频响(静态)');grid on;

% 估计信道可视化：各fading配置的oracle H_est（block1）时域CIR和频响
figure('Position',[100 350 900 500]);
nfig = size(fading_cfgs,1);
for fi=1:nfig
    blk_fft_fi = fading_cfgs{fi,5};
    off_sym = 0;  % LFM精确定时后offset=0
    eff_d = mod(sym_delays - off_sym, blk_fft_fi);

    % block1 H_est的时域CIR
    h_td_est = ifft(H_est_blocks_save{fi});

    % CIR幅度
    subplot(nfig, 2, (fi-1)*2+1);
    stem((0:blk_fft_fi-1)/sym_rate*1000, abs(h_td_est), 'b', 'MarkerSize',3, 'LineWidth',0.8);
    hold on;
    % 标注有效时延位置
    for p=1:length(eff_d)
        stem(eff_d(p)/sym_rate*1000, abs(h_td_est(eff_d(p)+1)), 'r', 'filled', 'MarkerSize',6, 'LineWidth',1.5);
    end
    xlabel('时延(ms)'); ylabel('|h|');
    title(sprintf('%s: CIR (blk1, offset=%dsym)', fading_cfgs{fi,1}, off_sym));
    grid on; xlim([0 blk_fft_fi/sym_rate*1000]);

    % 频响
    subplot(nfig, 2, fi*2);
    H_est_fi = H_est_blocks_save{fi};
    f_ax = (0:blk_fft_fi-1)*sym_rate/blk_fft_fi/1000;
    plot(f_ax, 20*log10(abs(H_est_fi)+1e-10), 'b', 'LineWidth',1);
    hold on;
    % 静态参考频响
    h_ref = zeros(1, blk_fft_fi);
    for p=1:length(sym_delays), if sym_delays(p)+1<=blk_fft_fi, h_ref(sym_delays(p)+1)=gains(p); end, end
    plot(f_ax, 20*log10(abs(fft(h_ref))+1e-10), 'r--', 'LineWidth',0.8);
    xlabel('频率(kHz)'); ylabel('|H|(dB)');
    title(sprintf('%s: 频响(蓝=估计,红=静态参考)', fading_cfgs{fi,1}));
    grid on; legend('Oracle H\_est','Static ref','Location','best');
end

% 时变CIR瀑布图（2D热力图：时延×时间×幅度）
figure('Position',[50 50 1200 400]);
for fi=1:size(fading_cfgs,1)
    subplot(1, size(fading_cfgs,1), fi);
    ci = ch_info_save{fi};
    h_tv = ci.h_time;           % num_paths × N_samples
    delays_ms = ci.delays_s * 1000;  % 时延(ms)
    [np, nt] = size(h_tv);

    % 构建完整CIR矩阵（时延轴 × 时间轴）
    delay_ax_ms = linspace(0, max(delays_ms)*1.2, 200);
    t_ax_s = (0:nt-1) / ci.fs;
    % 下采样时间轴（避免矩阵太大）
    t_step = max(1, floor(nt/500));
    t_idx = 1:t_step:nt;
    t_ax_ds = t_ax_s(t_idx);

    % 在每个时间点构建CIR
    cir_map = zeros(length(delay_ax_ms), length(t_idx));
    for p = 1:np
        [~, d_idx] = min(abs(delay_ax_ms - delays_ms(p)));
        cir_map(d_idx, :) = cir_map(d_idx, :) + abs(h_tv(p, t_idx));
    end

    imagesc(t_ax_ds*1000, delay_ax_ms, 20*log10(cir_map + 1e-6));
    set(gca, 'YDir', 'normal');
    colorbar; clim([-30 max(20*log10(cir_map(:)+1e-6))]);
    colormap(gca, 'jet');
    xlabel('时间 (ms)'); ylabel('时延 (ms)');
    title(sprintf('%s: 时变CIR (dB)', fading_cfgs{fi,1}));
    set(gca, 'FontSize', 10);
end
sgtitle('时变信道冲激响应瀑布图', 'FontSize', 14);

fprintf('\n完成\n');

%% ========== 保存结果到txt ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_scfde_timevarying_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'SC-FDE 通带时变信道测试结果 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '帧结构: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]\n');
fprintf(fid, 'fs=%dHz, fc=%dHz, HFM=%.0f~%.0fHz, sps=%d\n', fs, fc, f_lo, f_hi, sps);
fprintf(fid, '信道: %d径, delays=[%s], guard=%d\n\n', length(sym_delays), num2str(sym_delays), guard_samp);

% BER表格
fprintf(fid, '=== BER ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_matrix(fi,si)*100); end
    fprintf(fid, '  (blk=%d)\n', fading_cfgs{fi,5});
end

% 同步信息
fprintf(fid, '\n=== 同步信息（LFM定时）===\n');
lfm_expected_f = 2*N_preamble + 3*guard_samp + N_lfm + 1;
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s: lfm_pos=%d (expected~%d), hfm_peak=%.3f\n', ...
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
fprintf(fid, '\n=== CP诊断 (SNR=%ddB, blk_fft/cp/rate) ===\n', snr_list(1));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s: blk_fft=%d, blk_cp=%d, N_blocks=%d, cp_denom=%.1f\n', ...
        fading_cfgs{fi,1}, fading_cfgs{fi,5}, fading_cfgs{fi,6}, fading_cfgs{fi,7}, ...
        2*pi*fc*fading_cfgs{fi,5}/sym_rate);
end

% 信道估计
fprintf(fid, '\n=== H_est block1 各径增益 ===\n');
for fi=1:size(fading_cfgs,1)
    blk_fft_fi = fading_cfgs{fi,5};
    off_sym = 0;  % LFM精确定时后offset=0
    eff_d = mod(sym_delays - off_sym, blk_fft_fi);
    h_td1 = ifft(H_est_blocks_save{fi});
    fprintf(fid, '%-8s:', fading_cfgs{fi,1});
    for p=1:length(sym_delays)
        fprintf(fid, ' %.3f<%.0f°', abs(h_td1(eff_d(p)+1)), angle(h_td1(eff_d(p)+1))*180/pi);
    end
    fprintf(fid, '\n');
end
fprintf(fid, '静态参考:');
for p=1:length(sym_delays), fprintf(fid, ' %.3f', abs(gains(p))); end
fprintf(fid, '\n');

fclose(fid);
fprintf('结果已保存: %s\n', result_file);
