function [x_hat, w_final, mse_history] = eq_rls(y, training, lambda, num_taps, data_len)
% 功能：RLS自适应均衡器（SC-TDE专用，收敛快于LMS）
% 版本：V1.0.0
% 输入：
%   y         - 接收信号 (1xN)
%   training  - 训练序列 (1xL)
%   lambda    - 遗忘因子 (0<lambda<=1，默认 0.99)
%   num_taps  - 滤波器阶数 (默认 21)
%   data_len  - 数据段长度 (默认 N-L)
% 输出：
%   x_hat, w_final, mse_history

%% ========== 入参 ========== %%
y = y(:).'; training = training(:).';
L = length(training);
N = length(y);
if nargin < 5 || isempty(data_len), data_len = N - L; end
if nargin < 4 || isempty(num_taps), num_taps = 21; end
if nargin < 3 || isempty(lambda), lambda = 0.99; end

%% ========== RLS均衡 ========== %%
delta = 0.01;
P = eye(num_taps) / delta;            % 逆相关矩阵
w = zeros(num_taps, 1);
delay = floor(num_taps / 2);
total_len = L + data_len;
x_hat = zeros(1, total_len);
mse_history = zeros(1, L);

y_padded = [zeros(1, delay), y, zeros(1, num_taps)];

for n = 1:total_len
    y_vec = y_padded(n : n+num_taps-1).';

    % 滤波器输出
    x_hat(n) = w' * y_vec;

    % 误差
    if n <= L
        e = training(n) - x_hat(n);
        mse_history(n) = abs(e)^2;
    else
        e = sign(real(x_hat(n))) - x_hat(n);
    end

    % RLS更新
    k = (P * y_vec) / (lambda + y_vec' * P * y_vec);
    w = w + k * conj(e);
    P = (P - k * y_vec' * P) / lambda;
end

w_final = w;

end
