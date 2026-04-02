function [blk_fft, fd_est, T_coherence] = adaptive_block_len(rx_signal, pilot, fs, fc, blk_range)
% 功能：自适应块长选择——从接收信号估计多普勒扩展fd，计算最优块长
% 版本：V1.0.0
% 输入：
%   rx_signal  - 接收信号（含前后导频）(1×N)
%   pilot      - 导频序列 (1×L)
%   fs         - 采样率 (Hz)
%   fc         - 载波频率 (Hz)
%   blk_range  - 允许块长范围 [min, max]（默认 [32, 1024]）
% 输出：
%   blk_fft     - 推荐FFT块长（2的幂）
%   fd_est      - 估计的最大多普勒频移 (Hz)
%   T_coherence - 估计的信道相干时间 (秒)
%
% 原理：
%   1. 用导频互相关找到两个导频位置
%   2. 提取两处信道估计，计算信道变化率 → fd
%   3. 相干时间 T_c ≈ 1/(4·fd)
%   4. 块长 = T_c · sym_rate / 4（块时长≈25%相干时间，保守选择）
%   5. 取2的幂次对齐

%% ========== 入参 ========== %%
if nargin < 5 || isempty(blk_range), blk_range = [32, 1024]; end
rx_signal = rx_signal(:).';
pilot = pilot(:).';
L = length(pilot);

%% ========== 1. 找两个导频位置 ========== %%
% 滑窗互相关找前导频
corr1 = zeros(1, length(rx_signal)-L+1);
for k = 1:length(corr1)
    corr1(k) = abs(sum(rx_signal(k:k+L-1) .* conj(pilot)));
end
[~, idx1] = max(corr1);

% 在idx1之后搜索后导频（至少跳过半个信号长度）
search_start = idx1 + round(length(rx_signal)*0.3);
search_end = min(length(rx_signal)-L+1, length(rx_signal));
if search_start < search_end
    corr2 = zeros(1, search_end-search_start+1);
    for k = search_start:search_end
        corr2(k-search_start+1) = abs(sum(rx_signal(k:k+L-1) .* conj(pilot)));
    end
    [~, local_idx2] = max(corr2);
    idx2 = search_start + local_idx2 - 1;
else
    idx2 = idx1;
end

%% ========== 2. 估计信道变化率 ========== %%
if idx2 > idx1 + L
    % 两处导频位置的信道估计（简化：互相关峰值的相位变化率）
    R1 = sum(rx_signal(idx1:idx1+L-1) .* conj(pilot));
    R2 = sum(rx_signal(idx2:idx2+L-1) .* conj(pilot));

    % 两个时刻间的信道变化
    delta_t = (idx2 - idx1) / fs;  % 时间间隔
    phase_change = abs(angle(R2 * conj(R1)));  % 相位变化量

    % 信道变化率 → 多普勒频移估计
    % 相位变化 ≈ 2π·fd·delta_t (Jake模型下的近似)
    fd_est = phase_change / (2*pi*delta_t);
    fd_est = max(fd_est, 0.1);  % 最小0.1Hz（近似静态）

    % 功率变化也可以反映fd（补充估计）
    power_ratio = abs(R2)/abs(R1);
    if abs(power_ratio - 1) > 0.3  % 功率变化>30%，说明衰落显著
        fd_est = max(fd_est, 1/delta_t);  % 至少1个衰落周期
    end
else
    fd_est = 0.1;  % 找不到两个导频，假设近似静态
end

%% ========== 3. 计算相干时间和推荐块长 ========== %%
T_coherence = 1 / (4 * fd_est);  % Jake模型相干时间

% 块时长 = T_c/4 (保守：块内信道变化<25%)
sym_rate = fs / 8;  % 假设sps=8
blk_time = T_coherence / 4;
blk_raw = round(blk_time * sym_rate);

% 对齐到2的幂
blk_fft = 2^round(log2(blk_raw));
blk_fft = max(blk_fft, blk_range(1));
blk_fft = min(blk_fft, blk_range(2));

end
