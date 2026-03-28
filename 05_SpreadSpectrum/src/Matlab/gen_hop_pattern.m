function [pattern, num_freqs] = gen_hop_pattern(num_hops, num_freqs, seed)
% 功能：生成伪随机跳频图案
% 版本：V1.0.0
% 输入：
%   num_hops  - 跳频次数/图案长度 (正整数)
%   num_freqs - 可用频率数 (正整数，默认 16)
%   seed      - 随机种子 (非负整数，默认 0，收发须一致)
% 输出：
%   pattern   - 跳频图案 (1xnum_hops 数组，取值 0 ~ num_freqs-1)
%               每个元素表示该时隙的跳频偏移量
%   num_freqs - 实际使用的频率数
%
% 备注：
%   - 同一seed和参数始终产生相同图案，保证收发一致
%   - 不污染全局随机状态
%   - 图案为均匀分布的伪随机序列，各频率被近似等概率访问

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 3 || isempty(seed)
    seed = 0;
end
if nargin < 2 || isempty(num_freqs)
    num_freqs = 16;
end

%% ========== 2. 严格参数校验 ========== %%
if num_hops < 1 || num_hops ~= floor(num_hops)
    error('跳频次数必须为正整数！');
end
if num_freqs < 2 || num_freqs ~= floor(num_freqs)
    error('可用频率数必须为>=2的正整数！');
end
if seed < 0 || seed ~= floor(seed)
    error('随机种子必须为非负整数！');
end

%% ========== 3. 生成伪随机跳频图案 ========== %%
rng_state = rng;
rng(seed);
pattern = randi([0, num_freqs-1], 1, num_hops);
rng(rng_state);

end
