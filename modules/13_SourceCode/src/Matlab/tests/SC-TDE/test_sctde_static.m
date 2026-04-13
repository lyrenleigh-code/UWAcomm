%% test_sctde_static.m — SC-TDE通带仿真 SNR vs BER（静态信道）
% 对比多种均衡方法：LE / DFE / BiDFE / Turbo(LE+IC)
% 版本：V3.1.0 — 均衡方法对比

clc; close all;
fprintf('========================================\n');
fprintf('  SC-TDE 静态信道 — 均衡方法对比\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

%% ========== 参数 ========== %%
sps = 8; sym_rate = 6000; fs = sym_rate*sps; fc = 12000;
rolloff = 0.35; span_rrc = 6;
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;
pll = struct('enable',true,'Kp',0.01,'Ki',0.005);

sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

% 训练长度需 > 3×(num_ff+num_fb)_max，DFE(31,90)=121→训练≥400
train_len = 500; N_data_sym = 2000;
M_coded = 2*N_data_sym; N_info = M_coded/n_code - mem;

h_sym = zeros(1, max(sym_delays)+1);
for p=1:length(sym_delays), h_sym(sym_delays(p)+1)=gains(p); end
h_bb = zeros(1, max(sym_delays)*sps+1);
for p=1:length(sym_delays), h_bb(sym_delays(p)*sps+1)=gains(p); end

%% ========== 帧参数 ========== %%
bw_lfm = sym_rate*(1+rolloff); lfm_dur = 0.05;
f_lo = fc-bw_lfm/2; f_hi = fc+bw_lfm/2;
[LFM_pb,~] = gen_lfm(fs, lfm_dur, f_lo, f_hi); N_lfm = length(LFM_pb);
t_lfm = (0:N_lfm-1)/fs;
LFM_bb = exp(1j*2*pi*(-bw_lfm/2*t_lfm + 0.5*bw_lfm/lfm_dur*t_lfm.^2));
guard_samp = max(sym_delays)*sps + 80;

snr_sweep = [-10, -7, -5, -3, 0, 3, 5, 8, 10, 15, 20];

%% ========== 均衡方法定义 ========== %%
% h_src: 1=oracle, 3=MMSE, 4=OMP, 5=SBL, 6=GAMP, 7=VAMP, 8=Turbo-VAMP
eq_methods = {
%   名称                   函数类型    num_ff num_fb turbo_iter  h_src
    'orc',                'turbo_dfe',31,    90,    6,          1;
    'MMSE',               'turbo_dfe',31,    90,    6,          3;
    'OMP',                'turbo_dfe',31,    90,    6,          4;
    'SBL',                'turbo_dfe',31,    90,    6,          5;
    'GAMP',               'turbo_dfe',31,    90,    6,          6;
    'VAMP',               'turbo_dfe',31,    90,    6,          7;
    'TurboVAMP',          'turbo_dfe',31,    90,    6,          8;
};
N_methods = size(eq_methods, 1);

%% ========== TX ========== %%
rng(200);
info_bits = randi([0 1],1,N_info);
coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
coded = coded(1:M_coded);
[inter_all,~] = random_interleave(coded,codec.interleave_seed);
data_sym = bits2qpsk(inter_all);
training = constellation(randi(4,1,train_len));
tx_sym = [training, data_sym];

[shaped_bb,~,~] = pulse_shape(tx_sym, sps, 'rrc', rolloff, span_rrc);
N_shaped = length(shaped_bb);
[data_pb,~] = upconvert(shaped_bb, fs, fc);

lfm_scale = sqrt(mean(data_pb.^2)) / sqrt(mean(LFM_pb.^2));
LFM_pb = LFM_pb * lfm_scale; LFM_bb = LFM_bb * lfm_scale;

guard = zeros(1, guard_samp);
frame_pb = [LFM_pb, guard, data_pb, guard, LFM_pb];
frame_bb = [LFM_bb, zeros(1,guard_samp), shaped_bb, zeros(1,guard_samp), LFM_bb];
data_offset = N_lfm + guard_samp;

%% ========== 信道 ========== %%
rx_bb_frame = conv(frame_bb, h_bb);
[rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);

% 无噪声同步
[bb_clean,~] = downconvert(rx_pb_clean, fs, fc, bw_lfm);
[~, ~, corr_clean] = sync_detect(bb_clean, LFM_bb, 0.3);
dw = min(50, round(length(corr_clean)/2));
[sync_peak, sync_pos] = max(corr_clean(1:dw));

fprintf('帧: isreal=%d, LFM带宽=%.0f~%.0fHz, 训练=%d, 数据=%d\n', ...
    isreal(frame_pb), f_lo, f_hi, train_len, N_data_sym);
fprintf('信道: 6径, max_delay=%.1fms(90符号)\n', max(sym_delays)/sym_rate*1000);
fprintf('同步: pos=%d, peak=%.3f\n\n', sync_pos, sync_peak);

% 交织置换（公用）
[~,perm_all] = random_interleave(zeros(1,M_coded), codec.interleave_seed);

%% ========== SNR × 均衡方法 扫描 ========== %%
ber_all = zeros(N_methods, length(snr_sweep));

% 表头
fprintf('%-6s |', 'SNR');
for mi=1:N_methods, fprintf(' %14s', eq_methods{mi,1}); end
fprintf('\n%s\n', repmat('-',1,6+15*N_methods));

for si = 1:length(snr_sweep)
    snr_db = snr_sweep(si);
    rng(300+si);

    sig_pwr = mean(rx_pb_clean.^2);
    noise_var = sig_pwr * 10^(-snr_db/10);
    rx_pb = rx_pb_clean + sqrt(noise_var)*randn(size(rx_pb_clean));

    [bb_raw,~] = downconvert(rx_pb, fs, fc, bw_lfm);

    % 提取数据
    ds = sync_pos + data_offset;
    de = ds + N_shaped - 1;
    if de > length(bb_raw), rx_data_bb=[bb_raw(ds:end),zeros(1,de-length(bb_raw))];
    else, rx_data_bb=bb_raw(ds:de); end

    [rx_filt,~] = match_filter(rx_data_bb, sps, 'rrc', rolloff, span_rrc);
    best_off=0; best_pwr=0;
    for off=0:sps-1, st=rx_filt(off+1:sps:end);
        if length(st)>=10,c=abs(sum(st(1:10).*conj(tx_sym(1:10))));if c>best_pwr,best_pwr=c;best_off=off;end,end,end
    rx_sym_recv = rx_filt(best_off+1:sps:end);
    N_tx = length(tx_sym);
    if length(rx_sym_recv)>N_tx, rx_sym_recv=rx_sym_recv(1:N_tx);
    elseif length(rx_sym_recv)<N_tx, rx_sym_recv=[rx_sym_recv,zeros(1,N_tx-length(rx_sym_recv))]; end

    % 07-信道估计（从训练序列）
    rx_train = rx_sym_recv(1:train_len);
    L_h = max(sym_delays)+1;  % 信道长度=91抽头
    K_sparse = length(sym_delays);  % 稀疏度=6径

    % 构建Toeplitz观测矩阵（所有稀疏方法共用）
    T_mat = zeros(train_len, L_h);
    for col = 1:L_h
        T_mat(col:train_len, col) = training(1:train_len-col+1).';
    end
    y_obs = rx_train(:);

    % MMSE估计（频域）
    Y_train = fft(rx_train, train_len);
    X_train = fft(training, train_len);
    [~, h_mmse_full] = ch_est_mmse(Y_train, X_train, train_len, noise_var);
    h_est_mmse = h_mmse_full(1:L_h);

    % OMP稀疏估计
    [h_omp_vec, ~, ~] = ch_est_omp(y_obs, T_mat, L_h, K_sparse);
    h_est_omp = h_omp_vec(:).';

    % SBL稀疏贝叶斯
    [h_sbl_vec, ~, ~] = ch_est_sbl(y_obs, T_mat, L_h, 50);
    h_est_sbl = h_sbl_vec(:).';

    % GAMP广义近似消息传递
    [h_gamp_vec, ~] = ch_est_gamp(y_obs, T_mat, L_h, 50, noise_var);
    h_est_gamp = h_gamp_vec(:).';

    % VAMP变分近似消息传递
    [h_vamp_vec, ~, ~] = ch_est_vamp(y_obs, T_mat, L_h, 100, noise_var, K_sparse);
    h_est_vamp = h_vamp_vec(:).';

    % Turbo-VAMP
    [h_tvamp_vec, ~, ~, ~] = ch_est_turbo_vamp(y_obs, T_mat, L_h, 30, K_sparse, noise_var);
    h_est_tvamp = h_tvamp_vec(:).';

    fprintf('%-6d |', snr_db);

    for mi = 1:N_methods
        mtype = eq_methods{mi,2};
        nff = eq_methods{mi,3};
        nfb = eq_methods{mi,4};
        ti  = eq_methods{mi,5};
        h_src = eq_methods{mi,6};
        switch h_src
            case 1, h_pass = h_sym;        % oracle
            case 3, h_pass = h_est_mmse;   % MMSE
            case 4, h_pass = h_est_omp;    % OMP
            case 5, h_pass = h_est_sbl;    % SBL
            case 6, h_pass = h_est_gamp;   % GAMP
            case 7, h_pass = h_est_vamp;   % VAMP
            case 8, h_pass = h_est_tvamp;  % Turbo-VAMP
            otherwise, h_pass = [];
        end

        if strcmp(mtype, 'turbo')
            % 原始Turbo: LE(iter1) + ISI消除(iter2+)
            eq_p = struct('num_ff',nff,'num_fb',nfb,'lambda',0.998,'pll',pll);
            h_turbo = h_pass;
            [bits_out,~] = turbo_equalizer_sctde(rx_sym_recv, h_turbo, training, ...
                ti, noise_var, eq_p, codec);

        elseif strcmp(mtype, 'turbo_dfe')
            % DFE+Turbo: DFE(iter1) + 软ISI消除(iter2+)
            h_turbo = h_pass;
            h_turbo = h_turbo(:).';
            T = train_len;
            N_dsym = length(rx_sym_recv) - T;

            % iter 1: DFE with h_est初始化
            [LLR_dfe, x_hat_dfe, nv_dfe] = eq_dfe(rx_sym_recv, h_turbo, training, nff, nfb, 0.998, pll);
            LLR_eq = -LLR_dfe;  % 符号修正
            h0 = h_turbo(1); nv_zf = nv_dfe;

            % 生成交织置换
            [~,perm_turbo] = random_interleave(zeros(1,M_coded), codec.interleave_seed);
            x_bar_data = [];
            bits_decoded = [];

            for titer = 1:ti
                % 均衡输出 → 截断/填零 → 解交织 → BCJR
                LLR_trunc = LLR_eq(1:min(length(LLR_eq),M_coded));
                if length(LLR_trunc)<M_coded, LLR_trunc=[LLR_trunc,zeros(1,M_coded-length(LLR_trunc))]; end
                Le_deint = random_deinterleave(LLR_trunc, perm_turbo);
                Le_deint = max(min(Le_deint,30),-30);

                if strcmpi(codec.decode_mode,'sova')
                    [~,Lp_info,Lp_coded] = sova_decode_conv(Le_deint,[],codec.gen_polys,codec.constraint_len);
                else
                    [~,Lp_info,Lp_coded] = siso_decode_conv(Le_deint,[],codec.gen_polys,codec.constraint_len,codec.decode_mode);
                end
                bits_decoded = double(Lp_info > 0);

                % 反馈: BCJR后验 → 交织 → soft_mapper → 软符号
                if titer < ti
                    Lp_inter = random_interleave(Lp_coded, codec.interleave_seed);
                    if length(Lp_inter)<M_coded, Lp_inter=[Lp_inter,zeros(1,M_coded-length(Lp_inter))];
                    else, Lp_inter=Lp_inter(1:M_coded); end
                    [x_bar_data, ~] = soft_mapper(Lp_inter, 'qpsk');

                    % 软ISI消除 + 单抽头ZF（iter2+）
                    full_est = zeros(1, length(rx_sym_recv));
                    full_est(1:T) = training;
                    n_fill = min(length(x_bar_data), N_dsym);
                    if n_fill>0, full_est(T+1:T+n_fill)=x_bar_data(1:n_fill); end

                    isi_full = conv(full_est, h_turbo);
                    isi_full = isi_full(1:length(rx_sym_recv));
                    self_sig = h0 * full_est;
                    rx_ic = rx_sym_recv;
                    rx_ic(T+1:end) = rx_sym_recv(T+1:end) - isi_full(T+1:end) + self_sig(T+1:end);

                    data_eq = rx_ic(T+1:end) / h0;
                    nv_post = nv_zf / abs(h0)^2;
                    LLR_eq = zeros(1, 2*length(data_eq));
                    LLR_eq(1:2:end) = -2*sqrt(2)*real(data_eq)/nv_post;
                    LLR_eq(2:2:end) = -2*sqrt(2)*imag(data_eq)/nv_post;
                end
            end
            bits_out = bits_decoded;

        else
            % 单次DFE/BiDFE + BCJR
            if strcmp(mtype, 'bidfe')
                [LLR_raw,~,~] = eq_bidirectional_dfe(rx_sym_recv, h_pass, training, nff, nfb, 0.998, pll);
            else
                [LLR_raw,~,~] = eq_dfe(rx_sym_recv, h_pass, training, nff, nfb, 0.998, pll);
            end
            LLR_raw = LLR_raw(1:min(length(LLR_raw), M_coded));
            if length(LLR_raw)<M_coded, LLR_raw=[LLR_raw,zeros(1,M_coded-length(LLR_raw))]; end
            best_ber_m = 0.5; bits_out = [];
            for sgn = [+1, -1]
                LLR_try = sgn * LLR_raw;
                ld = random_deinterleave(LLR_try, perm_all);
                ld = max(min(ld,30),-30);
                [~,Lp,~] = siso_decode_conv(ld,[],codec.gen_polys,codec.constraint_len);
                bo = double(Lp>0);
                nc = min(length(bo), N_info);
                bt = mean(bo(1:nc) ~= info_bits(1:nc));
                if bt < best_ber_m, best_ber_m=bt; bits_out=bo; end
            end
        end

        nc = min(length(bits_out), N_info);
        ber = mean(bits_out(1:nc) ~= info_bits(1:nc));
        ber_all(mi, si) = ber;
        fprintf(' %13.2f%%', ber*100);
    end
    fprintf('\n');
end

%% ========== 可视化 ========== %%
figure('Position',[50 400 800 500]);
all_markers = {'o-','s-','d-','^-','v-','p-','h-'};
all_colors = lines(N_methods);
for mi=1:N_methods
    mk = all_markers{mod(mi-1,length(all_markers))+1};
    semilogy(snr_sweep, max(ber_all(mi,:),1e-5), mk, ...
        'Color',all_colors(mi,:), 'LineWidth',1.8, 'MarkerSize',7, ...
        'DisplayName', eq_methods{mi,1});
    hold on;
end
snr_lin=10.^(snr_sweep/10);
semilogy(snr_sweep, max(0.5*erfc(sqrt(snr_lin)),1e-5), 'k--', 'LineWidth',1, 'DisplayName','QPSK无编码');
grid on; xlabel('SNR (dB)'); ylabel('BER');
title('SC-TDE 静态6径信道 — 均衡方法对比');
legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',11);

figure('Position',[50 50 800 300]);
subplot(1,2,1);
delays_ms=sym_delays/sym_rate*1000;
stem(delays_ms,abs(gains),'filled','LineWidth',1.5);
xlabel('时延(ms)');ylabel('|h|');title(sprintf('信道CIR（%d径）',length(sym_delays)));grid on;
subplot(1,2,2);
h_show=zeros(1,1024);
for p=1:length(sym_delays),if sym_delays(p)+1<=1024,h_show(sym_delays(p)+1)=gains(p);end,end
f_khz=(0:1023)*sym_rate/1024/1000;
plot(f_khz,20*log10(abs(fft(h_show))+1e-10),'b','LineWidth',1);
xlabel('频率(kHz)');ylabel('|H|(dB)');title('信道频响');grid on;

% 通带帧波形
figure('Position',[50 350 900 250]);
t_frame=(0:length(frame_pb)-1)/fs*1000;
plot(t_frame, frame_pb, 'b', 'LineWidth',0.3); hold on;
xline(N_lfm/fs*1000,'r--'); xline((N_lfm+guard_samp)/fs*1000,'r--');
xline((N_lfm+guard_samp+N_shaped)/fs*1000,'r--');
xlabel('时间(ms)');ylabel('幅度');grid on;
title(sprintf('通带发射帧(fc=%dHz, %.1fms)', fc, length(frame_pb)/fs*1000));

fprintf('\n完成\n');
