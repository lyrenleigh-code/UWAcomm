%% test_ofdm_e2e.m — OFDM端到端通带仿真 SNR vs BER
% TX: 编码→交织→QPSK→CP→RRC成形→上变频→通带实信号
% 信道: 通带实信号→多径卷积+实噪声
% RX: 下变频→RRC匹配→下采样→去CP+FFT→MMSE→跨块BCJR
% 版本：V7.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  OFDM 通带仿真 SNR vs BER（静态信道）\n');
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
% 时延设计：最大~15ms = 15e-3 * sym_rate = 90符号
sym_delays = [0, 5, 15, 40, 60, 90];  % 0/0.83/2.5/6.7/10/15 ms
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

blk_fft = 1024; blk_cp = 128; N_blocks = 4;  % CP=128 > max_delay=90
M_per_blk = 2*blk_fft; M_total = M_per_blk*N_blocks;
N_info = M_total/n_code - mem;

snr_sweep = [0, 3, 5, 8, 10, 12, 15, 18, 20];

% 基带信道冲激响应（整数符号时延×sps = 过采样域整数时延）
h_bb = zeros(1, max(sym_delays)*sps + 1);
for p = 1:length(sym_delays)
    h_bb(sym_delays(p)*sps + 1) = gains(p);
end

fprintf('通带: fs=%dHz, fc=%dHz, sps=%d\n', fs, fc, sps);
fprintf('块: N_fft=%d, CP=%d, %d块, ~%d info bits\n\n', blk_fft, blk_cp, N_blocks, N_info);

fprintf('%-6s %10s\n', 'SNR', 'infoBER%');
fprintf('%s\n', repmat('-',1,18));

ber_results = zeros(1, length(snr_sweep));

% TX固定（所有SNR共用相同数据）
rng(200);
info_bits = randi([0 1],1,N_info);
coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
coded = coded(1:M_total);
[inter_all,perm_all] = random_interleave(coded,codec.interleave_seed);
sym_all = bits2qpsk(inter_all);

% 预生成各块的成形信号和信道后基带（信道固定，只有噪声变）
tx_passband_blocks = cell(1, N_blocks);
rx_bb_blocks = cell(1, N_blocks);
rx_pb_clean_blocks = cell(1, N_blocks);
shaped_blocks = cell(1, N_blocks);
x_cp_blocks = cell(1, N_blocks);

for bi = 1:N_blocks
    data_sym = sym_all((bi-1)*blk_fft+1:bi*blk_fft);
    x_cp = [data_sym(end-blk_cp+1:end), data_sym];
    [shaped,~,~] = pulse_shape(x_cp, sps, 'rrc', rolloff, span);
    [tx_pb, ~] = upconvert(shaped, fs, fc);
    rx_bb = conv(shaped, h_bb);
    rx_bb = rx_bb(1:length(shaped));
    [rx_pb_clean, ~] = upconvert(rx_bb, fs, fc);

    tx_passband_blocks{bi} = tx_pb;
    rx_bb_blocks{bi} = rx_bb;
    rx_pb_clean_blocks{bi} = rx_pb_clean;
    shaped_blocks{bi} = shaped;
    x_cp_blocks{bi} = x_cp;
end

