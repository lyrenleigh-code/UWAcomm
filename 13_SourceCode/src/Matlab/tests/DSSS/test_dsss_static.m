%% test_dsss_static.m — DSSS通带仿真 静态信道测试
% TX: 编码→BPSK(±1)→dsss_spread(Gold31)→RRC成形(码片率)→上变频→帧组装
%     帧: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|train_chips|data_chips]
% 信道: 等效基带帧→gen_uwa_channel(5径静态)→上变频→+实噪声
% RX: 下变频→LFM定时→RRC匹配→下采样到码片率→训练估信道→Rake(MRC)→硬判决→译码
% 版本：V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  DSSS 通带仿真 — 静态信道测试 V1.0\n');
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
chip_rate = 6000;  % 码片率 = 其他体制的符号率
sps = 8;           % 每码片采样数
fs = chip_rate * sps;  % 48kHz
fc = 12000;
rolloff = 0.35;
span_rrc = 6;

% 扩频参数
L = 31;            % Gold码长 (degree=5)
spread_code = gen_gold_code(5, 0);       % Gold码 (0/1)
spread_code_pm = 2*spread_code - 1;      % ±1形式
dsss_sym_rate = chip_rate / L;           % DSSS符号率 ≈ 193.5 sym/s

% 编解码
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;

% 数据参数
N_info = 500;                         % 信息比特数
M_coded = n_code * (N_info + mem);    % 编码后比特数
N_dsss_sym = M_coded;                 % BPSK: 1 bit/sym
N_data_chips = N_dsss_sym * L;        % 数据码片数
train_sym = 100;                      % 训练DSSS符号数
train_chips = train_sym * L;          % 训练码片数

% 5径水声信道 (delays < L, 无符号间干扰)
chip_delays = [0, 1, 3, 5, 8];
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

%% ========== 帧参数 ========== %%
bw = chip_rate * (1 + rolloff);
preamble_dur = 0.05;
f_lo = fc - bw/2; f_hi = fc + bw/2;

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

% HFM-基带
if abs(f1-f0) < 1e-6
    phase_hfm_neg = 2*pi*f1*t_pre;
else
    k_neg = f1*f0*T_pre/(f0-f1);
    phase_hfm_neg = -2*pi*k_neg*log(1 - (f0-f1)/f0*t_pre/T_pre);
end
HFM_bb_neg = exp(1j*(phase_hfm_neg - 2*pi*fc*t_pre));

% LFM基带
chirp_rate = (f_hi - f_lo) / preamble_dur;
phase_lfm = 2*pi * (f_lo * t_pre + 0.5 * chirp_rate * t_pre.^2);
LFM_bb = exp(1j*(phase_lfm - 2*pi*fc*t_pre));
N_lfm = length(LFM_bb);
guard_samp = max(chip_delays) * sps + 80;

snr_list = [-15, -10, -5, 0, 5, 10];

% 通信速率计算
code_rate = 1 / n_code;                          % 编码率 1/2
info_rate_bps = dsss_sym_rate * 1 * code_rate;    % 信息比特率 (bps)
chip_throughput = chip_rate;                       % 码片吞吐率

fprintf('通带: fs=%dHz, fc=%dHz, 带宽=%.0fHz\n', fs, fc, bw);
fprintf('DSSS: Gold(%d), L=%d, 码片率=%d, 符号率=%.1f sym/s\n', 5, L, chip_rate, dsss_sym_rate);
fprintf('通信速率: %.1f bps (BPSK, 编码率1/%d, 扩频因子%d)\n', info_rate_bps, n_code, L);
fprintf('数据: train=%d + data=%d DSSS符号 (=%d+%d chips)\n', train_sym, N_dsss_sym, train_chips, N_data_chips);
fprintf('信道: %d径, delays=[%s] chips, max_delay=%d < L=%d (无ISI)\n', ...
    length(chip_delays), num2str(chip_delays), max(chip_delays), L);
fprintf('处理增益: %.1f dB\n\n', 10*log10(L));

%% ========== TX ========== %%
rng(100);
% 训练序列（已知BPSK符号）
training = 2*randi([0,1],1,train_sym) - 1;  % ±1

% 信息数据
info_bits = randi([0 1], 1, N_info);
coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
coded = coded(1:M_coded);
[interleaved, ~] = random_interleave(coded, codec.interleave_seed);
data_sym = 2*interleaved - 1;  % BPSK: 0→-1, 1→+1

% 扩频
train_spread = dsss_spread(training, spread_code);
data_spread = dsss_spread(data_sym, spread_code);
all_chips = [train_spread, data_spread];
N_total_chips = length(all_chips);

