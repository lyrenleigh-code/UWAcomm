%% test_scfde_timevarying.m — SC-FDE通带仿真 时变信道测试
% 信道: 基带复数卷积(Jakes+多普勒) → 上变频+实噪声 → 下变频
% RX: 已知α补偿 → RRC匹配 → 去CP+FFT → oracle H_est → MMSE → 跨块BCJR
% 测试矩阵: fd=[0,1,5]Hz × SNR=[5,10,15,20]dB
% 版本：V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  SC-FDE 通带仿真 — 时变信道测试\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
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

% 6径水声信道（最大时延~15ms）
sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

snr_list = [5, 10, 15, 20];
fading_cfgs = {
%   名称     fading_type  fd   alpha=fd/fc  blk   cp    N_blocks
    'static', 'static',   0,   0,           1024, 128,  4;
    'fd=1Hz', 'slow',     1,   1/fc,        256,  128,  16;
    'fd=5Hz', 'slow',     5,   5/fc,        128,  128,  32;
};

fprintf('通带仿真: fs=%dHz, fc=%dHz, 6径(max_delay=15ms)\n', fs, fc);
fprintf('α补偿: 已知α, H_est: oracle块中点, 编码: 跨块BCJR\n\n');

ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname=fading_cfgs{fi,1}; ftype=fading_cfgs{fi,2};
    fd_hz=fading_cfgs{fi,3}; dop_rate=fading_cfgs{fi,4};
    blk_fft=fading_cfgs{fi,5}; blk_cp=fading_cfgs{fi,6}; N_blocks=fading_cfgs{fi,7};

    M_per_blk = 2*blk_fft;
    M_total = M_per_blk * N_blocks;
    N_info = M_total/n_code - mem;

    fprintf('%-8s |', fname);

    for si = 1:length(snr_list)
        snr_db = snr_list(si);

        rng(100 + fi);
        info_bits = randi([0 1],1,N_info);
        coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
        coded = coded(1:M_total);
        [inter_all,perm_all] = random_interleave(coded,codec.interleave_seed);
        sym_all = bits2qpsk(inter_all);

        LLR_all = zeros(1,M_total);

        for bi = 1:N_blocks
            data_sym = sym_all((bi-1)*blk_fft+1:bi*blk_fft);
            x_cp = [data_sym(end-blk_cp+1:end), data_sym];
            [shaped,~,~] = pulse_shape(x_cp, sps, 'rrc', rolloff, span);

            % 信道（基带时变）
            ch_params = struct('fs',fs,'delay_profile','custom',...
                'delays_s',sym_delays/sym_rate,'gains',gains_raw,...
                'num_paths',length(sym_delays),'doppler_rate',dop_rate,...
                'fading_type',ftype,'fading_fd_hz',fd_hz,...
                'snr_db',Inf,'seed',200+fi*100+si*10+bi);
            [rx_bb,ch_info] = gen_uwa_channel(shaped, ch_params);
            rx_bb = rx_bb(1:length(shaped));

            % 10-1 已知α
            if abs(dop_rate) > 1e-10
                rx_bb = comp_resample_spline(rx_bb, dop_rate, fs, 'fast');
                if length(rx_bb)>length(shaped), rx_bb=rx_bb(1:length(shaped));
                elseif length(rx_bb)<length(shaped), rx_bb=[rx_bb,zeros(1,length(shaped)-length(rx_bb))]; end
            end

            % 通带闭环
            [rx_pb_clean,~] = upconvert(rx_bb, fs, fc);
            sig_pwr = mean(rx_pb_clean.^2);
            noise_var = sig_pwr * 10^(-snr_db/10);
            rng(300+fi*1000+si*100+bi);
            rx_pb = rx_pb_clean + sqrt(noise_var)*randn(size(rx_pb_clean));
            [bb_raw,~] = downconvert(rx_pb, fs, fc, sym_rate*(1+rolloff));

            % RRC匹配+下采样
            [rx_filt,~] = match_filter(bb_raw,sps,'rrc',rolloff,span);
            best_off=0;best_pwr=0;
            for off=0:sps-1,st=rx_filt(off+1:sps:end);
                if length(st)>=10,c=abs(sum(st(1:10).*conj(x_cp(1:10))));if c>best_pwr,best_pwr=c;best_off=off;end,end,end
            rx_sym=rx_filt(best_off+1:sps:end);
            cpd=blk_cp+blk_fft;
            if length(rx_sym)>cpd,rx_sym=rx_sym(1:cpd);
            elseif length(rx_sym)<cpd,rx_sym=[rx_sym,zeros(1,cpd-length(rx_sym))];end
            rx_nocp = rx_sym(blk_cp+1:blk_cp+blk_fft);
            Y_freq = fft(rx_nocp);

            % Oracle H_est
            mid_samp = min(round(size(ch_info.h_time,2)/2), size(ch_info.h_time,2));
            h_mid = ch_info.h_time(:, mid_samp);
            h_norm = h_mid.' / sqrt(sum(abs(h_mid).^2));
            h_td = zeros(1, blk_fft);
            for p=1:length(sym_delays),if sym_delays(p)+1<=blk_fft,h_td(sym_delays(p)+1)=h_norm(p);end,end
            H_est = fft(h_td);
            nv_eq = max(noise_var, 1e-10);
            W = conj(H_est)./(abs(H_est).^2+nv_eq);
            x_hat = ifft(W.*Y_freq);

            LLR_blk = zeros(1, M_per_blk);
            LLR_blk(1:2:end) = -2*sqrt(2)*real(x_hat)/nv_eq;
            LLR_blk(2:2:end) = -2*sqrt(2)*imag(x_hat)/nv_eq;
            LLR_all((bi-1)*M_per_blk+1:bi*M_per_blk) = LLR_blk;
        end

        LLR_deint = random_deinterleave(LLR_all, perm_all);
        LLR_deint = max(min(LLR_deint,30),-30);
        [~,Lpost,~] = siso_decode_conv(LLR_deint,[],codec.gen_polys,codec.constraint_len);
        bits_out = double(Lpost>0);
        nc = min(length(bits_out),N_info);
        ber = mean(bits_out(1:nc)~=info_bits(1:nc));
        ber_matrix(fi,si) = ber;
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (blk=%d)\n', blk_fft);
end

