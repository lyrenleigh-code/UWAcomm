function [data_symbols, pilot_rx, pilot_indices, data_indices] = ofdm_pilot_extract(freq_symbols, N, pilot_pattern)
% 功能：OFDM频域导频提取——分离导频和数据子载波
% 版本：V1.0.0
% 输入：
%   freq_symbols  - 含导频的频域符号 (1xL 数组，L为N的整数倍)
%   N             - 子载波总数
%   pilot_pattern - 导频模式（须与插入端一致）
% 输出：
%   data_symbols   - 数据子载波符号 (1xM 数组)
%   pilot_rx       - 接收到的导频值 (num_symbols x num_pilots 矩阵)
%   pilot_indices  - 导频子载波索引
%   data_indices   - 数据子载波索引

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(pilot_pattern), pilot_pattern = 'comb_4'; end
freq_symbols = freq_symbols(:).';

%% ========== 2. 确定导频和数据位置 ========== %%
is_scattered = false;
scattered_spacing = 0;
scattered_shift = 0;

if ischar(pilot_pattern) || isstring(pilot_pattern)
    switch pilot_pattern
        case 'comb_4'
            pilot_indices = 1:4:N;
        case 'comb_8'
            pilot_indices = 1:8:N;
        case 'scattered_4'
            is_scattered = true;
            scattered_spacing = 4;
            scattered_shift = 1;
            pilot_indices = 1:4:N;
        case 'scattered_8'
            is_scattered = true;
            scattered_spacing = 8;
            scattered_shift = 2;
            pilot_indices = 1:8:N;
        case 'block'
            pilot_indices = 1:N;
        otherwise
            error('不支持的导频模式: %s！支持 comb_4/comb_8/scattered_4/scattered_8/block', pilot_pattern);
    end
else
    pilot_indices = pilot_pattern(:).';
end
data_indices = setdiff(1:N, pilot_indices);

%% ========== 3. 提取 ========== %%
if isempty(freq_symbols), error('频域符号不能为空！'); end
num_symbols = floor(length(freq_symbols) / N);

num_pilots_base = length(pilot_indices);
num_data_base = length(data_indices);

data_symbols = zeros(1, num_symbols * num_data_base);
pilot_rx = zeros(num_symbols, num_pilots_base);

for s = 1:num_symbols
    ofdm_sym = freq_symbols((s-1)*N+1 : s*N);

    if is_scattered
        offset = mod((s-1) * scattered_shift, scattered_spacing);
        p_idx_s = mod(pilot_indices - 1 + offset, N) + 1;
        d_idx_s = setdiff(1:N, p_idx_s);
    else
        p_idx_s = pilot_indices;
        d_idx_s = data_indices;
    end

    pilot_rx(s, :) = ofdm_sym(p_idx_s);
    data_symbols((s-1)*num_data_base+1 : s*num_data_base) = ofdm_sym(d_idx_s(1:num_data_base));
end

end
