%% test_scfde_static.m — SC-FDE通带仿真 SNR vs BER（静态信道）
% TX: 编码→交织→QPSK→CP→RRC成形→(上变频→通带实信号)
% 信道: 基带复数卷积 → 上变频+实噪声 → 下变频
% RX: RRC匹配→下采样→去CP+FFT→MMSE→跨块BCJR
% 版本：V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  SC-FDE 通带仿真 SNR vs BER（静态信道）\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
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

blk_fft = 1024; blk_cp = 128; N_blocks = 4;
M_per_blk = 2*blk_fft; M_total = M_per_blk*N_blocks;
N_info = M_total/n_code - mem;

h_bb = zeros(1, max(sym_delays)*sps+1);
for p=1:length(sym_delays), h_bb(sym_delays(p)*sps+1)=gains(p); end

snr_sweep = [0, 3, 5, 8, 10, 12, 15, 18, 20];

fprintf('通带: fs=%dHz, fc=%dHz, sps=%d\n', fs, fc, sps);
fprintf('块: N_fft=%d, CP=%d, %d块, ~%d info bits\n\n', blk_fft, blk_cp, N_blocks, N_info);

% TX固定
rng(200);
info_bits = randi([0 1],1,N_info);
coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
coded = coded(1:M_total);
[inter_all,perm_all] = random_interleave(coded,codec.interleave_seed);
sym_all = bits2qpsk(inter_all);

% 预生成
rx_pb_clean_blocks = cell(1,N_blocks);
x_cp_blocks = cell(1,N_blocks);
tx_pb_blocks = cell(1,N_blocks);
for bi=1:N_blocks
    data_sym = sym_all((bi-1)*blk_fft+1:bi*blk_fft);
    x_cp = [data_sym(end-blk_cp+1:end), data_sym];
    [shaped,~,~] = pulse_shape(x_cp,sps,'rrc',rolloff,span);
    [tx_pb,~] = upconvert(shaped,fs,fc);
    rx_bb = conv(shaped,h_bb); rx_bb=rx_bb(1:length(shaped));
    [rx_pb_clean,~] = upconvert(rx_bb,fs,fc);
    rx_pb_clean_blocks{bi}=rx_pb_clean;
    x_cp_blocks{bi}=x_cp;
    tx_pb_blocks{bi}=tx_pb;
end

fprintf('%-6s %10s\n','SNR','infoBER%');
fprintf('%s\n',repmat('-',1,18));
ber_results = zeros(1,length(snr_sweep));

for si=1:length(snr_sweep)
    snr_db=snr_sweep(si);
    rng(300+si);
    LLR_all=zeros(1,M_total);

    for bi=1:N_blocks
        x_cp=x_cp_blocks{bi}; rx_pb_clean=rx_pb_clean_blocks{bi};
        sig_pwr=mean(rx_pb_clean.^2);
        noise_var=sig_pwr*10^(-snr_db/10);
        rx_pb=rx_pb_clean+sqrt(noise_var)*randn(size(rx_pb_clean));

        [bb_raw,~]=downconvert(rx_pb,fs,fc,sym_rate*(1+rolloff));
        [rx_filt,~]=match_filter(bb_raw,sps,'rrc',rolloff,span);
        best_off=0;best_pwr=0;
        for off=0:sps-1,st=rx_filt(off+1:sps:end);
            if length(st)>=10,c=abs(sum(st(1:10).*conj(x_cp(1:10))));if c>best_pwr,best_pwr=c;best_off=off;end,end,end
        rx_sym=rx_filt(best_off+1:sps:end);
        cpd=blk_cp+blk_fft;
        if length(rx_sym)>cpd,rx_sym=rx_sym(1:cpd);elseif length(rx_sym)<cpd,rx_sym=[rx_sym,zeros(1,cpd-length(rx_sym))];end
        rx_nocp=rx_sym(blk_cp+1:blk_cp+blk_fft);
        Y_freq=fft(rx_nocp);

        h_td=zeros(1,blk_fft);
        for p=1:length(sym_delays),if sym_delays(p)+1<=blk_fft,h_td(sym_delays(p)+1)=gains(p);end,end
        H_est=fft(h_td);
        nv_eq=max(noise_var,1e-10);
        W=conj(H_est)./(abs(H_est).^2+nv_eq);
        x_hat=ifft(W.*Y_freq);

        LLR_blk=zeros(1,M_per_blk);
        LLR_blk(1:2:end)=-2*sqrt(2)*real(x_hat)/nv_eq;
        LLR_blk(2:2:end)=-2*sqrt(2)*imag(x_hat)/nv_eq;
        LLR_all((bi-1)*M_per_blk+1:bi*M_per_blk)=LLR_blk;
    end

    LLR_deint=random_deinterleave(LLR_all,perm_all);
    LLR_deint=max(min(LLR_deint,30),-30);
    [~,Lpost,~]=siso_decode_conv(LLR_deint,[],codec.gen_polys,codec.constraint_len);
    bits_out=double(Lpost>0);
    nc=min(length(bits_out),N_info);
    ber=mean(bits_out(1:nc)~=info_bits(1:nc));
    ber_results(si)=ber;
    fprintf('%-6d %9.2f%%\n',snr_db,ber*100);
end

%% 可视化
figure('Position',[50 400 600 400]);
semilogy(snr_sweep,max(ber_results,1e-5),'ro-','LineWidth',1.8,'MarkerSize',7,'DisplayName','SC-FDE通带');
hold on;
snr_lin=10.^(snr_sweep/10);
semilogy(snr_sweep,max(0.5*erfc(sqrt(snr_lin)),1e-5),'k--','LineWidth',1,'DisplayName','QPSK无编码');
grid on;xlabel('SNR (dB)');ylabel('BER');
title('SC-FDE 通带仿真 BER vs SNR（静态6径信道, max\_delay=15ms）');
legend('Location','southwest');ylim([1e-5 1]);set(gca,'FontSize',12);

figure('Position',[50 50 800 300]);
subplot(1,2,1);
delays_ms=sym_delays/sym_rate*1000;
stem(delays_ms,abs(gains),'filled','LineWidth',1.5);
xlabel('时延(ms)');ylabel('|h|');title(sprintf('信道CIR（%d径）',length(sym_delays)));grid on;
subplot(1,2,2);
h_td_show=zeros(1,blk_fft);
for p=1:length(sym_delays),if sym_delays(p)+1<=blk_fft,h_td_show(sym_delays(p)+1)=gains(p);end,end
f_khz=(0:blk_fft-1)*sym_rate/blk_fft/1000;
plot(f_khz,20*log10(abs(fft(h_td_show))+1e-10),'b','LineWidth',1);
xlabel('频率(kHz)');ylabel('|H|(dB)');title('信道频响');grid on;

fprintf('\n完成\n');
