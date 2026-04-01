%% test_scfde_e2e.m — SC-FDE端到端完整测试（对齐framework_v5）
% 信号流：
%   TX: info→编码→交织→QPSK→[加CP]→RRC↑sps→上变频→通带(DAC输出)
%   信道: RRC成形基带(复数) → gen_uwa_channel(多径+时变+多普勒+噪声)
%   RX: 10-1粗多普勒(xcorr+spline) → RRC匹配↓sps → 6'去CP+FFT
%       → 10-2残余CFO(旋转校正) → 7'MMSE-IC Turbo均衡 → 译码
% 版本：V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  SC-FDE 端到端测试（framework_v5完整链路）\n');
fprintf('========================================\n\n');

% 路径：tests/SC-FDE/ → src/Matlab/ → src/ → 13_SourceCode/ → UWAcomm/
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
N_fft = 1024;
cp_len = 64;
sps = 8;
sym_rate = 6000;
fs = sym_rate * sps;    % 48kHz
fc = 12000;
rolloff = 0.35;
span = 6;
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7);
n_code = 2; mem = codec.constraint_len - 1;
M_coded = 2 * N_fft;
N_info = M_coded / n_code - mem;
turbo_iter = 6;

% 信道参数
sym_delays = [0, 1, 3, 5, 8];
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

% 测速导频（LFM chirp，用于xcorr多普勒估计）
pilot_len = round(0.02 * fs);  % 20ms
t_pilot = (0:pilot_len-1) / fs;
pilot = exp(1j*pi*4000/t_pilot(end)*t_pilot.^2);  % 基带LFM chirp
pilot = pilot / sqrt(mean(abs(pilot).^2));

snr_list = [15];
% 扫描块长：找编码增益 vs ICI的最优折中
blk_sweep = [64, 128, 256, 512, 1024];
fading_configs = {
    'slow',   1, 5e-5;
    'fast',   5, 2e-4;
};

fprintf('N_fft=%d, CP=%d, sps=%d, %d径信道\n\n', N_fft, cp_len, sps, length(sym_delays));

snr_db = snr_list(1);
n_code = length(codec.gen_polys);
mem = codec.constraint_len - 1;

fprintf('SNR=%ddB, BEM-Turbo ICI均衡, 块长扫描\n\n', snr_db);
fprintf('%-8s', '衰落');
for bi = 1:length(blk_sweep), fprintf('%8d', blk_sweep(bi)); end
fprintf('\n%s\n', repmat('-', 1, 8+8*length(blk_sweep)));

