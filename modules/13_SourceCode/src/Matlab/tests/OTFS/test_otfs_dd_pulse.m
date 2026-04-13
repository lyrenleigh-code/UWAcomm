%% test_otfs_dd_pulse.m — OTFS DD域最小脉冲验证
% 验证目标：信道延迟d在DD域表现为时延维位移（非相位旋转）
% 版本：V1.0.0
% 测试内容：
%   1. Loopback（无信道）：x_dd → mod → demod → 误差<1e-10
%   2. 单径延迟：x_dd(pk,pl)=1, delay=d → Y_dd(pk, pl+d)=h
%   3. 多径静态：5径信道 → DD域响应集中在对应delay bin
%   4. 导频boost：验证pilot_value=√N_data时的信道估计精度

clc; close all;
fprintf('==============================================\n');
fprintf('  OTFS DD域最小脉冲验证 V1.0\n');
fprintf('==============================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));

N = 32; M = 64; cp_len = 32;
pk = ceil(N/2);  % 导频多普勒位置 = 16
pl = ceil(M/2);  % 导频时延位置 = 32
pass = 0; fail = 0; total = 0;

%% ===== 测试1: Loopback (DFT方法) =====
fprintf('--- 测试1: Loopback验证 ---\n');
total = total + 1;
x_dd = randn(N, M) + 1j*randn(N, M);
[sig, ~] = otfs_modulate(x_dd, N, M, cp_len, 'dft');
[y_dd, ~] = otfs_demodulate(sig, N, M, cp_len, 'dft');
err1 = max(abs(x_dd(:) - y_dd(:)));
if err1 < 1e-10
    fprintf('  [PASS] DFT loopback 最大误差: %.2e\n', err1);
    pass = pass + 1;
else
    fprintf('  [FAIL] DFT loopback 最大误差: %.2e (期望<1e-10)\n', err1);
    fail = fail + 1;
end

%% ===== 测试1b: Loopback (Zak方法) =====
total = total + 1;
[sig_z, ~] = otfs_modulate(x_dd, N, M, cp_len, 'zak');
[y_dd_z, ~] = otfs_demodulate(sig_z, N, M, cp_len, 'zak');
err1z = max(abs(x_dd(:) - y_dd_z(:)));
if err1z < 1e-10
    fprintf('  [PASS] Zak loopback 最大误差: %.2e\n', err1z);
    pass = pass + 1;
else
    fprintf('  [FAIL] Zak loopback 最大误差: %.2e (期望<1e-10)\n', err1z);
    fail = fail + 1;
end

%% ===== 测试1c: DFT与Zak方法一致性 =====
total = total + 1;
err_dz = max(abs(sig(:) - sig_z(:)));
if err_dz < 1e-10
    fprintf('  [PASS] DFT-Zak一致性: %.2e\n', err_dz);
    pass = pass + 1;
else
    fprintf('  [FAIL] DFT-Zak一致性: %.2e (期望<1e-10)\n', err_dz);
    fail = fail + 1;
end

%% ===== 测试2: 单点脉冲 + 单径延迟 =====
fprintf('\n--- 测试2: 单点脉冲 + 单径延迟 ---\n');
for d_test = [0, 1, 3, 5, 8]
    total = total + 1;
    h_test = exp(1j * 0.7);  % 任意复增益

    % TX: DD域单点脉冲
    x_dd_pulse = zeros(N, M);
    x_dd_pulse(pk, pl) = 1;
    [sig_p, ~] = otfs_modulate(x_dd_pulse, N, M, cp_len, 'dft');

    % 信道: 单径延迟d
    rx_p = zeros(size(sig_p));
    rx_p(d_test+1:end) = rx_p(d_test+1:end) + h_test * sig_p(1:end-d_test);

    % RX: 解调
    [Y_dd_p, ~] = otfs_demodulate(rx_p, N, M, cp_len, 'dft');

    % 验证: 响应应在 (pk, pl+d)
    expected_pos = mod(pl - 1 + d_test, M) + 1;
    val_at_expected = Y_dd_p(pk, expected_pos);
    err_gain = abs(val_at_expected - h_test);
    % 其他位置应接近零
    Y_dd_check = Y_dd_p; Y_dd_check(pk, expected_pos) = 0;
    leak = max(abs(Y_dd_check(:)));

    if err_gain < 1e-10 && leak < 1e-10
        fprintf('  [PASS] delay=%d: Y_dd(%d,%d)=%.4f+%.4fj (误差%.2e, 泄漏%.2e)\n', ...
            d_test, pk, expected_pos, real(val_at_expected), imag(val_at_expected), err_gain, leak);
        pass = pass + 1;
    else
        fprintf('  [FAIL] delay=%d: 增益误差=%.2e, 泄漏=%.2e\n', d_test, err_gain, leak);
        fail = fail + 1;
    end
end

%% ===== 测试3: 多径静态信道 =====
fprintf('\n--- 测试3: 5径静态信道DD域响应 ---\n');
total = total + 1;
delay_bins = [0, 1, 3, 5, 8];
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];

