%% test_otfs_timevarying.m — OTFS通带仿真 时变信道测试
% TX: 编码→交织→QPSK→DD域导频→OTFS调制→FFT上采样→上变频→通带实信号
% 信道: 等效基带(离散Doppler/Rician混合/Jakes)
% RX: 下变频→FFT降采样→OTFS解调→DD域信道估计→LMMSE+Turbo→译码
% 版本：V4.0.0 — 通带仿真 + 离散/混合/Jakes信道对比
% 特点：通带实噪声, FFT零延迟重采样(无RRC,保持DD域关系)

clc; close all;
use_oracle = false;
eq_type = 'lmmse';
uamp_inner = 5;
passband_mode = true;  % true=通带仿真, false=基带仿真

fprintf('========================================\n');
if passband_mode
    fprintf('  OTFS 通带仿真 V4.0\n');
else
    fprintf('  OTFS 基带仿真 V4.0\n');
end
fprintf('  均衡: %s, Oracle=%d\n', upper(eq_type), use_oracle);
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

%% ========== 参数 ========== %%
sym_rate = 6000;  % 基带采样率
fc = 12000;

% 5径信道 (须在OTFS参数前定义，cp_len依赖max delay)
delay_bins = [0, 1, 3, 5, 8];
delays_s = delay_bins / sym_rate;
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];

% OTFS参数
N = 32;          % 多普勒格点
M = 64;          % 时延格点
cp_len = 32;     % per-sub-block CP (需>max_delay, 较大余量避免ISI)
mp_iters = 20;
num_turbo = 3;

% 通带参数
sps = 6;                    % 上采样倍数 (需满足 fs_pb > 2*(fc+sym_rate/2))
fs_pb = sym_rate * sps;     % 通带采样率 36kHz

% QPSK
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits_per_sym = 2;

% 导频 (per-sub-block CP已消除β因子，无需delay_guard)
pilot_config = struct('mode','impulse', 'guard_k',4, 'guard_l',max(delay_bins)+2, ...
    'pilot_value',1);
[~,~,~,data_indices] = otfs_pilot_embed(zeros(1,1), N, M, pilot_config);
N_data_slots = length(data_indices);
pilot_config.pilot_value = sqrt(N_data_slots);

% 编解码
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;
M_coded = N_data_slots * bits_per_sym;
N_info = M_coded / n_code - mem;

% 通信速率
subcarrier_spacing = sym_rate / M;
frame_duration = (N*M + cp_len) / sym_rate;
info_rate_bps = N_info / frame_duration;

% 生成交织置换
[~, perm] = random_interleave(zeros(1, M_coded), codec.interleave_seed);

snr_list = [0, 5, 10, 15, 20];

% 多普勒分辨率 (DD域网格间距)
delta_nu = sym_rate / (N * M);  % = fs/(N*M) ≈ 2.93 Hz

% 信道配置：离散Doppler vs Jakes对比
% 格式: {名称, 类型, 参数}
%   'discrete': 每径固定Doppler ν_p → h_p*exp(j2πν_p*t)
%   'jakes':    Jakes衰落 (连续Doppler谱)
%   'static':   无Doppler
% 混合信道: Rician = sqrt(K/(K+1))*exp(j2πν_p*t) + sqrt(1/(K+1))*jakes(fd_sc)
% K=Rician因子(谱直散比), fd_sc=散射Doppler展宽
fading_cfgs = {
    'static',   'static',   zeros(1,5);
    'disc-5Hz', 'discrete', [0, 3, -4, 5, -2];
    'hyb-K20',  'hybrid',   struct('doppler_hz',[0,3,-4,5,-2], 'fd_scatter',0.5, 'K_rice',20);
    'hyb-K10',  'hybrid',   struct('doppler_hz',[0,3,-4,5,-2], 'fd_scatter',0.5, 'K_rice',10);
    'hyb-K5',   'hybrid',   struct('doppler_hz',[0,3,-4,5,-2], 'fd_scatter',1.0, 'K_rice',5);
    'jakes5Hz', 'jakes',    5;
};

fprintf('OTFS: N=%d x M=%d, CP=%d, df=%.1fHz, fs_bb=%dHz\n', N, M, cp_len, subcarrier_spacing, sym_rate);
if passband_mode
    fprintf('通带: sps=%d, fs_pb=%dHz, fc=%dHz\n', sps, fs_pb, fc);