for si = 1:length(snr_sweep)
    snr_db = snr_sweep(si);
    rng(300 + si);  % 只影响噪声

    LLR_all = zeros(1,M_total);

    for bi = 1:N_blocks
        x_cp = x_cp_blocks{bi};
        rx_pb_clean = rx_pb_clean_blocks{bi};

        %% 通带加噪
        sig_pwr = mean(rx_pb_clean.^2);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rx_pb = rx_pb_clean + sqrt(noise_var) * randn(size(rx_pb_clean));

        %% RX: 下变频
        lpf_bw = sym_rate * (1 + rolloff);
        [bb_raw, ~] = downconvert(rx_pb, fs, fc, lpf_bw);

        %% RX: RRC匹配 + 最优下采样
        [rx_filt,~] = match_filter(bb_raw, sps, 'rrc', rolloff, span);
        best_off=0; best_pwr=0;
        for off=0:sps-1
            st = rx_filt(off+1:sps:end);
            if length(st)>=10
                c = abs(sum(st(1:10).*conj(x_cp(1:10))));
                if c>best_pwr, best_pwr=c; best_off=off; end
            end
        end
        rx_sym = rx_filt(best_off+1:sps:end);
        cpd = blk_cp+blk_fft;
        if length(rx_sym)>cpd, rx_sym=rx_sym(1:cpd);
        elseif length(rx_sym)<cpd, rx_sym=[rx_sym,zeros(1,cpd-length(rx_sym))]; end

        %% RX: 去CP + FFT + MMSE
        rx_nocp = rx_sym(blk_cp+1:blk_cp+blk_fft);
        Y_freq = fft(rx_nocp);

        % H_est（已知信道，符号级时延）
        h_td = zeros(1, blk_fft);
        for p=1:length(sym_delays)
            if sym_delays(p)+1<=blk_fft, h_td(sym_delays(p)+1)=gains(p); end
        end
        H_est = fft(h_td);

        % 通带实噪声功率noise_var → 下变频后基带复噪声功率≈noise_var
        nv_eq = max(noise_var, 1e-10);
        W = conj(H_est)./(abs(H_est).^2+nv_eq);
        x_hat = ifft(W.*Y_freq);

        % LLR
        LLR_blk = zeros(1, M_per_blk);
        LLR_blk(1:2:end) = -2*sqrt(2)*real(x_hat)/nv_eq;
        LLR_blk(2:2:end) = -2*sqrt(2)*imag(x_hat)/nv_eq;
        LLR_all((bi-1)*M_per_blk+1:bi*M_per_blk) = LLR_blk;
    end

    % 跨块BCJR译码
    LLR_deint = random_deinterleave(LLR_all, perm_all);
    LLR_deint = max(min(LLR_deint,30),-30);
    [~,Lpost,~] = siso_decode_conv(LLR_deint,[],codec.gen_polys,codec.constraint_len);
    bits_out = double(Lpost>0);
    nc = min(length(bits_out),N_info);
    ber = mean(bits_out(1:nc)~=info_bits(1:nc));
    ber_results(si) = ber;

    fprintf('%-6d %9.2f%%\n', snr_db, ber*100);
end

%% ========== 可视化 ========== %%

% Figure 1: BER vs SNR
figure('Position',[50 400 600 400]);
semilogy(snr_sweep, max(ber_results,1e-5), 'bo-', 'LineWidth',1.8, 'MarkerSize',7, ...
    'DisplayName','OFDM通带(跨块编码+MMSE)');
hold on;
snr_lin = 10.^(snr_sweep/10);
ber_theory = 0.5*erfc(sqrt(snr_lin));
semilogy(snr_sweep, max(ber_theory,1e-5), 'k--', 'LineWidth',1, 'DisplayName','QPSK无编码理论');
grid on; xlabel('SNR (dB)'); ylabel('BER');
title('OFDM 通带仿真 BER vs SNR（静态5径信道）');
legend('Location','southwest'); ylim([1e-5 1]);
set(gca,'FontSize',12);

% Figure 2: 通带波形 + 频谱 + 星座图
figure('Position',[50 50 1000 600]);

% 通带波形（第1块的前500样本）
subplot(2,3,1);
t_show = (0:499)/fs*1000;
plot(t_show, tx_passband_blocks{1}(1:500), 'b', 'LineWidth',0.5);
xlabel('时间(ms)'); ylabel('幅度');
title('TX通带波形'); grid on;

