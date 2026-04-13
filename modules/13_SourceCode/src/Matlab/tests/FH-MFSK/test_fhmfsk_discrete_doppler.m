%% test_fhmfsk_discrete_doppler.m — FH-MFSK 离散Doppler/混合Rician信道对比
% TX: 编码->交织->8-FSK映射->跳频(16位)->基带FSK波形->帧组装
% 信道: apply_channel(离散Doppler/Rician混合/Jakes) — 等效基带
% RX: 下变频->LFM定时->FFT能量检测->去跳频->硬判决->译码
% 版本：V1.0.0 — 6种信道模型对比 (对标SC-FDE V1.0/OTFS V2.0信道配置)
% 特点：非相干能量检测，无需信道估计/均衡，跳频提供频率分集

clc; close all;
fprintf('========================================\n');
fprintf('  FH-MFSK 离散Doppler信道对比 V1.0\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

%% ========== 参数 ========== %%
fs = 48000; fc = 12000;

% FSK参数
M = 8;                       % 8-FSK
bits_per_sym = log2(M);      % 3 bits/sym
num_freqs = 16;              % 16个跳频位
freq_spacing = 500;          % 频率间隔(Hz), 保证正交
sym_duration = 1/freq_spacing; % 2ms (正交条件: T >= 1/df)
samples_per_sym = round(sym_duration * fs);  % 96

% 基带频率表: 16个频率精确对齐FFT bin
fb = ((0:num_freqs-1) - num_freqs/2) * freq_spacing;
total_bw = num_freqs * freq_spacing;  % 8000Hz

% 编解码
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;
hop_seed = 42;

% 数据
N_info = 500;
M_coded = n_code * (N_info + mem);
N_sym = ceil(M_coded / bits_per_sym);
N_coded_padded = N_sym * bits_per_sym;
N_data_samples = N_sym * samples_per_sym;

% 通信速率
code_rate = 1/n_code;
info_rate_bps = bits_per_sym / sym_duration * code_rate;  % 750 bps

% 5径信道
delays_s = [0, 0.167, 0.5, 0.833, 1.333] * 1e-3;  % 秒
delay_samp = round(delays_s * fs);  % 样本级时延 @fs=48kHz
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];

% 每径Doppler频移 (5径)
doppler_per_path = [0, 3, -4, 5, -2];  % Hz

%% ========== 帧参数 ========== %%
preamble_dur = 0.05;
f_lo = fc - total_bw/2; f_hi = fc + total_bw/2;
[HFM_pb,~] = gen_hfm(fs, preamble_dur, f_lo, f_hi);
N_preamble = length(HFM_pb);
t_pre = (0:N_preamble-1)/fs;

f0=f_lo; f1=f_hi; T_pre=preamble_dur;
if abs(f1-f0)<1e-6, phase_hfm=2*pi*f0*t_pre;
else, k_hfm=f0*f1*T_pre/(f1-f0); phase_hfm=-2*pi*k_hfm*log(1-(f1-f0)/f1*t_pre/T_pre); end
HFM_bb = exp(1j*(phase_hfm - 2*pi*fc*t_pre));

if abs(f1-f0)<1e-6, ph_neg=2*pi*f1*t_pre;
else, k_neg=f1*f0*T_pre/(f0-f1); ph_neg=-2*pi*k_neg*log(1-(f0-f1)/f0*t_pre/T_pre); end
HFM_bb_neg = exp(1j*(ph_neg - 2*pi*fc*t_pre));

chirp_rate_lfm=(f_hi-f_lo)/preamble_dur;
phase_lfm=2*pi*(f_lo*t_pre + 0.5*chirp_rate_lfm*t_pre.^2);
LFM_bb = exp(1j*(phase_lfm - 2*pi*fc*t_pre));
N_lfm = length(LFM_bb);
guard_samp = round(max(delays_s)*fs) + 80;

% LFM标称位置
lfm2_peak_nom = 2*N_preamble + 3*guard_samp + 2*N_lfm;
lfm_search_margin = round(max(delays_s)*fs) + 200;
data_offset = N_lfm + guard_samp;  % LFM2到数据起点

%% ========== 信道配置（6种，对标SC-FDE/OTFS）========== %%
snr_list = [-5, 0, 5, 10, 15, 20];
fading_cfgs = {
    'static',   'static',   zeros(1,5),  0;
    'disc-5Hz', 'discrete', doppler_per_path, 5;
    'hyb-K20',  'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',0.5, 'K_rice',20), 5;
    'hyb-K10',  'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',0.5, 'K_rice',10), 5;
    'hyb-K5',   'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',1.0, 'K_rice',5),  5;
    'jakes5Hz', 'jakes',    5, 5;
};