end
fprintf('均衡: %s + Turbo %d轮\n', upper(eq_type), num_turbo);
fprintf('速率: %.0f bps (QPSK, R=1/%d, %d data slots)\n', info_rate_bps, n_code, N_data_slots);
fprintf('帧长: %d样本 (%.1fms)\n', N*M+cp_len, frame_duration*1000);
fprintf('信道: %d径, delay_bins=[%s], max=%d < CP=%d\n', ...
    length(delay_bins), num2str(delay_bins), max(delay_bins), cp_len);
fprintf('多普勒分辨率: Δν=%.2f Hz\n\n', delta_nu);

%% ========== Loopback验证 ========== %%
fprintf('--- Loopback验证 ---\n');
rng(999);
test_data = constellation(randi(4,1,N_data_slots));
[dd_test,~,~,~] = otfs_pilot_embed(test_data, N, M, pilot_config);
[sig_test,~] = otfs_modulate(dd_test, N, M, cp_len, 'dft');
[dd_recv,~] = otfs_demodulate(sig_test, N, M, cp_len, 'dft');
err_loopback = max(abs(dd_test(:) - dd_recv(:)));
fprintf('  mod->demod 误差: %.2e %s\n\n', err_loopback, ...
    char((err_loopback<1e-10)*'V' + (err_loopback>=1e-10)*'X'));

%% ========== 主测试 ========== %%
ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));
ber_unc_matrix = zeros(size(fading_cfgs,1), length(snr_list));
ber_turbo_trace = cell(size(fading_cfgs,1), length(snr_list));
% 保存每配置的真实/估计DD信道（最高SNR时）用于可视化
ch_diag = struct('h_true',{}, 'h_est',{}, 'path_info',{});

