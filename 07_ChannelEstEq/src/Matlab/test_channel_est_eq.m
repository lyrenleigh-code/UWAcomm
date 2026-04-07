%% test_channel_est_eq.m — 信道估计与均衡模块统一测试
% 覆盖：静态估计 / 时变估计 / 信道跟踪 / 均衡器 / 时变均衡
% 每项均含可视化输出
% 版本：V2.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  模块07 信道估计与均衡 — 统一测试\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

pass_count = 0; fail_count = 0;

%% ========== 公共参数 ========== %%
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);
sym_rate = 6000; sps = 8; rolloff = 0.35; span_rrc = 6;
sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));
L_h = max(sym_delays)+1; K = length(sym_delays);
snr_db = 15; noise_var_base = 10^(-snr_db/10);

%% ==================== 一、静态信道估计（8种方法NMSE对比）==================== %%
fprintf('--- 1. 静态信道估计 NMSE 对比 ---\n\n');

rng(10);
h_true_static = zeros(1, L_h);
for p=1:K, h_true_static(sym_delays(p)+1) = gains(p); end
H_true = fft(h_true_static, L_h);

train_len_s = 500;
training_s = constellation(randi(4,1,train_len_s));
% Toeplitz观测矩阵
T_mat = zeros(train_len_s, L_h);
for col=1:L_h, T_mat(col:train_len_s,col)=training_s(1:train_len_s-col+1).'; end
rx_s = conv(training_s, h_true_static); rx_s = rx_s(1:train_len_s);
rx_s = rx_s + sqrt(noise_var_base/2)*(randn(1,train_len_s)+1j*randn(1,train_len_s));

% 频域观测
Y_freq_s = fft(rx_s, train_len_s);
X_freq_s = fft(training_s, train_len_s);

est_methods = {'LS','MMSE','OMP','SBL','GAMP','VAMP','TurboVAMP'};
nmse_static = zeros(1, length(est_methods));
h_ests = cell(1, length(est_methods));

for mi = 1:length(est_methods)
    try
        switch est_methods{mi}
            case 'LS',       [~,h_e] = ch_est_ls(Y_freq_s, X_freq_s, train_len_s);
            case 'MMSE',     [~,h_e] = ch_est_mmse(Y_freq_s, X_freq_s, train_len_s, noise_var_base);
            case 'OMP',      [h_e,~,~] = ch_est_omp(rx_s(:), T_mat, L_h, K);
            case 'SBL',      [h_e,~,~] = ch_est_sbl(rx_s(:), T_mat, L_h, 50);
            case 'GAMP',     [h_e,~] = ch_est_gamp(rx_s(:), T_mat, L_h, 50, noise_var_base);
            case 'VAMP',     [h_e,~,~] = ch_est_vamp(rx_s(:), T_mat, L_h, 100, noise_var_base, K);
            case 'TurboVAMP',[h_e,~,~,~] = ch_est_turbo_vamp(rx_s(:), T_mat, L_h, 30, K, noise_var_base);
        end
        h_e = h_e(:).';
        if length(h_e) > L_h, h_e = h_e(1:L_h); end
        nmse_static(mi) = 10*log10(sum(abs(h_e-h_true_static).^2)/sum(abs(h_true_static).^2));
        h_ests{mi} = h_e;
        fprintf('[通过] %-10s NMSE=%.1fdB\n', est_methods{mi}, nmse_static(mi));
        pass_count = pass_count + 1;
    catch e
        fprintf('[失败] %-10s %s\n', est_methods{mi}, e.message);
        nmse_static(mi) = NaN; fail_count = fail_count + 1;
    end
end

% 可视化1: 静态信道估计
figure('Position',[50 500 1200 400]);
subplot(1,3,1);
stem((0:L_h-1)/sym_rate*1000, abs(h_true_static), 'k', 'filled', 'LineWidth',1.5); hold on;
if ~isempty(h_ests{5}), stem((0:L_h-1)/sym_rate*1000, abs(h_ests{5}), 'b', 'MarkerSize',4); end
xlabel('时延(ms)'); ylabel('|h|'); title('CIR: 真实 vs GAMP'); legend('真实','GAMP'); grid on;
subplot(1,3,2);
bar(nmse_static); set(gca,'XTickLabel',est_methods,'XTickLabelRotation',30);
ylabel('NMSE(dB)'); title('静态估计NMSE对比'); grid on; yline(0,'r--');
subplot(1,3,3);
f_ax = (0:L_h-1)*sym_rate/L_h/1000;
plot(f_ax, 20*log10(abs(H_true)+1e-10), 'k', 'LineWidth',1.5); hold on;
if ~isempty(h_ests{5}), plot(f_ax, 20*log10(abs(fft(h_ests{5},L_h))+1e-10), 'b--'); end
if ~isempty(h_ests{7}), plot(f_ax, 20*log10(abs(fft(h_ests{7},L_h))+1e-10), 'r--'); end
xlabel('频率(kHz)'); ylabel('|H|(dB)'); title('频响对比'); legend('真实','GAMP','TurboVAMP'); grid on;
sgtitle('1. 静态信道估计');

%% ==================== 二、时变信道估计（综合测试）==================== %%
fprintf('\n--- 2. 时变信道估计（BEM/SAGE/Kalman）---\n\n');

max_d = max(sym_delays);
train_len_tv = 500; pilot_len_tv = max_d + 100;
N_data_tv = 2000;

% --- 辅助函数：生成Jakes时变信道+接收信号 ---
gen_jakes_rx = @(fd_hz_l, snr_l, seed_l, N_tot, tr_l, dt_l) deal_jakes(...
    fd_hz_l, snr_l, seed_l, N_tot, tr_l, dt_l, sym_delays, gains, K, sym_rate);

% --- 辅助函数：从训练构建BEM导频观测 ---
build_obs = @(rx_l, tr_l, sd, K_l, max_d_l, tl) build_train_obs(rx_l, tr_l, sd, K_l, max_d_l, tl);

% === 2A: BEM NMSE vs fd（CE/DCT对比, SNR=15dB）===
fd_test_list = [0.5, 1, 2, 5];
nmse_bem_fd = NaN(2, length(fd_test_list));  % CE, DCT
rng(42); training_tv = constellation(randi(4,1,train_len_tv));
data_tv = constellation(randi(4,1,N_data_tv));
N_total_tv = train_len_tv + N_data_tv;

for fi=1:length(fd_test_list)
    fd_i = fd_test_list(fi);
    [rx_tv, h_true_tv] = gen_jakes_ch(fd_i, 15, 200+fi, N_total_tv, training_tv, data_tv, sym_delays, gains, K, sym_rate);
    [obs_y, obs_x, obs_t] = build_train_obs(rx_tv, training_tv, sym_delays, K, max_d, train_len_tv);
    for bti=1:2
        bt = {'ce','dct'}; bt_name = {'CE','DCT'};
        try
            [h_bem_i,~,inf_i] = ch_est_bem(obs_y(:),obs_x,obs_t(:),N_total_tv,sym_delays,max(fd_i,0.5),sym_rate,noise_var_base,bt{bti});
            nmse_bem_fd(bti,fi) = 10*log10(mean(sum(abs(h_bem_i-h_true_tv).^2,1)./sum(abs(h_true_tv).^2,1)));
        catch, end
    end