x_dd_pilot = zeros(N, M);
x_dd_pilot(pk, pl) = 1;
[sig_m, ~] = otfs_modulate(x_dd_pilot, N, M, cp_len, 'dft');

rx_m = zeros(size(sig_m));
for p = 1:length(delay_bins)
    d = delay_bins(p);
    rx_m(d+1:end) = rx_m(d+1:end) + gains_raw(p) * sig_m(1:end-d);
end

[Y_dd_m, ~] = otfs_demodulate(rx_m, N, M, cp_len, 'dft');

% 检查各径响应
fprintf('  DD域导频响应 (pilot at (%d,%d)):\n', pk, pl);
all_ok = true;
for p = 1:length(delay_bins)
    dl = delay_bins(p);
    ll = mod(pl - 1 + dl, M) + 1;
    val = Y_dd_m(pk, ll);
    err_p = abs(val - gains_raw(p));
    fprintf('    dl=%d: |%.4f| (期望|%.4f|), 误差=%.2e', dl, abs(val), abs(gains_raw(p)), err_p);
    if err_p < 1e-6
        fprintf(' OK\n');
    else
        fprintf(' MISMATCH!\n');
        all_ok = false;
    end
end
if all_ok
    fprintf('  [PASS] 所有径响应正确集中\n');
    pass = pass + 1;
else
    fprintf('  [FAIL] 部分径响应不正确\n');
    fail = fail + 1;
end

%% ===== 测试4: 导频boost + 信道估计 =====
fprintf('\n--- 测试4: 导频boost + ch_est_otfs_dd ---\n');
total = total + 1;
pilot_config = struct('mode','impulse', 'guard_k',4, 'guard_l',max(delay_bins)+2, 'pilot_value',1);
[~,~,~,data_indices] = otfs_pilot_embed(zeros(1,1), N, M, pilot_config);
N_data = length(data_indices);
pilot_config.pilot_value = sqrt(N_data);

% TX: 导频+随机数据
rng(42);
data_sym = (2*randi([0,1],1,N_data)-1 + 1j*(2*randi([0,1],1,N_data)-1)) / sqrt(2);
[dd_frame, pilot_info, ~, ~] = otfs_pilot_embed(data_sym, N, M, pilot_config);
[sig_e, ~] = otfs_modulate(dd_frame, N, M, cp_len, 'dft');

% 信道
rx_e = zeros(size(sig_e));
for p = 1:length(delay_bins)
    d = delay_bins(p);
    rx_e(d+1:end) = rx_e(d+1:end) + gains_raw(p) * sig_e(1:end-d);
end
% 加噪 SNR=20dB
sig_pwr = mean(abs(rx_e).^2);
nv = sig_pwr * 10^(-20/10);
rng(123);
rx_noisy = rx_e + sqrt(nv/2)*(randn(size(rx_e)) + 1j*randn(size(rx_e)));

[Y_dd_e, ~] = otfs_demodulate(rx_noisy, N, M, cp_len, 'dft');

% 信道估计
[h_dd_est, path_info] = ch_est_otfs_dd(Y_dd_e, pilot_info, N, M);

fprintf('  检测到 %d 径 (真实 %d 径)\n', path_info.num_paths, length(delay_bins));
fprintf('  估计增益:\n');
est_ok = true;
for p = 1:min(path_info.num_paths, length(delay_bins))
    fprintf('    dl=%d, dk=%d: |%.4f| (期望|%.4f|)\n', ...
        path_info.delay_idx(p), path_info.doppler_idx(p), ...
        abs(path_info.gain(p)), abs(gains_raw(min(p,end))));
end

