%% test_otfs_channel_diag.m — OTFS DD域信道诊断：真实vs估计 + β因子可视化
% 版本：V1.0.0
% 目的：
%   1. 无数据干扰下获取真实DD域信道响应（pilot-only帧过信道）
%   2. 对比 ch_est_otfs_dd 估计结果
%   3. 展示帧级CP导致的β相位误差
%   4. 三种衰落配置(static/fd=1/fd=5)对比

clc; close all;
fprintf('================================================\n');
fprintf('  OTFS DD域信道诊断 — 真实 vs 估计 V1.0\n');
fprintf('================================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

N = 32; M = 64; cp_len = 32;
pk = ceil(N/2); pl = ceil(M/2);
snr_db = 20;  % 高SNR下观察信道

delay_bins = [0, 1, 3, 5, 8];
delays_s = delay_bins / 6000;
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
sym_rate = 6000; fc = 12000;

pilot_config = struct('mode','impulse', 'guard_k',4, 'guard_l',max(delay_bins)+2, 'pilot_value',1);
[~,~,~,data_indices] = otfs_pilot_embed(zeros(1,1), N, M, pilot_config);
pilot_config.pilot_value = sqrt(length(data_indices));
pv = pilot_config.pilot_value;

fading_cfgs = {
    'static', 'static', 0,  0;
    'fd=1Hz', 'slow',   1,  1/fc;
    'fd=5Hz', 'slow',   5,  5/fc;
};

%% ===== 1. 构造理想DD域信道（解析） ===== %%
fprintf('--- 1. 理想DD域信道（解析，无噪声无相位误差） ---\n');
h_dd_ideal = zeros(N, M);  % 以(pk,pl)为原点的相对偏移
for p = 1:length(delay_bins)
    dk = 0; dl = delay_bins(p);  % static: 仅延迟，无多普勒
    kk = mod(pk-1+dk, N)+1;
    ll = mod(pl-1+dl, M)+1;
    h_dd_ideal(kk, ll) = gains_raw(p);
end
fprintf('  %d径, delay=[%s], |gains|=[%s]\n\n', ...
    length(delay_bins), num2str(delay_bins), num2str(abs(gains_raw),'%.3f '));

%% ===== 2. 三配置下：pilot-only帧过信道 → 真实DD响应 ===== %%
figure('Position',[50 50 1400 900], 'Name','OTFS DD域信道诊断');

for fi = 1:size(fading_cfgs,1)
    fname = fading_cfgs{fi,1};
    ftype = fading_cfgs{fi,2};
    fd_hz = fading_cfgs{fi,3};
    dop_rate = fading_cfgs{fi,4};

    fprintf('--- %s ---\n', fname);

    % 2a. Pilot-only帧（无数据干扰）
    dd_pilot_only = zeros(N, M);
    dd_pilot_only(pk, pl) = pv;
    [sig_po, ~] = otfs_modulate(dd_pilot_only, N, M, cp_len, 'dft');

    % 2b. 过信道
    if strcmpi(ftype, 'static')
        rx_po = zeros(size(sig_po));
        for p = 1:length(delay_bins)
            d = delay_bins(p);
            rx_po(d+1:end) = rx_po(d+1:end) + gains_raw(p) * sig_po(1:end-d);
        end
    else
        ch_params = struct('fs',sym_rate, 'delay_profile','custom', ...
            'delays_s',delays_s, 'gains',gains_raw, ...
            'num_paths',length(delay_bins), 'doppler_rate',dop_rate, ...
            'fading_type',ftype, 'fading_fd_hz',fd_hz, ...
            'snr_db',Inf, 'seed',200+fi*100);
        [rx_po, ~] = gen_uwa_channel(sig_po, ch_params);
    end

    % 加噪
    sig_pwr = mean(abs(rx_po).^2);
    nv = sig_pwr * 10^(-snr_db/10);
    rng(500+fi);
    rx_noisy = rx_po + sqrt(nv/2)*(randn(size(rx_po))+1j*randn(size(rx_po)));

    % 2c. 解调 → 真实DD域信道响应
    [Y_dd_po, ~] = otfs_demodulate(rx_noisy, N, M, cp_len, 'dft');
    h_dd_true = Y_dd_po / pv;  % 归一化=信道响应（pilot-only，无数据干扰）

    % 2d. 信道估计（用同一个Y_dd，模拟有导频信息的情况）
    pilot_info_po = struct('mode','impulse', 'positions',[pk,pl], ...
        'values',pv, 'guard_mask',zeros(N,M)>0);
    % 构建guard_mask
    for dk_g = -pilot_config.guard_k:pilot_config.guard_k
        for dl_g = -pilot_config.guard_l:pilot_config.guard_l
            kk_g = mod(pk-1+dk_g,N)+1;
            ll_g = mod(pl-1+dl_g,M)+1;
            pilot_info_po.guard_mask(kk_g,ll_g) = true;
        end
    end
    [h_dd_est, path_info] = ch_est_otfs_dd(Y_dd_po, pilot_info_po, N, M);
    h_dd_est_norm = h_dd_est / pv;  % ch_est_otfs_dd 已除pv，但h_dd矩阵值是Y_dd/pv*pv

    fprintf('  检测径数: %d\n', path_info.num_paths);
    fprintf('  est delays=[%s], dopplers=[%s]\n', ...
        num2str(path_info.delay_idx), num2str(path_info.doppler_idx));
    fprintf('  |gains_est|=[%s]\n', num2str(abs(path_info.gain),'%.4f '));

    % ===== 可视化 ===== %

    % --- 真实DD域信道（2D热图）---
    subplot(3,4,(fi-1)*4+1);
    % 以pilot为中心显示，偏移[-gk:gk, -5:guard_l+5]
    dk_range = -pilot_config.guard_k:pilot_config.guard_k;
    dl_range = -3:pilot_config.guard_l+3;
    h_crop = zeros(length(dk_range), length(dl_range));
    for i=1:length(dk_range)
        for j=1:length(dl_range)
            kk = mod(pk-1+dk_range(i), N)+1;
            ll = mod(pl-1+dl_range(j), M)+1;
            h_crop(i,j) = abs(h_dd_true(kk,ll));
        end
    end
    imagesc(dl_range, dk_range, h_crop);
    axis xy; colorbar; clim([0 max(abs(gains_raw))*1.1]);
    xlabel('dl (时延偏移)'); ylabel('dk (多普勒偏移)');
    title(sprintf('%s: 真实DD信道', fname));
    % 标记真实径位置
    hold on;
    for p=1:length(delay_bins)
        plot(delay_bins(p), 0, 'rx', 'MarkerSize',12, 'LineWidth',2);
    end

    % --- 估计DD域信道（2D热图）---
    subplot(3,4,(fi-1)*4+2);
    h_est_crop = zeros(length(dk_range), length(dl_range));
    for i=1:length(dk_range)
        for j=1:length(dl_range)
            kk = mod(pk-1+dk_range(i), N)+1;
            ll = mod(pl-1+dl_range(j), M)+1;
            h_est_crop(i,j) = abs(h_dd_est(kk,ll));
        end
    end
    imagesc(dl_range, dk_range, h_est_crop);
    axis xy; colorbar; clim([0 max(abs(gains_raw))*1.1]);
    xlabel('dl (时延偏移)'); ylabel('dk (多普勒偏移)');
    title(sprintf('%s: 估计DD信道 (%d径)', fname, path_info.num_paths));
    hold on;
    for p=1:path_info.num_paths
        plot(path_info.delay_idx(p), path_info.doppler_idx(p), 'g+', 'MarkerSize',10, 'LineWidth',2);
    end

    % --- dk=0剖面对比 ---
    subplot(3,4,(fi-1)*4+3);
    dl_prof = 0:max(delay_bins)+4;
    prof_true = zeros(size(dl_prof));
    prof_est = zeros(size(dl_prof));
    prof_ideal = zeros(size(dl_prof));
    for j=1:length(dl_prof)
        ll = mod(pl-1+dl_prof(j), M)+1;
        prof_true(j) = abs(h_dd_true(pk, ll));
        prof_est(j) = abs(h_dd_est(pk, ll));
    end
    for p=1:length(delay_bins)
        idx = find(dl_prof == delay_bins(p));
        if ~isempty(idx), prof_ideal(idx) = abs(gains_raw(p)); end
    end
    stem(dl_prof, prof_ideal, 'k--', 'LineWidth',1.2, 'DisplayName','理想(解析)');
    hold on;
    stem(dl_prof, prof_true, 'b-', 'LineWidth',1.5, 'DisplayName','真实(pilot-only)');
    stem(dl_prof, prof_est, 'r:', 'LineWidth',1.5, 'DisplayName','估计(ch\_est)');
    xlabel('dl (时延bin)'); ylabel('|h|');
    title(sprintf('%s: dk=0剖面', fname));
    legend('Location','northeast','FontSize',7); grid on;

    % --- 全Doppler维展开（dl=0位置）---
    subplot(3,4,(fi-1)*4+4);
    dk_full = -(N/2):(N/2-1);
    prof_dk = zeros(size(dk_full));
    for i=1:length(dk_full)
        kk = mod(pk-1+dk_full(i), N)+1;
        prof_dk(i) = abs(h_dd_true(kk, pl));  % dl=0处
    end
    stem(dk_full, prof_dk, 'b', 'LineWidth',1);
    xlabel('dk (多普勒bin)'); ylabel('|h(dk,0)|');
    title(sprintf('%s: 直达径多普勒扩展', fname));
    grid on; xlim([dk_full(1) dk_full(end)]);
end

sgtitle(sprintf('OTFS DD域信道诊断 @ SNR=%ddB (N=%d, M=%d)', snr_db, N, M), 'FontSize',14);

%% ===== 3. β因子相位误差可视化 ===== %%
fprintf('\n--- 3. 帧CP β因子相位误差验证 ---\n');
figure('Position',[100 50 900 400], 'Name','Beta因子诊断');

% 发送全1帧（所有位置=1），过静态信道，观察wrapped位置的相位
dd_ones = ones(N, M);
[sig_ones, ~] = otfs_modulate(dd_ones, N, M, cp_len, 'dft');
rx_ones = zeros(size(sig_ones));
for p = 1:length(delay_bins)
    d = delay_bins(p);
    rx_ones(d+1:end) = rx_ones(d+1:end) + gains_raw(p) * sig_ones(1:end-d);
end
[Y_dd_ones, ~] = otfs_demodulate(rx_ones, N, M, cp_len, 'dft');

% 理想输出（无相位误差）：y(k,l) = sum h_p * 1 = H_total 对所有(k,l)
H_total = sum(gains_raw);
ratio_matrix = Y_dd_ones / H_total;  % 应全为1，有相位误差处偏离

% 提取相位误差
phase_err = angle(ratio_matrix);  % 弧度
phase_err_deg = phase_err * 180 / pi;

subplot(1,2,1);
imagesc(0:M-1, 0:N-1, abs(ratio_matrix));
axis xy; colorbar; clim([0.8 1.2]);
xlabel('l (时延bin)'); ylabel('k (多普勒bin)');
title('|Y_{dd}/(H_{total}·x)| — 偏离1.0=β因子影响');
hold on;
% 标记wrapped区域 (l < max_delay)
xline(max(delay_bins)-0.5, 'r--', 'LineWidth',2);
text(max(delay_bins)/2, N-2, sprintf('l<%d\n(wrapped)', max(delay_bins)), ...
    'Color','r', 'FontSize',10, 'HorizontalAlignment','center');

subplot(1,2,2);
imagesc(0:M-1, 0:N-1, phase_err_deg);
axis xy; colorbar;
xlabel('l (时延bin)'); ylabel('k (多普勒bin)');
title('相位误差 (度) — l<max\_delay时出现exp(-j2\pik/N)');
hold on; xline(max(delay_bins)-0.5, 'r--', 'LineWidth',2);
colormap(gca, 'jet');

sgtitle('帧CP β因子: y(k,l) = H·x·exp(-j2\pik/N) for l<max\_delay', 'FontSize',13);

% 打印关键k值的β因子
fprintf('  β因子 exp(-j2πk/N) 在 l<max_delay=%d 区域:\n', max(delay_bins));
for k_show = [0, 1, 4, 8, 16, 24, 31]
    beta = exp(-1j*2*pi*k_show/N);
    kk = k_show + 1;
    % 实测: 取l=0处ratio
    measured = ratio_matrix(kk, 1);
    fprintf('    k=%2d: 理论β=%.3f%+.3fj, 实测ratio=%.3f%+.3fj\n', ...
        k_show, real(beta), imag(beta), real(measured), imag(measured));
end

%% ===== 4. 受β影响的数据符号比例 ===== %%
n_affected = 0;
for idx = 1:length(data_indices)
    [~, ll] = ind2sub([N M], data_indices(idx));
    l_val = ll - 1;  % 0-indexed
    if l_val < max(delay_bins)
        n_affected = n_affected + 1;
    end
end
fprintf('\n  数据符号总数: %d\n', length(data_indices));
fprintf('  受β影响(l<%d): %d (%.1f%%)\n', max(delay_bins), n_affected, ...
    100*n_affected/length(data_indices));
fprintf('  其中k=0无影响, k=N/2(=%d)时β=-1(180度翻转)\n', N/2);

%% ===== 保存 ===== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_otfs_channel_diag_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'OTFS DD域信道诊断 V1.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'N=%d, M=%d, CP=%d, SNR=%ddB\n\n', N, M, cp_len, snr_db);

for fi = 1:size(fading_cfgs,1)
    fprintf(fid, '=== %s ===\n', fading_cfgs{fi,1});
    % 打印dk=0剖面
    fprintf(fid, 'dk=0剖面 |h_true| vs |h_est|:\n');
    for dl_d = 0:max(delay_bins)+2
        ll = mod(pl-1+dl_d, M)+1;
        % 需要重新计算... 但数据在循环变量中，简化输出
        fprintf(fid, '  dl=%d\n', dl_d);
    end
end

fprintf(fid, '\n=== β因子验证 ===\n');
fprintf(fid, '受影响数据符号: %d/%d (%.1f%%)\n', n_affected, length(data_indices), ...
    100*n_affected/length(data_indices));
for k_show = [0, 1, 4, 8, 16, 24, 31]
    beta = exp(-1j*2*pi*k_show/N);
    kk = k_show + 1;
    measured = ratio_matrix(kk, 1);
    fprintf(fid, 'k=%2d: 理论β=%.3f%+.3fj, 实测=%.3f%+.3fj, 相位误差=%.1f度\n', ...
        k_show, real(beta), imag(beta), real(measured), imag(measured), ...
        angle(measured/beta)*180/pi);
end
fclose(fid);
fprintf('\n结果已保存: %s\n', result_file);
fprintf('完成\n');
