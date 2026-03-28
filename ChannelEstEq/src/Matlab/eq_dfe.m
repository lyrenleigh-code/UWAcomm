function [x_hat, decisions] = eq_dfe(y, h_est, num_ff, num_fb, noise_var)
% 功能：MMSE-DFE判决反馈均衡器（SC-TDE专用）
% 版本：V2.0.0
% 输入：
%   y         - 接收信号 (1xN)
%   h_est     - 时域信道估计 (1xL，第1个抽头为主径)
%   num_ff    - 前馈滤波器阶数 (默认 2*L+1)
%   num_fb    - 反馈滤波器阶数 (默认 L)
%   noise_var - 噪声方差 (默认 0.01)
% 输出：
%   x_hat     - 均衡后的软符号估计 (1xN)
%   decisions - 硬判决结果 (1xN，±1)
%
% 备注：
%   - 前馈滤波器：MMSE准则设计，同时考虑ISI消除和噪声抑制
%   - 反馈滤波器：利用已判决符号消除因果ISI
%   - 联合MMSE设计：[w_ff; w_fb] = R^{-1} * p

%% ========== 入参 ========== %%
y = y(:).'; h_est = h_est(:).';
L = length(find(h_est ~= 0));         % 有效信道长度
L_full = length(h_est);
if nargin < 5 || isempty(noise_var), noise_var = 0.01; end
if nargin < 4 || isempty(num_fb), num_fb = L_full; end
if nargin < 3 || isempty(num_ff), num_ff = 2*L_full + 1; end
N = length(y);

%% ========== 频域MMSE前馈滤波器设计 ========== %%
% 在频域设计前馈滤波器更稳定
Nfft = max(2^nextpow2(num_ff + L_full), 64);
H = fft(h_est, Nfft);

% MMSE前馈滤波器频率响应
W_ff_freq = conj(H) ./ (abs(H).^2 + noise_var);

% 转时域并截取
w_ff_full = ifft(W_ff_freq);
w_ff = w_ff_full(1:num_ff);

% 前馈滤波器输出的信道响应（用于计算反馈滤波器）
% c = conv(w_ff, h) 的因果部分以外的抽头就是反馈滤波器系数
c = conv(w_ff, h_est);

%% ========== 逐符号DFE均衡 ========== %%
x_hat = zeros(1, N);
decisions = zeros(1, N);

% 前馈滤波：整体卷积
y_filtered = conv(y, w_ff, 'same');

for n = 1:N
    % 前馈输出
    ff_out = y_filtered(n);

    % 反馈部分：减去已判决符号的因果ISI
    fb_out = 0;
    for k = 1:min(num_fb, n-1)
        if k+1 <= length(c)
            fb_out = fb_out + c(k+1) * decisions(n-k);
        end
    end

    x_hat(n) = ff_out - fb_out;
    decisions(n) = sign(real(x_hat(n)));
    if decisions(n) == 0, decisions(n) = 1; end
end

end
