function hopped_indices = fh_spread(freq_indices, pattern, num_freqs)
% 功能：跳频扩频——对频率索引施加伪随机跳频偏移
% 版本：V1.0.0
% 输入：
%   freq_indices - 原始频率索引序列 (1xN 数组，取值 0 ~ num_freqs-1)
%                  通常由 mfsk_modulate 产生
%   pattern      - 跳频图案 (1xN 数组，取值 0 ~ num_freqs-1)
%                  由 gen_hop_pattern 生成，长度须与freq_indices一致
%   num_freqs    - 可用频率总数 (正整数，须与图案生成时一致)
% 输出：
%   hopped_indices - 跳频后的频率索引 (1xN 数组，取值 0 ~ num_freqs-1)
%
% 备注：
%   - 跳频操作：hopped = mod(freq_index + pattern, num_freqs)
%   - 等效于在频率域做循环移位，将信号分散到不同频率
%   - 抗窄带干扰：干扰仅影响部分跳频时隙

%% ========== 1. 入参解析 ========== %%
freq_indices = freq_indices(:).';
pattern = pattern(:).';

%% ========== 2. 严格参数校验 ========== %%
if isempty(freq_indices)
    error('频率索引不能为空！');
end
if length(freq_indices) ~= length(pattern)
    error('频率索引长度(%d)与跳频图案长度(%d)不一致！', ...
          length(freq_indices), length(pattern));
end
if any(freq_indices < 0) || any(freq_indices >= num_freqs)
    error('频率索引必须在 [0, %d] 范围内！', num_freqs-1);
end

%% ========== 3. 跳频 ========== %%
hopped_indices = mod(freq_indices + pattern, num_freqs);

end
