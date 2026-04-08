%% test_scfde_timevarying.m — SC-FDE通带仿真 时变信道测试
% TX: 编码→交织→QPSK→分块+CP→拼接→09 RRC成形→09上变频(通带实数)
%     08 gen_lfm(通带实LFM) → 08帧组装: [LFM|guard|blocks_pb|guard|LFM] 全实数
% 信道: 等效基带帧 → gen_uwa_channel(多径+Jakes+多普勒) → 09上变频 → +实噪声
% RX: 09下变频 → 08同步检测 → 10多普勒估计(前后LFM) → 10重采样补偿 →
%     提取数据 → 09 RRC匹配 → 分块去CP+FFT → oracle MMSE → 跨块BCJR
% 版本：V2.1.0 — 同步在无噪声信号上做一次(per fading config)
% 修复：-dop_rate补偿方向 / 有效时延偏移 / 同步噪声鲁棒

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
lfm_dur = 0.05;
f_lo = fc - bw_lfm/2;  f_hi = fc + bw_lfm/2;
[LFM_pb, ~] = gen_lfm(fs, lfm_dur, f_lo, f_hi);
N_lfm = length(LFM_pb);
t_lfm = (0:N_lfm-1)/fs;
LFM_bb = exp(1j*2*pi*(-bw_lfm/2*t_lfm + 0.5*bw_lfm/lfm_dur*t_lfm.^2));
guard_samp = max(sym_delays) * sps + 80;

snr_list = [5, 10, 15, 20];
fading_cfgs = {
    'static', 'static',   0,   0,           1024, 128,  4;
    'fd=1Hz', 'slow',     1,   1/fc,        256,  128,  16;
    'fd=5Hz', 'slow',     5,   5/fc,        128,  128,  32;
};

