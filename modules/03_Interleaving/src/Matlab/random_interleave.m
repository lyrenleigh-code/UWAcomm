function [interleaved, perm] = random_interleave(data, seed)
% 功能：随机交织器——基于伪随机置换对数据序列进行交织
% 版本：V1.0.0
% 输入：
%   data  - 待交织的数据序列 (1xN 数值数组)
%   seed  - 随机种子 (非负整数，编解码须一致，默认0)
% 输出：
%   interleaved - 交织后的数据序列 (1xN 数组)
%   perm        - 置换索引 (1xN 数组)，满足 interleaved = data(perm)
%                 需传递给 random_deinterleave 用于解交织
%
% 备注：
%   - 同一seed和数据长度始终生成相同置换，确保编解码一致性
%   - 不改变当前全局随机状态（内部保存/恢复rng）
%   - 可用于Turbo码交织、比特交织等场景

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 2 || isempty(seed)
    seed = 0;
end
data = data(:).';
N = length(data);

%% ========== 2. 严格参数校验 ========== %%
if isempty(data)
    error('输入数据不能为空！');
end
if seed < 0 || seed ~= floor(seed)
    error('随机种子必须为非负整数！');
end

%% ========== 3. 生成伪随机置换 ========== %%
rng_state = rng;                       % 保存当前随机状态
rng(seed);
perm = randperm(N);
rng(rng_state);                        % 恢复随机状态

%% ========== 4. 交织 ========== %%
interleaved = data(perm);

end
