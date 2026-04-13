%% test_dsss_discrete_doppler.m — DSSS 离散Doppler/混合Rician信道对比
% TX: 编码->BPSK(+-1)->dsss_spread(Gold31)->RRC成形(码片率)->上变频->帧组装
%     帧: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|train_chips|data_chips]
% 信道: apply_channel(离散Doppler/Rician混合/Jakes) — 等效基带
% RX: 下变频->LFM粗估alpha->精补偿->LFM定时->RRC匹配->训练估信道->Rake(MRC)->译码
% 版本：V1.0.0 — 6种信道模型对比 (对标SC-FDE/OTFS信道配置)

clc; close all;
fprintf('========================================\n');
fprintf('  DSSS 离散Doppler信道对比 V1.0\n');
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
chip_rate = 6000; sps = 8; fs = chip_rate*sps; fc = 12000;
rolloff = 0.35; span_rrc = 6;

% 扩频
L = 31;
spread_code = gen_gold_code(5, 0);
spread_code_pm = 2*spread_code - 1;
dsss_sym_rate = chip_rate / L;

% 编解码
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;

% 数据
N_info = 500;
M_coded = n_code * (N_info + mem);
N_dsss_sym = M_coded + 1;             % DBPSK: +1参考符号
N_data_chips = N_dsss_sym * L;
train_sym = 100;
train_chips = train_sym * L;

% 5径信道
chip_delays = [0, 1, 3, 5, 8];
delay_samp = chip_delays * sps;   % 样本级时延 @fs=48kHz
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));

% 每径Doppler频移 (5径)
doppler_per_path = [0, 3, -4, 5, -2];  % Hz

% 通信速率
code_rate = 1/n_code;
info_rate_bps = dsss_sym_rate * 1 * code_rate;

%% ========== 帧参数 ========== %%
bw = chip_rate * (1 + rolloff);
preamble_dur = 0.05;
f_lo = fc - bw/2; f_hi = fc + bw/2;

[HFM_pb, ~] = gen_hfm(fs, preamble_dur, f_lo, f_hi);
N_preamble = length(HFM_pb);
t_pre = (0:N_preamble-1)/fs;

f0=f_lo; f1=f_hi; T_pre=preamble_dur;
if abs(f1-f0)<1e-6, phase_hfm=2*pi*f0*t_pre;
else, k_hfm=f0*f1*T_pre/(f1-f0); phase_hfm=-2*pi*k_hfm*log(1-(f1-f0)/f1*t_pre/T_pre); end
HFM_bb = exp(1j*(phase_hfm - 2*pi*fc*t_pre));

if abs(f1-f0)<1e-6, phase_hfm_neg=2*pi*f1*t_pre;
else, k_neg=f1*f0*T_pre/(f0-f1); phase_hfm_neg=-2*pi*k_neg*log(1-(f0-f1)/f0*t_pre/T_pre); end
HFM_bb_neg = exp(1j*(phase_hfm_neg - 2*pi*fc*t_pre));

chirp_rate_lfm = (f_hi-f_lo)/preamble_dur;
phase_lfm = 2*pi*(f_lo*t_pre + 0.5*chirp_rate_lfm*t_pre.^2);
LFM_bb = exp(1j*(phase_lfm - 2*pi*fc*t_pre));
N_lfm = length(LFM_bb);
guard_samp = max(chip_delays)*sps + 80;

% LFM检测标称位置
lfm1_peak_nom = 2*N_preamble + 2*guard_samp + N_lfm;
lfm2_peak_nom = 2*N_preamble + 3*guard_samp + 2*N_lfm;
lfm_search_margin = max(chip_delays)*sps + 200;
T_v_lfm = (N_lfm + guard_samp) / fs;
lfm_data_offset = N_lfm + guard_samp;

