function [start_idx, peak_val, corr_out] = sync_detect(received, preamble, threshold)
% 功能：粗同步检测——匹配滤波寻找前导码起始位置
% 版本：V1.0.0
% 输入：
%   received  - 接收信号 (1xM 实数/复数数组)
%   preamble  - 前导码（参考信号，由gen_lfm/gen_hfm/gen_zc_seq/gen_barker生成）
%   threshold - 检测门限 (0~1，归一化相关峰值门限，默认 0.5)
% 输出：
%   start_idx - 检测到的前导起始位置索引 (标量，0表示未检测到)
%   peak_val  - 归一化相关峰值 (0~1)
%   corr_out  - 完整的归一化相关输出 (1x(M-L+1) 数组)
%
% 备注：
%   - 滑动窗口归一化互相关：消除幅度变化影响
%   - 归一化峰值接近1表示高置信度检测
%   - 多个峰超过门限时返回最大峰位置

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(threshold), threshold = 0.5; end
received = received(:).';
preamble = preamble(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(received), error('接收信号不能为空！'); end
if isempty(preamble), error('前导码不能为空！'); end
L = length(preamble);
M = length(received);
if L > M, error('前导码长度(%d)大于接收信号长度(%d)！', L, M); end

%% ========== 3. 滑动窗口归一化互相关 ========== %%
num_corr = M - L + 1;
corr_out = zeros(1, num_corr);

preamble_energy = sum(abs(preamble).^2);

for n = 1:num_corr
    segment = received(n : n+L-1);
    segment_energy = sum(abs(segment).^2);

    if segment_energy < 1e-20
        corr_out(n) = 0;
    else
        corr_out(n) = abs(sum(segment .* conj(preamble))) / ...
                      sqrt(segment_energy * preamble_energy);
    end
end

%% ========== 4. 峰值检测 ========== %%
[peak_val, peak_pos] = max(corr_out);

if peak_val >= threshold
    start_idx = peak_pos;
else
    start_idx = 0;                     % 未超过门限
    warning('同步检测未超过门限(峰值=%.3f, 门限=%.3f)！', peak_val, threshold);
end

end
