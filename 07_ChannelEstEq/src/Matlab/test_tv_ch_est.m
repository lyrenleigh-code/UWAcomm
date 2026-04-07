%% test_tv_ch_est.m — 时变信道估计新函数测试
% 对比：BEM(CE/P/DCT) / Kalman / T-SBL / SAGE
% 基线：GAMP(静态) / Oracle
% 版本：V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  时变信道估计函数 单元测试\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

%% ========== 信道参数 ========== %%
sym_rate = 6000;
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));
L_h = max(sym_delays)+1;
K = length(sym_delays);
train_len = 500; data_len = 2000;
N_total = train_len + data_len;
pilot_len = 50;
snr_db = 15;

pass_count = 0; fail_count = 0;

%% ========== 生成信号和信道 ========== %%
rng(42);
training = constellation(randi(4,1,train_len));
data_sym = constellation(randi(4,1,data_len));
tx = [training, data_sym];
pilot_sym = constellation(randi(4,1,pilot_len));

fd_hz = 5;  % 测试用fd=5Hz

% Jakes时变信道
rng(200);
t = (0:N_total-1)/sym_rate;
h_true = zeros(K, N_total);
for p = 1:K
    fad = zeros(1, N_total);
    for k = 1:8
        theta = 2*pi*rand; beta = pi*k/8;
        fad = fad + exp(1j*(2*pi*fd_hz*cos(beta)*t + theta));
    end
    h_true(p,:) = gains(p) * fad / sqrt(8);
end

% 时变卷积
rx = zeros(1, N_total);
for n = 1:N_total
    for p = 1:K
        d = sym_delays(p);
        if n-d >= 1, rx(n) = rx(n) + h_true(p,n) * tx(n-d); end
    end
end
noise_var = mean(abs(rx).^2) * 10^(-snr_db/10);
rng(300);
rx = rx + sqrt(noise_var/2)*(randn(size(rx))+1j*randn(size(rx)));

fprintf('信道: 6径, fd=%dHz, SNR=%ddB, N=%d(训练%d+数据%d)\n\n', ...
    fd_hz, snr_db, N_total, train_len, data_len);

%% ==================== 测试1: ch_est_bem ==================== %%
fprintf('--- 1. ch_est_bem (BEM基扩展) ---\n');

% 构建导频观测（训练段+散布导频）
pilot_interval = 300;
pilot_positions = train_len + (1:floor(data_len/pilot_interval)) * pilot_interval;
all_obs_times = [];
all_obs_y = [];
all_obs_x = [];

% 训练段观测
for n = 1:train_len
    x_vec = zeros(1, K);
    for p = 1:K
        idx = n - sym_delays(p);
        if idx >= 1, x_vec(p) = training(idx); end
    end
    if any(x_vec ~= 0)
        all_obs_times(end+1) = n;
        all_obs_y(end+1) = rx(n);
        all_obs_x = [all_obs_x; x_vec];
    end
end
% 散布导频观测（用已知data符号模拟导频）
for pi = 1:length(pilot_positions)
    pp = pilot_positions(pi);
    for kk = max(1,pp-pilot_len/2):min(N_total,pp+pilot_len/2-1)
        x_vec = zeros(1, K);
        for p = 1:K
            idx = kk - sym_delays(p);
            if idx >= 1 && idx <= N_total, x_vec(p) = tx(idx); end
        end
        if any(x_vec ~= 0)
            all_obs_times(end+1) = kk;
            all_obs_y(end+1) = rx(kk);
            all_obs_x = [all_obs_x; x_vec];
        end
    end
end

% 测试CE-BEM
try
    [h_bem_ce, c_ce, info_ce] = ch_est_bem(all_obs_y(:), all_obs_x, all_obs_times(:), ...
        N_total, sym_delays, fd_hz, sym_rate, noise_var, 'ce');
    nmse_ce = 10*log10(mean(sum(abs(h_bem_ce - h_true).^2, 1)) / mean(sum(abs(h_true).^2, 1)));
    fprintf('[通过] CE-BEM: Q=%d, NMSE=%.1fdB, 残差=%.1fdB\n', info_ce.Q, nmse_ce, info_ce.nmse_residual);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] CE-BEM: %s\n', e.message); fail_count = fail_count + 1;