fprintf('%-9s|', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname = fading_cfgs{fi,1};
    ftype = fading_cfgs{fi,2};
    fparams = fading_cfgs{fi,3};

    %% ===== TX ===== %%
    rng(100+fi);
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_coded);
    [interleaved,~] = random_interleave(coded, codec.interleave_seed);
    data_sym = constellation(bi2de(reshape(interleaved,2,[]).','left-msb')+1);

    [dd_frame, pilot_info, guard_mask, ~] = otfs_pilot_embed(data_sym, N, M, pilot_config);
    [otfs_signal, ~] = otfs_modulate(dd_frame, N, M, cp_len, 'dft');

    N_sig = length(otfs_signal);

    %% ===== 1) 信道(等效基带) ===== %%
    rx_clean = apply_channel(otfs_signal, delay_bins, gains_raw, ftype, fparams, sym_rate, fc);

    %% ===== 2) 通带帧组装: [LFM|guard|OTFS|guard|LFM] ===== %%
    if passband_mode
        % LFM同步信号 (通带)
        lfm_dur = 0.02; guard_dur = 0.005;
        N_guard_pb = round(guard_dur * fs_pb);
        [lfm_pb, ~] = gen_lfm(fs_pb, lfm_dur, fc-sym_rate/2, fc+sym_rate/2);
        lfm_bb = hilbert(lfm_pb);  % LFM基带版本(供RX匹配)
        lfm_bb = lfm_bb .* exp(-1j*2*pi*fc*(0:length(lfm_bb)-1)/fs_pb);  % 下变频到基带

        % OTFS逐子块上采样(消除Gibbs振铃) + 升余弦过渡
        [otfs_pb, tx_up] = otfs_to_passband(otfs_signal, N, M, cp_len, sps, fs_pb, fc);
        % RX侧同理
        [rx_otfs_pb, ~] = otfs_to_passband(rx_clean, N, M, cp_len, sps, fs_pb, fc);

        % 功率匹配
        lfm_pb = lfm_pb * sqrt(mean(otfs_pb.^2)) / sqrt(mean(lfm_pb.^2));

        % 帧组装
        guard_pb = zeros(1, N_guard_pb);
        frame_tx_pb = [lfm_pb, guard_pb, otfs_pb, guard_pb, lfm_pb];
        frame_rx_pb = [lfm_pb, guard_pb, rx_otfs_pb, guard_pb, lfm_pb];
        data_offset_pb = length(lfm_pb) + N_guard_pb;
        sig_pwr_pb = mean(frame_rx_pb.^2);

        % 无噪声同步(一次性, 确定LFM定时位置)
        [bb_sync,~] = downconvert(frame_rx_pb, fs_pb, fc, sym_rate*0.45);
        [~,~,corr_sync] = sync_detect(bb_sync, lfm_bb(1:min(end,500)), 0.3);
        % 找第1个LFM峰→数据起始
        [~, sync_pos] = max(corr_sync(1:length(lfm_pb)+N_guard_pb));
    else
        sig_pwr = mean(abs(rx_clean).^2);
    end

    % 保存第1配置波形(供可视化)
    if fi == 1
        if passband_mode
            vis_frame_tx = frame_tx_pb;
            vis_frame_info = struct('data_offset', data_offset_pb, ...
                'data_len', length(otfs_pb), 'lfm_len', length(lfm_pb), ...
                'guard_len', N_guard_pb);
        end
        vis_tx_bb = otfs_signal;
    end

    % === Pilot-only信道探测(基带) ===
    dd_pilot_only = zeros(N, M);
    dd_pilot_only(pilot_info.positions(1,1), pilot_info.positions(1,2)) = pilot_info.values(1);
    [sig_po, ~] = otfs_modulate(dd_pilot_only, N, M, cp_len, 'dft');
    rx_po = apply_channel(sig_po, delay_bins, gains_raw, ftype, fparams, sym_rate, fc);
    [Y_dd_po, ~] = otfs_demodulate(rx_po, N, M, cp_len, 'dft');
    ch_diag(fi).h_true = Y_dd_po / pilot_info.values(1);

    fprintf('%-9s|', fname);

    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        rng(300+fi*1000+si*100);

        if passband_mode
            % 通带帧加实噪声
            noise_pwr = sig_pwr_pb * 10^(-snr_db/10);
            frame_rx_noisy = frame_rx_pb + sqrt(noise_pwr) * randn(size(frame_rx_pb));
            % LFM匹配定时 → 提取OTFS数据段
            rx_otfs_seg = frame_rx_noisy(data_offset_pb+1 : data_offset_pb+length(rx_otfs_pb));
            % 逐子块下变频+降采样
            rx_noisy = passband_to_otfs(rx_otfs_seg, N, M, cp_len, sps, fs_pb, fc);
            noise_var = mean(abs(rx_clean).^2) * 10^(-snr_db/10);
            if fi == 1 && si == length(snr_list)
                vis_frame_rx = frame_rx_noisy;
            end
        else
            noise_var = mean(abs(rx_clean).^2) * 10^(-snr_db/10);
            rx_noisy = rx_clean + sqrt(noise_var/2)*(randn(size(rx_clean)) + 1j*randn(size(rx_clean)));
        end

        % 1. OTFS解调
        [Y_dd, ~] = otfs_demodulate(rx_noisy, N, M, cp_len, 'dft');
        pk_pos = pilot_info.positions(1,1);
        pl_pos = pilot_info.positions(1,2);
        pv_val = pilot_info.values(1);

        % 2. 信道获取：Oracle模式(真实信道) 或 估计模式
        if use_oracle
            % Oracle: guard区完整响应作为信道（无阈值，最大精度）
            % LMMSE用D=fft2(C)全局频响，完整guard给出最准确的C
            h_true = ch_diag(fi).h_true;  % NxM, 已归一化(无噪声pilot-only)
            h_dd = zeros(N, M);
            oracle_delays = []; oracle_dopplers = []; oracle_gains = [];
            for dk_o = -pilot_config.guard_k:pilot_config.guard_k
                for dl_o = 0:pilot_config.guard_l
                    kk_o = mod(pk_pos-1+dk_o, N)+1;
                    ll_o = mod(pl_pos-1+dl_o, M)+1;
                    val_o = h_true(kk_o, ll_o);
                    h_dd(kk_o, ll_o) = val_o;  % 无阈值，全部写入
                    oracle_delays = [oracle_delays, dl_o];
                    oracle_dopplers = [oracle_dopplers, dk_o];
                    oracle_gains = [oracle_gains, val_o];
                end
            end
            path_info.delay_idx = oracle_delays;
            path_info.doppler_idx = oracle_dopplers;
            path_info.gain = oracle_gains;
            path_info.num_paths = length(oracle_gains);
            nv_dd = max(noise_var, 1e-8);
        else
            % 估计模式
            [h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M);
            % 噪声方差估计
            detected_dl = unique(path_info.delay_idx);
            noise_mask = false(N, M);
            for dk_n = -pilot_config.guard_k:pilot_config.guard_k
                for dl_n = 0:pilot_config.guard_l
                    if ~ismember(dl_n, detected_dl)
                        kk_n = mod(pk_pos-1+dk_n, N)+1;
                        ll_n = mod(pl_pos-1+dl_n, M)+1;
                        noise_mask(kk_n, ll_n) = true;
                    end
                end
            end
            if any(noise_mask(:))
                nv_dd = max(mean(abs(Y_dd(noise_mask)).^2), 1e-8);
            else
                nv_dd = max(noise_var, 1e-8);
            end
        end

        % 3. 导频贡献去除
        Y_dd_eq = Y_dd;
        for pp_r = 1:path_info.num_paths
            kk_r = mod(pk_pos-1+path_info.doppler_idx(pp_r), N)+1;
            ll_r = mod(pl_pos-1+path_info.delay_idx(pp_r), M)+1;
            Y_dd_eq(kk_r, ll_r) = Y_dd_eq(kk_r, ll_r) - path_info.gain(pp_r) * pv_val;
        end

        % 诊断标记（最高SNR时保存eq_info）
        do_diag = (si == length(snr_list));
        if si == 1, diag_info = []; end

        % 保存（供可视化）
        if si == length(snr_list)
            ch_diag(fi).h_est = h_dd;
            ch_diag(fi).path_info = path_info;
        end

        %% ===== 5. Turbo迭代：UAMP/LMMSE + BCJR ===== %%
        prior_mean = [];
        prior_var = [];
        ber_trace = zeros(1, num_turbo);
        guard_indices = find(guard_mask);

        for turbo_iter = 1:num_turbo
            % 5a. 均衡器选择
            if strcmp(eq_type, 'uamp')
                % UAMP: Onsager修正允许多轮内部迭代, EM自适应噪声
                [x_hat, ~, x_mean, eq_info] = eq_otfs_uamp(Y_dd_eq, h_dd, path_info, N, M, ...
                    nv_dd, uamp_inner, constellation, prior_mean, prior_var);
            else
                % LMMSE: 单次线性滤波(max_iter=1)
                [x_hat, ~, x_mean, eq_info] = eq_otfs_lmmse(Y_dd_eq, h_dd, path_info, N, M, ...
                    nv_dd, 1, constellation, prior_mean, prior_var);
            end

            % 保存诊断信息（延迟到BER打印后输出，避免断行）
            if do_diag && turbo_iter == 1
                diag_info = eq_info;
            end

            % 5b. 提取数据符号 → LLR (用后验方差τ_r，比固定nv_dd更准确)
            x_data_soft = x_mean(data_indices);
            nv_llr = max(eq_info.nv_post, 1e-8);
            LLR_eq = zeros(1, M_coded);
            for k=1:N_data_slots
                LLR_eq(2*k-1) = -2*sqrt(2)*real(x_data_soft(k)) / nv_llr;
                LLR_eq(2*k)   = -2*sqrt(2)*imag(x_data_soft(k)) / nv_llr;
            end
            LLR_eq = max(min(LLR_eq, 30), -30);

            % 5c. 解交织 → SISO译码
            LLR_coded = random_deinterleave(LLR_eq, perm);
            [~, Lp_info, Lp_coded] = siso_decode_conv(LLR_coded, [], ...
                codec.gen_polys, codec.constraint_len, codec.decode_mode);
            bits_out = double(Lp_info > 0);
            nc = min(length(bits_out), N_info);
            ber_iter = mean(bits_out(1:nc) ~= info_bits(1:nc));
            ber_trace(turbo_iter) = ber_iter;

            % 5d. Turbo反馈：SISO后验 → 交织 → soft_mapper → DD域先验
            if turbo_iter < num_turbo
                Lp_coded_inter = random_interleave(Lp_coded, codec.interleave_seed);
                if length(Lp_coded_inter) < M_coded
                    Lp_coded_inter = [Lp_coded_inter, zeros(1, M_coded-length(Lp_coded_inter))];
                else
                    Lp_coded_inter = Lp_coded_inter(1:M_coded);
                end
                [x_bar, var_x] = soft_mapper(Lp_coded_inter, 'qpsk');
                var_x = max(var_x, nv_dd);

                % 构建完整NxM先验 (BCCB要求均匀v_x，guard用相同方差)
                prior_mean = zeros(N, M);
                prior_var = var_x * ones(N, M);
                n_fill = min(length(x_bar), N_data_slots);
                for i_d = 1:n_fill
                    prior_mean(data_indices(i_d)) = x_bar(i_d);
                end
            end
        end

        % uncoded BER
        x_data_hard = x_hat(data_indices);
        bits_hard = zeros(1, N_data_slots*2);
        for k=1:N_data_slots
            bits_hard(2*k-1) = real(x_data_hard(k)) < 0;
            bits_hard(2*k)   = imag(x_data_hard(k)) < 0;
        end
        ber_unc = mean(bits_hard(1:M_coded) ~= interleaved);

        ber = ber_trace(end);
        ber_matrix(fi,si) = ber;
        ber_unc_matrix(fi,si) = ber_unc;
        ber_turbo_trace{fi,si} = ber_trace;
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (p=%d)\n', path_info.num_paths);

    % 诊断
    if ~isempty(diag_info)
        fprintf('  nv_post=%.4f, v_x=%.4f\n', diag_info.nv_post, diag_info.v_x);
    end
