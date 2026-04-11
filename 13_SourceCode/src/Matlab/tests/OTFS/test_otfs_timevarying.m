%% test_otfs_timevarying.m — OTFS基带仿真 时变信道测试
% TX: 编码→交织→QPSK→DD域导频嵌入→OTFS调制(V2.0 真DD域)
% 信道: gen_uwa_channel(5径+Jakes, 基带sym_rate)→+噪声
% RX: OTFS解调→DD域信道估计(V1.1自适应阈值)→Turbo(MP+BCJR)均衡→译码
% 版本：V2.1.0 — DD域修正 + Turbo迭代 + 自适应阈值 + delay_guard消除β因子
% 特点：DD域天然分离时延和多普勒

clc; close all;
use_oracle = false;  % true=用真实信道(测均衡器上限), false=用估计信道
fprintf('========================================\n');
fprintf('  OTFS 基带仿真 — 时变信道测试 V2.1\n');
if use_oracle
    fprintf('  [Oracle模式] 真实信道 — 测均衡器性能上限\n');
else
    fprintf('  [估计模式] ch_est_otfs_dd V2.0\n');
end
fprintf('  (DD域修正 + delay_guard + Turbo)\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
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
mp_iters = 20;   % MP迭代次数
num_turbo = 3;   % 外层Turbo迭代次数

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
fading_cfgs = {
    'static', 'static', 0,  0;
    'fd=1Hz', 'slow',   1,  1/fc;
    'fd=5Hz', 'slow',   5,  5/fc;
};

fprintf('OTFS: N=%d x M=%d, CP=%d, df=%.1fHz, fs=%dHz\n', N, M, cp_len, subcarrier_spacing, sym_rate);
fprintf('Turbo: %d轮 (内层MP=%d iter)\n', num_turbo, mp_iters);
fprintf('速率: %.0f bps (QPSK, R=1/%d, %d data slots)\n', info_rate_bps, n_code, N_data_slots);
fprintf('帧长: %d样本 (%.1fms)\n', N*M+cp_len, frame_duration*1000);
fprintf('信道: %d径, delay_bins=[%s], max=%d < CP=%d\n', ...
    length(delay_bins), num2str(delay_bins), max(delay_bins), cp_len);
fprintf('多普勒分辨率: %.2f Hz\n\n', subcarrier_spacing/N);

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

fprintf('%-8s |', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname=fading_cfgs{fi,1}; ftype=fading_cfgs{fi,2};
    fd_hz=fading_cfgs{fi,3}; dop_rate=fading_cfgs{fi,4};

    %% ===== TX ===== %%
    rng(100+fi);
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_coded);
    [interleaved,~] = random_interleave(coded, codec.interleave_seed);
    data_sym = constellation(bi2de(reshape(interleaved,2,[]).','left-msb')+1);

    [dd_frame, pilot_info, guard_mask, ~] = otfs_pilot_embed(data_sym, N, M, pilot_config);
    [otfs_signal, ~] = otfs_modulate(dd_frame, N, M, cp_len, 'dft');

    %% ===== 信道 ===== %%
    if strcmpi(ftype, 'static')
        rx_clean = zeros(size(otfs_signal));
        for p = 1:length(delay_bins)
            d = delay_bins(p);
            rx_clean(d+1:end) = rx_clean(d+1:end) + gains_raw(p) * otfs_signal(1:end-d);
        end
    else
        ch_params = struct('fs',sym_rate, 'delay_profile','custom', ...
            'delays_s',delays_s, 'gains',gains_raw, ...
            'num_paths',length(delay_bins), 'doppler_rate',dop_rate, ...
            'fading_type',ftype, 'fading_fd_hz',fd_hz, ...
            'snr_db',Inf, 'seed',200+fi*100);
        [rx_clean,~] = gen_uwa_channel(otfs_signal, ch_params);
    end
    sig_pwr = mean(abs(rx_clean).^2);

    % === Pilot-only信道探测：获取真实DD域信道响应 ===
    dd_pilot_only = zeros(N, M);
    dd_pilot_only(pilot_info.positions(1,1), pilot_info.positions(1,2)) = pilot_info.values(1);
    [sig_po, ~] = otfs_modulate(dd_pilot_only, N, M, cp_len, 'dft');
    if strcmpi(ftype, 'static')
        rx_po = zeros(size(sig_po));
        for p = 1:length(delay_bins)
            d = delay_bins(p);
            rx_po(d+1:end) = rx_po(d+1:end) + gains_raw(p) * sig_po(1:end-d);
        end
    else
        ch_po = struct('fs',sym_rate, 'delay_profile','custom', ...
            'delays_s',delays_s, 'gains',gains_raw, ...
            'num_paths',length(delay_bins), 'doppler_rate',dop_rate, ...
            'fading_type',ftype, 'fading_fd_hz',fd_hz, ...
            'snr_db',Inf, 'seed',200+fi*100);  % 同seed=同信道
        [rx_po, ~] = gen_uwa_channel(sig_po, ch_po);
    end
    [Y_dd_po, ~] = otfs_demodulate(rx_po, N, M, cp_len, 'dft');
    ch_diag(fi).h_true = Y_dd_po / pilot_info.values(1);  % 归一化=真实DD信道

    fprintf('%-8s |', fname);

    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300+fi*1000+si*100);
        rx_noisy = rx_clean + sqrt(noise_var/2)*(randn(size(rx_clean)) + 1j*randn(size(rx_clean)));

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

        % 诊断（每配置最高SNR）
        if si == length(snr_list)
            if use_oracle, ch_mode='Oracle'; else, ch_mode='Est'; end
            fprintf('\n--- DD域诊断 %s@%ddB [%s] ---\n', fname, snr_db, ch_mode);
            fprintf('paths=%d, nv=%.2e\n', path_info.num_paths, nv_dd);
            fprintf('delays=[%s]\n', num2str(path_info.delay_idx));
            fprintf('dopplers=[%s]\n', num2str(path_info.doppler_idx));
            fprintf('|gains|=[%s]\n', num2str(abs(path_info.gain), '%.3f '));
        end

        % 保存（供可视化）
        if si == length(snr_list)
            ch_diag(fi).h_est = h_dd;
            ch_diag(fi).path_info = path_info;
        end

        %% ===== 5. Turbo迭代：LMMSE-IC + BCJR ===== %%
        prior_mean = [];
        prior_var = [];
        ber_trace = zeros(1, num_turbo);
        guard_indices = find(guard_mask);

        for turbo_iter = 1:num_turbo
            % 5a. LMMSE-IC均衡（BCCB 2D-FFT对角化，含先验）
            % LMMSE单次线性滤波(max_iter=1)，迭代由外层Turbo控制
            [x_hat, ~, x_mean, eq_info] = eq_otfs_lmmse(Y_dd_eq, h_dd, path_info, N, M, ...
                nv_dd, 1, constellation, prior_mean, prior_var);

            % 5b. 提取数据符号 → LLR (用LMMSE后验方差，比固定nv_dd更准确)
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

                % 构建完整NxM先验 (BCCB LMMSE要求均匀v_x，guard用相同方差)
                prior_mean = zeros(N, M);
                prior_var = var_x * ones(N, M);  % 均匀方差（BCCB兼容）
                % 数据位置：SISO反馈
                n_fill = min(length(x_bar), N_data_slots);
                for i_d = 1:n_fill
                    prior_mean(data_indices(i_d)) = x_bar(i_d);
                end
                % guard位置: prior_mean=0(已知零), prior_var=var_x(保持均匀)
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
    fprintf('  (paths=%d)\n', path_info.num_paths);
end

%% ========== 可视化 ========== %%
try
    markers={'o-','s-','d-'}; colors=[0 .45 .74; .85 .33 .1; .47 .67 .19];

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
    title(sprintf('OTFS %dx%d Turbo(%d) MP(%d) — %.0f bps', N, M, num_turbo, mp_iters, info_rate_bps));
    legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);

    % --- Figure 2: DD域信道 真实vs估计 (3配置 × 3列) ---
    figure('Position',[50 50 1400 750], 'Name','DD域信道: 真实 vs 估计');
    pk_pos = pilot_info.positions(1,1);
    pl_pos = pilot_info.positions(1,2);
    dk_range = -pilot_config.guard_k:pilot_config.guard_k;
    dl_range = -2:pilot_config.guard_l+3;
    cmax = max(abs(gains_raw)) * 1.1;

    for fi = 1:size(fading_cfgs,1)
        h_true = ch_diag(fi).h_true;
        h_est  = ch_diag(fi).h_est;
        pi_fi  = ch_diag(fi).path_info;

        % 裁剪保护区附近区域
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

        % 列1: 真实DD信道
        subplot(3,3,(fi-1)*3+1);
        imagesc(dl_range, dk_range, crop_true);
        axis xy; colorbar; caxis([0 cmax]);
        hold on;
        for p=1:length(delay_bins)
            plot(delay_bins(p), 0, 'rx', 'MarkerSize',12, 'LineWidth',2);
        end
        ylabel('dk (多普勒)');
        if fi==1, title('真实DD信道 (pilot-only)'); end
        text(-1.5, dk_range(end)-0.5, fading_cfgs{fi,1}, 'FontSize',12, 'FontWeight','bold');

        % 列2: 估计DD信道
        subplot(3,3,(fi-1)*3+2);
        imagesc(dl_range, dk_range, crop_est);
        axis xy; colorbar; caxis([0 cmax]);
        hold on;
        for p=1:pi_fi.num_paths
            plot(pi_fi.delay_idx(p), pi_fi.doppler_idx(p), 'g+', 'MarkerSize',10, 'LineWidth',2);
        end
        if fi==1, title(sprintf('估计DD信道 (ch\\_est, SNR=%ddB)', snr_list(end))); end

        % 列3: dk=0延迟剖面对比
        subplot(3,3,(fi-1)*3+3);
        dl_prof = 0:max(delay_bins)+4;
        prof_true = zeros(size(dl_prof));
        prof_est  = zeros(size(dl_prof));
        prof_ideal = zeros(size(dl_prof));
        for j=1:length(dl_prof)
            ll = mod(pl_pos-1+dl_prof(j), M)+1;
            prof_true(j) = abs(h_true(pk_pos, ll));
            prof_est(j)  = abs(h_est(pk_pos, ll));
        end
        for p=1:length(delay_bins)
            idx = find(dl_prof == delay_bins(p));
            if ~isempty(idx), prof_ideal(idx) = abs(gains_raw(p)); end
        end
        stem(dl_prof, prof_ideal, 'k--', 'LineWidth',1.2, 'MarkerSize',5, 'DisplayName','理想');
        hold on;
        stem(dl_prof, prof_true, 'b-', 'LineWidth',1.5, 'MarkerSize',4, 'DisplayName','真实');
        stem(dl_prof, prof_est, 'r:', 'LineWidth',1.5, 'MarkerSize',4, 'DisplayName','估计');
        xlabel('dl (时延bin)'); ylabel('|h|');
        if fi==1, title('dk=0 延迟剖面'); end
        legend('Location','northeast','FontSize',7); grid on;
        if fi==size(fading_cfgs,1), xlabel('dl (时延bin)'); end
    end
    sgtitle(sprintf('OTFS DD域信道诊断 (N=%d, M=%d, %d径)', N, M, length(delay_bins)), 'FontSize',14);

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
fprintf(fid, 'OTFS 时变信道测试结果 V2.1 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'OTFS: N=%d, M=%d, CP=%d, Turbo=%d, MP iter=%d (基带仿真)\n', N, M, cp_len, num_turbo, mp_iters);
fprintf(fid, '速率: %.0f bps (QPSK, R=1/%d, %d data slots)\n', info_rate_bps, n_code, N_data_slots);
fprintf(fid, '信道: %d径, delay_bins=[%s]\n', length(delay_bins), num2str(delay_bins));
fprintf(fid, 'Loopback误差: %.2e\n\n', err_loopback);

fprintf(fid, '=== BER (coded, Turbo %d轮) ===\n', num_turbo);
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
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
    fprintf(fid, '%-8s |', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_unc_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('结果已保存: %s\n', result_file);
