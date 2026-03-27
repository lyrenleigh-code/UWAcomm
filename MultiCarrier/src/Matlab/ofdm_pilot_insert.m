function [symbols_with_pilot, pilot_indices, data_indices] = ofdm_pilot_insert(data_symbols, N, pilot_pattern, pilot_values)
% 功能：OFDM频域导频插入（梳状、块状、离散）
% 版本：V1.1.0
% 输入：
%   data_symbols  - 数据符号 (1xM 数组)
%   N             - 子载波总数（FFT点数）
%   pilot_pattern - 导频模式 (字符串或数组)
%                   'comb_4'      : 每4个子载波插1个导频（默认）
%                   'comb_8'      : 每8个子载波插1个导频
%                   'scattered_4' : 离散导频，间隔4，每符号偏移1位
%                   'scattered_8' : 离散导频，间隔8，每符号偏移2位
%                   'block'       : 首个OFDM符号全导频，其余全数据
%                   [1xK数组] : 自定义导频子载波索引
%   pilot_values  - 导频符号值（标量或1xK数组，默认+1）
% 输出：
%   symbols_with_pilot - 含导频的频域符号 (1xL 数组，L为N的整数倍)
%   pilot_indices      - 导频子载波索引 (1xK 数组，1-based)
%   data_indices       - 数据子载波索引 (1xJ 数组)
%
% 备注：
%   - 梳状导频：每个OFDM符号中均匀插入导频，适合时变信道
%   - 块状导频：整个符号用作导频，适合频选信道
%   - 导频位置需在收发端一致

%% ========== 1. 入参解析 ========== %%
if nargin < 4 || isempty(pilot_values), pilot_values = 1; end
if nargin < 3 || isempty(pilot_pattern), pilot_pattern = 'comb_4'; end
data_symbols = data_symbols(:).';

%% ========== 2. 确定导频和数据子载波位置 ========== %%
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
            scattered_shift = 1;       % 每符号偏移1位
            pilot_indices = 1:4:N;     % 第0符号的基准位置
        case 'scattered_8'
            is_scattered = true;
            scattered_spacing = 8;
            scattered_shift = 2;       % 每符号偏移2位
            pilot_indices = 1:8:N;     % 第0符号的基准位置
        case 'block'
            pilot_indices = 1:N;       % 整个符号为导频
        otherwise
            error('不支持的导频模式: %s！支持 comb_4/comb_8/scattered_4/scattered_8/block/自定义数组', pilot_pattern);
    end
else
    pilot_indices = pilot_pattern(:).';
end

data_indices = setdiff(1:N, pilot_indices);
num_pilots_per_sym = length(pilot_indices);
num_data_per_sym = length(data_indices);

%% ========== 3. 参数校验 ========== %%
if isempty(data_symbols), error('数据符号不能为空！'); end
if num_data_per_sym == 0, error('数据子载波数为0，导频占满全部子载波！'); end

% 导频值扩展
if isscalar(pilot_values)
    pilot_values = pilot_values * ones(1, num_pilots_per_sym);
end

%% ========== 4. 插入导频 ========== %%
num_ofdm_symbols = ceil(length(data_symbols) / num_data_per_sym);
% 补零对齐
pad_len = num_ofdm_symbols * num_data_per_sym - length(data_symbols);
data_padded = [data_symbols, zeros(1, pad_len)];

symbols_with_pilot = zeros(1, num_ofdm_symbols * N);

for s = 1:num_ofdm_symbols
    ofdm_sym = zeros(1, N);

    % 离散导频：每个符号的导频位置偏移
    if is_scattered
        offset = mod((s-1) * scattered_shift, scattered_spacing);
        p_idx_s = mod(pilot_indices - 1 + offset, N) + 1;
        d_idx_s = setdiff(1:N, p_idx_s);
    else
        p_idx_s = pilot_indices;
        d_idx_s = data_indices;
    end

    % 导频值扩展（离散模式下数量可能变化）
    pv = pilot_values;
    if length(pv) < length(p_idx_s)
        pv = repmat(pv, 1, ceil(length(p_idx_s)/length(pv)));
    end

    % 填入导频
    ofdm_sym(p_idx_s) = pv(1:length(p_idx_s));

    % 填入数据
    data_block = data_padded((s-1)*num_data_per_sym+1 : s*num_data_per_sym);
    n_data_this = length(d_idx_s);
    ofdm_sym(d_idx_s) = data_block(1:min(n_data_this, length(data_block)));

    symbols_with_pilot((s-1)*N+1 : s*N) = ofdm_sym;
end

end
