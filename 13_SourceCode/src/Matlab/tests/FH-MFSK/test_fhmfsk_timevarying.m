%% test_fhmfsk_timevarying.m — FH-MFSK通带仿真 时变信道测试
% TX: 编码→交织→8-FSK映射→跳频(16位)→基带FSK波形→帧组装
% 信道: gen_uwa_channel(5径+Jakes+多普勒)→上变频→+实噪声
% RX: 下变频→LFM定时→FFT能量检测→去跳频→硬判决→译码
% 版本：V1.0.0
% 特点：非相干能量检测，无需信道估计/均衡，跳频提供频率分集

clc; close all;
fprintf('========================================\n');
fprintf('  FH-MFSK 通带仿真 — 时变信道测试 V1.0\n');
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
sym_duration = 1/freq_spacing; % 2ms (正交条件: T >= 1/Δf)
samples_per_sym = round(sym_duration * fs);  % 96

% 基带频率表: 16个频率精确对齐FFT bin (避免半bin歧义)
fb = ((0:num_freqs-1) - num_freqs/2) * freq_spacing;  % [-4000,-3500,...,0,...,+3500]
total_bw = num_freqs * freq_spacing;  % 8000Hz

% 编解码
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;
hop_seed = 42;  % 跳频种子

% 数据
N_info = 500;
M_coded = n_code * (N_info + mem);
N_sym = ceil(M_coded / bits_per_sym);            % FSK符号数
N_coded_padded = N_sym * bits_per_sym;            % 补齐到3的倍数
N_data_samples = N_sym * samples_per_sym;

% 通信速率
code_rate = 1/n_code;
info_rate_bps = bits_per_sym / sym_duration * code_rate;  % 750 bps

% 5径信道
chip_delays = [0, 1, 3, 5, 8];  % 延迟(码片=采样/sps, 这里直接用ms)
delays_s = [0, 0.167, 0.5, 0.833, 1.333] * 1e-3;  % 秒
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];

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
lfm1_peak_nom = 2*N_preamble + 2*guard_samp + N_lfm;
lfm2_peak_nom = 2*N_preamble + 3*guard_samp + 2*N_lfm;
lfm_search_margin = round(max(delays_s)*fs) + 200;
T_v_lfm = (N_lfm + guard_samp) / fs;
data_offset = N_lfm + guard_samp;  % LFM2到数据起点

snr_list = [-5, 0, 5, 10, 15, 20];
fading_cfgs = {
    'static', 'static', 0,  0;
    'fd=1Hz', 'slow',   1,  1/fc;
    'fd=5Hz', 'slow',   5,  5/fc;
};

fprintf('FH-MFSK: %d-FSK, %d跳频位, Δf=%dHz, T_sym=%.1fms\n', M, num_freqs, freq_spacing, sym_duration*1000);
fprintf('通信速率: %.0f bps (R=1/%d, %d bits/sym)\n', info_rate_bps, n_code, bits_per_sym);
fprintf('带宽: %.0f Hz ([%.0f, %.0f] Hz), 采样率 %d Hz\n', total_bw, fc-total_bw/2, fc+total_bw/2, fs);
fprintf('数据: %d FSK符号, 帧长 %.1f ms\n', N_sym, N_data_samples/fs*1000);
fprintf('信道: %d径, 相干带宽~%.0fHz (跳频间隔%dHz>相干BW→频率分集有效)\n\n', ...
    length(delays_s), 1/(5*max(delays_s)), freq_spacing);

ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));
ber_unc_matrix = zeros(size(fading_cfgs,1), length(snr_list));
sync_info_matrix = zeros(size(fading_cfgs,1), 2);

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname=fading_cfgs{fi,1}; ftype=fading_cfgs{fi,2};
    fd_hz=fading_cfgs{fi,3}; dop_rate=fading_cfgs{fi,4};

    %% ===== TX ===== %%
    rng(100+fi);
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_coded);
    [interleaved,~] = random_interleave(coded, codec.interleave_seed);

    % 补齐到bits_per_sym的整数倍
    coded_padded = [interleaved, zeros(1, N_coded_padded - M_coded)];

    % 8-FSK映射: 每3bit→freq_index [0,7]
    freq_indices = zeros(1, N_sym);
    for k = 1:N_sym
        bits3 = coded_padded((k-1)*bits_per_sym+1 : k*bits_per_sym);
        freq_indices(k) = bi2de(bits3, 'left-msb');
    end

    % 跳频
    hop_pattern = gen_hop_pattern(N_sym, num_freqs, hop_seed);
    hopped = fh_spread(freq_indices, hop_pattern, num_freqs);

    % 基带FSK波形生成 (复指数)
    fsk_bb = zeros(1, N_data_samples);
    t_sym = (0:samples_per_sym-1)/fs;
    phase_acc = 0;
    for k = 1:N_sym
        f_k = fb(hopped(k)+1);  % 基带频率
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

    %% ===== 信道 ===== %%
    ch_params = struct('fs',fs, 'delay_profile','custom', ...
        'delays_s',delays_s, 'gains',gains_raw, ...
        'num_paths',length(delays_s), 'doppler_rate',dop_rate, ...
        'fading_type',ftype, 'fading_fd_hz',fd_hz, ...
        'snr_db',Inf, 'seed',200+fi*100);
    [rx_bb_frame,~] = gen_uwa_channel(frame_bb, ch_params);
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

        % 2. 数据段提取（无多普勒补偿——能量检测天然不需要相位）
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

        % 预计算FFT bin索引 (fb精确对齐bin, 无round歧义)
        fft_bin_idx = mod(round(fb * samples_per_sym / fs), samples_per_sym) + 1;

        for k = 1:N_sym
            seg = rx_data((k-1)*samples_per_sym+1 : k*samples_per_sym);
            psd = abs(fft(seg, samples_per_sym)).^2;
            energy_matrix(k, :) = psd(fft_bin_idx);
        end

        % 去跳频: 对每个符号，将能量矩阵按hop_pattern反移
        for k = 1:N_sym
            shift = hop_pattern(k);
            energy_shifted = circshift(energy_matrix(k,:), -shift);
            [~, detected_indices(k)] = max(energy_shifted(1:M));
            detected_indices(k) = detected_indices(k) - 1;  % 0-based
        end

        % 4. FSK解映射 → bits
        detected_bits = zeros(1, N_coded_padded);
        for k = 1:N_sym
            bits3 = de2bi(detected_indices(k), bits_per_sym, 'left-msb');
            detected_bits((k-1)*bits_per_sym+1 : k*bits_per_sym) = bits3;
        end

        % 未编码BER
        ber_unc = mean(detected_bits(1:M_coded) ~= interleaved);

        % 5. 解交织 + Viterbi硬判决译码
        [~, perm] = random_interleave(zeros(1,M_coded), codec.interleave_seed);
        deint_bits = random_deinterleave(detected_bits(1:M_coded), perm);
        % 硬判决LLR: bit1→+LLR, bit0→-LLR (正值=bit1更可能)
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