% RRC成形（码片率→采样率）
[shaped_bb, ~, ~] = pulse_shape(all_chips, sps, 'rrc', rolloff, span_rrc);
N_shaped = length(shaped_bb);

% 上变频（用于功率归一化参考）
[data_pb, ~] = upconvert(shaped_bb, fs, fc);
data_rms = sqrt(mean(data_pb.^2));
lfm_scale = data_rms / sqrt(mean(HFM_pb.^2));
HFM_bb_n = HFM_bb * lfm_scale;
HFM_bb_neg_n = HFM_bb_neg * lfm_scale;
LFM_bb_n = LFM_bb * lfm_scale;

% 帧组装 (基带)
frame_bb = [HFM_bb_n, zeros(1,guard_samp), HFM_bb_neg_n, zeros(1,guard_samp), ...
            LFM_bb_n, zeros(1,guard_samp), LFM_bb_n, zeros(1,guard_samp), shaped_bb];
T_v_lfm = (N_lfm + guard_samp) / fs;
lfm_data_offset = N_lfm + guard_samp;

%% ========== 信道（固定）========== %%
ch_params = struct('fs',fs, 'delay_profile','custom', ...
    'delays_s',chip_delays/chip_rate, 'gains',gains_raw, ...
    'num_paths',length(chip_delays), 'doppler_rate',0, ...
    'fading_type','static', 'fading_fd_hz',0, ...
    'snr_db',Inf, 'seed',200);
[rx_bb_frame, ~] = gen_uwa_channel(frame_bb, ch_params);
[rx_pb_clean, ~] = upconvert(rx_bb_frame, fs, fc);
sig_pwr = mean(rx_pb_clean.^2);

%% ========== LFM检测参数 ========== %%
lfm2_peak_nom = 2*N_preamble + 3*guard_samp + 2*N_lfm;
lfm_search_margin = max(chip_delays)*sps + 200;
mf_lfm = conj(fliplr(LFM_bb_n));
lfm2_search_len = min(3*N_preamble + 4*guard_samp + 2*N_lfm, length(rx_bb_frame));

%% ========== SNR循环 ========== %%
ber_list = zeros(1, length(snr_list));
ber_uncoded = zeros(1, length(snr_list));

fprintf('%-6s | %-8s | %-8s | %-8s\n', 'SNR', 'BER', 'uncoded', 'sync');
fprintf('%s\n', repmat('-', 1, 45));