end

%% ========== 可视化 ========== %%
try
    n_cfg = size(fading_cfgs,1);
    markers={'o-','s-','d-','^-','v-','p-'};
    colors = lines(n_cfg);

    % --- Figure 0: 通带帧波形+频谱 ---
    if passband_mode && exist('vis_frame_tx','var')
        figure('Position',[30 50 1400 750], 'Name','OTFS 通带帧波形与频谱');
        t_frame = (0:length(vis_frame_tx)-1) / fs_pb * 1000;  % ms
        t_bb = (0:length(vis_tx_bb)-1) / sym_rate * 1000;
        dur_ms = t_frame(end);
        vfi = vis_frame_info;

        % (1,1) TX通带帧波形 (完整, 标注结构)
        subplot(3,2,1);
        plot(t_frame, vis_frame_tx, 'b', 'LineWidth', 0.3);
        xlabel('时间 (ms)'); ylabel('幅度'); grid on;
        title(sprintf('TX 通带帧 (%.1fms, fc=%dkHz)', dur_ms, fc/1000));
        hold on;
        % 标注帧结构
        lfm_end = vfi.lfm_len / fs_pb * 1000;
        data_start = vfi.data_offset / fs_pb * 1000;
        data_end = (vfi.data_offset + vfi.data_len) / fs_pb * 1000;
        yl = ylim;
        patch([0 lfm_end lfm_end 0], [yl(1) yl(1) yl(2) yl(2)], 'g', 'FaceAlpha',0.1,'EdgeColor','none');
        patch([data_start data_end data_end data_start], [yl(1) yl(1) yl(2) yl(2)], 'b', 'FaceAlpha',0.08,'EdgeColor','none');
        text(lfm_end/2, yl(2)*0.9, 'LFM', 'HorizontalAlignment','center','FontSize',8);
        text((data_start+data_end)/2, yl(2)*0.9, 'OTFS data', 'HorizontalAlignment','center','FontSize',8);

        % (1,2) RX通带帧波形 (完整)
        subplot(3,2,2);
        if exist('vis_frame_rx','var')
            plot(t_frame, vis_frame_rx, 'Color',[0.85 0.33 0.1], 'LineWidth', 0.3);
            title(sprintf('RX 通带帧 @%ddB', snr_list(end)));
        else
            title('RX (无数据)');
        end
        xlabel('时间 (ms)'); ylabel('幅度'); grid on;

        % (2,1) TX基带I/Q (OTFS数据, WOLA窗后)
        subplot(3,2,3);
        plot(t_bb, real(vis_tx_bb), 'b', 'LineWidth', 0.5); hold on;
        plot(t_bb, imag(vis_tx_bb), 'r', 'LineWidth', 0.5);
        xlabel('时间 (ms)'); ylabel('幅度'); grid on;
        title('TX 基带 I/Q (WOLA窗后)'); legend('I','Q','FontSize',7);

        % (2,2) TX/RX通带包络对比
        subplot(3,2,4);
        env_tx = abs(hilbert(vis_frame_tx));
        plot(t_frame, env_tx, 'b', 'LineWidth', 0.6);
        if exist('vis_frame_rx','var')
            hold on;
            env_rx = abs(hilbert(vis_frame_rx));
            plot(t_frame, env_rx, 'Color',[0.85 0.33 0.1], 'LineWidth', 0.3);
            legend('TX','RX','FontSize',7);
        end
        xlabel('时间 (ms)'); ylabel('包络'); grid on;
        title('帧包络对比');

        % (3,1) TX通带频谱
        subplot(3,2,5);
        N_fft = length(vis_frame_tx);
        f_pb = (0:N_fft-1) * fs_pb / N_fft;
        S_tx = 20*log10(abs(fft(vis_frame_tx)) / N_fft + 1e-12);
        plot(f_pb/1000, S_tx, 'b', 'LineWidth', 0.8);
        xlabel('频率 (kHz)'); ylabel('dB'); grid on;
        title('TX 通带频谱'); xlim([0, fs_pb/2000]);
        hold on;
        xline((fc-sym_rate/2)/1000, 'g--', 'LineWidth',1);
        xline((fc+sym_rate/2)/1000, 'g--', 'LineWidth',1);

        % (3,2) RX通带频谱
        subplot(3,2,6);
        if exist('vis_frame_rx','var')
            S_rx = 20*log10(abs(fft(vis_frame_rx)) / N_fft + 1e-12);
            plot(f_pb/1000, S_rx, 'Color',[0.85 0.33 0.1], 'LineWidth', 0.8); hold on;
            plot(f_pb/1000, S_tx, 'b--', 'LineWidth', 0.4);
            legend('RX','TX','FontSize',7);
            title(sprintf('RX 通带频谱 @%ddB', snr_list(end)));
        else
            title('RX 频谱 (无数据)');
        end
        xlabel('频率 (kHz)'); ylabel('dB'); grid on;
        xlim([0, fs_pb/2000]);

        sgtitle(sprintf('OTFS 通带仿真 — N=%dx%d, %.0f bps, fc=%dkHz, BW=%dkHz', ...
            N, M, info_rate_bps, fc/1000, sym_rate/1000), 'FontSize',13);
    end

    % --- Figure 1: BER曲线 ---
    figure('Position',[50 550 700 400]);
    for fi=1:size(fading_cfgs,1)
        semilogy(snr_list, max(ber_matrix(fi,:),1e-5), markers{fi}, ...
            'Color',colors(fi,:),'LineWidth',1.8,'MarkerSize',7,'DisplayName',fading_cfgs{fi,1});
        hold on;
    end
    snr_lin=10.^(snr_list/10);
    semilogy(snr_list,max(0.5*erfc(sqrt(snr_lin)),1e-5),'k--','LineWidth',1,'DisplayName','QPSK AWGN');
    grid on; xlabel('SNR (dB)'); ylabel('BER');
    title(sprintf('OTFS %dx%d %s Turbo(%d) — %.0f bps', N, M, upper(eq_type), num_turbo, info_rate_bps));
    legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);

    % --- Figure 2: DD域信道 真实vs估计 (前3配置 × 3列) ---
    n_vis = min(n_cfg, 3);  % 最多显示3行
    figure('Position',[50 50 1400 250*n_vis], 'Name','DD域信道: 真实 vs 估计');
    pk_pos = pilot_info.positions(1,1);
    pl_pos = pilot_info.positions(1,2);
    dk_range = -pilot_config.guard_k:pilot_config.guard_k;
    dl_range = -2:pilot_config.guard_l+3;
    cmax = max(abs(gains_raw)) * 1.1;

    for fi = 1:n_vis
        h_true = ch_diag(fi).h_true;
        h_est  = ch_diag(fi).h_est;
        pi_fi  = ch_diag(fi).path_info;
        crop_true = zeros(length(dk_range), length(dl_range));
        crop_est  = zeros(length(dk_range), length(dl_range));
        for i=1:length(dk_range)
            for j=1:length(dl_range)
                kk = mod(pk_pos-1+dk_range(i), N)+1;
                ll = mod(pl_pos-1+dl_range(j), M)+1;
                crop_true(i,j) = abs(h_true(kk, ll));
                crop_est(i,j)  = abs(h_est(kk, ll));
            end
        end
        subplot(n_vis,3,(fi-1)*3+1);
        imagesc(dl_range, dk_range, crop_true); axis xy; colorbar; caxis([0 cmax]);
        ylabel('dk'); text(-1.5, dk_range(end)-0.5, fading_cfgs{fi,1}, 'FontSize',11, 'FontWeight','bold');
        if fi==1, title('真实DD信道'); end
        subplot(n_vis,3,(fi-1)*3+2);
        imagesc(dl_range, dk_range, crop_est); axis xy; colorbar; caxis([0 cmax]);
        if fi==1, title('估计DD信道'); end
        subplot(n_vis,3,(fi-1)*3+3);
        dl_prof = 0:max(delay_bins)+4;
        prof_true = zeros(size(dl_prof)); prof_est = zeros(size(dl_prof));
        for j=1:length(dl_prof)
            ll = mod(pl_pos-1+dl_prof(j), M)+1;
            prof_true(j) = abs(h_true(pk_pos, ll));
            prof_est(j)  = abs(h_est(pk_pos, ll));
        end
        stem(dl_prof, prof_true, 'b-', 'LineWidth',1.5, 'MarkerSize',4); hold on;
        stem(dl_prof, prof_est, 'r:', 'LineWidth',1.5, 'MarkerSize',4);
        if fi==1, title('dk=0 延迟剖面'); legend('真实','估计','FontSize',7); end
        grid on;
    end
    sgtitle(sprintf('OTFS DD域信道诊断 (N=%d, M=%d)', N, M), 'FontSize',14);

    % --- Figure 3: Turbo收敛 ---
    figure('Position',[770 550 500 350]);
    for fi=1:size(fading_cfgs,1)
        for si=[2,3]
            trace = ber_turbo_trace{fi,si};
            if any(trace > 0)
                semilogy(1:num_turbo, max(trace,1e-5), [markers{fi}(1) '-'], ...
                    'Color',colors(fi,:),'LineWidth',1.2,'MarkerSize',6, ...
                    'DisplayName',sprintf('%s@%ddB',fading_cfgs{fi,1},snr_list(si)));
                hold on;
            end
        end
    end
    grid on; xlabel('Turbo迭代'); ylabel('BER');
    title('Turbo迭代收敛'); legend('Location','northeast'); set(gca,'FontSize',12);