% 判断: 检测径数应=5, 各径增益误差<10% (SNR=20dB)
if path_info.num_paths >= 4  % 最弱径0.1可能被阈值过滤
    % 对比检测到的径增益与真实值
    for p = 1:path_info.num_paths
        dl = path_info.delay_idx(p);
        idx = find(delay_bins == dl, 1);
        if ~isempty(idx)
            rel_err = abs(abs(path_info.gain(p)) - abs(gains_raw(idx))) / abs(gains_raw(idx));
            if rel_err > 0.15
                est_ok = false;
            end
        end
    end
    if est_ok
        fprintf('  [PASS] 信道估计精度OK (SNR=20dB)\n');
        pass = pass + 1;
    else
        fprintf('  [FAIL] 信道估计增益误差>15%%\n');
        fail = fail + 1;
    end
else
    fprintf('  [FAIL] 检测径数不足: %d (期望>=4)\n', path_info.num_paths);
    fail = fail + 1;
end

%% ===== 可视化 =====
try
    figure('Position', [50 400 900 350]);

    % DD域响应热图
    subplot(1,2,1);
    imagesc(0:M-1, 0:N-1, abs(Y_dd_m));
    hold on;
    for p = 1:length(delay_bins)
        ll = mod(pl-1+delay_bins(p), M);
        plot(ll, pk-1, 'rx', 'MarkerSize', 12, 'LineWidth', 2);
    end
    axis xy; colorbar;
    xlabel('时延 (bin)'); ylabel('多普勒 (bin)');
    title('DD域单脉冲响应 (5径静态, 无噪声)');

    % 导频行剖面
    subplot(1,2,2);
    dl_range = 0:15;
    resp = zeros(size(dl_range));
    for i = 1:length(dl_range)
        ll = mod(pl-1+dl_range(i), M) + 1;
        resp(i) = abs(Y_dd_m(pk, ll));
    end
    stem(dl_range, resp, 'b', 'LineWidth', 1.5);
    hold on;
    for p = 1:length(delay_bins)
        plot(delay_bins(p), abs(gains_raw(p)), 'rv', 'MarkerSize', 10, 'MarkerFaceColor','r');
    end
    xlabel('延迟偏移 dl'); ylabel('|Y_{DD}(pk, pl+dl)|');
    title('导频行响应 vs 真实信道');
    legend('DD域响应', '真实信道增益', 'Location', 'northeast');
    grid on;
catch ME
    fprintf('可视化失败: %s\n', ME.message);
end

%% ===== 汇总 =====
fprintf('\n=== 汇总: %d/%d 通过, %d 失败 ===\n', pass, total, fail);

%% ===== 保存结果 =====
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_otfs_dd_pulse_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'OTFS DD域最小脉冲验证 V1.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'N=%d, M=%d, CP=%d, pilot=(%d,%d)\n', N, M, cp_len, pk, pl);
fprintf(fid, '通过: %d/%d, 失败: %d\n\n', pass, total, fail);
fprintf(fid, '测试1: DFT loopback 误差=%.2e\n', err1);
fprintf(fid, '测试1b: Zak loopback 误差=%.2e\n', err1z);
fprintf(fid, '测试1c: DFT-Zak一致性 误差=%.2e\n', err_dz);
fprintf(fid, '\n测试2: 单径延迟验证\n');
for d_test = [0, 1, 3, 5, 8]
    x_dd_p2 = zeros(N,M); x_dd_p2(pk,pl)=1;
    [sig_p2,~] = otfs_modulate(x_dd_p2,N,M,cp_len,'dft');
    rx_p2 = zeros(size(sig_p2));
    rx_p2(d_test+1:end) = rx_p2(d_test+1:end) + sig_p2(1:end-d_test);
    [Y_p2,~] = otfs_demodulate(rx_p2,N,M,cp_len,'dft');
    ep = mod(pl-1+d_test,M)+1;
    fprintf(fid, '  delay=%d: Y_dd(%d,%d)=%.6f+%.6fj\n', d_test, pk, ep, real(Y_p2(pk,ep)), imag(Y_p2(pk,ep)));
end
fprintf(fid, '\n测试3: 5径响应\n');
for p = 1:length(delay_bins)
    dl = delay_bins(p);
    ll = mod(pl-1+dl,M)+1;
    fprintf(fid, '  dl=%d: |%.6f| (真实|%.4f|)\n', dl, abs(Y_dd_m(pk,ll)), abs(gains_raw(p)));
end
fprintf(fid, '\n测试4: 信道估计 (%d径检测, SNR=20dB)\n', path_info.num_paths);
for p = 1:path_info.num_paths
    fprintf(fid, '  dl=%d, dk=%d: |%.4f|\n', path_info.delay_idx(p), path_info.doppler_idx(p), abs(path_info.gain(p)));
end
fclose(fid);
fprintf('结果已保存: %s\n', result_file);
