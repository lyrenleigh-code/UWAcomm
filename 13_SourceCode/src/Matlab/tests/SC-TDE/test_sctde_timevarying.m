%% test_sctde_timevarying.m — SC-TDE通带仿真 时变信道测试
% TX: 编码→交织→QPSK→[训练+数据]→09 RRC成形(基带)→09上变频(通带实数)
%     08 gen_lfm(通带实LFM) → 08帧组装: [LFM|guard|data_pb|guard|LFM] 全实数
% 信道: 等效基带帧 → gen_uwa_channel(多径+Jakes+多普勒) → 09上变频 → +实噪声
% RX: 09下变频 → 08同步检测(无噪声,直达径窗口) → 10多普勒估计 →
%     10重采样补偿(-alpha) → 提取数据 → 09 RRC匹配 → 下采样 →
%     12 Turbo均衡(RLS+PLL+BCJR) → 译码
% 版本：V3.1.0 — 对齐SC-FDE V2.1（无噪声sync+直达径窗口+-alpha+固定seed）

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

    %% ===== TX（固定）===== %%
    rng(100+fi);
    info_bits = randi([0 1],1,N_info);
    coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
    coded = coded(1:M_coded);
    [inter_all,~] = random_interleave(coded,codec.interleave_seed);
    data_sym = bits2qpsk(inter_all);
    training = constellation(randi(4,1,train_len));
    tx_sym = [training, data_sym];

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
    [sync_peak_clean, sync_pos_fixed] = max(corr_clean(1:dw));

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
        if de > length(bb_comp), rx_data_bb=[bb_comp(ds:end),zeros(1,de-length(bb_comp))];
        else, rx_data_bb=bb_comp(ds:de); end

        % RRC匹配+下采样
        [rx_filt,~] = match_filter(rx_data_bb, sps, 'rrc', rolloff, span_rrc);
        best_off=0; best_pwr=0;
        for off=0:sps-1, st=rx_filt(off+1:sps:end);
            if length(st)>=10,c=abs(sum(st(1:10).*conj(tx_sym(1:10))));if c>best_pwr,best_pwr=c;best_off=off;end,end,end
        rx_sym_recv = rx_filt(best_off+1:sps:end);
        N_tx = length(tx_sym);
        if length(rx_sym_recv)>N_tx, rx_sym_recv=rx_sym_recv(1:N_tx);
        elseif length(rx_sym_recv)<N_tx, rx_sym_recv=[rx_sym_recv,zeros(1,N_tx-length(rx_sym_recv))]; end

        % 07-GAMP信道估计（从训练序列）
        rx_train = rx_sym_recv(1:train_len);
        L_h = max(sym_delays)+1;
        K_sparse = length(sym_delays);
        T_mat = zeros(train_len, L_h);
        for col = 1:L_h
            T_mat(col:train_len, col) = training(1:train_len-col+1).';
        end
        [h_gamp_vec, ~] = ch_est_gamp(rx_train(:), T_mat, L_h, 50, noise_var);
        h_est_gamp = h_gamp_vec(:).';

        if strcmpi(ftype, 'static')
            %% === 静态：标准Turbo（DFE iter1 + 固定h_est ISI消除 iter2+）===
            [bits_out,~] = turbo_equalizer_sctde(rx_sym_recv, h_est_gamp, training, ...
                turbo_iter, noise_var, eq_params, codec);
        else
            %% === 时变：DFE iter1 + Kalman跟踪ISI消除 iter2+ ===
            h_paths_init = h_est_gamp(sym_delays+1);
            T = train_len; N_dsym = N_tx - T;
            nv_eq = max(noise_var, 1e-10);
            P_paths = length(sym_delays);

            % Kalman AR(1)参数
            alpha_ar = besselj(0, 2*pi*fd_hz/sym_rate);
            q_proc = (1 - alpha_ar^2) * max(mean(abs(h_paths_init).^2), 1e-6);
            q_proc = max(q_proc, 1e-8);

            % iter 1: DFE
            [LLR_dfe, ~, nv_dfe] = eq_dfe(rx_sym_recv, h_est_gamp, training, ...
                eq_params.num_ff, eq_params.num_fb, eq_params.lambda, eq_params.pll);
            LLR_eq = -LLR_dfe;
            nv_zf = nv_dfe;

            [~,perm_turbo] = random_interleave(zeros(1,M_coded), codec.interleave_seed);
            bits_decoded = [];

            for titer = 1:turbo_iter
                LLR_trunc = LLR_eq(1:min(length(LLR_eq),M_coded));
                if length(LLR_trunc)<M_coded, LLR_trunc=[LLR_trunc,zeros(1,M_coded-length(LLR_trunc))]; end
                Le_deint = random_deinterleave(LLR_trunc, perm_turbo);
                Le_deint = max(min(Le_deint,30),-30);
                [~,Lp_info,Lp_coded] = siso_decode_conv(Le_deint,[],codec.gen_polys,...
                    codec.constraint_len,codec.decode_mode);
                bits_decoded = double(Lp_info > 0);

                if titer < turbo_iter
                    Lp_inter = random_interleave(Lp_coded, codec.interleave_seed);
                    if length(Lp_inter)<M_coded, Lp_inter=[Lp_inter,zeros(1,M_coded-length(Lp_inter))];
                    else, Lp_inter=Lp_inter(1:M_coded); end
                    [x_bar_data, ~] = soft_mapper(Lp_inter, 'qpsk');

                    % 全帧软符号
                    full_soft = zeros(1, N_tx);
                    full_soft(1:T) = training;
                    n_fill = min(length(x_bar_data), N_dsym);
                    if n_fill>0, full_soft(T+1:T+n_fill) = x_bar_data(1:n_fill); end

                    % Kalman稀疏信道跟踪（6维）
                    h_kalman = zeros(P_paths, N_dsym);
                    hk = h_paths_init(:);
                    Pk = q_proc * 10 * eye(P_paths);  % 初始不确定性较大
                    for n = 1:N_dsym
                        nn = T + n;
                        hk_pred = alpha_ar * hk;
                        Pk_pred = alpha_ar^2 * Pk + q_proc * eye(P_paths);
                        phi = zeros(P_paths, 1);
                        for pp = 1:P_paths
                            idx = nn - sym_delays(pp);
                            if idx >= 1 && idx <= N_tx, phi(pp) = full_soft(idx); end
                        end
                        innov = rx_sym_recv(nn) - phi' * hk_pred;
                        S = phi' * Pk_pred * phi + nv_eq;
                        Kgain = Pk_pred * phi / S;
                        hk = hk_pred + Kgain * innov;
                        Pk = (eye(P_paths) - Kgain * phi') * Pk_pred;
                        h_kalman(:, n) = hk;
                    end

                    % 时变ISI消除 + 单抽头ZF
                    data_eq = zeros(1, N_dsym);
                    for n = 1:N_dsym
                        nn = T + n;
                        isi = 0;
                        for pp = 1:P_paths
                            d = sym_delays(pp);
                            idx = nn - d;
                            if idx >= 1 && idx <= N_tx && d > 0
                                isi = isi + h_kalman(pp,n) * full_soft(idx);
                            end
                        end
                        h0_n = h_kalman(1,n);
                        rx_ic = rx_sym_recv(nn) - isi;
                        if abs(h0_n)>1e-6, data_eq(n)=rx_ic/h0_n; else, data_eq(n)=rx_ic; end
                    end

                    nv_post = nv_zf / max(mean(abs(h_kalman(1,:)).^2), 1e-6);
                    LLR_eq = zeros(1, 2*N_dsym);
                    LLR_eq(1:2:end) = -2*sqrt(2)*real(data_eq)/nv_post;
                    LLR_eq(2:2:end) = -2*sqrt(2)*imag(data_eq)/nv_post;
                end
            end
            bits_out = bits_decoded;
        end

        nc = min(length(bits_out),N_info);
        ber = mean(bits_out(1:nc)~=info_bits(1:nc));
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
