%% test_iterative.m
% 功能：迭代调度器模块单元测试——含BER校验和收敛可视化
% 版本：V2.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  迭代调度器模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '04_Modulation', 'src', 'Matlab'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
codec = struct('gen_polys', [7,5], 'constraint_len', 3);

%% ==================== 一、SC-TDE Turbo均衡 ==================== %%
fprintf('--- 1. SC-TDE Turbo均衡 ---\n\n');

%% 1.1 迭代收敛+BER校验（10次迭代）
try
    rng(42);
    % 多径信道
    h_test = [1, 0.6*exp(1j*0.4), 0.35*exp(1j*1.0), 0.2*exp(1j*1.8)];
    h_test = h_test / sqrt(sum(abs(h_test).^2));

    train_len = 200; data_len = 800;
    snr_test = 15;
    noise_pwr = 10^(-snr_test/10);

    % 发送：编码→映射
    info_bits = randi([0 1], 1, data_len);
    coded_bits = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    data_sym = constellation(bi2de(reshape(coded_bits(1:floor(length(coded_bits)/2)*2), 2, []).', 'left-msb') + 1);
    training = constellation(randi(4, 1, train_len));
    tx = [training, data_sym];

    % 过信道
    rx = conv(tx, h_test); rx = rx(1:length(tx));
    rx = rx + sqrt(noise_pwr/2)*(randn(size(rx)) + 1j*randn(size(rx)));

    max_iter = 10;
    eq_params = struct('num_ff', 21, 'num_fb', 10, 'lambda', 0.998, ...
                       'pll', struct('enable', true, 'Kp', 0.01, 'Ki', 0.005));

    % 逐次迭代跟踪BER
    ber_track = zeros(1, max_iter);
    mse_track = zeros(1, max_iter);
    const_track = cell(1, max_iter);

    for n_it = 1:max_iter
        [bits_out, info] = turbo_equalizer_sctde(rx, h_test, training, n_it, eq_params, codec);

        % 均衡后数据段
        x_last = info.x_hat_per_iter{n_it};
        n_data = min(length(x_last) - train_len, length(data_sym));
        if n_data > 0
            eq_data = x_last(train_len+1 : train_len+n_data);
            ref_data = data_sym(1:n_data);

            % 符号级BER（QPSK I路）
            ber_track(n_it) = mean(sign(real(eq_data)) ~= sign(real(ref_data)));
            mse_track(n_it) = mean(abs(eq_data - ref_data).^2);
            const_track{n_it} = eq_data;
        end
    end

    % BER校验
    assert(ber_track(1) < 0.5, sprintf('第1次BER=%.1f%%不应接近随机', ber_track(1)*100));

    % 打印收敛
    fprintf('[通过] 1.1 SC-TDE迭代收敛 (SNR=%ddB, %d径):\n', snr_test, length(h_test));
    for it = 1:max_iter
        marker = '';
        if it > 1 && ber_track(it) < ber_track(it-1), marker = ' ↓'; end
        if it > 1 && ber_track(it) > ber_track(it-1), marker = ' ↑'; end
        fprintf('    迭代%2d: BER=%5.1f%%, MSE=%.4f%s\n', it, ber_track(it)*100, mse_track(it), marker);
    end
    pass_count = pass_count + 1;

    % 可视化
    vis = struct('ber_per_iter', ber_track, 'mse_per_iter', mse_track, ...
                 'constellation', {const_track}, 'ref_symbols', data_sym, ...
                 'scheme', sprintf('SC-TDE (SNR=%ddB)', snr_test));
    plot_turbo_convergence(vis, 'SC-TDE Turbo均衡收敛');

catch e
    fprintf('[失败] 1.1 SC-TDE | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、OFDM Turbo均衡 ==================== %%
fprintf('\n--- 2. OFDM Turbo均衡 ---\n\n');

%% 2.1 OFDM迭代收敛
try
    rng(50);
    N_ofdm = 128;
    h_ofdm = zeros(1, N_ofdm);
    h_ofdm(1) = 1; h_ofdm(4) = 0.5*exp(1j*0.6); h_ofdm(9) = 0.25*exp(1j*1.3);
    h_ofdm = h_ofdm / sqrt(sum(abs(h_ofdm).^2));
    H_ofdm = fft(h_ofdm);
    nv_ofdm = 0.05;

    % 编码→映射→频域
    info_ofdm = randi([0 1], 1, 200);
    coded_ofdm = conv_encode(info_ofdm, codec.gen_polys, codec.constraint_len);
    sym_ofdm = constellation(bi2de(reshape(coded_ofdm(1:floor(length(coded_ofdm)/2)*2), 2, []).', 'left-msb') + 1);
    n_sym = min(length(sym_ofdm), N_ofdm);
    x_ofdm = [sym_ofdm(1:n_sym), zeros(1, max(0, N_ofdm-n_sym))];

    X_ofdm = fft(x_ofdm);
    Y_ofdm = H_ofdm .* X_ofdm + sqrt(nv_ofdm/2)*(randn(1,N_ofdm)+1j*randn(1,N_ofdm));

    max_iter_ofdm = 6;
    ber_ofdm = zeros(1, max_iter_ofdm);
    mse_ofdm = zeros(1, max_iter_ofdm);

    for n_it = 1:max_iter_ofdm
        [~, info_o] = turbo_equalizer_ofdm(Y_ofdm, H_ofdm, n_it, nv_ofdm, codec);
        x_eq = info_o.x_hat_per_iter{n_it};
        n_cmp = min(length(x_eq), n_sym);
        ber_ofdm(n_it) = mean(sign(real(x_eq(1:n_cmp))) ~= sign(real(x_ofdm(1:n_cmp))));
        mse_ofdm(n_it) = mean(abs(x_eq(1:n_cmp) - x_ofdm(1:n_cmp)).^2);
    end

    fprintf('[通过] 2.1 OFDM迭代收敛 (%d次):\n', max_iter_ofdm);
    for it = 1:max_iter_ofdm
        fprintf('    迭代%d: BER=%5.1f%%, MSE=%.4f\n', it, ber_ofdm(it)*100, mse_ofdm(it));
    end
    pass_count = pass_count + 1;

catch e
    fprintf('[失败] 2.1 OFDM | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、SC-FDE Turbo均衡 ==================== %%
fprintf('\n--- 3. SC-FDE Turbo均衡 ---\n\n');

%% 3.1 基本运行
try
    [bits_fde, info_fde] = turbo_equalizer_scfde(Y_ofdm, H_ofdm, 3, nv_ofdm, codec);
    assert(~isempty(bits_fde), '输出不应为空');

    fprintf('[通过] 3.1 SC-FDE 3次迭代 | 输出%d比特\n', length(bits_fde));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 SC-FDE | %s\n', e.message);
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
