%% test_iterative.m
% 功能：迭代调度器模块单元测试
% 版本：V1.0.0
% 运行方式：>> run('test_iterative.m')

clc; close all;
fprintf('========================================\n');
fprintf('  迭代调度器模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

% 添加依赖
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '04_Modulation', 'src', 'Matlab'));

%% ==================== 一、SC-TDE Turbo均衡 ==================== %%
fprintf('--- 1. SC-TDE Turbo均衡 ---\n\n');

%% 1.1 基本运行（1次迭代=无Turbo基线）
try
    rng(10);
    % 简单信道
    h = [1, 0.5*exp(1j*0.3), 0.2*exp(1j*1.1)];
    train_len = 100; data_len = 200;
    constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);

    training = constellation(randi(4, 1, train_len));
    data = constellation(randi(4, 1, data_len));
    tx = [training, data];

    rx = conv(tx, h); rx = rx(1:length(tx));
    rx = rx + 0.1*(randn(size(rx))+1j*randn(size(rx)));

    [bits_1, info_1] = turbo_equalizer_sctde(rx, h, training, 1);

    assert(~isempty(bits_1), '输出比特不应为空');
    assert(info_1.num_iter == 1, '迭代次数应为1');

    fprintf('[通过] 1.1 SC-TDE 1次迭代 | 输出%d比特\n', length(bits_1));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 SC-TDE 1次 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.2 多次迭代
try
    [bits_3, info_3] = turbo_equalizer_sctde(rx, h, training, 3);

    assert(info_3.num_iter == 3, '迭代次数应为3');
    assert(length(info_3.llr_per_iter) == 3, '应有3次LLR记录');

    fprintf('[通过] 1.2 SC-TDE 3次迭代 | 输出%d比特\n', length(bits_3));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 SC-TDE 3次 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.3 SC-TDE迭代收敛可视化（6次迭代，跟踪BER/MSE/星座图）
try
    rng(15);
    % 更强的信道（更多ISI）
    h_strong = [1, 0.7*exp(1j*0.4), 0.5*exp(1j*0.9), 0.3*exp(1j*1.5), 0.15*exp(1j*2.1)];
    h_strong = h_strong / sqrt(sum(abs(h_strong).^2));

    train_len2 = 150; data_len2 = 500;
    training2 = constellation(randi(4, 1, train_len2));
    data2 = constellation(randi(4, 1, data_len2));
    data2_bits_I = real(data2) > 0;    % QPSK I路比特
    tx2 = [training2, data2];

    snr_test = 12;                     % 12dB——中等SNR，迭代增益明显
    noise_power = 10^(-snr_test/10);
    rx2 = conv(tx2, h_strong); rx2 = rx2(1:length(tx2));
    rx2 = rx2 + sqrt(noise_power/2)*(randn(size(rx2))+1j*randn(size(rx2)));

    max_turbo_iter = 6;
    [~, info_6] = turbo_equalizer_sctde(rx2, h_strong, training2, max_turbo_iter);

    % 计算每次迭代的BER和MSE
    ber_track = zeros(1, max_turbo_iter);
    mse_track = zeros(1, max_turbo_iter);
    const_track = cell(1, max_turbo_iter);

    for it = 1:max_turbo_iter
        x_it = info_6.x_hat_per_iter{it};
        % 取数据段
        n_data = min(length(x_it) - train_len2, data_len2);
        if n_data > 0
            eq_data = x_it(train_len2+1 : train_len2+n_data);
            ref_data = data2(1:n_data);

            % BER（QPSK I路）
            dec_I = real(eq_data) > 0;
            ref_I = real(ref_data) > 0;
            ber_track(it) = sum(dec_I ~= ref_I) / n_data;

            % MSE
            mse_track(it) = mean(abs(eq_data - ref_data).^2);

            const_track{it} = eq_data;
        else
            ber_track(it) = 0.5;
            mse_track(it) = 1;
            const_track{it} = [];
        end
    end

    % 可视化
    vis_results = struct();
    vis_results.ber_per_iter = ber_track;
    vis_results.mse_per_iter = mse_track;
    vis_results.constellation = const_track;
    vis_results.ref_symbols = data2;
    vis_results.scheme = sprintf('SC-TDE (SNR=%ddB, %d径信道)', snr_test, length(h_strong));

    plot_turbo_convergence(vis_results, 'SC-TDE Turbo均衡收敛');

    % 打印收敛过程
    fprintf('[通过] 1.3 SC-TDE迭代收敛 (%d次):\n', max_turbo_iter);
    for it = 1:max_turbo_iter
        fprintf('    迭代%d: BER=%.2f%%, MSE=%.4f (%.1fdB)\n', ...
                it, ber_track(it)*100, mse_track(it), 10*log10(mse_track(it)+1e-30));
    end
    if ber_track(end) < ber_track(1)
        fprintf('    → 迭代增益: BER从%.1f%%降至%.1f%%\n', ber_track(1)*100, ber_track(end)*100);
    end
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.3 收敛可视化 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、SC-FDE Turbo均衡 ==================== %%
fprintf('\n--- 2. SC-FDE Turbo均衡 ---\n\n');

%% 2.1 基本运行
try
    rng(20);
    N_fde = 64;
    h_fde = zeros(1, N_fde);
    h_fde(1) = 1; h_fde(3) = 0.4*exp(1j*0.5); h_fde(7) = 0.2*exp(1j*1.2);
    H_fde = fft(h_fde);
    noise_var_fde = 0.05;

    x_fde = constellation(randi(4, 1, N_fde));
    X_fde = fft(x_fde);
    Y_fde = H_fde .* X_fde + sqrt(noise_var_fde/2)*(randn(1,N_fde)+1j*randn(1,N_fde));

    [bits_fde, info_fde] = turbo_equalizer_scfde(Y_fde, H_fde, 2, noise_var_fde);

    assert(~isempty(bits_fde), '输出不应为空');
    assert(info_fde.num_iter == 2, '迭代次数应为2');

    fprintf('[通过] 2.1 SC-FDE 2次迭代 | 输出%d比特\n', length(bits_fde));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 SC-FDE | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、OTFS Turbo均衡 ==================== %%
fprintf('\n--- 3. OTFS Turbo均衡 ---\n\n');

%% 3.1 基本运行
try
    rng(30);
    N_otfs = 4; M_otfs = 16;

    % 简单DD域数据
    dd_data = constellation(randi(4, N_otfs, M_otfs));

    % 简单信道（1条路径=无ISI）
    h_dd = zeros(N_otfs, M_otfs);
    h_dd(1,1) = 1;
    path_info = struct('num_paths', 1, 'delay_idx', 0, 'doppler_idx', 0, 'gain', 1);

    Y_dd = dd_data;                    % 无信道畸变
    noise_var_otfs = 0.05;
    Y_dd = Y_dd + sqrt(noise_var_otfs/2)*(randn(size(Y_dd))+1j*randn(size(Y_dd)));

    [bits_otfs, info_otfs] = turbo_equalizer_otfs(Y_dd, h_dd, path_info, N_otfs, M_otfs, 2, noise_var_otfs);

    assert(~isempty(bits_otfs), '输出不应为空');

    fprintf('[通过] 3.1 OTFS 2次迭代 | 输出%d比特\n', length(bits_otfs));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 OTFS | %s\n', e.message);
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