fprintf('FH-MFSK: %d-FSK, %d跳频位, df=%dHz, T_sym=%.1fms\n', M, num_freqs, freq_spacing, sym_duration*1000);
fprintf('通信速率: %.0f bps (R=1/%d, %d bits/sym)\n', info_rate_bps, n_code, bits_per_sym);
fprintf('信道: %d径, delays=[%s]ms, 每径Doppler=[%s]Hz\n', ...
    length(delays_s), num2str(delays_s*1000,'%.3f '), num2str(doppler_per_path));
fprintf('相干BW~%.0fHz (跳频间隔%dHz>相干BW→频率分集有效)\n\n', 1/(5*max(delays_s)), freq_spacing);

N_fading = size(fading_cfgs, 1);
ber_matrix = zeros(N_fading, length(snr_list));
ber_unc_matrix = zeros(N_fading, length(snr_list));
sync_info_matrix = zeros(N_fading, 2);

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:N_fading
    fname   = fading_cfgs{fi,1};
    ftype   = fading_cfgs{fi,2};
    fparams = fading_cfgs{fi,3};
    fd_hz   = fading_cfgs{fi,4};

    %% ===== TX ===== %%
    rng(100+fi);
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_coded);
    [interleaved,~] = random_interleave(coded, codec.interleave_seed);

    coded_padded = [interleaved, zeros(1, N_coded_padded - M_coded)];

    % 8-FSK映射
    freq_indices = zeros(1, N_sym);
    for k = 1:N_sym
        bits3 = coded_padded((k-1)*bits_per_sym+1 : k*bits_per_sym);
        freq_indices(k) = bi2de(bits3, 'left-msb');
    end

    % 跳频
    hop_pattern = gen_hop_pattern(N_sym, num_freqs, hop_seed);
    hopped = fh_spread(freq_indices, hop_pattern, num_freqs);

    % 基带FSK波形生成
    fsk_bb = zeros(1, N_data_samples);
    t_sym = (0:samples_per_sym-1)/fs;
    phase_acc = 0;
    for k = 1:N_sym
        f_k = fb(hopped(k)+1);
        seg = exp(1j*(2*pi*f_k*t_sym + phase_acc));
        fsk_bb((k-1)*samples_per_sym+1 : k*samples_per_sym) = seg;
        phase_acc = phase_acc + 2*pi*f_k*samples_per_sym/fs;
    end

    % 功率归一化
    [fsk_pb_ref,~] = upconvert(fsk_bb, fs, fc);
    data_rms = sqrt(mean(fsk_pb_ref.^2));
    lfm_scale = data_rms / sqrt(mean(HFM_pb.^2));
    HFM_bb_n=HFM_bb*lfm_scale; HFM_bb_neg_n=HFM_bb_neg*lfm_scale; LFM_bb_n=LFM_bb*lfm_scale;

    % 帧组装
    frame_bb = [HFM_bb_n, zeros(1,guard_samp), HFM_bb_neg_n, zeros(1,guard_samp), ...
                LFM_bb_n, zeros(1,guard_samp), LFM_bb_n, zeros(1,guard_samp), fsk_bb];

    %% ===== 信道（apply_channel替代gen_uwa_channel）===== %%
    rx_bb_frame = apply_channel(frame_bb, delay_samp, gains_raw, ftype, fparams, fs, fc);
    [rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);
    sig_pwr = mean(rx_pb_clean.^2);

    % 无噪声sync
    mf_lfm = conj(fliplr(LFM_bb_n));
    lfm2_search_len = min(3*N_preamble+4*guard_samp+2*N_lfm, length(rx_bb_frame));
    [bb_clean,~] = downconvert(rx_pb_clean, fs, fc, total_bw);
    corr_c = abs(filter(mf_lfm, 1, bb_clean));
    c2_lo=max(1,lfm2_peak_nom-lfm_search_margin);
    c2_hi=min(lfm2_peak_nom+lfm_search_margin,length(corr_c));
    [~,l2]=max(corr_c(c2_lo:c2_hi));
    lfm_pos = c2_lo+l2-1 - N_lfm+1;
    sync_info_matrix(fi,:) = [lfm_pos, max(corr_c)/sum(abs(LFM_bb_n).^2)];

    fprintf('%-8s |', fname);

    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300+fi*1000+si*100);
        rx_pb = rx_pb_clean + sqrt(noise_var)*randn(size(rx_pb_clean));

        % 1. 下变频
        [bb_raw,~] = downconvert(rx_pb, fs, fc, total_bw);

        % 2. 数据段提取
        ds = lfm_pos + data_offset;
        de = ds + N_data_samples - 1;
        if de > length(bb_raw)
            rx_data = [bb_raw(ds:end), zeros(1, de-length(bb_raw))];
        else
            rx_data = bb_raw(ds:de);
        end

        % 3. FFT能量检测 + 去跳频
        detected_indices = zeros(1, N_sym);
        energy_matrix = zeros(N_sym, num_freqs);
        fft_bin_idx = mod(round(fb * samples_per_sym / fs), samples_per_sym) + 1;

        for k = 1:N_sym
            seg = rx_data((k-1)*samples_per_sym+1 : k*samples_per_sym);
            psd = abs(fft(seg, samples_per_sym)).^2;
            energy_matrix(k, :) = psd(fft_bin_idx);
        end

        for k = 1:N_sym
            shift = hop_pattern(k);
            energy_shifted = circshift(energy_matrix(k,:), -shift);
            [~, detected_indices(k)] = max(energy_shifted(1:M));
            detected_indices(k) = detected_indices(k) - 1;
        end

        % 4. FSK解映射
        detected_bits = zeros(1, N_coded_padded);
        for k = 1:N_sym
            bits3 = de2bi(detected_indices(k), bits_per_sym, 'left-msb');
            detected_bits((k-1)*bits_per_sym+1 : k*bits_per_sym) = bits3;
        end

        ber_unc = mean(detected_bits(1:M_coded) ~= interleaved);

        % 5. 解交织 + Viterbi
        [~, perm] = random_interleave(zeros(1,M_coded), codec.interleave_seed);
        deint_bits = random_deinterleave(detected_bits(1:M_coded), perm);
        hard_llr = (2*deint_bits - 1) * 10;
        [~,Lp_info,~] = siso_decode_conv(hard_llr, [], codec.gen_polys, ...
            codec.constraint_len, codec.decode_mode);
        bits_out = double(Lp_info > 0);

        nc = min(length(bits_out), N_info);
        ber = mean(bits_out(1:nc) ~= info_bits(1:nc));
        ber_matrix(fi,si) = ber;
        ber_unc_matrix(fi,si) = ber_unc;
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (lfm=%d)\n', sync_info_matrix(fi,1));
end

