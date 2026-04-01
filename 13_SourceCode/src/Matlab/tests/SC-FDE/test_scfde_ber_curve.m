%% test_scfde_ber_curve.m — SC-FDE BER vs SNR曲线（static/slow/fast）
% 最优参数：跨块编码 + 对角MMSE(块中点H_est) + 自适应块长
% 版本：V1.0.0

clc; close all;
% 路径
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

%% ========== 固化最优参数 ========== %%
sps = 8; sym_rate = 6000; fs = sym_rate*sps; fc = 12000;
rolloff = 0.35; span = 6;
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7);
n_code = 2; mem = codec.constraint_len - 1;

sym_delays = [0, 1, 3, 5, 8];
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];

pilot_len = round(0.02*fs);
t_pilot = (0:pilot_len-1)/fs;
pilot = exp(1j*pi*4000/t_pilot(end)*t_pilot.^2);
pilot = pilot/sqrt(mean(abs(pilot).^2));

% 最优配置（自扫描结果固化）
fading_cfgs = {
%   名称      fd   alpha    blk_fft  blk_cp  N_blocks
    'static', 0,   0,       1024,    64,     4;
    'slow',   1,   5e-5,    512,     16,     8;
    'fast',   5,   2e-4,    64,      16,     32;
};

snr_list = [0, 3, 5, 8, 10, 12, 15, 18, 20];

%% ========== 主循环 ========== %%
ber_results = zeros(size(fading_cfgs,1), length(snr_list));

fprintf('SC-FDE BER vs SNR（跨块编码+对角MMSE, 最优块长）\n\n');

for fi = 1:size(fading_cfgs,1)
    fname = fading_cfgs{fi,1};
    fd_hz = fading_cfgs{fi,2};
    doppler_rate = fading_cfgs{fi,3};
    blk_fft = fading_cfgs{fi,4};
    blk_cp = fading_cfgs{fi,5};
    N_blocks = fading_cfgs{fi,6};

    M_coded_per_blk = 2 * blk_fft;
    M_coded_total = M_coded_per_blk * N_blocks;
    N_info_total = M_coded_total / n_code - mem;

    fprintf('%s (fd=%dHz, blk=%d, %d块): ', fname, fd_hz, blk_fft, N_blocks);

    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        rng(200 + fi*100 + si);

        % TX: 一次性编码+交织
        info_bits = randi([0 1], 1, N_info_total);
        coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
        coded = coded(1:M_coded_total);
        [inter_all, perm_all] = random_interleave(coded, codec.interleave_seed);
        sym_all = bits2qpsk(inter_all);

        LLR_all = zeros(1, M_coded_total);

        % 逐块处理
        for bi = 1:N_blocks
            data_sym = sym_all((bi-1)*blk_fft+1 : bi*blk_fft);
            x_block = data_sym;
            x_cp = [x_block(end-blk_cp+1:end), x_block];
            [shaped,~,~] = pulse_shape(x_cp, sps, 'rrc', rolloff, span);

            gap = zeros(1, round(0.005*fs));
            T_v = (length(shaped)+2*length(gap))/fs;
            tx_frame = [pilot, gap, shaped, gap, pilot];

            ch_params = struct('fs',fs, 'delay_profile','custom', ...
                'delays_s',sym_delays/sym_rate, 'gains',gains_raw, ...
                'num_paths',length(sym_delays), 'doppler_rate',doppler_rate, ...
                'fading_type',fname, 'fading_fd_hz',fd_hz, ...
                'snr_db',snr_db, 'seed',300+fi*1000+si*100+bi);
            [rx_frame, ch_info] = gen_uwa_channel(tx_frame, ch_params);

            % 10-1 多普勒补偿
            if abs(doppler_rate) > 1e-10
                alpha_est = doppler_rate;
                rx_comp = comp_resample_spline(rx_frame, alpha_est, fs, 'fast');
            else
                rx_comp = rx_frame;
            end

            % 提取+匹配+下采样
            ds = length(pilot)+length(gap)+1;
            de = ds+length(shaped)-1;
            if de<=length(rx_comp), rx_up=rx_comp(ds:de);
            else, rx_up=[rx_comp(ds:end),zeros(1,length(shaped)-(length(rx_comp)-ds+1))]; end
            [rx_filt,~] = match_filter(rx_up, sps, 'rrc', rolloff, span);
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

            % 去CP+FFT+MMSE(块中点H_est)
            rx_nocp = rx_sym(blk_cp+1:blk_cp+blk_fft);
            Y_freq = fft(rx_nocp);

            mid_samp = min(round(length(tx_frame)/2), size(ch_info.h_time,2));
            h_mid = ch_info.h_time(:, mid_samp);
            gains_norm = h_mid.' / sqrt(sum(abs(h_mid).^2));
            h_td = zeros(1, blk_fft);
            for p=1:length(sym_delays)
                if sym_delays(p)+1<=blk_fft, h_td(sym_delays(p)+1)=gains_norm(p); end
            end
            H_est = fft(h_td);
            nv = max(ch_info.noise_var, 1e-10);
            W = conj(H_est)./(abs(H_est).^2+nv);
            x_hat = ifft(W.*Y_freq);

            LLR_blk = zeros(1, 2*blk_fft);
            LLR_blk(1:2:end) = -2*sqrt(2)*real(x_hat)/nv;
            LLR_blk(2:2:end) = -2*sqrt(2)*imag(x_hat)/nv;
            LLR_all((bi-1)*M_coded_per_blk+1:bi*M_coded_per_blk) = LLR_blk(1:M_coded_per_blk);
        end

        % 跨块译码
        LLR_deint = random_deinterleave(LLR_all, perm_all);
        LLR_deint = max(min(LLR_deint,30),-30);
        [~, Lpost_info, ~] = siso_decode_conv(LLR_deint, [], codec.gen_polys, codec.constraint_len);
        bits_out = double(Lpost_info > 0);
        n_cmp = min(length(bits_out), N_info_total);
        ber_results(fi, si) = mean(bits_out(1:n_cmp) ~= info_bits(1:n_cmp));

        fprintf('%.1e ', ber_results(fi,si));
    end
    fprintf('\n');
end

%% ========== 可视化 ========== %%
figure('Position',[100 200 800 500]);
markers = {'o-','s-','d-'};
colors = [0 0.45 0.74; 0.85 0.33 0.1; 0.47 0.67 0.19];
for fi = 1:size(fading_cfgs,1)
    semilogy(snr_list, max(ber_results(fi,:), 1e-4), markers{fi}, ...
        'Color',colors(fi,:), 'LineWidth',1.8, 'MarkerSize',7, ...
        'DisplayName',sprintf('%s(fd=%dHz,blk=%d)', ...
        fading_cfgs{fi,1}, fading_cfgs{fi,2}, fading_cfgs{fi,4}));
    hold on;
end
% QPSK理论线
snr_lin = 10.^(snr_list/10);
ber_theory = 0.5*erfc(sqrt(snr_lin));
semilogy(snr_list, max(ber_theory,1e-4), 'k--', 'LineWidth',1, 'DisplayName','QPSK无编码理论');
grid on; xlabel('SNR (dB)'); ylabel('BER');
title('SC-FDE BER vs SNR（跨块编码+自适应块长+多普勒补偿）');
legend('Location','southwest'); ylim([1e-4, 1]);
set(gca, 'FontSize', 12);

fprintf('\n完成\n');
