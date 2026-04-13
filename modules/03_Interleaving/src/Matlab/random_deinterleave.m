function deinterleaved = random_deinterleave(data, perm)
% 功能：随机解交织器——随机交织的逆操作
% 版本：V1.0.0
% 输入：
%   data  - 待解交织的数据序列 (1xN 数值数组)
%   perm  - 置换索引 (1xN 数组，由 random_interleave 生成)
% 输出：
%   deinterleaved - 解交织后的数据序列 (1xN 数组)
%
% 备注：
%   - perm 必须与交织时使用的置换完全一致
%   - 内部计算逆置换：deperm(perm) = 1:N

%% ========== 1. 入参解析与初始化 ========== %%
data = data(:).';

%% ========== 2. 严格参数校验 ========== %%
if isempty(data)
    error('输入数据不能为空！');
end
if isempty(perm)
    error('置换索引不能为空！');
end
if length(data) ~= length(perm)
    error('数据长度(%d)与置换索引长度(%d)不一致！', length(data), length(perm));
end

%% ========== 3. 计算逆置换并解交织 ========== %%
N = length(data);
deperm = zeros(1, N);
deperm(perm) = 1:N;                   % 逆置换映射

deinterleaved = data(deperm);

end
