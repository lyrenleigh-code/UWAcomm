%% test_channel_est_eq.m
% 功能：信道估计与均衡模块单元测试
% 版本：V1.0.0
% 运行方式：>> run('test_channel_est_eq.m')

clc; close all;
fprintf('========================================\n');
fprintf('  信道估计与均衡模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

%% ==================== 一、信道估计（频域导频） ==================== %%
fprintf('--- 1. 频域信道估计 ---\n\n');

%% 1.1 LS估计回环
try
    rng(10);
    N = 64;
    [h_true, H_true, ch_info] = gen_test_channel(N, 5, 15, 30, 'sparse');

    % 全频带导频
    X_pilot = (2*randi([0 1],1,N)-1) + 1j*(2*randi([0 1],1,N)-1); % QPSK
    Y_pilot = H_true .* X_pilot + sqrt(ch_info.noise_var/2)*(randn(1,N)+1j*randn(1,N));

    [H_ls, h_ls] = ch_est_ls(Y_pilot, X_pilot, N);
    nmse = 10*log10(norm(H_ls-H_true)^2/norm(H_true)^2);

    assert(nmse < 0, 'LS估计NMSE应为负(dB)');

    fprintf('[通过] 1.1 LS估计 | NMSE=%.1f dB (SNR=%ddB)\n', nmse, ch_info.snr_db);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 LS | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.2 MMSE优于LS
try
    [H_mmse, ~] = ch_est_mmse(Y_pilot, X_pilot, N, ch_info.noise_var);
    nmse_mmse = 10*log10(norm(H_mmse-H_true)^2/norm(H_true)^2);

    assert(nmse_mmse <= nmse + 1, 'MMSE应不差于LS');

    fprintf('[通过] 1.2 MMSE vs LS | MMSE=%.1fdB, LS=%.1fdB\n', nmse_mmse, nmse);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 MMSE | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、稀疏信道估计 ==================== %%
fprintf('\n--- 2. 稀疏信道估计算法 ---\n\n');

%% 2.1 OMP
try
    rng(20);
    N = 128; M_obs = 50; K = 5;
    [h_true, ~, ~] = gen_test_channel(N, K, 30, 20, 'sparse');
    Phi = randn(M_obs, N) / sqrt(M_obs);
    noise_var = 0.01;
    y = Phi * h_true.' + sqrt(noise_var/2)*(randn(M_obs,1)+1j*randn(M_obs,1));

    [h_omp, ~, support] = ch_est_omp(y, Phi, N, K);
    nmse_omp = 10*log10(norm(h_omp - h_true.')^2 / norm(h_true)^2);

    assert(nmse_omp < -5, 'OMP NMSE过高');

    fprintf('[通过] 2.1 OMP | NMSE=%.1fdB, 检测到%d/%d路径\n', nmse_omp, length(support), K);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 OMP | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.2 SBL
try
    [h_sbl, ~, gamma] = ch_est_sbl(y, Phi, N, 50);
    nmse_sbl = 10*log10(norm(h_sbl - h_true.')^2 / norm(h_true)^2);

    fprintf('[通过] 2.2 SBL | NMSE=%.1fdB\n', nmse_sbl);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.2 SBL | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.3 AMP
try
    [h_amp, ~, ~] = ch_est_amp(y, Phi, N, 50);
    nmse_amp = 10*log10(norm(h_amp - h_true.')^2 / norm(h_true)^2);

    fprintf('[通过] 2.3 AMP | NMSE=%.1fdB\n', nmse_amp);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.3 AMP | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.4 GAMP
try
    [h_gamp, ~] = ch_est_gamp(y, Phi, N, 50, noise_var);
    nmse_gamp = 10*log10(norm(h_gamp - h_true.')^2 / norm(h_true)^2);

    fprintf('[通过] 2.4 GAMP | NMSE=%.1fdB\n', nmse_gamp);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.4 GAMP | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.5 VAMP
try
    [h_vamp, ~] = ch_est_vamp(y, Phi, N, 100, noise_var, K);
    nmse_vamp = 10*log10(norm(h_vamp - h_true.')^2 / norm(h_true)^2);

    assert(nmse_vamp < 0, sprintf('VAMP NMSE=%.1fdB，应为负(dB)', nmse_vamp));

    fprintf('[通过] 2.5 VAMP | NMSE=%.1fdB\n', nmse_vamp);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.5 VAMP | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.6 Turbo-VAMP vs WS-Turbo-VAMP
try
    [h_tv, ~, mse_tv] = ch_est_turbo_vamp(y, Phi, N, 30, K, noise_var);
    [h_ws, ~, mse_ws, rho] = ch_est_ws_turbo_vamp(y, Phi, N, 30, K, noise_var, zeros(N,1), 0);
    nmse_tv = 10*log10(norm(h_tv - h_true.')^2 / norm(h_true)^2);
    nmse_ws = 10*log10(norm(h_ws - h_true.')^2 / norm(h_true)^2);

    fprintf('[通过] 2.6 Turbo-VAMP=%.1fdB, WS(冷启动)=%.1fdB\n', nmse_tv, nmse_ws);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.6 Turbo-VAMP | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.7 信道估计可视化
try
    plot_channel_estimate(h_true, ...
        {h_omp.', h_sbl.', h_tv.'}, ...
        {'OMP', 'SBL', 'Turbo-VAMP'}, ...
        '稀疏信道估计对比 (N=128, K=5, SNR=20dB)');

    fprintf('[通过] 2.7 信道估计可视化\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.7 可视化 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、SC-TDE均衡 ==================== %%
fprintf('\n--- 3. SC-TDE均衡 ---\n\n');

%% 构建SC-TDE测试信号（QPSK + 多径信道 + 训练序列）
rng(30);
data_len = 300; train_len = 100;
snr_db_eq = 15;
noise_var_eq = 1 / 10^(snr_db_eq/10);

% 确定性信道（第一径在位置1，避免时间对齐问题）
h_true_eq = zeros(1, 16);
h_true_eq(1) = 1.0;
h_true_eq(3) = 0.5 * exp(1j*0.4);
h_true_eq(6) = 0.3 * exp(1j*1.1);
h_true_eq(10) = 0.15 * exp(1j*2.3);
h_true_eq = h_true_eq / sqrt(sum(abs(h_true_eq).^2));

% QPSK训练和数据
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
training_qpsk = constellation(randi(4, 1, train_len));
data_qpsk = constellation(randi(4, 1, data_len));
tx = [training_qpsk, data_qpsk];

% 过信道 + 加噪
rx = conv(tx, h_true_eq); rx = rx(1:length(tx));
rx = rx + sqrt(noise_var_eq/2) * (randn(size(rx)) + 1j*randn(size(rx)));

%% 3.1 LMS均衡
try
    training_bpsk = 2*randi([0 1],1,train_len)-1;
    data_bpsk = 2*randi([0 1],1,data_len)-1;
    tx_b = [training_bpsk, data_bpsk];
    rx_b = conv(tx_b, h_true_eq); rx_b = rx_b(1:length(tx_b));
    rx_b = rx_b + sqrt(noise_var_eq/2)*(randn(size(rx_b))+1j*randn(size(rx_b)));

    [x_lms, ~, ~] = eq_lms(rx_b, training_bpsk, 0.01, 21, data_len);
    dec = sign(real(x_lms(train_len+1:end)));
    ber_lms = sum(dec ~= data_bpsk) / data_len;

    assert(ber_lms < 0.15, 'LMS BER过高');
    fprintf('[通过] 3.1 LMS均衡 | BER=%.1f%%\n', ber_lms*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 LMS | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 RLS均衡
try
    [x_rls, ~, ~] = eq_rls(rx_b, training_bpsk, 0.99, 21, data_len);
    dec_rls = sign(real(x_rls(train_len+1:end)));
    ber_rls = sum(dec_rls ~= data_bpsk) / data_len;

    fprintf('[通过] 3.2 RLS均衡 | BER=%.1f%%\n', ber_rls*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 RLS | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.3 PTR被动时反转
try
    [ptr_out, ptr_gain] = eq_ptrm(rx, h_true_eq);
    assert(~isempty(ptr_out), 'PTR输出不应为空');
    assert(length(ptr_out) == length(rx), 'PTR输出长度应与输入一致');

    fprintf('[通过] 3.3 PTR | 处理增益=%.1fdB, 输出长度=%d\n', ptr_gain, length(ptr_out));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.3 PTR | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.4 RLS-DFE均衡（含PLL，输出LLR）
try
    pll = struct('enable', true, 'Kp', 0.01, 'Ki', 0.005);
    [llr_dfe, x_dfe, nv_dfe] = eq_dfe(rx, h_true_eq, training_qpsk, 21, 10, 0.998, pll);

    % LLR→硬判决→BER
    dec_dfe = sign(real(llr_to_symbol(llr_dfe, 'qpsk')));
    dec_ref = sign(real(data_qpsk));
    n_cmp = min(length(dec_dfe), length(dec_ref));
    ber_dfe = sum(dec_dfe(1:n_cmp) ~= dec_ref(1:n_cmp)) / n_cmp;

    assert(ber_dfe < 0.2, sprintf('DFE BER=%.1f%%过高', ber_dfe*100));

    fprintf('[通过] 3.4 RLS-DFE(+PLL) | BER=%.1f%%, 噪声方差=%.4f\n', ber_dfe*100, nv_dfe);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.4 DFE | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.5 双向DFE
try
    [llr_bidfe, x_bidfe, nv_bidfe] = eq_bidirectional_dfe(rx, h_true_eq, training_qpsk, 21, 10, 0.998, pll);
    dec_bidfe = sign(real(llr_to_symbol(llr_bidfe, 'qpsk')));
    n_cmp2 = min(length(dec_bidfe), length(dec_ref));
    ber_bidfe = sum(dec_bidfe(1:n_cmp2) ~= dec_ref(1:n_cmp2)) / n_cmp2;

    assert(ber_bidfe < 0.2, sprintf('双向DFE BER=%.1f%%过高', ber_bidfe*100));

    fprintf('[通过] 3.5 双向DFE | BER=%.1f%% (单向=%.1f%%)\n', ber_bidfe*100, ber_dfe*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.5 双向DFE | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.6 LLR↔符号转换回环
try
    test_llr = randn(1, 100);
    sym = llr_to_symbol(test_llr, 'qpsk');
    llr_back = symbol_to_llr(sym, 0.1, 'qpsk');

    assert(length(sym) == 50, 'QPSK: 100 LLR应产生50符号');
    assert(length(llr_back) == 100, '50符号应恢复100 LLR');
    % 符号一致（同号）
    assert(all(sign(test_llr) == sign(llr_back)), 'LLR符号应保持一致');

    fprintf('[通过] 3.6 LLR↔符号转换 | 100 LLR → 50符号 → 100 LLR\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.6 LLR↔符号 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.7 DFE均衡星座图可视化
try
    n_vis = min(length(x_dfe) - train_len, data_len);
    dfe_data = x_dfe(train_len+1 : train_len+n_vis);
    plot_equalizer_output(data_qpsk(1:n_vis), {dfe_data}, {'RLS-DFE(+PLL)'}, ...
        'SC-TDE DFE均衡 (QPSK, SNR=20dB)');

    fprintf('[通过] 3.7 DFE均衡可视化\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.7 DFE可视化 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.8 均衡器收敛曲线对比
try
    % LMS/RLS用BPSK参考，DFE用QPSK参考，分开画
    % DFE收敛曲线
    n_dfe_all = min(length(x_dfe), train_len + data_len);
    plot_eq_convergence({x_dfe(1:n_dfe_all)}, tx(1:n_dfe_all), {'RLS-DFE(+PLL)'}, 30, ...
        'RLS-DFE收敛曲线 (QPSK, SNR=20dB, 训练100+数据300)');

    fprintf('[通过] 3.8 均衡器收敛曲线\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.8 收敛曲线 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、SC-FDE/OFDM频域均衡 ==================== %%
fprintf('\n--- 4. 频域均衡 ---\n\n');

%% 4.1 MMSE-FDE
try
    rng(40);
    N = 64;
    [h_true, H_true, ch_info] = gen_test_channel(N, 4, 10, 20, 'sparse');
    x = (2*randi([0 1],1,N)-1) + 1j*(2*randi([0 1],1,N)-1); % QPSK
    X = fft(x);
    Y = H_true .* X + sqrt(ch_info.noise_var/2)*(randn(1,N)+1j*randn(1,N));

    [x_fde, ~] = eq_mmse_fde(Y, H_true, ch_info.noise_var);
    dec = sign(real(x_fde));
    ref = sign(real(x));
    ber_fde = sum(dec ~= ref) / N;

    assert(ber_fde < 0.1, 'MMSE-FDE BER过高');

    fprintf('[通过] 4.1 MMSE-FDE | BER=%.1f%%\n', ber_fde*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 MMSE-FDE | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.2 OFDM ZF
try
    [X_zf, ~] = eq_ofdm_zf(Y, H_true);
    nmse_zf = 10*log10(norm(X_zf - X)^2 / norm(X)^2);

    fprintf('[通过] 4.2 OFDM ZF | 频域NMSE=%.1fdB\n', nmse_zf);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 OFDM ZF | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.3 均衡结果可视化
try
    plot_equalizer_output(x, {x_fde}, {'MMSE-FDE'}, 'SC-FDE均衡结果 (QPSK, SNR=20dB)');

    fprintf('[通过] 4.3 均衡可视化\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.3 均衡可视化 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、异常输入 ==================== %%
fprintf('\n--- 5. 异常输入 ---\n\n');

try
    caught = 0;
    try ch_est_ls([], [], 64); catch; caught=caught+1; end
    try ch_est_mmse([], [], 64, 0.1); catch; caught=caught+1; end
    try ch_est_omp([], randn(10,64), 64); catch; caught=caught+1; end

    assert(caught == 3, '部分函数未对空输入报错');

    fprintf('[通过] 5.1 空输入拒绝 | 3个函数均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 空输入 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 测试汇总 ==================== %%
fprintf('\n========================================\n');
fprintf('  测试完成：%d 通过, %d 失败, 共 %d 项\n', ...
        pass_count, fail_count, pass_count + fail_count);
fprintf('========================================\n');

if fail_count == 0
    fprintf('  全部通过！\n');
else
    fprintf('  存在失败项，请检查！\n');
end