for ci = 1:size(fading_configs, 1)
    fading_type = fading_configs{ci,1};
    fd_hz = fading_configs{ci,2};
    doppler_rate = fading_configs{ci,3};
    fprintf('%-8s', fading_type);

  for bi = 1:length(blk_sweep)
    blk_fft = blk_sweep(bi);
    blk_cp = min(16, blk_fft/4);  % CP自适应

    rng(50 + ci);

    % 按块长重算编码参数
    M_coded_blk = 2 * blk_fft;
    N_info_blk = M_coded_blk / n_code - mem;
    N_blocks = ceil(2000 / N_info_blk);   % 总约2000信息比特
    total_info = N_blocks * N_info_blk;

    info_bits_all = randi([0 1], 1, total_info);
    bits_out_all = [];

    %% ========== 逐块处理 ========== %%
    for bi = 1:N_blocks
        info_blk = info_bits_all((bi-1)*N_info_blk+1 : bi*N_info_blk);

        % TX: 编码→交织→QPSK→CP→RRC
        coded_blk = conv_encode(info_blk, codec.gen_polys, codec.constraint_len);
        coded_blk = coded_blk(1:M_coded_blk);
        [inter_blk, perm_blk] = random_interleave(coded_blk, codec.interleave_seed + bi);
        data_sym = bits2qpsk(inter_blk);
        x_block = data_sym(1:blk_fft);
        x_cp = [x_block(end-blk_cp+1:end), x_block];

        [shaped, ~, ~] = pulse_shape(x_cp, sps, 'rrc', rolloff, span);

        % 帧：[pilot, gap, data, gap, pilot]
        gap = zeros(1, round(0.005*fs));
        T_v = (length(shaped) + 2*length(gap)) / fs;
        tx_frame = [pilot, gap, shaped, gap, pilot];

        % 信道（基带复数）
        ch_params = struct('fs', fs, 'delay_profile', 'custom', ...
            'delays_s', sym_delays / sym_rate, ...
            'gains', gains_raw, 'num_paths', length(sym_delays), ...
            'doppler_rate', doppler_rate, ...
            'fading_type', fading_type, 'fading_fd_hz', fd_hz, ...
            'snr_db', snr_db, 'seed', 42+ci*100+bi);

        [rx_frame, ch_info] = gen_uwa_channel(tx_frame, ch_params);

        % 10-1: 粗多普勒补偿
        if abs(doppler_rate) > 1e-10
            try
                [rx_comp, alpha_est_blk, ~] = doppler_coarse_compensate(rx_frame, pilot, fs, ...
                    'est_method', 'xcorr', 'comp_method', 'spline', 'comp_mode', 'fast', ...
                    'fc', fc, 'T_v', T_v);
            catch
                alpha_est_blk = doppler_rate;
                rx_comp = comp_resample_spline(rx_frame, alpha_est_blk, fs, 'fast');
            end
        else
            alpha_est_blk = 0;
            rx_comp = rx_frame;
        end

        % 提取数据 + RRC匹配 + 下采样
        ds = length(pilot) + length(gap) + 1;
        de = ds + length(shaped) - 1;
        if de <= length(rx_comp)
            rx_up = rx_comp(ds:de);
        else
            rx_up = rx_comp(ds:end);
            rx_up = [rx_up, zeros(1, length(shaped)-length(rx_up))];
        end
        [rx_filt, ~] = match_filter(rx_up, sps, 'rrc', rolloff, span);
        best_off = 0; best_pwr = 0;
        for off = 0:sps-1
            st = rx_filt(off+1:sps:end);
            if length(st) >= 10
                c = abs(sum(st(1:10) .* conj(x_cp(1:10))));
                if c > best_pwr, best_pwr = c; best_off = off; end
            end
        end
        rx_sym = rx_filt(best_off+1:sps:end);
        if length(rx_sym) > length(x_cp), rx_sym = rx_sym(1:length(x_cp));
        elseif length(rx_sym) < length(x_cp), rx_sym = [rx_sym, zeros(1, length(x_cp)-length(rx_sym))]; end

        % 6': 去CP + FFT
        rx_nocp = rx_sym(blk_cp+1:blk_cp+blk_fft);
        Y_freq = fft(rx_nocp);

        % H_est: 用块中点的时变信道（oracle，仿真可用）
        mid_samp = round(length(tx_frame)/2);
        mid_samp = min(mid_samp, size(ch_info.h_time, 2));
        h_mid = ch_info.h_time(:, mid_samp);
        h_td = zeros(1, blk_fft);
        for p = 1:length(sym_delays)
            if sym_delays(p)+1 <= blk_fft
                h_td(sym_delays(p)+1) = h_mid(p);
            end
        end
        H_est = fft(h_td);

        % 10-2: 残余CFO
        if abs(doppler_rate) > 1e-10
            alpha_res = doppler_rate - alpha_est_blk;
            cfo_res = alpha_res * fc;
            if abs(cfo_res) > 0.1
                rx_nocp = comp_cfo_rotate(rx_nocp, cfo_res, sym_rate);
                Y_freq = fft(rx_nocp);
            end
        end

        % 7': 均衡+译码
        codec_blk = codec;
        codec_blk.interleave_seed = codec.interleave_seed + bi;
        nv_eq = max(ch_info.noise_var, 1e-10);

        if ~strcmpi(fading_type, 'static') && size(ch_info.h_time, 2) > 1
            % 时变：BEM-Turbo迭代ICI消除均衡
            data_pb_start = length(pilot) + length(gap);
            cp_pb = blk_cp * sps;
            h_block = zeros(length(sym_delays), blk_fft);
            for sn = 1:blk_fft
                pb_idx = data_pb_start + cp_pb + (sn-1)*sps + 1;
                pb_idx = min(pb_idx, size(ch_info.h_time, 2));
                h_block(:, sn) = ch_info.h_time(:, pb_idx);
            end
            [bits_blk, ~] = eq_bem_turbo_fde(Y_freq, h_block, sym_delays, ...
                blk_fft, nv_eq, codec_blk, 3);
        else
            % 静态：标准Turbo均衡
            [bits_blk, ~] = turbo_equalizer_scfde(Y_freq, H_est, turbo_iter, nv_eq, codec_blk);
        end
        bits_out_all = [bits_out_all, bits_blk(:).']; %#ok<AGROW>
    end

    %% BER
    n_cmp = min(length(bits_out_all), total_info);
    ber = mean(bits_out_all(1:n_cmp) ~= info_bits_all(1:n_cmp));

    fprintf('%7.1f%%', ber*100);
  end  % blk_sweep
  fprintf('\n');
end  % fading

fprintf('\n完成\n');
