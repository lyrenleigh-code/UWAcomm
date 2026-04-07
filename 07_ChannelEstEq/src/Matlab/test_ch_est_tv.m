%% test_ch_est_tv.m — 时变信道估计性能独立评价
% 纯信道估计NMSE对比（不含均衡/译码）
% 用已知符号驱动（消除判决误差影响）
% 版本：V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  时变信道估计 NMSE 独立评价\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));

%% ========== 参数 ========== %%
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

rng(42);
training = constellation(randi(4,1,train_len));
data_sym = constellation(randi(4,1,data_len));
tx = [training, data_sym];
pilot_sym = constellation(randi(4,1,pilot_len));

fd_list = [0.5, 1, 2, 5];
methods = {'固定(TVAMP)', 'BEM(Q自适应)', 'Kalman(已知x)', 'Kalman(训练后预测)'};

fprintf('SNR=%ddB, 训练=%d, 数据=%d, 导频=%d/段\n', snr_db, train_len, data_len, pilot_len);
fprintf('信道: 6径, max_delay=90sym\n\n');

figure('Position',[50 100 1200 800]);

for fi = 1:length(fd_list)
    fd_hz = fd_list(fi);

    % Jakes时变信道
    rng(200+fi);
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

    % 接收信号
    rx = zeros(1, N_total);
    for n = 1:N_total
        for p = 1:K
            d = sym_delays(p);
            if n-d >= 1, rx(n) = rx(n) + h_true(p,n) * tx(n-d); end
        end
    end
    noise_var = mean(abs(rx).^2) * 10^(-snr_db/10);
    rng(300+fi);
    rx = rx + sqrt(noise_var/2)*(randn(size(rx))+1j*randn(size(rx)));

    % === 方法1: Turbo-VAMP（训练段固定）===
    T_mat = zeros(train_len, L_h);
    for col=1:L_h, T_mat(col:train_len,col)=training(1:train_len-col+1).'; end
    [h_tvamp,~,~,~] = ch_est_turbo_vamp(rx(1:train_len)', T_mat, L_h, 30, K, noise_var);
    h_tvamp_paths = h_tvamp(sym_delays+1);  % K×1

    h_est_fixed = repmat(h_tvamp_paths(:), 1, data_len);  % 固定不变

    % === 方法2: BEM（训练+散布导频）===
    % 构建带导频的帧（用于BEM观测）
    % 导频位置：每256符号插入一段
    pilot_interval = 256;
    n_pilots = floor(data_len / pilot_interval);
    pilot_pos_in_data = (1:n_pilots) * pilot_interval;  % 在数据段内的位置

    T_frame = N_total / sym_rate;
    Q_bem = max(5, 2*ceil(fd_hz * T_frame) + 3);
    q_range = -(Q_bem-1)/2 : (Q_bem-1)/2;

    % 观测：训练段
    obs_y = []; obs_x = []; obs_n = [];
    for n = 1:train_len
        x_vec = zeros(1, K);
        for p=1:K
            idx = n-sym_delays(p);
            if idx>=1, x_vec(p)=training(idx); end
        end
        if any(x_vec~=0)
            obs_y(end+1) = rx(n);
            obs_x = [obs_x; x_vec];
            obs_n(end+1) = n;
        end
    end
    % 观测：数据段中的"已知符号"位置（模拟导频）
    for pi = 1:n_pilots
        pp = train_len + pilot_pos_in_data(pi);
        for kk = max(1,pp-pilot_len/2+1):min(N_total, pp+pilot_len/2)
            x_vec = zeros(1, K);
            for p=1:K
                idx = kk-sym_delays(p);
                if idx>=1 && idx<=N_total, x_vec(p)=tx(idx); end
            end
            if any(x_vec~=0)
                obs_y(end+1) = rx(kk);
                obs_x = [obs_x; x_vec];
                obs_n(end+1) = kk;
            end
        end
    end
    % BEM LS
    N_obs = length(obs_y);
    Phi = zeros(N_obs, K*Q_bem);
    for ii=1:N_obs
        n=obs_n(ii);
        for p=1:K
            for qi=1:Q_bem
                q=q_range(qi);
                Phi(ii,(p-1)*Q_bem+qi) = obs_x(ii,p)*exp(1j*2*pi*q*n/N_total);
            end
        end
    end
    c_bem = (Phi'*Phi + noise_var*eye(size(Phi,2))) \ (Phi'*obs_y(:));
    % 重构每个数据符号时刻的信道
    h_est_bem = zeros(K, data_len);
    for n = 1:data_len
        nn = train_len + n;
        for p=1:K
            for qi=1:Q_bem
                q=q_range(qi);
                h_est_bem(p,n) = h_est_bem(p,n) + c_bem((p-1)*Q_bem+qi)*exp(1j*2*pi*q*nn/N_total);
            end
        end
    end

    % === 方法3: Kalman（已知x驱动）===
    alpha_ar = besselj(0, 2*pi*fd_hz/sym_rate);
    q_proc = max((1-alpha_ar^2)*mean(abs(h_tvamp_paths).^2), 1e-8);
    hk = h_tvamp_paths(:);
    Pk = q_proc*10*eye(K);
    h_est_kalman = zeros(K, data_len);
    for n = 1:data_len
        nn = train_len + n;
        hk_p = alpha_ar * hk;
        Pk_p = alpha_ar^2*Pk + q_proc*eye(K);
        phi = zeros(K,1);
        for p=1:K
            idx = nn-sym_delays(p);
            if idx>=1 && idx<=N_total, phi(p)=tx(idx); end  % 已知符号！
        end
        inn = rx(nn) - phi'*hk_p;
        S = phi'*Pk_p*phi + noise_var;
        Kg = Pk_p*phi/S;
        hk = hk_p + Kg*inn;
        Pk = (eye(K)-Kg*phi')*Pk_p;
        h_est_kalman(:,n) = hk;
    end

    % === 方法4: Kalman（训练后纯预测，不更新）===
    h_est_predict = zeros(K, data_len);
    hk_pred = h_tvamp_paths(:);
    for n = 1:data_len
        hk_pred = alpha_ar * hk_pred;
        h_est_predict(:,n) = hk_pred;
    end

    % === NMSE计算（逐符号）===
    h_true_data = h_true(:, train_len+1:train_len+data_len);
    nmse_fixed = zeros(1, data_len);
    nmse_bem = zeros(1, data_len);
    nmse_kalman = zeros(1, data_len);
    nmse_predict = zeros(1, data_len);
    for n = 1:data_len
        ref_pwr = sum(abs(h_true_data(:,n)).^2);
        nmse_fixed(n) = sum(abs(h_est_fixed(:,n)-h_true_data(:,n)).^2) / ref_pwr;
        nmse_bem(n) = sum(abs(h_est_bem(:,n)-h_true_data(:,n)).^2) / ref_pwr;
        nmse_kalman(n) = sum(abs(h_est_kalman(:,n)-h_true_data(:,n)).^2) / ref_pwr;
        nmse_predict(n) = sum(abs(h_est_predict(:,n)-h_true_data(:,n)).^2) / ref_pwr;
    end

    % 打印平均NMSE
    fprintf('fd=%.1fHz: Q_bem=%d | 固定=%.1fdB | BEM=%.1fdB | Kalman(已知x)=%.1fdB | 纯预测=%.1fdB\n', ...
        fd_hz, Q_bem, ...
        10*log10(mean(nmse_fixed)), 10*log10(mean(nmse_bem)), ...
        10*log10(mean(nmse_kalman)), 10*log10(mean(nmse_predict)));

    % 可视化：NMSE随时间变化
    subplot(2, length(fd_list), fi);
    t_data = (1:data_len)/sym_rate*1000;
    plot(t_data, 10*log10(movmean(nmse_fixed,50)+1e-10), 'r', 'LineWidth',1); hold on;
    plot(t_data, 10*log10(movmean(nmse_bem,50)+1e-10), 'b', 'LineWidth',1.5);
    plot(t_data, 10*log10(movmean(nmse_kalman,50)+1e-10), 'g', 'LineWidth',1.5);
    plot(t_data, 10*log10(movmean(nmse_predict,50)+1e-10), 'm--', 'LineWidth',1);
    xlabel('时间(ms)'); ylabel('NMSE(dB)'); grid on;
    title(sprintf('fd=%.1fHz', fd_hz));
    legend('固定(TVAMP)','BEM','Kalman(已知x)','纯预测','Location','best');
    ylim([-30 5]);

    % 可视化：主径幅度跟踪
    subplot(2, length(fd_list), length(fd_list)+fi);
    plot(t_data, abs(h_true_data(1,:)), 'k', 'LineWidth',1.5); hold on;
    plot(t_data, abs(h_est_fixed(1,:)), 'r--', 'LineWidth',1);
    plot(t_data, abs(h_est_bem(1,:)), 'b', 'LineWidth',1);
    plot(t_data, abs(h_est_kalman(1,:)), 'g', 'LineWidth',1);
    xlabel('时间(ms)'); ylabel('|h_1|');
    title(sprintf('fd=%.1fHz 主径跟踪', fd_hz));
    legend('真实','固定','BEM','Kalman','Location','best'); grid on;
end

sgtitle(sprintf('时变信道估计NMSE对比 (SNR=%ddB, 6径, 训练=%d)', snr_db, train_len));
fprintf('\n完成\n');
