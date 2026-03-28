function [x_hat, mse] = eq_dfe(y, h_est, num_ff, num_fb, noise_var)
% 功能：DFE判决反馈均衡器（SC-TDE专用）
% 版本：V1.0.0
% 输入：
%   y         - 接收信号 (1xN)
%   h_est     - 时域信道估计 (1xL)
%   num_ff    - 前馈滤波器阶数 (默认 2*L)
%   num_fb    - 反馈滤波器阶数 (默认 L-1)
%   noise_var - 噪声方差 (默认 0.01)
% 输出：
%   x_hat - 均衡后的符号估计 (1xN)
%   mse   - 均方误差（若有参考信号）

%% ========== 入参 ========== %%
y = y(:).'; h_est = h_est(:).';
L = length(h_est);
if nargin < 5 || isempty(noise_var), noise_var = 0.01; end
if nargin < 4 || isempty(num_fb), num_fb = L - 1; end
if nargin < 3 || isempty(num_ff), num_ff = 2 * L; end
N = length(y);

%% ========== MMSE-DFE滤波器设计 ========== %%
% 信道卷积矩阵
H_mat = toeplitz([h_est(:); zeros(num_ff-1, 1)], [h_est(1); zeros(num_ff-1, 1)]);
H_ff = H_mat(1:num_ff+L-1, 1:num_ff);

% 自相关矩阵
Ryy = H_ff * H_ff' + noise_var * eye(num_ff+L-1);

% 前馈滤波器（取第一个符号的MMSE解）
delay = floor(num_ff/2);
p = H_ff(:, min(delay+1, size(H_ff,2)));
w_ff = Ryy \ p;

%% ========== 逐符号DFE均衡 ========== %%
x_hat = zeros(1, N);
pad_len = num_ff + L;
y_padded = [zeros(1, pad_len), y, zeros(1, pad_len)];
decisions = zeros(1, N);

for n = 1:N
    % 前馈部分
    y_seg = y_padded(n : n+num_ff+L-2);
    if length(y_seg) < length(w_ff)
        y_seg = [y_seg, zeros(1, length(w_ff)-length(y_seg))];
    end
    ff_out = w_ff' * y_seg(1:length(w_ff)).';

    % 反馈部分（减去已判决符号的ISI）
    fb_out = 0;
    for k = 1:min(num_fb, n-1)
        if k < L
            fb_out = fb_out + h_est(k+1) * decisions(n-k);
        end
    end

    x_hat(n) = ff_out - fb_out;
    decisions(n) = sign(real(x_hat(n)));  % BPSK硬判决
end

mse = mean(abs(x_hat).^2);

end