%% ========== 信道配置（6种，对标SC-FDE/OTFS）========== %%
snr_list = [-15, -10, -5, 0, 5, 10];
fading_cfgs = {
    'static',   'static',   zeros(1,5),  0;
    'disc-5Hz', 'discrete', doppler_per_path, 5;
    'hyb-K20',  'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',0.5, 'K_rice',20), 5;
    'hyb-K10',  'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',0.5, 'K_rice',10), 5;
    'hyb-K5',   'hybrid',   struct('doppler_hz',doppler_per_path, 'fd_scatter',1.0, 'K_rice',5),  5;
    'jakes5Hz', 'jakes',    5, 5;
};

fprintf('通带: fs=%dHz, fc=%dHz, 带宽=%.0fHz\n', fs, fc, bw);
fprintf('DSSS: Gold(%d), L=%d, 码片率=%d, 符号率=%.1f sym/s\n', 5, L, chip_rate, dsss_sym_rate);
fprintf('通信速率: %.1f bps (BPSK, R=1/%d, L=%d)\n', info_rate_bps, n_code, L);
fprintf('信道: %d径, delays=[%s] chips, 每径Doppler=[%s]Hz\n', ...
    length(chip_delays), num2str(chip_delays), num2str(doppler_per_path));
fprintf('处理增益: %.1f dB\n\n', 10*log10(L));

