function W = gen_walsh_hadamard(N)
% 功能：生成Walsh-Hadamard码矩阵（NxN正交码集）
% 版本：V1.0.0
% 输入：
%   N - 码长 (必须为2的幂，如 4/8/16/32/64/128)
% 输出：
%   W - NxN Walsh-Hadamard矩阵，值为 +1/-1
%       每一行为一个长度为N的正交码字
%       任意两行满足 W(i,:) * W(j,:)' = 0 (i≠j)
%
% 备注：
%   - 递归Sylvester构造: H(2N) = [H(N) H(N); H(N) -H(N)]
%   - 码集大小 = 码长 = N，所有码字完全正交
%   - 适用于DS-CDMA同步多用户场景（正交多址）

%% ========== 1. 严格参数校验 ========== %%
if N < 1 || mod(log2(N), 1) ~= 0
    error('N必须为2的幂(2/4/8/16/...)！');
end

%% ========== 2. 递归构造 ========== %%
W = 1;
while size(W, 1) < N
    W = [W, W; W, -W];
end

end
