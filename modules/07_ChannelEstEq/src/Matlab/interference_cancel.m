function y_clean = interference_cancel(y, soft_symbols, channel_est)
% 功能：干扰消除——从接收信号中减去已知/估计的干扰分量
% 版本：V1.0.0
% 输入：
%   y            - 接收信号 (1xN 或 KxN 多通道)
%   soft_symbols - 干扰源的软符号估计 (1xM)
%   channel_est  - 干扰源的信道估计 (1xL 或 KxL 多通道)
% 输出：
%   y_clean - 干扰消除后的信号（与y同尺寸）
%
% 备注：
%   - 干扰重构：interference = conv(soft_symbols, channel_est)
%   - 从接收信号减去重构干扰
%   - 在Turbo迭代中用于：
%     1. 多用户干扰消除（减去其他用户的信号）
%     2. 软干扰消除（减去数据的先验估计，保留新息）

%% ========== 入参 ========== %%
soft_symbols = soft_symbols(:).';

if isvector(y)
    y = y(:).';
    K = 1;
else
    K = size(y, 1);
end

if isvector(channel_est)
    channel_est = channel_est(:).';
end

N = size(y, 2);

%% ========== 干扰重构与消除 ========== %%
y_clean = y;

for k = 1:K
    interference = conv(soft_symbols, channel_est(min(k, size(channel_est,1)), :));
    interference = interference(1:min(N, length(interference)));
    if length(interference) < N
        interference = [interference, zeros(1, N - length(interference))]; %#ok<AGROW>
    end
    y_clean(k, :) = y(k, :) - interference;
end

end
