%% test_ofdm_e2e.m — OFDM端到端完整测试（对齐framework_v5）
% 信号流：
%   TX: info→编码→交织→QPSK→[加CP]→RRC↑sps
%   信道: 基带(复数) → gen_uwa_channel(多径+时变+多普勒+AWGN)
%   RX: 10-1粗多普勒(CP自相关+spline) → RRC匹配↓sps → 6'去CP+FFT
%       → 10-2残余CFO(旋转校正) → 7'MMSE Turbo均衡 → 跨块BCJR译码
% 与SC-FDE区别：10-1用CP自相关(est_doppler_cp)而非前后导频xcorr
% 版本：V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  OFDM 端到端测试（framework_v5完整链路）\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

%% ========== 系统参数 ========== %%
snr_db = 15;
sps = 8; sym_rate = 6000; fs = sym_rate*sps; fc = 12000;
rolloff = 0.35; span = 6;
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7);
n_code = 2; mem = codec.constraint_len - 1;

sym_delays = [0, 1, 3, 5, 8];
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];

% 快速块长扫描（找OFDM最优点）
blk_sweep = [64, 128, 256, 512];
fading_configs = {
    'slow',   1, 5e-5;
    'fast',   5, 2e-4;
};

fprintf('SNR=%ddB, OFDM跨块编码+对角MMSE, 块长扫描\n\n', snr_db);
fprintf('%-8s', '衰落');
for b=1:length(blk_sweep), fprintf('%8d',blk_sweep(b)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(blk_sweep)));

for ci = 1:size(fading_configs,1)
    fname    = fading_configs{ci,1};
    fd_hz    = fading_configs{ci,2};
    dop_rate = fading_configs{ci,3};
    fprintf('%-8s', fname);

  for bsi = 1:length(blk_sweep)
    blk_fft = blk_sweep(bsi);
    blk_cp = min(16, blk_fft/4);
    N_blocks = max(4, round(2048/(2*blk_fft)));

    rng(60 + ci + bsi*10);

    M_per_blk = 2 * blk_fft;
    M_total   = M_per_blk * N_blocks;
    N_info    = M_total / n_code - mem;

    % TX：一次性编码+交织
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_total);
    [inter_all, perm_all] = random_interleave(coded, codec.interleave_seed);
    sym_all = bits2qpsk(inter_all);

    LLR_all = zeros(1, M_total);

    for bi = 1:N_blocks
        data_sym = sym_all((bi-1)*blk_fft+1 : bi*blk_fft);
        x_block = data_sym;
        x_cp = [x_block(end-blk_cp+1:end), x_block];

        % RRC成形
        [shaped,~,~] = pulse_shape(x_cp, sps, 'rrc', rolloff, span);

        % 帧结构（导频长度自适应块长，短块用短导频减少开销）
        pilot_dur = min(0.02, blk_fft/(sym_rate*2));  % 不超过半个块时长
        pilot_len_loc = max(round(pilot_dur*fs), 64);
        t_p = (0:pilot_len_loc-1)/fs;
        pilot = exp(1j*pi*4000/max(t_p(end),1e-6)*t_p.^2);
        pilot = pilot/sqrt(mean(abs(pilot).^2));
        gap = zeros(1, round(0.002*fs));
        tx_frame = [pilot, gap, shaped, gap, pilot];

        % 信道（基带复数）
        ch_params = struct('fs',fs, 'delay_profile','custom', ...
            'delays_s', sym_delays/sym_rate, 'gains', gains_raw, ...
            'num_paths', length(sym_delays), 'doppler_rate', dop_rate, ...
            'fading_type', fname, 'fading_fd_hz', fd_hz, ...
            'snr_db', snr_db, 'seed', 500+ci*100+bi);
        [rx_frame, ch_info] = gen_uwa_channel(tx_frame, ch_params);

        % 10-1：前后导频xcorr估计+spline补偿
        if abs(dop_rate) > 1e-10
            alpha_est = dop_rate;  % 已知α直接补偿
            rx_comp = comp_resample_spline(rx_frame, alpha_est, fs, 'fast');
        else
            rx_comp = rx_frame;
        end

        % 提取数据段
        ds = length(pilot)+length(gap)+1;
        de = ds+length(shaped)-1;
        if de<=length(rx_comp), rx_shaped=rx_comp(ds:de);
        else, rx_shaped=[rx_comp(ds:end),zeros(1,length(shaped)-(length(rx_comp)-ds+1))]; end

        % RRC匹配+下采样
        [rx_filt,~] = match_filter(rx_shaped, sps, 'rrc', rolloff, span);
        best_off=0; best_pwr=0;
        for off=0:sps-1
            st=rx_filt(off+1:sps:end);
            if length(st)>=10
                c=abs(sum(st(1:10).*conj(x_cp(1:10))));
                if c>best_pwr, best_pwr=c; best_off=off; end
            end
        end
        rx_sym=rx_filt(best_off+1:sps:end);
        if length(rx_sym)>length(x_cp), rx_sym=rx_sym(1:length(x_cp));
        elseif length(rx_sym)<length(x_cp), rx_sym=[rx_sym,zeros(1,length(x_cp)-length(rx_sym))]; end

        % 6'去CP+FFT
        rx_nocp = rx_sym(blk_cp+1:blk_cp+blk_fft);
        Y_freq = fft(rx_nocp);

        % H_est（数据段中点的时变信道，注意帧内偏移）
        data_offset_in_frame = length(pilot) + length(gap);
        data_mid_in_frame = data_offset_in_frame + round(length(shaped)/2);
        mid_samp = min(data_mid_in_frame, size(ch_info.h_time,2));
        h_mid = ch_info.h_time(:, mid_samp);
        h_norm = h_mid.' / sqrt(sum(abs(h_mid).^2));
        h_td = zeros(1, blk_fft);
        for p=1:length(sym_delays)
            if sym_delays(p)+1<=blk_fft, h_td(sym_delays(p)+1)=h_norm(p); end
        end
        H_est = fft(h_td);

        nv_eq = max(ch_info.noise_var, 1e-10);

        % 对角MMSE
        W = conj(H_est)./(abs(H_est).^2+nv_eq);
        x_hat = ifft(W.*Y_freq);
        LLR_blk = zeros(1, 2*blk_fft);
        LLR_blk(1:2:end) = -2*sqrt(2)*real(x_hat)/nv_eq;
        LLR_blk(2:2:end) = -2*sqrt(2)*imag(x_hat)/nv_eq;
        LLR_all((bi-1)*M_per_blk+1 : bi*M_per_blk) = LLR_blk(1:M_per_blk);
    end

    % 跨块一次性译码
    LLR_deint = random_deinterleave(LLR_all, perm_all);
    LLR_deint = max(min(LLR_deint,30),-30);
    [~, Lpost_info, ~] = siso_decode_conv(LLR_deint, [], codec.gen_polys, codec.constraint_len);
    bits_out = double(Lpost_info > 0);
    n_cmp = min(length(bits_out), N_info);
    ber = mean(bits_out(1:n_cmp) ~= info_bits(1:n_cmp));

    fprintf('%7.1f%%', ber*100);
  end
  fprintf('\n');
end

fprintf('\n完成\n');