for si = 1:length(snr_list)
    snr_db = snr_list(si);
    noise_var = sig_pwr * 10^(-snr_db/10);
    rng(300 + si*100);
    rx_pb = rx_pb_clean + sqrt(noise_var) * randn(size(rx_pb_clean));

    % 1. 下变频
    [bb_raw, ~] = downconvert(rx_pb, fs, fc, bw);

    % 2. LFM定时（标称峰值窗口搜索）
    corr_lfm = abs(filter(mf_lfm, 1, bb_raw(1:min(lfm2_search_len, length(bb_raw)))));
    c2_lo = max(1, lfm2_peak_nom - lfm_search_margin);
    c2_hi = min(lfm2_peak_nom + lfm_search_margin, length(corr_lfm));
    [~, lfm2_local] = max(corr_lfm(c2_lo:c2_hi));
    lfm2_peak_idx = c2_lo + lfm2_local - 1;
    lfm_pos = lfm2_peak_idx - N_lfm + 1;

    % 3. 数据段提取 + RRC匹配 + 下采样到码片率
    ds = lfm_pos + lfm_data_offset;
    de = ds + N_shaped - 1;
    if de > length(bb_raw)
        rx_data_bb = [bb_raw(ds:end), zeros(1, de-length(bb_raw))];
    else
        rx_data_bb = bb_raw(ds:de);
    end
    [rx_filt, ~] = match_filter(rx_data_bb, sps, 'rrc', rolloff, span_rrc);

    % 最佳采样点（训练相关对齐）
    best_off = 0; best_pwr = 0;
    for off = 0:sps-1
        idx = off+1 : sps : length(rx_filt);
        n_check = min(length(idx), train_chips);
        if n_check >= L
            c = abs(sum(rx_filt(idx(1:n_check)) .* conj(train_spread(1:n_check))));
            if c > best_pwr, best_pwr = c; best_off = off; end
        end
    end
    rx_chips = rx_filt(best_off+1 : sps : end);
    if length(rx_chips) > N_total_chips
        rx_chips = rx_chips(1:N_total_chips);
    elseif length(rx_chips) < N_total_chips
        rx_chips = [rx_chips, zeros(1, N_total_chips - length(rx_chips))];
    end

    % 4. 信道估计（训练段Rake finger增益估计）
    h_est = zeros(1, length(chip_delays));
    for p = 1:length(chip_delays)
        d = chip_delays(p);
        acc = 0;
        for k = 1:train_sym
            chip_start = (k-1)*L + d + 1;
            chip_end = chip_start + L - 1;
            if chip_end <= train_chips
                block = rx_chips(chip_start:chip_end);
                despread_val = sum(block .* spread_code_pm) / L;
                acc = acc + despread_val * conj(training(k));
            end
        end
        h_est(p) = acc / train_sym;
    end

    % 5. Rake接收（训练段→估nv_eff, 数据段→符号估计）
    rake_train_opts = struct('combine','mrc', 'offset',0);
    [rake_train, ~] = eq_rake(rx_chips, spread_code, chip_delays, h_est, train_sym, rake_train_opts);
    nv_eff = max(var(rake_train - training), 1e-6);

    rake_data_opts = struct('combine','mrc', 'offset',train_chips);
    [rake_out, rake_info] = eq_rake(rx_chips, spread_code, chip_delays, h_est, N_dsss_sym, rake_data_opts);

    % 6. BPSK硬判决（未编码BER参考）
    bits_hard = double(real(rake_out) > 0);  % BPSK: bit1→+1 → real>0即bit1
    ber_unc = mean(bits_hard ~= interleaved);

    % 7. LLR计算 + 解交织 + Viterbi译码
    % BPSK映射: bit0→-1, bit1→+1 → LLR = 2*r/nv (正值→bit1更可能)
    LLR_interleaved = 2 * real(rake_out) / nv_eff;
    LLR_interleaved = max(min(LLR_interleaved, 30), -30);
    [~, perm] = random_interleave(zeros(1, M_coded), codec.interleave_seed);
    LLR_coded = random_deinterleave(LLR_interleaved, perm);

    [~, Lp_info, ~] = siso_decode_conv(LLR_coded, [], codec.gen_polys, ...
        codec.constraint_len, codec.decode_mode);
    bits_out = double(Lp_info > 0);

    nc = min(length(bits_out), N_info);
    ber = mean(bits_out(1:nc) ~= info_bits(1:nc));
    ber_list(si) = ber;
    ber_uncoded(si) = ber_unc;

    fprintf('%-6s | %6.2f%% | %6.2f%% | pos=%d\n', ...
        sprintf('%ddB', snr_db), ber*100, ber_unc*100, lfm_pos);
end

%% ========== 可视化 ========== %%

% --- Figure 1: BER曲线 ---
figure('Position',[50 500 700 450]);
semilogy(snr_list, max(ber_list, 1e-5), 'bo-', 'LineWidth',1.8, 'MarkerSize',7, ...
    'DisplayName','DSSS Rake+Viterbi');
hold on;
semilogy(snr_list, max(ber_uncoded, 1e-5), 'rs--', 'LineWidth',1.2, 'MarkerSize',6, ...
    'DisplayName','DSSS Rake (uncoded)');
snr_lin = 10.^(snr_list/10);
semilogy(snr_list, max(0.5*erfc(sqrt(snr_lin)), 1e-5), 'k--', 'LineWidth',1, ...
    'DisplayName','BPSK uncoded AWGN');
semilogy(snr_list, max(0.5*erfc(sqrt(snr_lin*L)), 1e-5), 'g-.', 'LineWidth',1, ...
    'DisplayName',sprintf('BPSK+PG(%ddB) AWGN', round(10*log10(L))));
grid on; xlabel('SNR (dB)'); ylabel('BER');
title(sprintf('DSSS Gold(%d) Rake(MRC) — %.1f bps (BPSK, R=1/%d, L=%d)', L, info_rate_bps, n_code, L));
legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);

% --- Figure 2: TX通带帧波形 + 频谱 ---
[frame_pb_vis, ~] = upconvert(frame_bb, fs, fc);
figure('Position',[50 350 900 500]);
subplot(2,1,1);
t_frame = (0:length(frame_pb_vis)-1)/fs*1000;
plot(t_frame, frame_pb_vis, 'b', 'LineWidth',0.3);
xlabel('时间 (ms)'); ylabel('幅度'); grid on;
title(sprintf('TX通带帧（实信号, fc=%dHz, 全长%.1fms, 信息速率%.1f bps）', fc, t_frame(end), info_rate_bps));
xline(N_preamble/fs*1000, 'r--');
xline((2*N_preamble+2*guard_samp)/fs*1000, 'r--');
text(N_preamble/2/fs*1000, max(frame_pb_vis)*0.8, 'HFM+/-', 'FontSize',8, 'Color','r', 'HorizontalAlignment','center');
text((2*N_preamble+3*guard_samp+N_lfm)/fs*1000, max(frame_pb_vis)*0.8, 'LFM1+2', 'FontSize',8, 'Color','r', 'HorizontalAlignment','center');