%% ========== 可视化 ========== %%
figure('Position',[50 500 800 450]);
markers={'o-','s-','d-','^-','v-','x-'};
colors=[0 .45 .74; .85 .33 .1; .47 .67 .19; .93 .69 .13; .49 .18 .56; .3 .3 .3];
for fi=1:N_fading
    semilogy(snr_list, max(ber_matrix(fi,:),1e-5), markers{fi}, ...
        'Color',colors(fi,:),'LineWidth',1.8,'MarkerSize',7,'DisplayName',fading_cfgs{fi,1});
    hold on;
end
grid on; xlabel('SNR (dB)'); ylabel('BER');
title(sprintf('FH-%d-FSK 离散Doppler信道对比 — %.0f bps', M, info_rate_bps));
legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);

fprintf('\n--- 同步 ---\n');
for fi=1:N_fading
    fprintf('%-8s: lfm_pos=%d, peak=%.3f\n', fading_cfgs{fi,1}, sync_info_matrix(fi,1), sync_info_matrix(fi,2));
end
fprintf('\n完成\n');

%% ========== 保存结果 ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_fhmfsk_discrete_doppler_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'FH-MFSK 离散Doppler信道对比 V1.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'FH-%d-FSK, %d跳频位, df=%dHz, T_sym=%.1fms\n', M, num_freqs, freq_spacing, sym_duration*1000);
fprintf(fid, '通信速率: %.0f bps (R=1/%d, %d bits/sym)\n', info_rate_bps, n_code, bits_per_sym);
fprintf(fid, '信道: %d径, 每径Doppler=[%s]Hz\n\n', length(delays_s), num2str(doppler_per_path));

fprintf(fid, '=== BER (coded) ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:N_fading
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

fprintf(fid, '\n=== BER (uncoded) ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:N_fading
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_unc_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

fprintf(fid, '\n=== 同步 ===\n');
for fi=1:N_fading
    fprintf(fid, '%-8s: lfm_pos=%d, peak=%.3f\n', fading_cfgs{fi,1}, sync_info_matrix(fi,1), sync_info_matrix(fi,2));
end
fclose(fid);
fprintf('结果已保存: %s\n', result_file);
