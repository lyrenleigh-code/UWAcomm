function [symbols, constellation, bit_map] = qam_modulate(bits, M, mapping)
% 功能：QAM/PSK符号映射，支持BPSK/QPSK/8QAM/16QAM/64QAM
% 版本：V1.0.0
% 输入：
%   bits    - 比特序列 (1xN 数组，N须为 log2(M) 的整数倍)
%   M       - 调制阶数 (2/4/8/16/64)
%   mapping - 映射方式 (字符串，'gray'(默认) 或 'natural')
% 输出：
%   symbols       - 调制后的复数符号序列 (1x(N/log2(M)) 数组)
%   constellation - 星座点集合 (1xM 复数数组，归一化为单位平均功率)
%   bit_map       - 各星座点对应的比特模式 (M x log2(M) 矩阵)
%
% 备注：
%   - 星座图归一化为单位平均功率 E[|s|^2] = 1
%   - BPSK(M=2): 实轴 ±1
%   - QPSK(M=4): 2x2方形星座
%   - 8QAM(M=8): 4x2矩形星座
%   - 16QAM(M=16): 4x4方形星座
%   - 64QAM(M=64): 8x8方形星座
%   - Gray映射保证相邻星座点仅差1比特

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 3 || isempty(mapping)
    mapping = 'gray';
end
bits = double(bits(:).');
bps = log2(M);                         % 每符号比特数

%% ========== 2. 严格参数校验 ========== %%
if isempty(bits)
    error('输入比特不能为空！');
end
if ~ismember(M, [2, 4, 8, 16, 64])
    error('调制阶数M必须为 2/4/8/16/64！');
end
if any(bits ~= 0 & bits ~= 1)
    error('输入必须为二进制比特(0或1)！');
end
if mod(length(bits), bps) ~= 0
    error('比特长度(%d)必须为 log2(M)=%d 的整数倍！', length(bits), bps);
end

%% ========== 3. 生成星座图和比特映射 ========== %%
[constellation, bit_map] = generate_constellation(M, mapping);

%% ========== 4. 比特到符号映射 ========== %%
num_symbols = length(bits) / bps;
symbols = zeros(1, num_symbols);

% 构建比特模式到星座点索引的查找表
lookup = containers.Map();
for k = 1:M
    key = num2str(bit_map(k, :));
    lookup(key) = k;
end

for s = 1:num_symbols
    bit_group = bits((s-1)*bps+1 : s*bps);
    key = num2str(bit_group);
    idx = lookup(key);
    symbols(s) = constellation(idx);
end

end

% --------------- 辅助函数1：生成星座图和比特映射表 --------------- %
function [constellation, bit_map] = generate_constellation(M, mapping)
% GENERATE_CONSTELLATION 生成归一化星座图和对应的比特映射
% 输入参数：
%   M       - 调制阶数
%   mapping - 'gray' 或 'natural'
% 输出参数：
%   constellation - 1xM 复数星座点（单位平均功率）
%   bit_map       - Mx(log2(M)) 比特映射矩阵

bps = log2(M);

if M == 2
    % BPSK: 实轴 ±1
    constellation = [-1, 1];
    bit_map = [0; 1];

elseif M == 8
    % 8QAM: 4x2 矩形（I:4级, Q:2级）
    bps_I = 2; bps_Q = 1;
    levels_I = 4; levels_Q = 2;

    pam_I = gen_pam_levels(levels_I, mapping);
    pam_Q = gen_pam_levels(levels_Q, mapping);

    constellation = zeros(1, M);
    bit_map = zeros(M, bps);
    idx = 0;
    for qi = 1:levels_Q
        for ii = 1:levels_I
            idx = idx + 1;
            constellation(idx) = pam_I(ii).level + 1j * pam_Q(qi).level;
            bit_map(idx, :) = [pam_I(ii).bits, pam_Q(qi).bits];
        end
    end

else
    % 方形QAM: QPSK(2x2), 16QAM(4x4), 64QAM(8x8)
    K = sqrt(M);
    bps_dim = log2(K);

    pam = gen_pam_levels(K, mapping);

    constellation = zeros(1, M);
    bit_map = zeros(M, bps);
    idx = 0;
    for qi = 1:K
        for ii = 1:K
            idx = idx + 1;
            constellation(idx) = pam(ii).level + 1j * pam(qi).level;
            bit_map(idx, :) = [pam(ii).bits, pam(qi).bits];
        end
    end
end

% 归一化为单位平均功率
avg_power = mean(abs(constellation).^2);
constellation = constellation / sqrt(avg_power);

end

% --------------- 辅助函数2：生成PAM电平及比特映射 --------------- %
function pam = gen_pam_levels(K, mapping)
% GEN_PAM_LEVELS 生成K级PAM电平和对应比特映射
% 输入参数：
%   K       - 电平数 (2的幂)
%   mapping - 'gray' 或 'natural'
% 输出参数：
%   pam     - 1xK 结构体数组，每个元素含 .level（幅度）和 .bits（比特）

bps = log2(K);
levels = -(K-1):2:(K-1);              % 对称PAM: -(K-1), -(K-3), ..., (K-3), (K-1)

if strcmp(mapping, 'gray')
    % Gray码索引
    gray_idx = gray_code_order(K);
else
    % 自然顺序
    gray_idx = 0:K-1;
end

pam = struct('level', {}, 'bits', {});
for i = 1:K
    pam(i).level = levels(i);
    pam(i).bits = de2bi(gray_idx(i), bps, 'left-msb');
end

end

% --------------- 辅助函数3：生成Gray码顺序 --------------- %
function order = gray_code_order(K)
% GRAY_CODE_ORDER 生成K个Gray码索引（反射二进制码）
% 输入参数：
%   K - 电平数 (2的幂)
% 输出参数：
%   order - 1xK Gray码索引 (0 ~ K-1)

order = 0:K-1;
order = bitxor(order, bitshift(order, -1));

end