N_fading = size(fading_cfgs, 1);
ber_matrix = zeros(N_fading, length(snr_list));
ber_unc_matrix = zeros(N_fading, length(snr_list));
alpha_est_matrix = zeros(N_fading, 1);
sync_info_matrix = zeros(N_fading, 2);

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:N_fading
    fname   = fading_cfgs{fi,1};
    ftype   = fading_cfgs{fi,2};
    fparams = fading_cfgs{fi,3};
    fd_hz   = fading_cfgs{fi,4};

    %% ===== TX ===== %%
    rng(100+fi);
    training = 2*randi([0,1],1,train_sym) - 1;
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_coded);
    [interleaved, ~] = random_interleave(coded, codec.interleave_seed);

    % DBPSK差分编码
    diff_encoded = zeros(1, M_coded + 1);
    diff_encoded(1) = 1;
    for k = 1:M_coded
        diff_encoded(k+1) = xor(interleaved(k), diff_encoded(k));
    end
    data_sym = 2*diff_encoded - 1;

    train_spread = dsss_spread(training, spread_code);
    data_spread = dsss_spread(data_sym, spread_code);
    all_chips = [train_spread, data_spread];
    N_total_chips = length(all_chips);

    [shaped_bb,~,~] = pulse_shape(all_chips, sps, 'rrc', rolloff, span_rrc);
    N_shaped = length(shaped_bb);
    [data_pb,~] = upconvert(shaped_bb, fs, fc);
    data_rms = sqrt(mean(data_pb.^2));
    lfm_scale = data_rms / sqrt(mean(HFM_pb.^2));
    HFM_bb_n = HFM_bb*lfm_scale; HFM_bb_neg_n = HFM_bb_neg*lfm_scale; LFM_bb_n = LFM_bb*lfm_scale;

    frame_bb = [HFM_bb_n, zeros(1,guard_samp), HFM_bb_neg_n, zeros(1,guard_samp), ...
                LFM_bb_n, zeros(1,guard_samp), LFM_bb_n, zeros(1,guard_samp), shaped_bb];

    %% ===== 信道（apply_channel替代gen_uwa_channel）===== %%
    rx_bb_frame = apply_channel(frame_bb, delay_samp, gains_raw, ftype, fparams, fs, fc);
    [rx_pb_clean,~] = upconvert(rx_bb_frame, fs, fc);
    sig_pwr = mean(rx_pb_clean.^2);

    mf_lfm = conj(fliplr(LFM_bb_n));
    lfm2_search_len = min(3*N_preamble + 4*guard_samp + 2*N_lfm, length(rx_bb_frame));

    % ===== 无噪声sync+doppler估计 =====
    [bb_clean,~] = downconvert(rx_pb_clean, fs, fc, bw);
    corr_clean = filter(mf_lfm, 1, bb_clean);
    corr_clean_abs = abs(corr_clean);
    p1_lo = max(1, lfm1_peak_nom - lfm_search_margin);
    p1_hi = min(lfm1_peak_nom + lfm_search_margin, length(corr_clean_abs));
    [~, p1_rel] = max(corr_clean_abs(p1_lo:p1_hi));
    p1_idx = p1_lo + p1_rel - 1;
    p2_lo = max(1, lfm2_peak_nom - lfm_search_margin);
    p2_hi = min(lfm2_peak_nom + lfm_search_margin, length(corr_clean_abs));
    [~, p2_rel] = max(corr_clean_abs(p2_lo:p2_hi));
    p2_idx = p2_lo + p2_rel - 1;
    R1 = corr_clean(p1_idx); R2 = corr_clean(p2_idx);
    alpha_est = angle(R2 * conj(R1)) / (2*pi*fc*T_v_lfm);
    sync_peak = abs(R1) / sum(abs(LFM_bb_n).^2);
    alpha_est_matrix(fi) = alpha_est;

    % 精补偿 + LFM精确定时（无噪声）
    if abs(alpha_est) > 1e-10
        bb_comp_clean = comp_resample_spline(bb_clean, alpha_est, fs, 'fast');
    else
        bb_comp_clean = bb_clean;
    end
    corr_comp_clean = abs(filter(mf_lfm, 1, bb_comp_clean(1:min(lfm2_search_len,length(bb_comp_clean)))));
    c2_lo = max(1, lfm2_peak_nom - lfm_search_margin);
    c2_hi = min(lfm2_peak_nom + lfm_search_margin, length(corr_comp_clean));
    [~, lfm2_local] = max(corr_comp_clean(c2_lo:c2_hi));
    lfm2_peak_idx = c2_lo + lfm2_local - 1;
    lfm_pos = lfm2_peak_idx - N_lfm + 1;
    sync_info_matrix(fi,:) = [lfm_pos, sync_peak];

    fprintf('%-8s |', fname);

    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300+fi*1000+si*100);
        rx_pb = rx_pb_clean + sqrt(noise_var)*randn(size(rx_pb_clean));

        % 1. 下变频
        [bb_raw,~] = downconvert(rx_pb, fs, fc, bw);

        % 2. 多普勒补偿
        if abs(alpha_est) > 1e-10
            bb_comp = comp_resample_spline(bb_raw, alpha_est, fs, 'fast');
        else
            bb_comp = bb_raw;
        end

        % 3. 数据段提取 + RRC匹配 + 下采样
        ds = lfm_pos + lfm_data_offset;
        de = ds + N_shaped - 1;
        if de > length(bb_comp)
            rx_data_bb = [bb_comp(ds:end), zeros(1, de-length(bb_comp))];
        else
            rx_data_bb = bb_comp(ds:de);
        end
        [rx_filt,~] = match_filter(rx_data_bb, sps, 'rrc', rolloff, span_rrc);

        best_off=0; best_pwr=0;
        for off=0:sps-1
            idx=off+1:sps:length(rx_filt);
            n_check=min(length(idx),train_chips);
            if n_check>=L
                c=abs(sum(rx_filt(idx(1:n_check)).*conj(train_spread(1:n_check))));
                if c>best_pwr, best_pwr=c; best_off=off; end
            end
        end
        rx_chips = rx_filt(best_off+1:sps:end);
        if length(rx_chips)>N_total_chips, rx_chips=rx_chips(1:N_total_chips);
        elseif length(rx_chips)<N_total_chips, rx_chips=[rx_chips,zeros(1,N_total_chips-length(rx_chips))]; end

        % 残余CFO补偿
        if abs(alpha_est) > 1e-10
            cfo_res = alpha_est * fc;
            t_chip = (0:length(rx_chips)-1) / chip_rate;
            rx_chips = rx_chips .* exp(-1j*2*pi*cfo_res*t_chip);
        end

        % 4. 训练段信道估计（Rake finger增益）
        h_est = zeros(1, length(chip_delays));
        for p = 1:length(chip_delays)
            d = chip_delays(p);
            acc = 0;
            for k = 1:train_sym
                cs = (k-1)*L + d + 1; ce = cs + L - 1;
                if ce <= train_chips
                    acc = acc + (sum(rx_chips(cs:ce).*spread_code_pm)/L) * conj(training(k));
                end
            end
            h_est(p) = acc / train_sym;
        end

        % 5. Rake接收
        [rake_out,~] = eq_rake(rx_chips, spread_code, chip_delays, h_est, N_dsss_sym, struct('combine','mrc','offset',train_chips));

        % 6. DCD差分检测
        [dcd_decisions, dcd_diff] = det_dcd(rake_out);
        bits_dcd = double(dcd_decisions < 0);
        ber_unc = mean(bits_dcd ~= interleaved);

        % 7. 软LLR + Viterbi
        nv_diff = max(var(real(dcd_diff)) * 0.5, 1e-6);
        LLR_inter = max(min(-real(dcd_diff) / nv_diff, 30), -30);
        [~,perm] = random_interleave(zeros(1,M_coded), codec.interleave_seed);
        LLR_coded = random_deinterleave(LLR_inter, perm);
        [~,Lp_info,~] = siso_decode_conv(LLR_coded, [], codec.gen_polys, codec.constraint_len, codec.decode_mode);
        bits_out = double(Lp_info > 0);

        nc = min(length(bits_out), N_info);
        ber = mean(bits_out(1:nc) ~= info_bits(1:nc));
        ber_matrix(fi,si) = ber;
        ber_unc_matrix(fi,si) = ber_unc;
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (lfm=%d, pk=%.3f)\n', sync_info_matrix(fi,1), sync_info_matrix(fi,2));
end

