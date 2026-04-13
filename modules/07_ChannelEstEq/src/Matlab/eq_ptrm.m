function [output, gain] = eq_ptrm(received, channel_est)
% 功能：PTR被动时反转——多通道匹配滤波空间聚焦
% 版本：V1.0.0 — 参考Turbo Equalization工程实现
% 输入：
%   received     - 多通道接收信号 (KxN 矩阵，K=通道数，N=信号长度)
%                  单通道时为 1xN
%   channel_est  - 多通道信道估计 (KxL 矩阵)
% 输出：
%   output - PTR输出（聚焦后的单路信号，1xN）
%   gain   - PTR处理增益 (dB)
%
% 备注：
%   - PTR原理：每通道与时间反转共轭的信道做匹配滤波，然后多通道求和
%   - output = sum_k conv(received_k, fliplr(conj(h_k)))
%   - 等效于在发端聚焦，空间分集增益约 10*log10(K) dB
%   - 单通道时退化为匹配滤波器
%   - 级联DFE可消除残余ISI

%% ========== 入参 ========== %%
if isvector(received)
    received = received(:).';
    K = 1;
else
    K = size(received, 1);
end
if isvector(channel_est)
    channel_est = channel_est(:).';
end

%% ========== 参数校验 ========== %%
if isempty(received), error('接收信号不能为空！'); end
if size(received, 1) ~= size(channel_est, 1)
    error('通道数不匹配：接收%d通道，信道%d通道！', size(received,1), size(channel_est,1));
end

N = size(received, 2);

%% ========== 多通道匹配滤波+求和 ========== %%
output = zeros(1, N);
power_before = 0;
power_after = 0;

for k = 1:K
    % 匹配滤波：与时间反转共轭信道卷积
    h_matched = fliplr(conj(channel_est(k, :)));
    conv_result = conv(received(k, :), h_matched);

    % 截取与输入等长的中心部分
    L = length(channel_est(k, :));
    start_idx = floor(L/2) + 1;
    end_idx = start_idx + N - 1;
    if end_idx > length(conv_result)
        conv_result = [conv_result, zeros(1, end_idx - length(conv_result))]; %#ok<AGROW>
    end

    output = output + conv_result(start_idx : end_idx);
    power_before = power_before + mean(abs(received(k,:)).^2);
end

% 归一化
output = output / max(abs(output));

% 处理增益估计
power_after = mean(abs(output).^2);
if power_before > 0
    gain = 10 * log10(K);             % 理论增益 = 通道数
else
    gain = 0;
end

end
