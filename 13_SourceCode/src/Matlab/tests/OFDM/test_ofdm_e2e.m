%% test_ofdm_e2e.m — OFDM通带仿真 SNR vs BER（静态信道）
% TX: 编码→交织→QPSK→分块+CP→拼接→09 RRC成形(基带)→09上变频(通带实数)
%     08 gen_lfm(通带实LFM) → 08帧组装: [LFM|guard|blocks_pb|guard|LFM] 全实数
% 信道: 等效基带帧 → 多径卷积 → 09上变频 → +实噪声
% RX: 09下变频 → 08同步检测 → 提取数据 → 09 RRC匹配 → 下采样 →
%     分块去CP+FFT → MMSE均衡 → 跨块BCJR译码
% 版本：V8.0.0 — 通带实数帧+同步（对齐SC-FDE V2）

clc; close all;
fprintf('========================================\n');
fprintf('  OFDM 通带仿真 SNR vs BER（静态信道）\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

%% ========== 参数 ========== %%
sps = 8; sym_rate = 6000; fs = sym_rate*sps; fc = 12000;
rolloff = 0.35; span = 6;
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7);
n_code = 2; mem = codec.constraint_len - 1;

sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

blk_fft = 1024; blk_cp = 128; N_blocks = 4;
M_per_blk = 2*blk_fft; M_total = M_per_blk*N_blocks;
N_info = M_total/n_code - mem;
sym_per_block = blk_cp + blk_fft;

h_bb = zeros(1, max(sym_delays)*sps+1);
for p=1:length(sym_delays), h_bb(sym_delays(p)*sps+1)=gains(p); end

%% ========== 帧参数 ========== %%
bw_lfm = sym_rate * (1 + rolloff);
lfm_dur = 0.05;
f_lo = fc - bw_lfm/2;  f_hi = fc + bw_lfm/2;
[LFM_pb, ~] = gen_lfm(fs, lfm_dur, f_lo, f_hi);
N_lfm = length(LFM_pb);
t_lfm = (0:N_lfm-1)/fs;
LFM_bb = exp(1j*2*pi*(-bw_lfm/2*t_lfm + 0.5*bw_lfm/lfm_dur*t_lfm.^2));
guard_samp = max(sym_delays) * sps + 80;

snr_sweep = [-10, -7, -5, -3, 0, 3, 5, 8, 10, 15, 20];

%% ========== TX ========== %%
rng(200);
info_bits = randi([0 1],1,N_info);
coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
coded = coded(1:M_total);
[inter_all,perm_all] = random_interleave(coded,codec.interleave_seed);
sym_all = bits2qpsk(inter_all);

all_cp_data = zeros(1, N_blocks * sym_per_block);
for bi=1:N_blocks
    data_sym = sym_all((bi-1)*blk_fft+1:bi*blk_fft);
    x_cp = [data_sym(end-blk_cp+1:end), data_sym];
    all_cp_data((bi-1)*sym_per_block+1:bi*sym_per_block) = x_cp;
end

[shaped_bb,~,~] = pulse_shape(all_cp_data, sps, 'rrc', rolloff, span);
N_shaped = length(shaped_bb);
[data_pb,~] = upconvert(shaped_bb, fs, fc);

% 功率归一化
lfm_scale = sqrt(mean(data_pb.^2)) / sqrt(mean(LFM_pb.^2));
LFM_pb = LFM_pb * lfm_scale;
LFM_bb = LFM_bb * lfm_scale;

% 帧组装
guard = zeros(1, guard_samp);
frame_pb = [LFM_pb, guard, data_pb, guard, LFM_pb];
frame_bb = [LFM_bb, zeros(1,guard_samp), shaped_bb, zeros(1,guard_samp), LFM_bb];
data_offset = N_lfm + guard_samp;

fprintf('通带: fs=%dHz, fc=%dHz, sps=%d\n', fs, fc, sps);
fprintf('帧: LFM(%d)+guard(%d)+data(%d)+guard(%d)+LFM(%d) = %d, isreal=%d\n', ...
    N_lfm, guard_samp, N_shaped, guard_samp, N_lfm, length(frame_pb), isreal(frame_pb));
fprintf('块: N_fft=%d, CP=%d, %d块, ~%d info bits\n\n', blk_fft, blk_cp, N_blocks, N_info);

%% ========== 信道 ========== %%
rx_bb_frame = conv(frame_bb, h_bb);
[rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);