end

% 测试P-BEM
try
    [h_bem_p, ~, info_p] = ch_est_bem(all_obs_y(:), all_obs_x, all_obs_times(:), ...
        N_total, sym_delays, fd_hz, sym_rate, noise_var, 'poly');
    nmse_p = 10*log10(mean(sum(abs(h_bem_p - h_true).^2, 1)) / mean(sum(abs(h_true).^2, 1)));
    fprintf('[通过] P-BEM:  Q=%d, NMSE=%.1fdB\n', info_p.Q, nmse_p);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] P-BEM: %s\n', e.message); fail_count = fail_count + 1;
end

% 测试DCT-BEM
try
    [h_bem_d, ~, info_d] = ch_est_bem(all_obs_y(:), all_obs_x, all_obs_times(:), ...
        N_total, sym_delays, fd_hz, sym_rate, noise_var, 'dct');
    nmse_d = 10*log10(mean(sum(abs(h_bem_d - h_true).^2, 1)) / mean(sum(abs(h_true).^2, 1)));
    fprintf('[通过] DCT-BEM: Q=%d, NMSE=%.1fdB\n', info_d.Q, nmse_d);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] DCT-BEM: %s\n', e.message); fail_count = fail_count + 1;
end

%% ==================== 测试2: ch_track_kalman ==================== %%
fprintf('\n--- 2. ch_track_kalman (Kalman跟踪) ---\n');

% 用已知符号驱动（上界测试）
try
    h_init = h_true(:, round(train_len/2));  % 训练中点真值初始化
    [h_kal, P_kal, info_kal] = ch_track_kalman(rx(train_len+1:end), tx(train_len+1:end), ...
        sym_delays, h_init, fd_hz, sym_rate, noise_var);
    h_true_data = h_true(:, train_len+1:end);
    nmse_kal = 10*log10(mean(sum(abs(h_kal - h_true_data).^2, 1)) / mean(sum(abs(h_true_data).^2, 1)));
    fprintf('[通过] Kalman(已知x): NMSE=%.1fdB, 更新%d/%d, α=%.4f\n', ...
        nmse_kal, info_kal.n_updated, data_len, info_kal.alpha);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] Kalman(已知x): %s\n', e.message); fail_count = fail_count + 1;
end

% 用GAMP估计初始化
try
    T_mat = zeros(train_len, L_h);
    for col = 1:L_h, T_mat(col:train_len,col) = training(1:train_len-col+1).'; end
    [h_gamp,~] = ch_est_gamp(rx(1:train_len)', T_mat, L_h, 50, noise_var);
    h_init_gamp = h_gamp(sym_delays+1);

    [h_kal2, ~, info_kal2] = ch_track_kalman(rx(train_len+1:end), tx(train_len+1:end), ...
        sym_delays, h_init_gamp, fd_hz, sym_rate, noise_var);
    nmse_kal2 = 10*log10(mean(sum(abs(h_kal2 - h_true_data).^2, 1)) / mean(sum(abs(h_true_data).^2, 1)));
    fprintf('[通过] Kalman(GAMP init): NMSE=%.1fdB\n', nmse_kal2);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] Kalman(GAMP init): %s\n', e.message); fail_count = fail_count + 1;
end

%% ==================== 测试3: ch_est_tsbl ==================== %%
fprintf('\n--- 3. ch_est_tsbl (T-SBL时序稀疏贝叶斯) ---\n');

