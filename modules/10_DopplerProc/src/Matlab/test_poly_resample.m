%% test_poly_resample.m
% 单元测试：poly_resample 正确性 + 与 MATLAB resample 等价性 + 自逆
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

fprintf('========================================\n');
fprintf('  poly_resample 单元测试\n');
fprintf('========================================\n\n');

rng(42);

%% Test 1：p=q=1 identity
x = randn(1, 1000) + 1j*randn(1, 1000);
y = poly_resample(x, 1, 1);
err = max(abs(y - x));
fprintf('[Test 1] p=q=1 identity: max|err| = %.3e  %s\n', err, ...
        tern(err < 1e-12, 'PASS', 'FAIL'));

%% Test 2：self-inverse (poly_resample x2 with inverse factors)
fprintf('\n[Test 2] self-inverse 测试（长度 4096 复数随机）\n');
fprintf('%-10s | %-10s | %-10s | %-s\n', 'p/q', 'len round', 'NMSE (dB)', '判定');
fprintf('%s\n', repmat('-', 1, 55));

N = 4096;
x = randn(1, N) + 1j*randn(1, N);
ratios = [101 100; 103 100; 1017 1000; 51 50; 1015 1000];
for k = 1:size(ratios, 1)
    p = ratios(k,1); q = ratios(k,2);
    y = poly_resample(x, p, q);
    x_back = poly_resample(y, q, p);
    L_cmp = min(length(x), length(x_back));
    edge = round(0.1 * L_cmp);
    err = x(edge+1:L_cmp-edge) - x_back(edge+1:L_cmp-edge);
    sig = x(edge+1:L_cmp-edge);
    nmse = 10*log10(mean(abs(err).^2) / mean(abs(sig).^2));
    fprintf('%-10s | %-10d | %-+10.2f | %s\n', ...
            sprintf('%d/%d', p, q), length(y), nmse, tern(nmse < -60, 'PASS', 'FAIL'));
end

%% Test 3：vs MATLAB resample（相同 p/q 下输出应高度一致）
fprintf('\n[Test 3] 与 MATLAB resample 对比（NMSE vs. MATLAB 输出）\n');
fprintf('%-10s | %-12s | %-12s | %-s\n', 'p/q', 'ours len', 'matlab len', 'NMSE (dB)');
fprintf('%s\n', repmat('-', 1, 55));

for k = 1:size(ratios, 1)
    p = ratios(k,1); q = ratios(k,2);
    y_ours = poly_resample(x, p, q);
    y_mat  = resample(x, p, q);
    L_cmp = min(length(y_ours), length(y_mat));
    edge = round(0.1 * L_cmp);
    err = y_ours(edge+1:L_cmp-edge) - y_mat(edge+1:L_cmp-edge);
    sig = y_mat(edge+1:L_cmp-edge);
    nmse = 10*log10(mean(abs(err).^2) / (mean(abs(sig).^2)+eps));
    fprintf('%-10s | %-12d | %-12d | %-+.2f\n', ...
            sprintf('%d/%d', p, q), length(y_ours), length(y_mat), nmse);
end

%% Test 4：带限信号（窄带 QPSK 类似）self-inverse 应近完美
fprintf('\n[Test 4] 带限信号 self-inverse（sym_rate=6000, fs=48000）\n');
fs = 48000; sym_rate = 6000; sps = fs/sym_rate;
N_sym = 1024;
syms = (2*randi([0 1], 1, N_sym)-1) + 1j*(2*randi([0 1], 1, N_sym)-1);
syms = syms / sqrt(2);
x_bl = kron(syms, ones(1, sps));
h_lp = fir1(64, sym_rate/fs);
x_bl = conv(x_bl, h_lp, 'same');

fprintf('%-10s | %-10s | %-s\n', 'p/q', 'NMSE (dB)', '判定');
fprintf('%s\n', repmat('-', 1, 38));
for k = 1:size(ratios, 1)
    p = ratios(k,1); q = ratios(k,2);
    y = poly_resample(x_bl, p, q);
    x_back = poly_resample(y, q, p);
    L_cmp = min(length(x_bl), length(x_back));
    edge = round(0.1 * L_cmp);
    err = x_bl(edge+1:L_cmp-edge) - x_back(edge+1:L_cmp-edge);
    sig = x_bl(edge+1:L_cmp-edge);
    nmse = 10*log10(mean(abs(err).^2) / mean(abs(sig).^2));
    fprintf('%-10s | %-+10.2f | %s\n', ...
            sprintf('%d/%d', p, q), nmse, tern(nmse < -80, 'PASS', 'FAIL'));
end

fprintf('\n========================================\n');
fprintf('  完成\n');
fprintf('========================================\n');

function s = tern(cond, t, f)
    if cond, s = t; else, s = f; end
end