catch ME
    fprintf('可视化异常: %s\n', ME.message);
end

fprintf('\n完成\n');

%% ========== 保存结果 ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_otfs_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'OTFS 时变信道测试结果 V4.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
if passband_mode
    fprintf(fid, '模式: 通带 (sps=%d, fs_pb=%dHz, fc=%dHz)\n', sps, fs_pb, fc);
else
    fprintf(fid, '模式: 基带 (fs=%dHz)\n', sym_rate);
end
fprintf(fid, 'OTFS: N=%d, M=%d, CP=%d, 均衡=%s, Turbo=%d\n', N, M, cp_len, upper(eq_type), num_turbo);
fprintf(fid, '速率: %.0f bps (QPSK, R=1/%d, %d data slots)\n', info_rate_bps, n_code, N_data_slots);
fprintf(fid, '信道: %d径, delay_bins=[%s]\n', length(delay_bins), num2str(delay_bins));
fprintf(fid, 'Loopback误差: %.2e\n\n', err_loopback);

fprintf(fid, '=== BER (coded, Turbo %d轮) ===\n', num_turbo);
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-9s|', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

fprintf(fid, '\n=== Turbo收敛轨迹 (每轮BER) ===\n');
for fi=1:size(fading_cfgs,1)
    for si=1:length(snr_list)
        trace = ber_turbo_trace{fi,si};
        fprintf(fid, '%s@%ddB:', fading_cfgs{fi,1}, snr_list(si));
        for t=1:num_turbo, fprintf(fid, ' %.2f%%', trace(t)*100); end
        fprintf(fid, '\n');
    end