%% ========== 可视化 ========== %%
figure('Position',[50 500 800 450]);
markers={'o-','s-','d-','^-','v-','x-'};
colors=[0 .45 .74; .85 .33 .1; .47 .67 .19; .93 .69 .13; .49 .18 .56; .3 .3 .3];
for fi=1:N_fading
    semilogy(snr_list, max(ber_matrix(fi,:),1e-5), markers{fi}, ...
        'Color',colors(fi,:),'LineWidth',1.8,'MarkerSize',7,'DisplayName',fading_cfgs{fi,1});
    hold on;
end
grid on; xlabel('SNR (dB)'); ylabel('BER');
title(sprintf('DSSS Gold(%d) 离散Doppler信道对比 — %.1f bps', L, info_rate_bps));
legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);

fprintf('\n--- 同步 ---\n');
for fi=1:N_fading
    fprintf('%-8s: lfm_pos=%d, alpha_est=%.4e, peak=%.3f\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), alpha_est_matrix(fi), sync_info_matrix(fi,2));
end
fprintf('\n完成\n');

%% ========== 保存结果 ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_dsss_discrete_doppler_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'DSSS 离散Doppler信道对比 V1.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'DSSS: Gold(%d), L=%d, chip_rate=%d, sym_rate=%.1f\n', 5, L, chip_rate, dsss_sym_rate);
fprintf(fid, '通信速率: %.1f bps (BPSK, R=1/%d, L=%d)\n', info_rate_bps, n_code, L);
fprintf(fid, '信道: %d径, delays=[%s], 每径Doppler=[%s]Hz\n', length(chip_delays), num2str(chip_delays), num2str(doppler_per_path));
fprintf(fid, '处理增益: %.1f dB, Rake: %d fingers MRC\n\n', 10*log10(L), length(chip_delays));

fprintf(fid, '=== BER (coded) ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:N_fading
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

fprintf(fid, '\n=== BER (uncoded) ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:N_fading
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_unc_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

fprintf(fid, '\n=== 同步 + 多普勒 ===\n');
for fi=1:N_fading
    fprintf(fid, '%-8s: lfm_pos=%d, alpha_est=%.4e, peak=%.3f\n', ...
        fading_cfgs{fi,1}, sync_info_matrix(fi,1), alpha_est_matrix(fi), sync_info_matrix(fi,2));
end
fclose(fid);
fprintf('结果已保存: %s\n', result_file);