% 通带频谱
subplot(2,3,2);
tx_pb1 = tx_passband_blocks{1};
N_fft_spec = length(tx_pb1);
f_axis = (-N_fft_spec/2:N_fft_spec/2-1)*fs/N_fft_spec/1000;
spec = 20*log10(abs(fftshift(fft(tx_pb1)))/N_fft_spec + 1e-10);
plot(f_axis, spec, 'b', 'LineWidth',0.5);
xlabel('频率(kHz)'); ylabel('dB');
title('TX通带频谱'); grid on; xlim([-fs/2000, fs/2000]);

% 信道冲激响应
subplot(2,3,3);
delays_ms = sym_delays / sym_rate * 1000;  % 符号时延→毫秒
stem(delays_ms, abs(gains), 'filled', 'LineWidth',1.5);
xlabel('时延(ms)'); ylabel('|h|');
title(sprintf('信道CIR (%d径)', length(sym_delays))); grid on;

% 信道频响
subplot(2,3,4);
h_td_show = zeros(1, blk_fft);
for p=1:length(sym_delays)
    if sym_delays(p)+1<=blk_fft, h_td_show(sym_delays(p)+1)=gains(p); end
end
H_show = fft(h_td_show);
f_sub = (0:blk_fft-1) * sym_rate / blk_fft / 1000;  % 子载波频率(kHz)
plot(f_sub, 20*log10(abs(H_show)+1e-10), 'b', 'LineWidth',1);
xlabel('频率(kHz)'); ylabel('|H| (dB)');
title('信道频响'); grid on;

% 星座图（SNR=15dB的均衡输出）
idx_15 = find(snr_sweep==15, 1);
if ~isempty(idx_15)
    % 重新生成SNR=15的均衡输出用于星座图
    rng(300+idx_15);
    x_cp_show = x_cp_blocks{1};
    rx_pb_show = rx_pb_clean_blocks{1} + sqrt(mean(rx_pb_clean_blocks{1}.^2)*10^(-15/10))*randn(size(rx_pb_clean_blocks{1}));
    [bb_show,~] = downconvert(rx_pb_show, fs, fc, sym_rate*(1+rolloff));
    [rf_show,~] = match_filter(bb_show, sps, 'rrc', rolloff, span);
    bo2=0;bp2=0;
    for off=0:sps-1,st=rf_show(off+1:sps:end);if length(st)>=10,c=abs(sum(st(1:10).*conj(x_cp_show(1:10))));if c>bp2,bp2=c;bo2=off;end,end,end
    rs_show = rf_show(bo2+1:sps:end);
    if length(rs_show)>blk_cp+blk_fft, rs_show=rs_show(1:blk_cp+blk_fft); end
    rn_show = rs_show(blk_cp+1:min(blk_cp+blk_fft,length(rs_show)));
    if length(rn_show)<blk_fft, rn_show=[rn_show,zeros(1,blk_fft-length(rn_show))]; end
    Yf_show = fft(rn_show);
    H_show2 = fft(h_td_show);
    nv_show = mean(rx_pb_clean_blocks{1}.^2)*10^(-15/10);
    W_show = conj(H_show2)./(abs(H_show2).^2+nv_show);
    xh_show = ifft(W_show.*Yf_show);

    subplot(2,3,5);
    plot(real(xh_show), imag(xh_show), '.', 'MarkerSize', 3, 'Color', [0.3 0.6 0.9]);
    hold on;
    plot(real(constellation), imag(constellation), 'r+', 'MarkerSize', 14, 'LineWidth', 2);
    axis equal; xlim([-1.5 1.5]); ylim([-1.5 1.5]); grid on;
    title('均衡后星座 (SNR=15dB)');
end

% BER柱状图
subplot(2,3,6);
bar(snr_sweep, ber_results*100);
xlabel('SNR (dB)'); ylabel('BER (%)');
title('BER vs SNR'); grid on;

sgtitle('OFDM 通带端到端仿真（静态5径信道）', 'FontSize', 13);

fprintf('\n完成\n');
