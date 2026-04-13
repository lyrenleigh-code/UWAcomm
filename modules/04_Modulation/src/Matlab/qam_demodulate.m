function [bits, LLR] = qam_demodulate(symbols, M, mapping, noise_var)
% 功能：QAM/PSK符号判决，支持硬判决和软判决(LLR)
% 版本：V1.0.0
% 输入：
%   symbols   - 接收符号序列 (1xL 复数数组)
%   M         - 调制阶数 (2/4/8/16/64)
%   mapping   - 映射方式 (字符串，'gray'(默认) 或 'natural')
%   noise_var - 噪声方差 sigma^2 (正实数，可选)
%               若提供则计算软判决LLR，否则LLR输出为空
% 输出：
%   bits - 硬判决比特序列 (1x(L*log2(M)) 数组)
%   LLR  - 软判决对数似然比 (1x(L*log2(M)) 数组)
%          正值→比特1更可能，负值→比特0更可能
%          未提供noise_var时为空 []
%
% 备注：
%   - 硬判决：最小欧氏距离判决，选择最近星座点
%   - 软判决：Max-Log-MAP近似
%     LLR_k = (1/sigma^2)(min_{s:b_k=0}|y-s|^2 - min_{s:b_k=1}|y-s|^2)
%   - 星座图和映射必须与调制端一致

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 4
    noise_var = [];
end
if nargin < 3 || isempty(mapping)
    mapping = 'gray';
end
symbols = symbols(:).';
bps = log2(M);                         % 每符号比特数

%% ========== 2. 严格参数校验 ========== %%
if isempty(symbols)
    error('输入符号不能为空！');
end
if ~ismember(M, [2, 4, 8, 16, 64])
    error('调制阶数M必须为 2/4/8/16/64！');
end
if ~isempty(noise_var) && noise_var <= 0
    error('噪声方差必须为正数！');
end

%% ========== 3. 生成参考星座图 ========== %%
[constellation, bit_map] = generate_constellation_demod(M, mapping);

%% ========== 4. 硬判决 ========== %%
num_symbols = length(symbols);
bits = zeros(1, num_symbols * bps);

for s = 1:num_symbols
    % 计算到所有星座点的距离
    distances = abs(symbols(s) - constellation).^2;
    [~, min_idx] = min(distances);
    bits((s-1)*bps+1 : s*bps) = bit_map(min_idx, :);
end

%% ========== 5. 软判决 (LLR) ========== %%
if isempty(noise_var)
    LLR = [];
    return;
end

LLR = zeros(1, num_symbols * bps);

for s = 1:num_symbols
    distances = abs(symbols(s) - constellation).^2;

    for k = 1:bps
        bit_col = bit_map(:, k);

        % 比特k=0的星座点集合
        idx_0 = (bit_col == 0);
        min_dist_0 = min(distances(idx_0));

        % 比特k=1的星座点集合
        idx_1 = (bit_col == 1);
        min_dist_1 = min(distances(idx_1));

        % Max-Log-MAP LLR: 正值→bit 1
        llr_idx = (s-1)*bps + k;
        LLR(llr_idx) = (min_dist_0 - min_dist_1) / noise_var;
    end
end

end

% --------------- 辅助函数：生成星座图（与调制端一致） --------------- %
function [constellation, bit_map] = generate_constellation_demod(M, mapping)
% 复用qam_modulate中的星座生成逻辑
% 调用qam_modulate生成参考星座
dummy_bits = zeros(1, log2(M));
[~, constellation, bit_map] = qam_modulate(dummy_bits, M, mapping);
end