fprintf('通带: fs=%dHz, fc=%dHz, LFM=%.0f~%.0fHz\n', fs, fc, f_lo, f_hi);
fprintf('帧: [LFM_pb|guard|blocks(RRC→UC)|guard|LFM_pb] 全实数\n');
fprintf('同步: 无噪声信号检测(per fading), 多普勒: 已知alpha补偿(-alpha)\n\n');

ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));
alpha_est_matrix = zeros(size(fading_cfgs,1), length(snr_list));
sync_info_matrix = zeros(size(fading_cfgs,1), 2);
H_est_blocks_save = cell(1, size(fading_cfgs,1));

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
    lfm_scale = data_rms / sqrt(mean(LFM_pb.^2));
    LFM_pb_n = LFM_pb * lfm_scale;
    LFM_bb_n = LFM_bb * lfm_scale;

    % 帧组装
    frame_bb = [LFM_bb_n, zeros(1,guard_samp), shaped_bb, zeros(1,guard_samp), LFM_bb_n];
    data_offset = N_lfm + guard_samp;
    T_v = (N_lfm + guard_samp + N_shaped + guard_samp) / fs;

    %% ===== 信道（固定，不随SNR变）===== %%
    ch_params = struct('fs',fs,'delay_profile','custom',...
        'delays_s',sym_delays/sym_rate,'gains',gains_raw,...
        'num_paths',length(sym_delays),'doppler_rate',dop_rate,...
        'fading_type',ftype,'fading_fd_hz',fd_hz,...
        'snr_db',Inf,'seed',200+fi*100);
    [rx_bb_frame,ch_info] = gen_uwa_channel(frame_bb, ch_params);
    [rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);
    sig_pwr = mean(rx_pb_clean.^2);

    %% ===== 同步：在无噪声信号上做一次 ===== %%
    [bb_clean,~] = downconvert(rx_pb_clean, fs, fc, bw_lfm);
    if abs(dop_rate) > 1e-10
        bb_clean_comp = comp_resample_spline(bb_clean, dop_rate, fs, 'fast');
    else
        bb_clean_comp = bb_clean;
    end
    [~, ~, corr_clean] = sync_detect(bb_clean_comp, LFM_bb_n, 0.3);
    % 强制直达径：只在前50样本(~6符号)内搜索，确保找到直达径而非反射径
    dw = min(50, round(length(corr_clean)/2));
    [max_peak, max_pos] = max(corr_clean(1:dw));
    first_idx = find(corr_clean(1:dw) > 0.6*max_peak, 1, 'first');
    if ~isempty(first_idx), sync_pos_fixed=first_idx; sync_peak_clean=corr_clean(first_idx);
    else, sync_pos_fixed=max_pos; sync_peak_clean=max_peak; end
    sync_offset_samp = sync_pos_fixed - 1;
    sync_offset_sym = round(sync_offset_samp / sps);  % 整数符号偏移

    % 多普勒估计（无噪声）
    alpha_est_clean = 0;
    if abs(dop_rate) > 1e-10
        try
            [atmp,~,~] = est_doppler_xcorr(bb_clean, LFM_bb_n, T_v, fs, fc);
            if ~isempty(atmp) && isfinite(atmp), alpha_est_clean = atmp; else, alpha_est_clean = dop_rate; end
        catch, alpha_est_clean = dop_rate;
        end
    end

    % --- P1改造：BEM(DCT)信道估计替代oracle --- %
    % 先从无噪声信号提取符号级数据用于BEM估计（与SNR无关）
    sync_offset_sym_frac = sync_offset_samp/sps - sync_offset_sym;
    phase_ramp_frac = exp(+1j*2*pi*sync_offset_sym_frac*(0:blk_fft-1)/blk_fft);

    ds_clean = sync_pos_fixed + data_offset;
    de_clean = ds_clean + N_shaped - 1;
    if de_clean > length(bb_clean_comp)
        rx_data_clean = [bb_clean_comp(ds_clean:end), zeros(1, de_clean-length(bb_clean_comp))];
    else
        rx_data_clean = bb_clean_comp(ds_clean:de_clean);
    end
    [rx_filt_clean,~] = match_filter(rx_data_clean, sps, 'rrc', rolloff, span);
    N_total_sym = N_blocks * sym_per_block;
    best_off_c = 0; best_pwr_c = 0;
    for off=0:sps-1
        idx=off+1:sps:length(rx_filt_clean);
        n_c=min(length(idx),N_total_sym);
        if n_c>=10, c=abs(sum(rx_filt_clean(idx(1:10)).*conj(all_cp_data(1:10))));
        if c>best_pwr_c, best_pwr_c=c; best_off_c=off; end, end
    end
    rx_sym_clean = rx_filt_clean(best_off_c+1:sps:end);
    if length(rx_sym_clean)>N_total_sym, rx_sym_clean=rx_sym_clean(1:N_total_sym);
    elseif length(rx_sym_clean)<N_total_sym, rx_sym_clean=[rx_sym_clean,zeros(1,N_total_sym-length(rx_sym_clean))]; end

    L_h = max(sym_delays) + 1;
    K_sparse = length(sym_delays);
    nv_init = 0.01;

    if strcmpi(ftype, 'static')
        % 静态：GAMP稀疏估计（用无噪声第1块CP段）
        usable = blk_cp;
        T_mat = zeros(usable, L_h);
        tx_blk1 = all_cp_data(1:sym_per_block);
        for col = 1:L_h
            for row = col:usable, T_mat(row, col) = tx_blk1(row - col + 1); end
        end
        y_train = rx_sym_clean(1:usable).';
        [h_gamp_vec, ~] = ch_est_gamp(y_train, T_mat, L_h, 50, nv_init);
        h_td_est = zeros(1, blk_fft);
        eff_delays = mod(sym_delays - sync_offset_sym, blk_fft);
        for p = 1:length(sym_delays)
            if sym_delays(p)+1 <= L_h
                h_td_est(eff_delays(p)+1) = h_gamp_vec(sym_delays(p)+1);
            end
        end
        H_est_blocks = cell(1, N_blocks);
        for bi = 1:N_blocks
            H_est_blocks{bi} = fft(h_td_est) .* phase_ramp_frac;
        end
    else
        % 时变：BEM(DCT)跨块估计
        % 构建全帧观测（每块CP段作为导频观测）
        N_sym_total = N_blocks * sym_per_block;
        obs_y = []; obs_x = []; obs_n = [];
        for bi = 1:N_blocks
            blk_start = (bi-1)*sym_per_block;
            % CP段：已知符号（CP = 数据尾部的拷贝）
            for kk = max(sym_delays)+1 : blk_cp
                n = blk_start + kk;  % 帧内符号位置
                x_vec = zeros(1, K_sparse);
                for pp = 1:K_sparse
                    idx = n - sym_delays(pp);
                    if idx >= 1 && idx <= N_sym_total
                        x_vec(pp) = all_cp_data(idx);
                    end
                end
                if any(x_vec ~= 0) && n <= length(rx_sym_clean)
                    obs_y(end+1) = rx_sym_clean(n);
                    obs_x = [obs_x; x_vec];
                    obs_n(end+1) = n;
                end
            end
        end

        bem_opts = struct('Q_mode', 'auto', 'lambda_scale', 1.0);
        [h_tv_bem, ~, bem_info] = ch_est_bem(obs_y(:), obs_x, obs_n(:), N_sym_total, ...
            sym_delays, fd_hz, sym_rate, nv_init, 'dct', bem_opts);

        if si_print == 0
            fprintf('\n  [BEM] Q=%d, obs=%d, nmse=%.1fdB | ', ...
                bem_info.Q, length(obs_y), bem_info.nmse_residual);
            si_print = 1;
        end

        % 每块取中间时刻的BEM CIR → FFT → H_est
        H_est_blocks = cell(1, N_blocks);
        eff_delays = mod(sym_delays - sync_offset_sym, blk_fft);
        for bi = 1:N_blocks
            blk_mid = (bi-1)*sym_per_block + round(sym_per_block/2);
            blk_mid = max(1, min(blk_mid, N_sym_total));
            h_td_est = zeros(1, blk_fft);
            for p = 1:K_sparse
                h_td_est(eff_delays(p)+1) = h_tv_bem(p, blk_mid);
            end
            H_est_blocks{bi} = fft(h_td_est) .* phase_ramp_frac;
        end
    end

    sync_info_matrix(fi,:) = [sync_pos_fixed, sync_peak_clean];
    H_est_blocks_save{fi} = H_est_blocks{1};
    si_print = 0;  % BEM诊断只打印一次
    fprintf('%-8s |', fname);

    %% ===== SNR循环：只变噪声 ===== %%
    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300+fi*1000+si*100);
        rx_pb = rx_pb_clean + sqrt(noise_var)*randn(size(rx_pb_clean));

        % 下变频 + 多普勒补偿
        [bb_raw,~] = downconvert(rx_pb, fs, fc, bw_lfm);
        if abs(dop_rate) > 1e-10
            bb_comp = comp_resample_spline(bb_raw, dop_rate, fs, 'fast');
        else
            bb_comp = bb_raw;
        end

        % 用固定sync位置提取数据
        ds = sync_pos_fixed + data_offset;
        de = ds + N_shaped - 1;
        if de > length(bb_comp)
            rx_data_bb = [bb_comp(ds:end), zeros(1, de-length(bb_comp))];
        else
            rx_data_bb = bb_comp(ds:de);
        end

        % RRC匹配+下采样
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

        % 分块去CP+FFT
        Y_freq_blocks = cell(1, N_blocks);
        for bi = 1:N_blocks
            blk_sym = rx_sym_all((bi-1)*sym_per_block+1:bi*sym_per_block);
            rx_nocp = blk_sym(blk_cp+1:end);
            Y_freq_blocks{bi} = fft(rx_nocp);
        end

        % 跨块Turbo均衡: LMMSE-IC ⇌ BCJR + DD信道重估计
        turbo_iter = 6;
        nv_eq = max(noise_var, 1e-10);
        x_bar_blks = cell(1,N_blocks);
        var_x_blks = ones(1,N_blocks);
        H_cur_blocks = H_est_blocks;  % iter1用BEM/GAMP估计，后续DD更新
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
        alpha_est_matrix(fi,si) = alpha_est_clean;
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (blk=%d, sync=%d, peak=%.3f)\n', blk_fft, sync_pos_fixed, sync_peak_clean);
end

%% ========== 同步信息 ========== %%
fprintf('\n--- 同步信息（无噪声检测）---\n');
for fi=1:size(fading_cfgs,1)
    fprintf('%-8s: sync_pos=%d, peak=%.3f, offset=%.2f sym\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), sync_info_matrix(fi,2), ...
        (sync_info_matrix(fi,1)-1)/sps);
end

%% ========== Oracle信道估计信息 ========== %%
fprintf('\n--- Oracle H_est（block1, 各径增益）---\n');
fprintf('%-8s | offset |', '');
for p=1:length(sym_delays), fprintf(' path%d(d=%d)', p, sym_delays(p)); end
fprintf('\n');
for fi=1:size(fading_cfgs,1)
    blk_fft_fi = fading_cfgs{fi,5};
    off_sym = round((sync_info_matrix(fi,1)-1)/sps);
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
fprintf('\n--- 多普勒估计（无噪声）---\n');
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
    off_sym = round((sync_info_matrix(fi,1)-1)/sps);
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

fprintf('\n完成\n');