subplot(2,1,2);
N_fft_vis = 2^nextpow2(length(frame_pb_vis));
F_tx = fft(frame_pb_vis, N_fft_vis);
f_axis = (0:N_fft_vis-1) * fs / N_fft_vis / 1000;
plot(f_axis(1:N_fft_vis/2), 20*log10(abs(F_tx(1:N_fft_vis/2))+1e-10), 'b', 'LineWidth',0.8);
xlabel('频率 (kHz)'); ylabel('幅度 (dB)'); grid on;
title('TX通带频谱');
xlim([0 fs/2/1000]);
xline(fc/1000, 'r--', sprintf('fc=%dkHz', fc/1000));
xline((fc-bw/2)/1000, 'm--'); xline((fc+bw/2)/1000, 'm--');

% --- Figure 3: RX波形 + 频谱 (最高SNR) ---
figure('Position',[50 50 900 500]);
% 使用最后一个SNR的rx_pb
subplot(2,1,1);
t_rx = (0:length(rx_pb)-1)/fs*1000;
plot(t_rx, rx_pb, 'b', 'LineWidth',0.3);
xlabel('时间 (ms)'); ylabel('幅度'); grid on;
title(sprintf('RX通带（SNR=%ddB, 含噪声+多径）', snr_list(end)));

subplot(2,1,2);
N_fft_rx = 2^nextpow2(length(rx_pb));
F_rx = fft(rx_pb, N_fft_rx);
f_rx = (0:N_fft_rx-1) * fs / N_fft_rx / 1000;
plot(f_rx(1:N_fft_rx/2), 20*log10(abs(F_rx(1:N_fft_rx/2))+1e-10), 'b', 'LineWidth',0.8);
xlabel('频率 (kHz)'); ylabel('幅度 (dB)'); grid on;
title(sprintf('RX通带频谱（SNR=%ddB）', snr_list(end)));
xlim([0 fs/2/1000]);
xline(fc/1000, 'r--'); xline((fc-bw/2)/1000, 'm--'); xline((fc+bw/2)/1000, 'm--');

% --- Figure 4: 信道CIR + 扩频码自相关 ---
figure('Position',[770 400 500 450]);
subplot(2,1,1);
stem(chip_delays, abs(gains), 'filled', 'LineWidth',1.5);
xlabel('延迟 (chips)'); ylabel('|h|');
title(sprintf('信道CIR（%d径, max\\_delay=%d chips）', length(chip_delays), max(chip_delays)));
grid on;

subplot(2,1,2);
ac = xcorr(spread_code_pm, 'biased') * L;
lags = -(L-1):(L-1);
plot(lags, ac, 'b', 'LineWidth',1.2);
xlabel('延迟 (chips)'); ylabel('自相关');
title(sprintf('Gold(%d) 自相关 (L=%d, 峰值=%d)', 5, L, L));
grid on;

fprintf('\n完成\n');

%% ========== 保存结果 ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_dsss_static_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'DSSS 静态信道测试结果 V1.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'DSSS: Gold(%d), L=%d, chip_rate=%d, sym_rate=%.1f\n', 5, L, chip_rate, dsss_sym_rate);
fprintf(fid, '通信速率: %.1f bps (BPSK, R=1/%d, 扩频因子%d)\n', info_rate_bps, n_code, L);
fprintf(fid, '信道: %d径, delays=[%s], max_delay=%d < L=%d\n', ...
    length(chip_delays), num2str(chip_delays), max(chip_delays), L);
fprintf(fid, 'train=%d sym, data=%d sym (N_info=%d bits)\n\n', train_sym, N_dsss_sym, N_info);
fprintf(fid, '=== BER ===\n');
fprintf(fid, '%-6s | %-8s | %-8s\n', 'SNR', 'coded', 'uncoded');
fprintf(fid, '%s\n', repmat('-', 1, 30));
for si = 1:length(snr_list)
    fprintf(fid, '%-6s | %6.2f%% | %6.2f%%\n', ...
        sprintf('%ddB', snr_list(si)), ber_list(si)*100, ber_uncoded(si)*100);
end
fprintf(fid, '\n处理增益: %.1f dB\n', 10*log10(L));
fprintf(fid, 'Rake fingers: %d, combine: MRC\n', length(chip_delays));
fclose(fid);
fprintf('结果已保存: %s\n', result_file);