%% 可视化
figure('Position',[100 300 700 450]);
markers = {'o-','s-','d-'};
colors = [0 0.45 0.74; 0.85 0.33 0.1; 0.47 0.67 0.19];
for fi=1:size(fading_cfgs,1)
    semilogy(snr_list, max(ber_matrix(fi,:),1e-5), markers{fi}, ...
        'Color',colors(fi,:), 'LineWidth',1.8, 'MarkerSize',7, ...
        'DisplayName',sprintf('%s(blk=%d)', fading_cfgs{fi,1}, fading_cfgs{fi,5}));
    hold on;
end
snr_lin=10.^(snr_list/10);
semilogy(snr_list,max(0.5*erfc(sqrt(snr_lin)),1e-5),'k--','LineWidth',1,'DisplayName','QPSK无编码');
grid on;xlabel('SNR (dB)');ylabel('BER');
title('SC-FDE 通带时变信道 BER vs SNR（6径, max\_delay=15ms）');
legend('Location','southwest');ylim([1e-5 1]);set(gca,'FontSize',12);

figure('Position',[100 50 800 300]);
subplot(1,2,1);
delays_ms=sym_delays/sym_rate*1000;
stem(delays_ms,abs(gains),'filled','LineWidth',1.5);
xlabel('时延(ms)');ylabel('|h|');title(sprintf('信道CIR（%d径）',length(sym_delays)));grid on;
subplot(1,2,2);
h_td_show=zeros(1,1024);
for p=1:length(sym_delays),if sym_delays(p)+1<=1024,h_td_show(sym_delays(p)+1)=gains(p);end,end
f_khz=(0:1023)*sym_rate/1024/1000;
plot(f_khz,20*log10(abs(fft(h_td_show))+1e-10),'b','LineWidth',1);
xlabel('频率(kHz)');ylabel('|H|(dB)');title('信道频响');grid on;

fprintf('\n完成\n');
