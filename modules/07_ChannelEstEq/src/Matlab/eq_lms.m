function [x_hat, w_final, mse_history] = eq_lms(y, training, mu, num_taps, data_len)
% 功能：LMS自适应均衡器（SC-TDE专用）
% 版本：V1.0.0
% 输入：
%   y         - 接收信号 (1xN，训练段+数据段)
%   training  - 训练序列 (1xL，已知符号)
%   mu        - 步长 (默认 0.01)
%   num_taps  - 滤波器阶数 (默认 21)
%   data_len  - 数据段长度 (默认 N-L)
% 输出：
%   x_hat       - 均衡后符号 (1x(L+data_len))
%   w_final     - 收敛后的滤波器系数
%   mse_history - 训练阶段MSE历史

%% ========== 入参 ========== %%
y = y(:).'; training = training(:).';
L = length(training);
N = length(y);
if nargin < 5 || isempty(data_len), data_len = N - L; end
if nargin < 4 || isempty(num_taps), num_taps = 21; end
if nargin < 3 || isempty(mu), mu = 0.01; end

%% ========== LMS均衡 ========== %%
w = zeros(num_taps, 1);
delay = floor(num_taps / 2);
total_len = L + data_len;
x_hat = zeros(1, total_len);
mse_history = zeros(1, L);

y_padded = [zeros(1, delay), y, zeros(1, num_taps)];

for n = 1:total_len
    % 输入向量
    y_vec = y_padded(n : n+num_taps-1).';

    % 滤波器输出
    x_hat(n) = w' * y_vec;

    % 误差
    if n <= L
        % 训练模式：用已知符号
        e = training(n) - x_hat(n);
        mse_history(n) = abs(e)^2;
    else
        % 判决引导模式（QPSK最近星座点）
        d = (sign(real(x_hat(n))) + 1j*sign(imag(x_hat(n)))) / sqrt(2);
        e = d - x_hat(n);
    end

    % 权重更新
    w = w + mu * conj(e) * y_vec;
end

w_final = w;

end