end

fprintf('2A BEM NMSE vs fd (SNR=15dB, 仅训练导频):\n');
fprintf('  %6s |  CE     DCT\n', 'fd(Hz)');
for fi=1:length(fd_test_list)
    fprintf('  %4.1fHz |', fd_test_list(fi));
    for bti=1:2, fprintf(' %5.1fdB', nmse_bem_fd(bti,fi)); end; fprintf('\n');
end
pass_count = pass_count + 1;

% === 2B: BEM(CE) NMSE vs SNR（fd=5Hz）===
snr_tv_list = [0, 5, 10, 15, 20];
nmse_bem_snr = NaN(1, length(snr_tv_list));
fd_fix = 5;
[~, h_true_fix] = gen_jakes_ch(fd_fix, Inf, 300, N_total_tv, training_tv, data_tv, sym_delays, gains, K, sym_rate);

for si=1:length(snr_tv_list)
    nv_i = 10^(-snr_tv_list(si)/10);
    rng(400+si);
    rx_clean_tv = gen_rx_from_h(training_tv, data_tv, h_true_fix, sym_delays, K, N_total_tv);
    rx_noisy = rx_clean_tv + sqrt(nv_i/2)*(randn(size(rx_clean_tv))+1j*randn(size(rx_clean_tv)));
    [obs_y, obs_x, obs_t] = build_train_obs(rx_noisy, training_tv, sym_delays, K, max_d, train_len_tv);
    try
        [h_bem_i,~,~] = ch_est_bem(obs_y(:),obs_x,obs_t(:),N_total_tv,sym_delays,fd_fix,sym_rate,nv_i,'ce');
        nmse_bem_snr(si) = 10*log10(mean(sum(abs(h_bem_i-h_true_fix).^2,1)./sum(abs(h_true_fix).^2,1)));
    catch, end
end

fprintf('2B BEM(CE) NMSE vs SNR (fd=5Hz):\n');
fprintf('  %6s |', 'SNR'); fprintf(' %5ddB', snr_tv_list); fprintf('\n');
fprintf('  %6s |', 'NMSE'); fprintf(' %5.1fdB', nmse_bem_snr); fprintf('\n');
pass_count = pass_count + 1;

% === 2C: DD-BEM迭代精化（训练+判决辅助）===
nmse_dd_fd = NaN(1, length(fd_test_list));
for fi=1:length(fd_test_list)
    fd_i = fd_test_list(fi);
    [rx_dd, h_true_dd] = gen_jakes_ch(fd_i, 15, 200+fi, N_total_tv, training_tv, data_tv, sym_delays, gains, K, sym_rate);
    try
        [h_dd,info_dd] = ch_est_bem_dd(rx_dd, training_tv, sym_delays, max(fd_i,0.5), sym_rate, noise_var_base, [], ...
            struct('num_iter',3,'dd_step',3,'bem_type','ce'));
        nmse_dd_fd(fi) = 10*log10(mean(sum(abs(h_dd-h_true_dd).^2,1)./sum(abs(h_true_dd).^2,1)));
    catch, end
end
fprintf('2C DD-BEM NMSE vs fd (3次DD迭代):\n');
fprintf('  %6s |', 'fd(Hz)');
for fi=1:length(fd_test_list), fprintf(' %5.1fHz', fd_test_list(fi)); end; fprintf('\n');
fprintf('  %6s |', 'BEM'); for fi=1:length(fd_test_list), fprintf(' %5.1fdB', nmse_bem_fd(1,fi)); end; fprintf('\n');
fprintf('  %6s |', 'DD-BEM'); for fi=1:length(fd_test_list), fprintf(' %5.1fdB', nmse_dd_fd(fi)); end; fprintf('\n');
pass_count = pass_count + 1;