end

fprintf(fid, '\n=== BER (uncoded) ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-9s|', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_unc_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('结果已保存: %s\n', result_file);

%% ========== 辅助函数：逐子块上变频(消除Gibbs振铃) ========== %%
function [pb_signal, bb_up] = otfs_to_passband(bb_signal, N, M, cp_len, sps, fs_pb, fc)
% 逐子块FFT上采样 + 升余弦过渡 + 上变频
% 关键: 每子块独立interpft, 避免跨子块Gibbs振铃
    sub_size = M + cp_len;
    sub_up = sub_size * sps;
    win_samp = 4 * sps;  % 过渡区样本数(通带率)
    taper_up = 0.5*(1 - cos(pi*(0:win_samp-1)/win_samp));
    taper_dn = 0.5*(1 + cos(pi*(0:win_samp-1)/win_samp));

    bb_up = zeros(1, N * sub_up);
    for n = 1:N
        offset_bb = (n-1) * sub_size;
        sub = bb_signal(offset_bb+1 : offset_bb+sub_size);
        sub_interp = interpft(sub, sub_up);  % 逐子块FFT插值

        % 升余弦过渡: CP首部上升, 数据尾部下降
        if n > 1
            sub_interp(1:win_samp) = sub_interp(1:win_samp) .* taper_up;
        end
        if n < N
            sub_interp(end-win_samp+1:end) = sub_interp(end-win_samp+1:end) .* taper_dn;
        end

        offset_up = (n-1) * sub_up;
        bb_up(offset_up+1 : offset_up+sub_up) = sub_interp;
    end

    % 上变频
    [pb_signal, ~] = upconvert(bb_up, fs_pb, fc);
end

%% ========== 辅助函数：逐子块下变频(匹配上变频) ========== %%
function bb_signal = passband_to_otfs(pb_segment, N, M, cp_len, sps, fs_pb, fc)
% 下变频 + 逐子块FFT降采样
    [bb_raw, ~] = downconvert(pb_segment, fs_pb, fc, fs_pb/(2*sps)*0.9);
    sub_size = M + cp_len;
    sub_up = sub_size * sps;
    bb_signal = zeros(1, N * sub_size);

    for n = 1:N
        offset_up = (n-1) * sub_up;
        if offset_up + sub_up <= length(bb_raw)
            sub_raw = bb_raw(offset_up+1 : offset_up+sub_up);
        else
            sub_raw = [bb_raw(offset_up+1:end), zeros(1, sub_up-(length(bb_raw)-offset_up))];
        end
        sub_down = interpft(sub_raw, sub_size);  % 逐子块FFT降采样
        bb_signal((n-1)*sub_size+1 : n*sub_size) = sub_down;
    end
end

%% ========== 辅助函数：信道施加 ========== %%
function rx = apply_channel(tx, delay_bins, gains_raw, ftype, fparams, fs, fc)
% 支持三种信道类型: static, discrete(固定Doppler), jakes(连续Doppler谱)
    tx = tx(:).';
    rx = zeros(size(tx));
    N_tx = length(tx);

    switch ftype
        case 'static'
            % 静态多径: h_p * x(n-d_p)
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                rx(d+1:end) = rx(d+1:end) + gains_raw(p) * tx(1:end-d);
            end

        case 'discrete'
            % 离散Doppler: h_p * exp(j2πν_p*n/fs) * x(n-d_p)
            % fparams = [ν_1, ν_2, ..., ν_P] (Hz)
            doppler_hz = fparams;
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                n_range = (d+1):N_tx;
                phase = exp(1j * 2 * pi * doppler_hz(p) * (n_range-1) / fs);
                rx(n_range) = rx(n_range) + gains_raw(p) * phase .* tx(n_range-d);
            end

        case 'hybrid'
            % Rician混合: 离散Doppler(强) + Jakes散射(弱)
            % h_p(t) = h_p * exp(j2πν_p*t) * [√(K/(K+1)) + √(1/(K+1))*g(t)]
            % g(t) = Jakes过程(fd_scatter), 散射Doppler谱以ν_p为中心
            doppler_hz = fparams.doppler_hz;
            fd_sc = fparams.fd_scatter;
            K = fparams.K_rice;
            spec_amp = sqrt(K / (K+1));      % 直达(谱)分量幅度
            scat_amp = sqrt(1 / (K+1));       % 散射分量幅度
            t = (0:N_tx-1) / fs;
            N_osc = 8;
            rng_state = rng;  % 保存
            rng(43);          % 固定seed保证可复现
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                n_range = (d+1):N_tx;
                t_r = t(n_range);
                % 离散Doppler相位
                phase_disc = exp(1j * 2*pi * doppler_hz(p) * t_r);
                % Jakes散射 (单位功率, 以ν_p为中心)
                g_scat = zeros(1, length(n_range));
                for n_osc = 1:N_osc
                    theta = 2*pi*rand;
                    beta = pi*n_osc / N_osc;
                    g_scat = g_scat + exp(1j*(2*pi*fd_sc*cos(beta)*t_r + theta));
                end
                g_scat = g_scat / sqrt(N_osc);
                % Rician组合: 稳定谱 + 弱散射, 再乘离散Doppler
                h_tv = gains_raw(p) * phase_disc .* (spec_amp + scat_amp * g_scat);
                rx(n_range) = rx(n_range) + h_tv .* tx(n_range-d);
            end
            rng(rng_state);  % 恢复

        case 'jakes'
            % Jakes衰落: fparams = fd_hz (最大多普勒频移)
            fd_hz = fparams;
            delays_s = delay_bins / fs;
            ch_params = struct('fs',fs, 'delay_profile','custom', ...
                'delays_s',delays_s, 'gains',gains_raw, ...
                'num_paths',length(delay_bins), 'doppler_rate',fd_hz/fc, ...
                'fading_type','slow', 'fading_fd_hz',fd_hz, ...
                'snr_db',Inf, 'seed',42);
            [rx,~] = gen_uwa_channel(tx, ch_params);

        otherwise
            error('不支持的信道类型: %s', ftype);
    end
end
