function freq_indices = fh_despread(hopped_indices, pattern, num_freqs)
% 功能：去跳频——移除跳频偏移，还原原始频率索引
% 版本：V1.0.0
% 输入：
%   hopped_indices - 跳频后的频率索引 (1xN 数组)
%   pattern        - 跳频图案 (1xN 数组，须与发端完全一致)
%   num_freqs      - 可用频率总数 (须与发端一致)
% 输出：
%   freq_indices   - 还原的原始频率索引 (1xN 数组，取值 0 ~ num_freqs-1)
%
% 备注：
%   - 去跳频操作：freq_index = mod(hopped - pattern, num_freqs)
%   - pattern 必须与发端完全一致，否则解跳频错误

%% ========== 1. 入参解析 ========== %%
hopped_indices = hopped_indices(:).';
pattern = pattern(:).';

%% ========== 2. 严格参数校验 ========== %%
if isempty(hopped_indices)
    error('跳频索引不能为空！');
end
if length(hopped_indices) ~= length(pattern)
    error('跳频索引长度(%d)与图案长度(%d)不一致！', ...
          length(hopped_indices), length(pattern));
end

%% ========== 3. 去跳频 ========== %%
freq_indices = mod(hopped_indices - pattern, num_freqs);

end