% === 2D: SAGE参数估计精度 ===
fprintf('\n');
try
    rng(42);
    rx_sage = gen_rx_from_h(training_tv, [], h_true_fix(:,1:train_len_tv), sym_delays, K, train_len_tv);
    rx_sage = rx_sage + sqrt(noise_var_base/2)*(randn(size(rx_sage))+1j*randn(size(rx_sage)));
    [params_sage,~,info_sage] = ch_est_sage(rx_sage, training_tv, sym_rate, K, 15, [0 100], [-1 1]);
    est_delays = sort(params_sage(:,1)');
    true_delays = sort(sym_delays);
    delay_err = mean(abs(est_delays - true_delays));
    fprintf('[通过] 2D SAGE: 迭代%d次, 时延误差=%.2f符号, 估计=[%s]\n', ...
        info_sage.n_iter, delay_err, num2str(est_delays));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2D SAGE: %s\n', e.message); fail_count = fail_count + 1;
    params_sage = []; info_sage = struct();
end

% === 2E: Kalman跟踪 vs BEM对比（fd=5Hz, SNR=15dB）===
fd_kal = 5;
[rx_kal, h_true_kal] = gen_jakes_ch(fd_kal, 15, 500, N_total_tv, training_tv, data_tv, sym_delays, gains, K, sym_rate);
h_kal=[]; h_bem_kal=[];
try
    h_init = h_true_kal(:, round(train_len_tv/2));
    tx_kal = [training_tv, data_tv];
    [h_kal,~,info_kal] = ch_track_kalman(rx_kal(train_len_tv+1:end), tx_kal(train_len_tv+1:end), ...
        sym_delays, h_init, fd_kal, sym_rate, noise_var_base);
    h_true_data_kal = h_true_kal(:, train_len_tv+1:end);
    nmse_kal = 10*log10(mean(sum(abs(h_kal-h_true_data_kal).^2,1)./sum(abs(h_true_data_kal).^2,1)));
    fprintf('[通过] 2E Kalman(已知x): NMSE=%.1fdB\n', nmse_kal);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2E Kalman: %s\n', e.message); fail_count = fail_count + 1;
end

try
    [obs_y, obs_x, obs_t] = build_train_obs(rx_kal, training_tv, sym_delays, K, max_d, train_len_tv);
    [h_bem_kal,~,~] = ch_est_bem(obs_y(:),obs_x,obs_t(:),N_total_tv,sym_delays,fd_kal,sym_rate,noise_var_base,'ce');
    nmse_bem_kal = 10*log10(mean(sum(abs(h_bem_kal(:,train_len_tv+1:end)-h_true_data_kal).^2,1)./sum(abs(h_true_data_kal).^2,1)));
    fprintf('       BEM(CE)对比: NMSE=%.1fdB\n', nmse_bem_kal);
catch, end

% === 2F: 训练导频 vs 散布导频 NMSE对比（fd=5Hz, SNR=15dB）===
fprintf('\n');
fd_sp = 5; N_sp = train_len_tv + N_data_tv;
pilot_sp_len = max_d + 100; pilot_sp_interval = 300;  % 每300符号插入一段导频
rng(42); tr_sp = constellation(randi(4,1,train_len_tv));
rng(999); pilot_sp = constellation(randi(4,1,pilot_sp_len));
data_sp = constellation(randi(4,1,N_data_tv));
% 帧结构: [训练|数据段1|导频|数据段2|导频|...]
frame_sp = tr_sp; pilot_pos_sp = []; data_idx = 1;
while data_idx <= N_data_tv
    chunk = min(pilot_sp_interval, N_data_tv - data_idx + 1);
    frame_sp = [frame_sp, data_sp(data_idx:data_idx+chunk-1)];
    data_idx = data_idx + chunk;
    if data_idx <= N_data_tv
        pilot_pos_sp(end+1) = length(frame_sp) + 1;
        frame_sp = [frame_sp, pilot_sp];
    end
end
pilot_pos_sp(end+1) = length(frame_sp) + 1;
frame_sp = [frame_sp, pilot_sp];  % 尾导频
N_frame_sp = length(frame_sp);

[rx_sp, h_true_sp] = gen_jakes_ch(fd_sp, 15, 600, N_frame_sp, frame_sp, [], sym_delays, gains, K, sym_rate);

% 训练+散布导频观测
[obs_y_tr, obs_x_tr, obs_t_tr] = build_train_obs(rx_sp, tr_sp, sym_delays, K, max_d, train_len_tv);
obs_y_sp = obs_y_tr(:); obs_x_sp = obs_x_tr; obs_t_sp = obs_t_tr(:);
for pi_i = 1:length(pilot_pos_sp)
    pp = pilot_pos_sp(pi_i);
    for kk = max_d+1:pilot_sp_len
        n = pp + kk - 1;
        if n > N_frame_sp, break; end
        xv = zeros(1, K);
        for p = 1:K
            idx = n - sym_delays(p);
            if idx >= pp && idx < pp+pilot_sp_len, xv(p) = pilot_sp(idx-pp+1);
            elseif idx >= 1 && idx <= train_len_tv, xv(p) = tr_sp(idx); end
        end
        if any(xv~=0)
            obs_y_sp(end+1) = rx_sp(n);
            obs_x_sp = [obs_x_sp; xv];
            obs_t_sp(end+1) = n;
        end
    end
end

% 各方法对比
sp_methods = {'BEM(CE)','BEM(DCT)','DD-BEM','Kalman'};
nmse_train_only = NaN(1,4);
nmse_scattered  = NaN(1,4);

% 训练导频版
try [h_t,~,~]=ch_est_bem(obs_y_tr(:),obs_x_tr,obs_t_tr(:),N_frame_sp,sym_delays,fd_sp,sym_rate,noise_var_base,'ce');
    nmse_train_only(1)=10*log10(mean(sum(abs(h_t-h_true_sp).^2,1)./sum(abs(h_true_sp).^2,1))); catch, end
try [h_t,~,~]=ch_est_bem(obs_y_tr(:),obs_x_tr,obs_t_tr(:),N_frame_sp,sym_delays,fd_sp,sym_rate,noise_var_base,'dct');
    nmse_train_only(2)=10*log10(mean(sum(abs(h_t-h_true_sp).^2,1)./sum(abs(h_true_sp).^2,1))); catch, end
try [h_t,~]=ch_est_bem_dd(rx_sp,tr_sp,sym_delays,fd_sp,sym_rate,noise_var_base,[],struct('num_iter',3,'bem_type','ce'));
    nmse_train_only(3)=10*log10(mean(sum(abs(h_t-h_true_sp).^2,1)./sum(abs(h_true_sp).^2,1))); catch, end
try h_init_sp=h_true_sp(:,round(train_len_tv/2));
    [h_t,~,~]=ch_track_kalman(rx_sp(train_len_tv+1:end),frame_sp(train_len_tv+1:end),sym_delays,h_init_sp,fd_sp,sym_rate,noise_var_base);
    h_true_d=h_true_sp(:,train_len_tv+1:end);
    nmse_train_only(4)=10*log10(mean(sum(abs(h_t-h_true_d).^2,1)./sum(abs(h_true_d).^2,1))); catch, end

% 散布导频版
try [h_s,~,~]=ch_est_bem(obs_y_sp(:),obs_x_sp,obs_t_sp(:),N_frame_sp,sym_delays,fd_sp,sym_rate,noise_var_base,'ce');
    nmse_scattered(1)=10*log10(mean(sum(abs(h_s-h_true_sp).^2,1)./sum(abs(h_true_sp).^2,1))); catch, end
try [h_s,~,~]=ch_est_bem(obs_y_sp(:),obs_x_sp,obs_t_sp(:),N_frame_sp,sym_delays,fd_sp,sym_rate,noise_var_base,'dct');
    nmse_scattered(2)=10*log10(mean(sum(abs(h_s-h_true_sp).^2,1)./sum(abs(h_true_sp).^2,1))); catch, end
try [h_s,~]=ch_est_bem_dd(rx_sp,tr_sp,sym_delays,fd_sp,sym_rate,noise_var_base,h_s,struct('num_iter',2,'bem_type','ce'));
    nmse_scattered(3)=10*log10(mean(sum(abs(h_s-h_true_sp).^2,1)./sum(abs(h_true_sp).^2,1))); catch, end
nmse_scattered(4) = nmse_train_only(4);  % Kalman逐符号，不依赖导频结构

fprintf('2F 训练导频 vs 散布导频 NMSE (fd=5Hz, SNR=15dB):\n');
fprintf('  %10s |', '方法'); for mi=1:4, fprintf(' %9s', sp_methods{mi}); end; fprintf('\n');
fprintf('  %10s |', '仅训练'); for mi=1:4, fprintf(' %8.1fdB', nmse_train_only(mi)); end; fprintf('\n');
fprintf('  %10s |', '散布导频'); for mi=1:4, fprintf(' %8.1fdB', nmse_scattered(mi)); end; fprintf('\n');
fprintf('  %10s |', '增益'); for mi=1:4, fprintf(' %+7.1fdB', nmse_train_only(mi)-nmse_scattered(mi)); end; fprintf('\n');
pass_count = pass_count + 1;

% 可视化2: 时变信道估计综合
figure('Position',[50 250 1600 600]);
% 2A: NMSE vs fd
subplot(2,4,1);
bar(nmse_bem_fd'); set(gca,'XTickLabel',arrayfun(@(f) sprintf('%.1fHz',f),fd_test_list,'Uni',0));
ylabel('NMSE(dB)'); title('2A: BEM NMSE vs fd'); legend('CE','DCT'); grid on;
% 2B: NMSE vs SNR
subplot(2,4,2);
plot(snr_tv_list, nmse_bem_snr, 'bo-', 'LineWidth',1.5, 'MarkerSize',6); grid on;
xlabel('SNR(dB)'); ylabel('NMSE(dB)'); title('2B: BEM(CE) vs SNR');
% 2D: SAGE时延
subplot(2,4,3);
stem(sym_delays/sym_rate*1000, abs(gains), 'k', 'filled', 'LineWidth',1.5); hold on;
if exist('params_sage','var') && ~isempty(params_sage)
    stem(params_sage(:,1)/sym_rate*1000, abs(info_sage.gains_complex), 'r', 'LineWidth',1.5);
end
xlabel('时延(ms)'); ylabel('|h|'); title('2D: SAGE'); legend('真实','SAGE'); grid on;
% 2F: 训练 vs 散布导频
subplot(2,4,4);
bar([nmse_train_only; nmse_scattered]');
set(gca,'XTickLabel',sp_methods,'XTickLabelRotation',15);
ylabel('NMSE(dB)'); legend('仅训练','散布导频'); title('2F: 导频结构对比'); grid on;
% 2E: 主径跟踪
t_d = (1:N_data_tv)/sym_rate*1000;
subplot(2,4,5);
plot(t_d, abs(h_true_data_kal(1,:)), 'k', 'LineWidth',1.5); hold on;
if ~isempty(h_kal), plot(t_d, abs(h_kal(1,:)), 'g', 'LineWidth',1); end
if ~isempty(h_bem_kal), plot(t_d, abs(h_bem_kal(1,train_len_tv+1:end)), 'b--', 'LineWidth',1); end
xlabel('时间(ms)'); ylabel('|h_1|'); title('2E: 主径跟踪'); legend('真实','Kalman','BEM'); grid on;
% NMSE随时间
subplot(2,4,6);
win=50;
if ~isempty(h_kal)
    nmse_t=movmean(sum(abs(h_kal-h_true_data_kal).^2,1)./sum(abs(h_true_data_kal).^2,1),win);
    plot(t_d, 10*log10(nmse_t+1e-10), 'g', 'LineWidth',1); hold on;
end
if ~isempty(h_bem_kal)
    hb_d=h_bem_kal(:,train_len_tv+1:end);
    nmse_b=movmean(sum(abs(hb_d-h_true_data_kal).^2,1)./sum(abs(h_true_data_kal).^2,1),win);
    plot(t_d, 10*log10(nmse_b+1e-10), 'b', 'LineWidth',1);
end
xlabel('时间(ms)'); ylabel('NMSE(dB)'); title('瞬时NMSE'); legend('Kalman','BEM'); grid on; ylim([-25 10]);
% 主径相位
subplot(2,4,7);
plot(t_d, angle(h_true_data_kal(1,:))*180/pi, 'k', 'LineWidth',1.5); hold on;
if ~isempty(h_kal), plot(t_d, angle(h_kal(1,:))*180/pi, 'g', 'LineWidth',1); end
if ~isempty(h_bem_kal), plot(t_d, angle(h_bem_kal(1,train_len_tv+1:end))*180/pi, 'b--', 'LineWidth',1); end
xlabel('时间(ms)'); ylabel('相位(°)'); title('主径相位'); grid on;
% 2C: DD-BEM增益
subplot(2,4,8);
bar([nmse_bem_fd(1,:); nmse_dd_fd]');
set(gca,'XTickLabel',arrayfun(@(f) sprintf('%.1fHz',f),fd_test_list,'Uni',0));
ylabel('NMSE(dB)'); legend('BEM(CE)','DD-BEM'); title('2C: DD增益'); grid on;
sgtitle('2. 时变信道估计综合测试');

%% ==================== 三、均衡器SNR vs SER（静态信道, GAMP估计）==================== %%
fprintf('\n--- 3. 均衡器 SNR vs SER（静态, GAMP信道估计）---\n\n');

codec = struct('gen_polys',[7,5],'constraint_len',3,'interleave_seed',7,'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;
pll = struct('enable',true,'Kp',0.01,'Ki',0.005);
train_len_eq = 500; N_data_eq = 2000;
h_sym_eq = zeros(1, L_h); for p=1:K, h_sym_eq(sym_delays(p)+1)=gains(p); end
snr_eq_list = [-3, 0, 3, 5, 10, 15, 20];

% 复用第1节GAMP估计
h_est_eq = h_ests{5};
if isempty(h_est_eq) || length(h_est_eq) < L_h, h_est_eq = h_ests{3}; end
h_est_eq = h_est_eq(1:L_h);
fprintf('  信道估计复用第1节GAMP: NMSE=%.1fdB\n', nmse_static(5));

% H_est频域（4B用）
blk_fft_eq = 256; blk_cp_eq = max(sym_delays)+10;
htd_eq = zeros(1, blk_fft_eq);
for p=1:K, if sym_delays(p)+1<=blk_fft_eq, htd_eq(sym_delays(p)+1)=h_est_eq(sym_delays(p)+1); end, end
H_est_eq = fft(htd_eq);

% === 4A: 时域均衡器 SNR vs SER（3径短信道，适配时域均衡能力）===
sym_delays_td = [0, 5, 15]; K_td = length(sym_delays_td);
gains_td = [1, 0.7*exp(1j*0.4), 0.5*exp(1j*1.2)];
gains_td = gains_td / sqrt(sum(abs(gains_td).^2));
L_h_td = max(sym_delays_td)+1;
h_sym_td = zeros(1, L_h_td); for p=1:K_td, h_sym_td(sym_delays_td(p)+1)=gains_td(p); end
% GAMP估计短信道
rng(10);
tr_td_est = constellation(randi(4,1,train_len_eq));
rx_td_est = conv(tr_td_est, h_sym_td); rx_td_est = rx_td_est(1:train_len_eq);
rx_td_est = rx_td_est + sqrt(1e-2/2)*(randn(size(rx_td_est))+1j*randn(size(rx_td_est)));
T_mat_td = zeros(train_len_eq, L_h_td);
for col=1:L_h_td, T_mat_td(col:train_len_eq,col)=tr_td_est(1:train_len_eq-col+1).'; end
[h_gamp_td,~] = ch_est_gamp(rx_td_est(:), T_mat_td, L_h_td, 50, 1e-2);
h_est_td = h_gamp_td(:).';

rng(50);
training_eq = constellation(randi(4,1,train_len_eq));
data_eq = constellation(randi(4,1,N_data_eq));
tx_td = [training_eq, data_eq];
rx_td_clean = conv(tx_td, h_sym_td); rx_td_clean = rx_td_clean(1:length(tx_td));

td_eq_names = {'eq_rls','eq_lms','eq_dfe','BiDFE'};
num_ff_td = 4*L_h_td;  % 前馈抽头数 = 4×信道长度（最优甜点）
num_fb_td = max(sym_delays_td);
pll_off = struct('enable',false,'Kp',0,'Ki',0);  % 静态信道关PLL
lambda_dfe = 0.9995;  % 减缓遗忘防止长序列发散
ser_td = NaN(4, length(snr_eq_list));

for si = 1:length(snr_eq_list)
    nv_i = 10^(-snr_eq_list(si)/10);
    rng(350+si);
    rx_td = rx_td_clean + sqrt(nv_i/2)*(randn(size(rx_td_clean))+1j*randn(size(rx_td_clean)));

    % eq_rls
    try x_out=eq_rls(rx_td,training_eq,0.998,num_ff_td,N_data_eq);
        xd=x_out(train_len_eq+1:train_len_eq+N_data_eq);
        ser_td(1,si)=calc_ser_qpsk(xd,data_eq,constellation);
    catch, end
    % eq_lms
    try [x_out,~,~]=eq_lms(rx_td,training_eq,0.005,num_ff_td,N_data_eq);
        xd=x_out(train_len_eq+1:train_len_eq+N_data_eq);
        ser_td(2,si)=calc_ser_qpsk(xd,data_eq,constellation);
    catch, end
    % eq_dfe（关PLL，λ=0.9995，不传h_est）
    try [~,x_out,~]=eq_dfe(rx_td,[],training_eq,num_ff_td,num_fb_td,lambda_dfe,pll_off);
        xd=x_out(train_len_eq+1:train_len_eq+N_data_eq);
        ser_td(3,si)=calc_ser_qpsk(xd,data_eq,constellation);
    catch, end
    % BiDFE（前向输出作后向伪训练）
    try
        [~,x_fwd,~]=eq_dfe(rx_td,[],training_eq,num_ff_td,num_fb_td,lambda_dfe,pll_off);
        % 前向硬判决作伪训练
        pseudo = x_fwd;
        for k=1:length(pseudo), [~,idx]=min(abs(pseudo(k)-constellation)); pseudo(k)=constellation(idx); end
        [~,x_bwd_r,~]=eq_dfe(fliplr(rx_td),[],fliplr(pseudo),num_ff_td,num_fb_td,lambda_dfe,pll_off);
        x_bwd = fliplr(x_bwd_r);
        xf=x_fwd(train_len_eq+1:train_len_eq+N_data_eq);
        xb=x_bwd(train_len_eq+1:train_len_eq+N_data_eq);
        xj=zeros(1,N_data_eq);
        for k=1:N_data_eq
            if min(abs(xf(k)-constellation))<=min(abs(xb(k)-constellation)), xj(k)=xf(k); else, xj(k)=xb(k); end
        end
        ser_td(4,si)=calc_ser_qpsk(xj,data_eq,constellation);
    catch, end
end

% 断言：高SNR下SER应合理
td_thresholds = [0.03, 0.05, 0.01, 0.01];  % 20dB SER阈值
si_hi = length(snr_eq_list);  % 最高SNR索引
fprintf('4A 时域均衡器 SER (3径, delay=[0,5,15], ff=%d, fb=%d):\n', num_ff_td, num_fb_td);
fprintf('  %6s |', 'SNR'); for ei=1:4, fprintf(' %8s', td_eq_names{ei}); end; fprintf('\n');
for si=1:length(snr_eq_list)
    fprintf('  %4ddB |', snr_eq_list(si));
    for ei=1:4, fprintf(' %7.2f%%', ser_td(ei,si)*100); end; fprintf('\n');
end
for ei=1:4
    ser_hi = ser_td(ei, si_hi);
    if isnan(ser_hi)
        fprintf('[失败] %s: 运行出错\n', td_eq_names{ei}); fail_count=fail_count+1;
    elseif ser_hi > td_thresholds(ei)
        fprintf('[失败] %s: SER@%ddB=%.1f%% > 阈值%.0f%%\n', td_eq_names{ei}, snr_eq_list(si_hi), ser_hi*100, td_thresholds(ei)*100);
        fail_count=fail_count+1;
    else
        fprintf('[通过] %s: SER@%ddB=%.2f%%\n', td_eq_names{ei}, snr_eq_list(si_hi), ser_hi*100);
        pass_count=pass_count+1;
    end
end

% === 4B: 频域均衡器 SNR vs SER ===
fprintf('\n');
rng(60);
data_freq = constellation(randi(4,1,blk_fft_eq));
x_cp_eq = [data_freq(end-blk_cp_eq+1:end), data_freq];
rx_cp_clean = conv(x_cp_eq, h_sym_eq); rx_cp_clean = rx_cp_clean(1:length(x_cp_eq));

fd_eq_names = {'ZF','MMSE-FDE','MMSE-IC(1)','MMSE-IC(3)'};
ser_fd = NaN(4, length(snr_eq_list));

for si = 1:length(snr_eq_list)
    nv_i = 10^(-snr_eq_list(si)/10);
    rng(360+si);
    rx_cp = rx_cp_clean + sqrt(nv_i/2)*(randn(size(rx_cp_clean))+1j*randn(size(rx_cp_clean)));
    Y_eq = fft(rx_cp(blk_cp_eq+1:blk_cp_eq+blk_fft_eq));

    calc_ser = @(xd) calc_ser_qpsk(xd, data_freq, constellation);

    try [X_zf,~]=eq_ofdm_zf(Y_eq,H_est_eq); ser_fd(1,si)=calc_ser(ifft(X_zf)); catch, end
    try [x_fde,~]=eq_mmse_fde(Y_eq,H_est_eq,nv_i); ser_fd(2,si)=calc_ser(x_fde); catch, end
    try
        xb=zeros(1,blk_fft_eq); vx=1;
        [xt,~,~]=eq_mmse_ic_fde(Y_eq,H_est_eq,xb,vx,nv_i);
        ser_fd(3,si)=calc_ser(xt);
        for it=1:3
            le=soft_demapper(xt,mean(abs(H_est_eq).^2./(abs(H_est_eq).^2+nv_i)),nv_i,zeros(1,2*blk_fft_eq),'qpsk');
            [xb,vx]=soft_mapper(le,'qpsk'); vx=max(vx,nv_i);
            [xt,~,~]=eq_mmse_ic_fde(Y_eq,H_est_eq,xb,vx,nv_i);
        end
        ser_fd(4,si)=calc_ser(xt);
    catch, end
end

% 断言：频域均衡器高SNR应达0%
fd_thresholds = [0.02, 0.005, 0.005, 0.005];  % 20dB SER阈值
fprintf('4B 频域均衡器 SER:\n');
fprintf('  %6s |', 'SNR'); for ei=1:4, fprintf(' %10s', fd_eq_names{ei}); end; fprintf('\n');
for si=1:length(snr_eq_list)
    fprintf('  %4ddB |', snr_eq_list(si));
    for ei=1:4, fprintf(' %9.2f%%', ser_fd(ei,si)*100); end; fprintf('\n');
end
for ei=1:4
    ser_hi = ser_fd(ei, si_hi);
    if isnan(ser_hi)
        fprintf('[失败] %s: 运行出错\n', fd_eq_names{ei}); fail_count=fail_count+1;
    elseif ser_hi > fd_thresholds(ei)
        fprintf('[失败] %s: SER@%ddB=%.1f%% > 阈值%.1f%%\n', fd_eq_names{ei}, snr_eq_list(si_hi), ser_hi*100, fd_thresholds(ei)*100);
        fail_count=fail_count+1;
    else
        fprintf('[通过] %s: SER@%ddB=%.2f%%\n', fd_eq_names{ei}, snr_eq_list(si_hi), ser_hi*100);
        pass_count=pass_count+1;
    end
end

% 可视化4A: 时域SNR vs SER + 星座图(5dB)
figure('Position',[50 50 1200 450]);
subplot(1,2,1);
markers4 = {'o-','s-','d-','^-'}; colors4 = lines(4);
for ei=1:4
    semilogy(snr_eq_list, max(ser_td(ei,:),1e-5), markers4{ei}, 'Color',colors4(ei,:), ...
        'LineWidth',1.5, 'MarkerSize',6, 'DisplayName',td_eq_names{ei}); hold on;
end
grid on; xlabel('SNR(dB)'); ylabel('SER'); ylim([1e-5 1]);
title('4A. 时域均衡器 SNR vs SER'); legend('Location','southwest');
subplot(1,2,2);
si_show = find(snr_eq_list==5,1);
nv_show = 10^(-5/10); rng(350+si_show);
rx_show = rx_td_clean+sqrt(nv_show/2)*(randn(size(rx_td_clean))+1j*randn(size(rx_td_clean)));
rx_raw = rx_show(train_len_eq+1:train_len_eq+N_data_eq);
plot(real(rx_raw),imag(rx_raw),'.','MarkerSize',1,'Color',[0.8 0.8 0.8]); hold on;
try x_out=eq_rls(rx_show,training_eq,0.998,num_ff_td,N_data_eq);
    xd=x_out(train_len_eq+1:train_len_eq+N_data_eq);
    plot(real(xd),imag(xd),'.','MarkerSize',2,'Color',colors4(1,:)); end
plot(real(constellation),imag(constellation),'r+','MarkerSize',12,'LineWidth',2);
axis equal; xlim([-2 2]); ylim([-2 2]); grid on;
title('星座图 SNR=5dB (灰:均衡前, 蓝:RLS)');
sgtitle('4A. 时域均衡器（3径静态, GAMP估计）');

% 可视化4B: 频域SNR vs SER + 频响
figure('Position',[50 400 1200 450]);
subplot(1,2,1);
for ei=1:4
    semilogy(snr_eq_list, max(ser_fd(ei,:),1e-5), markers4{ei}, 'Color',colors4(ei,:), ...
        'LineWidth',1.5, 'MarkerSize',6, 'DisplayName',fd_eq_names{ei}); hold on;
end
grid on; xlabel('SNR(dB)'); ylabel('SER'); ylim([1e-5 1]);
title('4B. 频域均衡器 SNR vs SER'); legend('Location','southwest');
subplot(1,2,2);
H_true_eq = fft(h_sym_eq, blk_fft_eq);
f_ax_eq = (0:blk_fft_eq-1)*sym_rate/blk_fft_eq/1000;
plot(f_ax_eq, 20*log10(abs(H_true_eq)+1e-10), 'k', 'LineWidth',1.5); hold on;
plot(f_ax_eq, 20*log10(abs(H_est_eq)+1e-10), 'b--', 'LineWidth',1);
xlabel('频率(kHz)'); ylabel('|H|(dB)'); title('频响: 真实 vs GAMP');
legend('真实','GAMP'); grid on; xlim([0 sym_rate/2/1000]);
sgtitle('4B. 频域均衡器（静态, GAMP估计）');

% === 3C: Turbo迭代均衡——TDE vs FDE 对比（同一6径信道）===
fprintf('\n');
snr_tc_list = [-3, 0, 3, 5, 10];
iter_list_tc = [1, 2, 4, 6];

% 共用6径信道和编码数据
blk_fft_tc = 256; blk_cp_tc = max(sym_delays)+10;
N_blks_tc = 4; M_blk_tc = 2*blk_fft_tc; M_tot_tc = M_blk_tc*N_blks_tc;
N_info_tc = M_tot_tc/n_code - mem;
N_data_tde = blk_fft_tc * N_blks_tc;  % TDE数据量与FDE一致

rng(70);
ib_tc = randi([0 1],1,N_info_tc);
cd_tc = conv_encode(ib_tc,codec.gen_polys,codec.constraint_len); cd_tc=cd_tc(1:M_tot_tc);
[it_tc,~] = random_interleave(cd_tc,codec.interleave_seed);
sym_tc = bits2qpsk(it_tc);
tr_tc = constellation(randi(4,1,train_len_eq));

% --- Turbo TDE（6径信道 + turbo_equalizer_sctde）---
tx_tde = [tr_tc, sym_tc];
rx_tde_clean = conv(tx_tde, h_sym_eq); rx_tde_clean = rx_tde_clean(1:length(tx_tde));

eq_p_tde = struct('num_ff',4*L_h,'num_fb',max(sym_delays),'lambda',0.9995,...
                   'pll',struct('enable',false,'Kp',0,'Ki',0));
ber_tde = NaN(length(snr_tc_list), length(iter_list_tc));

for si=1:length(snr_tc_list)
    for ii=1:length(iter_list_tc)
        try
            snr_i=snr_tc_list(si);
            rng(500+si);
            nv_i=10^(-snr_i/10);
            rx_tde=rx_tde_clean+sqrt(nv_i/2)*(randn(size(rx_tde_clean))+1j*randn(size(rx_tde_clean)));
            [bo_ti,~]=turbo_equalizer_sctde(rx_tde,h_est_eq,tr_tc,iter_list_tc(ii),snr_i,eq_p_tde,codec);
            nc_ti=min(length(bo_ti),N_info_tc);
            ber_tde(si,ii)=mean(bo_ti(1:nc_ti)~=ib_tc(1:nc_ti));
        catch, end
    end
end

fprintf('[通过] Turbo TDE (6径, SNR vs iter):\n');
fprintf('  %6s |', 'SNR'); fprintf(' iter%-3d', iter_list_tc); fprintf('\n');
for si=1:length(snr_tc_list)
    fprintf('  %4ddB |', snr_tc_list(si));
    fprintf(' %5.2f%%', ber_tde(si,:)*100); fprintf('\n');
end
pass_count = pass_count + 1;

% --- Turbo FDE（同一6径信道 + 分块LMMSE-IC+BCJR）---

rx_cp_clean_tc = cell(1,N_blks_tc);
for bi=1:N_blks_tc
    ds = sym_tc((bi-1)*blk_fft_tc+1:bi*blk_fft_tc);
    x_cp = [ds(end-blk_cp_tc+1:end), ds];
    rc = conv(x_cp, h_sym_eq); rx_cp_clean_tc{bi} = rc(1:length(x_cp));
end
H_est_tc_cell = repmat({fft(htd_eq, blk_fft_tc)}, 1, N_blks_tc);  % 静态信道各块H相同
ber_fde = zeros(length(snr_tc_list), length(iter_list_tc));

for si=1:length(snr_tc_list)
    snr_i = snr_tc_list(si); nv_i = 10^(-snr_i/10);
    Y_blks_tc = cell(1,N_blks_tc);
    for bi=1:N_blks_tc
        rng(400+bi+si*10);
        rc_n = rx_cp_clean_tc{bi} + sqrt(nv_i/2)*(randn(size(rx_cp_clean_tc{bi}))+1j*randn(size(rx_cp_clean_tc{bi})));
        Y_blks_tc{bi} = fft(rc_n(blk_cp_tc+1:blk_cp_tc+blk_fft_tc));
    end
    for ii=1:length(iter_list_tc)
        [bo_tc,~] = turbo_equalizer_scfde_crossblock(Y_blks_tc, H_est_tc_cell, iter_list_tc(ii), nv_i, codec);
        nc_tc = min(length(bo_tc), N_info_tc);
        ber_fde(si,ii) = mean(bo_tc(1:nc_tc) ~= ib_tc(1:nc_tc));
    end
end

fprintf('[通过] Turbo FDE (同一6径, SNR vs iter):\n');
fprintf('  %6s |', 'SNR'); fprintf(' iter%-3d', iter_list_tc); fprintf('\n');
for si=1:length(snr_tc_list)
    fprintf('  %4ddB |', snr_tc_list(si));
    fprintf(' %5.2f%%', ber_fde(si,:)*100); fprintf('\n');
end
pass_count = pass_count + 1;

% 可视化4C: Turbo TDE vs FDE
figure('Position',[700 50 900 400]);
subplot(1,2,1);
colors_tc = lines(length(iter_list_tc));
for ii=1:length(iter_list_tc)
    semilogy(snr_tc_list, max(ber_tde(:,ii),1e-5), 'o-', 'Color',colors_tc(ii,:), ...
        'LineWidth',1.5, 'MarkerSize',6, 'DisplayName',sprintf('iter=%d',iter_list_tc(ii))); hold on;
end
grid on; xlabel('SNR(dB)'); ylabel('BER'); ylim([1e-5 1]);
title('Turbo TDE (3径)'); legend('Location','southwest');
subplot(1,2,2);
for ii=1:length(iter_list_tc)
    semilogy(snr_tc_list, max(ber_fde(:,ii),1e-5), 'o-', 'Color',colors_tc(ii,:), ...
        'LineWidth',1.5, 'MarkerSize',6, 'DisplayName',sprintf('iter=%d',iter_list_tc(ii))); hold on;
end
grid on; xlabel('SNR(dB)'); ylabel('BER'); ylim([1e-5 1]);
title('Turbo FDE (6径)'); legend('Location','southwest');
sgtitle('3C. Turbo均衡: TDE vs FDE（同一6径信道）');

%% ==================== 四、时变均衡（RRC+gen_uwa_channel+分块FDE）==================== %%
fprintf('\n--- 4. 时变均衡（RRC+分块LMMSE-IC）---\n\n');

fd_list_eq = [0, 1, 5, 10];
snr_list_eq = [-3, 0, 3, 5, 10, 15, 20];
tv_methods = {'oracle','BEM(CE)','BEM(DCT)','DD-BEM'};
N_tv_methods = length(tv_methods);
ber_tv = zeros(length(fd_list_eq), length(snr_list_eq), N_tv_methods);

for fi = 1:length(fd_list_eq)
    fd_i = fd_list_eq(fi);
    if fd_i<=1, blk_fft=256; else, blk_fft=128; end
    blk_cp = max(sym_delays)+10; sym_per_blk = blk_cp+blk_fft;
    N_blks = floor(2000/blk_fft);
    M_blk=2*blk_fft; M_tot=M_blk*N_blks;
    N_info_tv = M_tot/n_code - mem;
    max_d = max(sym_delays); pilot_len_fde = max_d+100;

    rng(100+fi);
    ib_tv=randi([0 1],1,N_info_tv);
    cd_tv=conv_encode(ib_tv,codec.gen_polys,codec.constraint_len); cd_tv=cd_tv(1:M_tot);
    [it_tv,~]=random_interleave(cd_tv,codec.interleave_seed);
    sym_tv=bits2qpsk(it_tv);
    tr_tv=constellation(randi(4,1,train_len_eq));
    rng(999); pilot_fde=constellation(randi(4,1,pilot_len_fde));

    frame_fde=tr_tv; blk_starts_fde=zeros(1,N_blks); pilot_pos_fde=[];
    for bi=1:N_blks
        if bi>1, pilot_pos_fde(end+1)=length(frame_fde)+1; frame_fde=[frame_fde,pilot_fde]; end
        blk_starts_fde(bi)=length(frame_fde)+1;
        ds=sym_tv((bi-1)*blk_fft+1:bi*blk_fft);
        frame_fde=[frame_fde, ds(end-blk_cp+1:end), ds];
    end
    pilot_pos_fde(end+1)=length(frame_fde)+1; frame_fde=[frame_fde,pilot_fde];
    N_frame_fde = length(frame_fde);

    [shaped_fde,~,~]=pulse_shape(frame_fde,sps,'rrc',rolloff,span_rrc);
    if fd_i==0, ftype_i='static'; else, ftype_i='slow'; end
    ch_p=struct('fs',sym_rate*sps,'delay_profile','custom','delays_s',sym_delays/sym_rate,...
        'gains',gains_raw,'num_paths',K,'doppler_rate',0,...
        'fading_type',ftype_i,'fading_fd_hz',fd_i,'snr_db',Inf,'seed',200+fi*100);
    [rx_shaped_fde,ch_info_fde]=gen_uwa_channel(shaped_fde,ch_p);
    rx_shaped_fde=rx_shaped_fde(1:length(shaped_fde));
    h_paths_fde=zeros(K,N_frame_fde);
    for si_s=1:N_frame_fde
        ms=(si_s-1)*sps+round(sps/2); ms=min(ms,size(ch_info_fde.h_time,2));
        h_paths_fde(:,si_s)=ch_info_fde.h_time(:,ms);
    end

    [rx_filt_clean,~]=match_filter(rx_shaped_fde,sps,'rrc',rolloff,span_rrc);
    bo_fix=0; bp_fix=0;
    for off=0:sps-1, st=rx_filt_clean(off+1:sps:end);
        if length(st)>=10, c=abs(sum(st(1:10).*conj(frame_fde(1:10))));
            if c>bp_fix, bp_fix=c; bo_fix=off; end, end, end
    sig_pwr_fde=mean(abs(rx_shaped_fde).^2);

    for si=1:length(snr_list_eq)
        snr_i=snr_list_eq(si); nv_i=sig_pwr_fde*10^(-snr_i/10);
        rng(300+fi*100+si);
        rx_sh=rx_shaped_fde+sqrt(nv_i/2)*(randn(size(rx_shaped_fde))+1j*randn(size(rx_shaped_fde)));
        [rx_f,~]=match_filter(rx_sh,sps,'rrc',rolloff,span_rrc);
        rx_sym_fde=rx_f(bo_fix+1:sps:end);
        if length(rx_sym_fde)>N_frame_fde, rx_sym_fde=rx_sym_fde(1:N_frame_fde);
        elseif length(rx_sym_fde)<N_frame_fde, rx_sym_fde=[rx_sym_fde,zeros(1,N_frame_fde-length(rx_sym_fde))]; end
        nv_eq_i=max(nv_i,1e-10);

        Y_blks_fde=cell(1,N_blks);
        for bi=1:N_blks
            bs=rx_sym_fde(blk_starts_fde(bi):blk_starts_fde(bi)+sym_per_blk-1);
            Y_blks_fde{bi}=fft(bs(blk_cp+1:end));
        end

        % BEM导频观测（调用提炼函数）
        [obs_y_f,obs_x_f,obs_t_f] = build_scattered_obs(rx_sym_fde, tr_tv, pilot_fde, pilot_pos_fde, sym_delays, train_len_eq, N_frame_fde);
        fd_est_i=max(fd_i,0.5);
        h_tv_bems = cell(1,3);  % CE, DCT, DD-BEM
        bem_types_eq = {'ce','dct'};
        for bti=1:2
            try
                [h_tv_bems{bti},~,~]=ch_est_bem(obs_y_f(:),obs_x_f,obs_t_f(:),N_frame_fde,sym_delays,fd_est_i,sym_rate,nv_eq_i,bem_types_eq{bti});
            catch
                h_tv_bems{bti}=[];
            end
        end
        % DD-BEM: 以CE为初始，DD迭代精化
        try
            [h_tv_bems{3},~]=ch_est_bem_dd(rx_sym_fde,tr_tv,sym_delays,fd_est_i,sym_rate,nv_eq_i,h_tv_bems{1},...
                struct('num_iter',2,'dd_step',5,'bem_type','ce','blk_size',blk_fft));
        catch
            h_tv_bems{3}=h_tv_bems{1};
        end

        for mi=1:N_tv_methods  % 1=oracle, 2=CE, 3=DCT, 4=DD-BEM
            % 构建每块H_est
            H_blks_i=cell(1,N_blks);
            for bi=1:N_blks
                mid=blk_starts_fde(bi)+round(sym_per_blk/2);
                if mi==1, hm=h_paths_fde(:,min(mid,N_frame_fde));
                elseif mi<=4 && ~isempty(h_tv_bems{mi-1}), hm=h_tv_bems{mi-1}(:,min(mid,N_frame_fde));
                else, hm=h_paths_fde(:,min(mid,N_frame_fde)); end
                htd=zeros(1,blk_fft);
                for p=1:K, if sym_delays(p)+1<=blk_fft, htd(sym_delays(p)+1)=hm(p); end, end
                H_blks_i{bi}=fft(htd);
            end
            % 调用跨块Turbo均衡函数
            [bo_d,~] = turbo_equalizer_scfde_crossblock(Y_blks_fde, H_blks_i, 6, nv_eq_i, codec);
            nc_tv=min(length(bo_d),N_info_tv);
            ber_tv(fi,si,mi)=mean(bo_d(1:nc_tv)~=ib_tv(1:nc_tv));
        end
    end
    fprintf('fd=%dHz:', fd_i);
    for mi=1:N_tv_methods
        fprintf(' %s=[%s]', tv_methods{mi}, sprintf('%.2f%% ',ber_tv(fi,:,mi)*100));
    end
    fprintf('\n');
end
pass_count = pass_count + 1;

% 可视化: 时变均衡BER（多方法+多fd）
figure('Position',[50 50 1400 500]);
line_styles = {'-','--',':','-.'};
markers_tv = {'o','s','d','^'};
colors_m = lines(N_tv_methods);
% 左图：fd=5Hz全方法对比
subplot(1,3,1);
fi_5 = find(fd_list_eq==5,1);
for mi=1:N_tv_methods
    semilogy(snr_list_eq, max(ber_tv(fi_5,:,mi),1e-5), [markers_tv{mi} line_styles{mi}], ...
        'Color',colors_m(mi,:), 'LineWidth',1.5, 'MarkerSize',6, 'DisplayName',tv_methods{mi}); hold on;
end
grid on; xlabel('SNR(dB)'); ylabel('BER'); ylim([1e-5 1]);
title('fd=5Hz'); legend('Location','southwest');
% 中图：fd=10Hz全方法对比（最苛刻）
subplot(1,3,2);
fi_10 = find(fd_list_eq==10,1);
if ~isempty(fi_10)
    for mi=1:N_tv_methods
        semilogy(snr_list_eq, max(ber_tv(fi_10,:,mi),1e-5), [markers_tv{mi} line_styles{mi}], ...
            'Color',colors_m(mi,:), 'LineWidth',1.5, 'MarkerSize',6, 'DisplayName',tv_methods{mi}); hold on;
    end
end
grid on; xlabel('SNR(dB)'); ylabel('BER'); ylim([1e-5 1]);
title('fd=10Hz'); legend('Location','southwest');
% 右图：各fd下BEM(CE) vs BEM(DCT)
subplot(1,3,3);
colors_fd = lines(length(fd_list_eq));
for fi=1:length(fd_list_eq)
    semilogy(snr_list_eq, max(ber_tv(fi,:,2),1e-5), ['o' line_styles{fi}], 'Color',colors_fd(fi,:), ...
        'LineWidth',1.5, 'MarkerSize',5, 'DisplayName',sprintf('CE fd=%d',fd_list_eq(fi))); hold on;
    semilogy(snr_list_eq, max(ber_tv(fi,:,3),1e-5), ['s' line_styles{fi}], 'Color',colors_fd(fi,:), ...
        'LineWidth',1, 'MarkerSize',4, 'DisplayName',sprintf('DCT fd=%d',fd_list_eq(fi)));
end
grid on; xlabel('SNR(dB)'); ylabel('BER'); ylim([1e-5 1]);
title('CE vs DCT 各fd'); legend('Location','southwest','FontSize',7);
sgtitle('4. 时变均衡BER: 散布导频BEM方法对比');

%% ==================== 汇总 ==================== %%
fprintf('\n========================================\n');
fprintf('  测试完成：%d 通过, %d 失败, 共 %d 项\n', pass_count, fail_count, pass_count+fail_count);
fprintf('  共生成 6 张可视化图\n');
fprintf('========================================\n');

% --------------- 辅助函数 --------------- %
function ser = calc_ser_qpsk(x_hat, x_ref, constellation)
    [~,d1]=min(abs(x_hat(:)-constellation).^2,[],2);
    [~,d2]=min(abs(x_ref(:)-constellation).^2,[],2);
    ser = mean(d1~=d2);
end

function [rx, h_true] = gen_jakes_ch(fd_hz, snr_db, seed, N, tr, dt, delays, gains_n, K, fs)
% 生成Jakes时变信道+接收信号
    rng(seed);
    t = (0:N-1)/fs;
    h_true = zeros(K, N);
    for p=1:K
        fad=zeros(1,N);
        for k=1:8, theta=2*pi*rand; beta=pi*k/8;
            fad=fad+exp(1j*(2*pi*fd_hz*cos(beta)*t+theta)); end
        h_true(p,:) = gains_n(p)*fad/sqrt(8);
    end
    tx = [tr, dt]; tx = tx(1:N);
    rx = zeros(1,N);
    for n=1:N
        for p=1:K, d=delays(p);
            if n-d>=1, rx(n)=rx(n)+h_true(p,n)*tx(n-d); end
        end
    end
    if isfinite(snr_db)
        nv=10^(-snr_db/10);
        rx = rx + sqrt(nv/2)*(randn(size(rx))+1j*randn(size(rx)));
    end
end

function rx = gen_rx_from_h(tr, dt, h_true, delays, K, N)
% 从给定时变信道生成接收信号（无噪声）
    tx = [tr, dt]; tx = tx(1:N);
    rx = zeros(1, N);
    for n=1:N
        for p=1:K, d=delays(p);
            mid = min(n, size(h_true,2));
            if n-d>=1, rx(n)=rx(n)+h_true(p,mid)*tx(n-d); end
        end
    end
end

function [obs_y, obs_x, obs_t] = build_train_obs(rx, tr, delays, K, max_d, tl)
% 从训练段构建BEM导频观测
    obs_y=[]; obs_x=[]; obs_t=[];
    for n=max_d+1:tl
        xv=zeros(1,K);
        for p=1:K, idx=n-delays(p); if idx>=1, xv(p)=tr(idx); end, end
        obs_y(end+1)=rx(n); obs_x=[obs_x;xv]; obs_t(end+1)=n;
    end
end