% 无噪声同步（直达径窗口）
[bb_clean,~] = downconvert(rx_pb_clean, fs, fc, bw_lfm);
[~, ~, corr_clean] = sync_detect(bb_clean, LFM_bb, 0.3);
dw = min(50, round(length(corr_clean)/2));
[sync_peak, sync_pos] = max(corr_clean(1:dw));
sync_offset_sym = round((sync_pos - 1) / sps);
fprintf('同步: pos=%d, peak=%.3f, offset=%d sym\n\n', sync_pos, sync_peak, sync_offset_sym);

fprintf('%-6s %10s\n','SNR','infoBER%');
fprintf('%s\n',repmat('-',1,18));
ber_results = zeros(1,length(snr_sweep));

for si=1:length(snr_sweep)
    snr_db=snr_sweep(si);
    rng(300+si);

    sig_pwr=mean(rx_pb_clean.^2);
    noise_var=sig_pwr*10^(-snr_db/10);
    rx_pb=rx_pb_clean+sqrt(noise_var)*randn(size(rx_pb_clean));

    [bb_raw,~]=downconvert(rx_pb,fs,fc,bw_lfm);

    ds = sync_pos + data_offset;
    de = ds + N_shaped - 1;
    if de > length(bb_raw), rx_data_bb=[bb_raw(ds:end),zeros(1,de-length(bb_raw))];
    else, rx_data_bb=bb_raw(ds:de); end

    [rx_filt,~]=match_filter(rx_data_bb,sps,'rrc',rolloff,span);
    best_off=0;best_pwr=0;
    for off=0:sps-1,st=rx_filt(off+1:sps:end);
        if length(st)>=10,c=abs(sum(st(1:10).*conj(all_cp_data(1:10))));if c>best_pwr,best_pwr=c;best_off=off;end,end,end
    rx_sym_all=rx_filt(best_off+1:sps:end);
    N_total_sym=N_blocks*sym_per_block;
    if length(rx_sym_all)>N_total_sym,rx_sym_all=rx_sym_all(1:N_total_sym);
    elseif length(rx_sym_all)<N_total_sym,rx_sym_all=[rx_sym_all,zeros(1,N_total_sym-length(rx_sym_all))];end

    LLR_all=zeros(1,M_total); nv_eq=max(noise_var,1e-10);
    for bi=1:N_blocks
        blk_sym=rx_sym_all((bi-1)*sym_per_block+1:bi*sym_per_block);
        rx_nocp=blk_sym(blk_cp+1:end); Y_freq=fft(rx_nocp);
        eff_delays=mod(sym_delays-sync_offset_sym,blk_fft);
        h_td=zeros(1,blk_fft);
        for p=1:length(sym_delays),h_td(eff_delays(p)+1)=h_td(eff_delays(p)+1)+gains(p);end
        H_est=fft(h_td); W=conj(H_est)./(abs(H_est).^2+nv_eq);
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

%% ========== 可视化 ========== %%
figure('Position',[50 500 600 400]);
semilogy(snr_sweep,max(ber_results,1e-5),'bo-','LineWidth',1.8,'MarkerSize',7,'DisplayName','OFDM通带');
hold on;
snr_lin=10.^(snr_sweep/10);
semilogy(snr_sweep,max(0.5*erfc(sqrt(snr_lin)),1e-5),'k--','LineWidth',1,'DisplayName','QPSK无编码');
grid on;xlabel('SNR (dB)');ylabel('BER');
title('OFDM 通带仿真 BER vs SNR（静态6径, max\_delay=15ms）');
legend('Location','southwest');ylim([1e-5 1]);set(gca,'FontSize',12);

figure('Position',[50 50 900 300]);
subplot(1,3,1);
delays_ms=sym_delays/sym_rate*1000;
stem(delays_ms,abs(gains),'filled','LineWidth',1.5);
xlabel('时延(ms)');ylabel('|h|');title(sprintf('信道CIR（%d径）',length(sym_delays)));grid on;
subplot(1,3,2);
h_show=zeros(1,blk_fft);
for p=1:length(sym_delays),if sym_delays(p)+1<=blk_fft,h_show(sym_delays(p)+1)=gains(p);end,end
f_khz=(0:blk_fft-1)*sym_rate/blk_fft/1000;
plot(f_khz,20*log10(abs(fft(h_show))+1e-10),'b','LineWidth',1);
xlabel('频率(kHz)');ylabel('|H|(dB)');title('信道频响');grid on;
subplot(1,3,3);
t_frame=(0:length(frame_pb)-1)/fs*1000;
plot(t_frame,frame_pb,'b','LineWidth',0.3);
xlabel('时间(ms)');ylabel('幅度');title(sprintf('通带发射帧(fc=%dHz)',fc));grid on;

fprintf('\n完成\n');