try
    % T-SBL多快照：每快照用同一导频序列（重复导频），观测不同时刻的信道
    % 模拟：帧内每隔一段插入相同的短导频序列
    pilot_rep = training(1:200);  % 用训练前200符号作为重复导频
    M_snap = length(pilot_rep) - max(sym_delays);
    T_snap = 8;  % 8个时刻快照
    snap_interval = floor(data_len / (T_snap+1));

    % 构建共享Phi（导频Toeplitz矩阵）
    Phi_snap = zeros(M_snap, L_h);
    for col = 1:L_h
        if col <= M_snap
            Phi_snap(col:M_snap, col) = pilot_rep(1:M_snap-col+1).';
        end
    end

    % 每快照：用该时刻的真实信道生成观测（模拟重复导频接收）
    Y_multi = zeros(M_snap, T_snap);
    for tt = 1:T_snap
        t_center = train_len + tt*snap_interval;
        % 用该时刻的信道对导频做卷积
        h_at_t = h_true(:, min(t_center, N_total));  % K×1 该时刻各径增益
        h_full = zeros(L_h, 1);
        for p = 1:K, h_full(sym_delays(p)+1) = h_at_t(p); end
        rx_pilot = conv(pilot_rep, h_full.');
        rx_pilot = rx_pilot(1:length(pilot_rep));
        rx_pilot = rx_pilot + sqrt(noise_var/2)*(randn(1,length(pilot_rep))+1j*randn(1,length(pilot_rep)));
        Y_multi(:, tt) = rx_pilot(max(sym_delays)+1:max(sym_delays)+M_snap).';
    end

    [H_tsbl, h_tsbl, gamma_tsbl, info_tsbl] = ch_est_tsbl(Y_multi, Phi_snap, L_h, T_snap, 50, 1e-5, 0.95);
    fprintf('[通过] T-SBL: 检测%d径(真实%d), 迭代%d次, σ²=%.2e\n', ...
        info_tsbl.K_detected, K, info_tsbl.n_iter, info_tsbl.sigma2);
    fprintf('  支撑集: [%s]\n', num2str(info_tsbl.support'));
    fprintf('  真实位置: [%s]\n', num2str(sym_delays+1));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] T-SBL: %s\n', e.message); fail_count = fail_count + 1;
end

%% ==================== 测试4: ch_est_sage ==================== %%
fprintf('\n--- 4. ch_est_sage (SAGE/EM多径参数估计) ---\n');

try
    % 用静态信道段测试SAGE（SAGE更适合初始参数获取）
    rx_static = conv(tx(1:train_len), [gains(1) zeros(1,4) gains(2) zeros(1,9) gains(3) ...
        zeros(1,24) gains(4) zeros(1,19) gains(5) zeros(1,29) gains(6)]);
    rx_static = rx_static(1:train_len);
    rx_static = rx_static + sqrt(noise_var/2)*(randn(size(rx_static))+1j*randn(size(rx_static)));

    [params_sage, h_sage, info_sage] = ch_est_sage(rx_static, training, sym_rate, K, 15, [0 100], [-1 1]);
    fprintf('[通过] SAGE: 收敛=%d, 迭代%d次\n', info_sage.converged, info_sage.n_iter);
    fprintf('  估计时延: [%s]\n', num2str(params_sage(:,1)'));
    fprintf('  真实时延: [%s]\n', num2str(sym_delays));
    fprintf('  估计增益: [%s]\n', num2str(abs(info_sage.gains_complex)','%.3f '));
    fprintf('  真实增益: [%s]\n', num2str(abs(gains),'%.3f '));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] SAGE: %s\n', e.message); fail_count = fail_count + 1;
end

%% ==================== 测试5: NMSE对比 ==================== %%
fprintf('\n--- 5. NMSE综合对比 (数据段, fd=%dHz, SNR=%ddB) ---\n', fd_hz, snr_db);

% 基线：GAMP固定
h_gamp_fixed = repmat(h_gamp(sym_delays+1), 1, data_len);
nmse_gamp = 10*log10(mean(sum(abs(h_gamp_fixed - h_true_data).^2,1)) / mean(sum(abs(h_true_data).^2,1)));

fprintf('%-20s NMSE(dB)\n', '方法');
fprintf('%s\n', repmat('-',1,32));
fprintf('%-20s %7.1f\n', 'GAMP(固定)', nmse_gamp);
if exist('nmse_ce','var'),   fprintf('%-20s %7.1f\n', 'BEM(CE)', nmse_ce); end
if exist('nmse_p','var'),    fprintf('%-20s %7.1f\n', 'BEM(Poly)', nmse_p); end
if exist('nmse_d','var'),    fprintf('%-20s %7.1f\n', 'BEM(DCT)', nmse_d); end
if exist('nmse_kal','var'),  fprintf('%-20s %7.1f\n', 'Kalman(已知x)', nmse_kal); end
if exist('nmse_kal2','var'), fprintf('%-20s %7.1f\n', 'Kalman(GAMP init)', nmse_kal2); end
fprintf('%-20s %7.1f\n', 'Oracle', -Inf);

%% ==================== 可视化 ==================== %%
figure('Position',[50 50 1400 700]);
t_data = (1:data_len)/sym_rate*1000;
win = 50;

% --- 主径幅度跟踪 ---
subplot(2,2,1);
plot(t_data, abs(h_true_data(1,:)), 'k', 'LineWidth',2); hold on;
plot(t_data, abs(h_gamp_fixed(1,:)), 'r--', 'LineWidth',1);
if exist('h_bem_ce','var'), plot(t_data, abs(h_bem_ce(1,train_len+1:end)), 'b', 'LineWidth',1.5); end
if exist('h_bem_d','var'), plot(t_data, abs(h_bem_d(1,train_len+1:end)), 'c', 'LineWidth',1); end
if exist('h_kal','var'), plot(t_data, abs(h_kal(1,:)), 'g', 'LineWidth',1); end
% T-SBL（离散快照→标记点）
if exist('h_tsbl','var') && exist('snap_interval','var')
    for tt = 1:T_snap
        t_pt = tt*snap_interval/sym_rate*1000;
        h_tsbl_path1 = abs(h_tsbl(sym_delays(1)+1, tt));
        plot(t_pt, h_tsbl_path1, 'mp', 'MarkerSize',10, 'LineWidth',2);
    end
end
% SAGE（静态估计→水平线）
if exist('info_sage','var')
    yline(abs(info_sage.gains_complex(1)), 'm--', 'LineWidth',1);
end
xlabel('时间(ms)'); ylabel('|h_1|'); grid on;
title('主径(d=0)幅度跟踪');
leg = {'Oracle','GAMP固定'};
if exist('h_bem_ce','var'), leg{end+1}='BEM(CE)'; end
if exist('h_bem_d','var'), leg{end+1}='BEM(DCT)'; end
if exist('h_kal','var'), leg{end+1}='Kalman'; end
if exist('h_tsbl','var'), leg{end+1}='T-SBL快照'; end
if exist('info_sage','var'), leg{end+1}='SAGE(静态)'; end
legend(leg,'Location','best','FontSize',8);

% --- 第3径(d=15)跟踪 ---
subplot(2,2,2);
plot(t_data, abs(h_true_data(3,:)), 'k', 'LineWidth',2); hold on;
plot(t_data, abs(h_gamp_fixed(3,:)), 'r--', 'LineWidth',1);
if exist('h_bem_ce','var'), plot(t_data, abs(h_bem_ce(3,train_len+1:end)), 'b', 'LineWidth',1.5); end
if exist('h_kal','var'), plot(t_data, abs(h_kal(3,:)), 'g', 'LineWidth',1); end
xlabel('时间(ms)'); ylabel('|h_3|'); grid on;
title('第3径(d=15)幅度跟踪');
legend('Oracle','GAMP固定','BEM(CE)','Kalman','Location','best','FontSize',8);

% --- NMSE随时间 ---
subplot(2,2,3);
nmse_t_gamp = movmean(sum(abs(h_gamp_fixed-h_true_data).^2,1)./sum(abs(h_true_data).^2,1), win);
plot(t_data, 10*log10(nmse_t_gamp+1e-10), 'r--', 'LineWidth',1); hold on;
if exist('h_bem_ce','var')
    h_bem_data = h_bem_ce(:, train_len+1:end);
    nmse_t_bem = movmean(sum(abs(h_bem_data-h_true_data).^2,1)./sum(abs(h_true_data).^2,1), win);
    plot(t_data, 10*log10(nmse_t_bem+1e-10), 'b', 'LineWidth',1.5);
end
if exist('h_bem_d','var')
    h_bemd_data = h_bem_d(:, train_len+1:end);
    nmse_t_bemd = movmean(sum(abs(h_bemd_data-h_true_data).^2,1)./sum(abs(h_true_data).^2,1), win);
    plot(t_data, 10*log10(nmse_t_bemd+1e-10), 'c', 'LineWidth',1);
end
if exist('h_kal','var')
    nmse_t_kal = movmean(sum(abs(h_kal-h_true_data).^2,1)./sum(abs(h_true_data).^2,1), win);
    plot(t_data, 10*log10(nmse_t_kal+1e-10), 'g', 'LineWidth',1);
end
xlabel('时间(ms)'); ylabel('NMSE(dB)'); grid on; ylim([-30 5]);
title('NMSE随时间变化');
legend('GAMP固定','BEM(CE)','BEM(DCT)','Kalman','Location','best','FontSize',8);

% --- NMSE柱状对比 ---
subplot(2,2,4);
method_names = {}; nmse_vals = [];
method_names{end+1}='GAMP固定'; nmse_vals(end+1)=10*log10(mean(sum(abs(h_gamp_fixed-h_true_data).^2,1)./sum(abs(h_true_data).^2,1)));
if exist('nmse_ce','var'), method_names{end+1}='BEM(CE)'; nmse_vals(end+1)=nmse_ce; end
if exist('nmse_d','var'), method_names{end+1}='BEM(DCT)'; nmse_vals(end+1)=nmse_d; end
if exist('nmse_p','var'), method_names{end+1}='BEM(Poly)'; nmse_vals(end+1)=nmse_p; end
if exist('nmse_kal','var'), method_names{end+1}='Kalman(真x)'; nmse_vals(end+1)=nmse_kal; end
if exist('nmse_kal2','var'), method_names{end+1}='Kalman(GAMP)'; nmse_vals(end+1)=nmse_kal2; end
bar(nmse_vals);
set(gca, 'XTickLabel', method_names, 'XTickLabelRotation', 30, 'FontSize', 9);
ylabel('NMSE(dB)'); grid on;
title('方法NMSE对比');
yline(0, 'r--', '0dB(无效)');

sgtitle(sprintf('时变信道估计全方法对比 (fd=%dHz, SNR=%ddB)', fd_hz, snr_db));

% === 第二张图：时变细节（放大+相位）===
figure('Position',[50 50 1400 600]);

% 放大视图：前100ms主径幅度+相位
zoom_n = min(600, data_len);  % 前100ms
t_zoom = (1:zoom_n)/sym_rate*1000;

subplot(2,3,1);
plot(t_zoom, abs(h_true_data(1,1:zoom_n)), 'k', 'LineWidth',2); hold on;
plot(t_zoom, abs(h_gamp_fixed(1,1:zoom_n)), 'r--', 'LineWidth',1);
if exist('h_bem_ce','var'), plot(t_zoom, abs(h_bem_ce(1,train_len+(1:zoom_n))), 'b', 'LineWidth',1.5); end
if exist('h_kal','var'), plot(t_zoom, abs(h_kal(1,1:zoom_n)), 'g', 'LineWidth',1); end
xlabel('时间(ms)'); ylabel('|h_1|'); grid on;
title('主径幅度(放大)'); legend('真实','GAMP固定','BEM(CE)','Kalman','Location','best','FontSize',8);

subplot(2,3,4);
plot(t_zoom, angle(h_true_data(1,1:zoom_n))*180/pi, 'k', 'LineWidth',2); hold on;
plot(t_zoom, angle(h_gamp_fixed(1,1:zoom_n))*180/pi, 'r--', 'LineWidth',1);
if exist('h_bem_ce','var'), plot(t_zoom, angle(h_bem_ce(1,train_len+(1:zoom_n)))*180/pi, 'b', 'LineWidth',1.5); end
if exist('h_kal','var'), plot(t_zoom, angle(h_kal(1,1:zoom_n))*180/pi, 'g', 'LineWidth',1); end
xlabel('时间(ms)'); ylabel('相位(°)'); grid on;
title('主径相位(放大)');

% 第3径幅度+相位
subplot(2,3,2);
plot(t_zoom, abs(h_true_data(3,1:zoom_n)), 'k', 'LineWidth',2); hold on;
if exist('h_bem_ce','var'), plot(t_zoom, abs(h_bem_ce(3,train_len+(1:zoom_n))), 'b', 'LineWidth',1.5); end
if exist('h_kal','var'), plot(t_zoom, abs(h_kal(3,1:zoom_n)), 'g', 'LineWidth',1); end
xlabel('时间(ms)'); ylabel('|h_3|'); grid on;
title('第3径(d=15)幅度'); legend('真实','BEM(CE)','Kalman','Location','best','FontSize',8);

subplot(2,3,5);
plot(t_zoom, angle(h_true_data(3,1:zoom_n))*180/pi, 'k', 'LineWidth',2); hold on;
if exist('h_bem_ce','var'), plot(t_zoom, angle(h_bem_ce(3,train_len+(1:zoom_n)))*180/pi, 'b', 'LineWidth',1.5); end
if exist('h_kal','var'), plot(t_zoom, angle(h_kal(3,1:zoom_n))*180/pi, 'g', 'LineWidth',1); end
xlabel('时间(ms)'); ylabel('相位(°)'); grid on;
title('第3径(d=15)相位');

% 第6径（最弱径d=90）
subplot(2,3,3);
plot(t_zoom, abs(h_true_data(6,1:zoom_n)), 'k', 'LineWidth',2); hold on;
if exist('h_bem_ce','var'), plot(t_zoom, abs(h_bem_ce(6,train_len+(1:zoom_n))), 'b', 'LineWidth',1.5); end
if exist('h_kal','var'), plot(t_zoom, abs(h_kal(6,1:zoom_n)), 'g', 'LineWidth',1); end
xlabel('时间(ms)'); ylabel('|h_6|'); grid on;
title('第6径(d=90)幅度'); legend('真实','BEM(CE)','Kalman','Location','best','FontSize',8);

subplot(2,3,6);
plot(t_zoom, angle(h_true_data(6,1:zoom_n))*180/pi, 'k', 'LineWidth',2); hold on;
if exist('h_bem_ce','var'), plot(t_zoom, angle(h_bem_ce(6,train_len+(1:zoom_n)))*180/pi, 'b', 'LineWidth',1.5); end
if exist('h_kal','var'), plot(t_zoom, angle(h_kal(6,1:zoom_n))*180/pi, 'g', 'LineWidth',1); end
xlabel('时间(ms)'); ylabel('相位(°)'); grid on;
title('第6径(d=90)相位');

sgtitle(sprintf('时变信道跟踪细节 — 幅度+相位 (fd=%dHz, 前%.0fms)', fd_hz, zoom_n/sym_rate*1000));

%% ==================== 汇总 ==================== %%
fprintf('\n========================================\n');
fprintf('  测试完成：%d 通过, %d 失败, 共 %d 项\n', pass_count, fail_count, pass_count+fail_count);
fprintf('========================================\n');