% --- Figure 1: BER ---
figure('Position',[50 500 700 450]);
markers={'o-','s-','d-'}; colors=[0 .45 .74; .85 .33 .1; .47 .67 .19];
for fi=1:size(fading_cfgs,1)
    semilogy(snr_list, max(ber_matrix(fi,:),1e-5), markers{fi}, ...
        'Color',colors(fi,:),'LineWidth',1.8,'MarkerSize',7,'DisplayName',fading_cfgs{fi,1});
    hold on;
end
grid on; xlabel('SNR (dB)'); ylabel('BER');
title(sprintf('FH-%d-FSK (16跳频位) — %.0f bps (R=1/%d)', M, info_rate_bps, n_code));
legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);

% --- Figure 2: TX波形 + 频谱 ---
[frame_pb_vis,~] = upconvert(frame_bb, fs, fc);
figure('Position',[50 350 900 500]);
subplot(2,1,1);
t_f=(0:length(frame_pb_vis)-1)/fs*1000;
plot(t_f, frame_pb_vis,'b','LineWidth',0.3);
xlabel('时间 (ms)'); ylabel('幅度'); grid on;
title(sprintf('TX通带帧 (fc=%dHz, %.1fms, %.0f bps)', fc, t_f(end), info_rate_bps));
subplot(2,1,2);
Nfft_v=2^nextpow2(length(frame_pb_vis));
F_tx=fft(frame_pb_vis,Nfft_v);
f_ax=(0:Nfft_v-1)*fs/Nfft_v/1000;
plot(f_ax(1:Nfft_v/2),20*log10(abs(F_tx(1:Nfft_v/2))+1e-10),'b','LineWidth',0.8);
xlabel('频率 (kHz)'); ylabel('幅度 (dB)'); grid on; title('TX通带频谱');
xlim([0 fs/2/1000]); xline(fc/1000,'r--');
xline((fc-total_bw/2)/1000,'m--'); xline((fc+total_bw/2)/1000,'m--');

% --- Figure 3: RX波形 + 频谱 ---
figure('Position',[50 50 900 500]);
subplot(2,1,1); t_rx=(0:length(rx_pb)-1)/fs*1000;
plot(t_rx, rx_pb,'b','LineWidth',0.3);
xlabel('时间 (ms)'); ylabel('幅度'); grid on;
title(sprintf('RX通带 (SNR=%ddB, %s)', snr_list(end), fading_cfgs{end,1}));
subplot(2,1,2);
Nfft_r=2^nextpow2(length(rx_pb)); F_rx=fft(rx_pb,Nfft_r);
f_rx=(0:Nfft_r-1)*fs/Nfft_r/1000;
plot(f_rx(1:Nfft_r/2),20*log10(abs(F_rx(1:Nfft_r/2))+1e-10),'b','LineWidth',0.8);
xlabel('频率 (kHz)'); ylabel('幅度 (dB)'); grid on; title('RX通带频谱');
xlim([0 fs/2/1000]); xline(fc/1000,'r--');

% --- Figure 4: 频谱图 (时频跳频图案) ---
figure('Position',[770 350 500 400]);
N_show = min(50, N_sym);
imagesc(1:N_show, fb/1000, energy_matrix(1:N_show,:).');
axis xy; colorbar; xlabel('符号序号'); ylabel('基带频率 (kHz)');
title(sprintf('RX能量矩阵 (前%d符号, SNR=%ddB)', N_show, snr_list(end)));

fprintf('\n--- 同步 ---\n');
for fi=1:size(fading_cfgs,1)
    fprintf('%-8s: lfm_pos=%d\n', fading_cfgs{fi,1}, sync_info_matrix(fi,1));
end
fprintf('\n完成\n');

%% ========== 保存结果 ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_fhmfsk_timevarying_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'FH-MFSK 时变信道测试结果 V1.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'FH-%d-FSK, %d跳频位, Δf=%dHz, T_sym=%.1fms\n', M, num_freqs, freq_spacing, sym_duration*1000);
fprintf(fid, '通信速率: %.0f bps (R=1/%d, %d bits/sym)\n', info_rate_bps, n_code, bits_per_sym);
fprintf(fid, '信道: %d径, 相干BW~%.0fHz\n\n', length(delays_s), 1/(5*max(delays_s)));

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
fclose(fid);
fprintf('结果已保存: %s\n', result_file);
