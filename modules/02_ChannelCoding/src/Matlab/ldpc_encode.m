function [codeword, H, G] = ldpc_encode(message, n, rate, H_seed)
% 功能：LDPC（低密度奇偶校验）码编码
% 版本：V1.0.0
% 输入：
%   message     - 信息比特序列 (1xN 数组，N须为k的整数倍)
%   n           - 码字长度 (正整数，默认 64)
%   rate        - 码率 (0~1之间，默认 0.5，k = round(n*rate))
%   H_seed      - 校验矩阵生成随机种子 (正整数，默认 0，编解码须一致)
% 输出：
%   codeword    - 编码后比特序列 (1xM 数组)
%   H           - 校验矩阵 ((n-k) x n 稀疏二进制矩阵)
%   G           - 生成矩阵 (k x n 二进制矩阵)
%
% 备注：
%   - 采用Gallager规则构造正则LDPC码的校验矩阵
%   - 每列恒定重量 wc=3（每个码字比特参与3个校验方程）
%   - 通过高斯消元将H化为系统形式 [P | I_(n-k)]，得到 G = [I_k | P']
%   - 信息比特长度须为k的整数倍，按块编码

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 4 || isempty(H_seed)
    H_seed = 0;
end
if nargin < 3 || isempty(rate)
    rate = 0.5;
end
if nargin < 2 || isempty(n)
    n = 64;
end
message = double(message(:).');

k = round(n * rate);                  % 信息位长度
m = n - k;                            % 校验位长度

%% ========== 2. 严格参数校验 ========== %%
if isempty(message)
    error('输入信息比特不能为空！');
end
if any(message ~= 0 & message ~= 1)
    error('输入信息必须为二进制比特(0或1)！');
end
if n < 4
    error('码字长度n必须>=4！');
end
if rate <= 0 || rate >= 1
    error('码率rate必须在(0,1)之间！');
end
if k < 1 || m < 1
    error('码率和码长组合无效，信息位k=%d, 校验位m=%d！', k, m);
end
if mod(length(message), k) ~= 0
    error('信息比特长度(%d)必须为k=%d的整数倍！请补零对齐。', length(message), k);
end

%% ========== 3. 构造LDPC校验矩阵H ========== %%
H = build_ldpc_H(n, m, H_seed);

%% ========== 4. 高斯消元化为系统形式，求生成矩阵G ========== %%
[G, col_perm] = build_generator_from_H(H, n, k, m);

% 对H做相同的列重排，使前k列为信息位，后m列为校验位
H = H(:, col_perm);

%% ========== 5. 分块编码 ========== %%
num_blocks = length(message) / k;
codeword = zeros(1, num_blocks * n);

for b = 1:num_blocks
    idx_in  = (b-1)*k + 1 : b*k;
    idx_out = (b-1)*n + 1 : b*n;
    codeword(idx_out) = mod(message(idx_in) * G, 2);
end

end

% --------------- 辅助函数1：构造正则LDPC校验矩阵 --------------- %
function H = build_ldpc_H(n, m, seed)
% BUILD_LDPC_H 基于Gallager方法构造正则LDPC码的校验矩阵
% 输入参数：
%   n    - 码字长度
%   m    - 校验位数 (行数)
%   seed - 随机种子
% 输出参数：
%   H    - m x n 二进制稀疏校验矩阵，列重约3

rng_state = rng;
rng(seed);

wc = 3;                               % 目标列重
% 子矩阵行数
sub_rows = ceil(m / wc);

H = zeros(m, n);

% 第一个子矩阵：规则排列
H1 = zeros(sub_rows, n);
for j = 1:n
    row_idx = mod(j-1, sub_rows) + 1;
    H1(row_idx, j) = 1;
end

% 后续子矩阵：对第一个子矩阵的列进行随机置换
H_parts = {H1};
for w = 2:wc
    col_perm = randperm(n);
    H_parts{w} = H1(:, col_perm);
end

% 纵向拼接并截取前m行
H_full = vertcat(H_parts{:});
H = H_full(1:m, :);

rng(rng_state);

end

% --------------- 辅助函数2：从H矩阵通过高斯消元求G矩阵 --------------- %
function [G, col_perm] = build_generator_from_H(H, n, k, m)
% BUILD_GENERATOR_FROM_H 通过GF(2)高斯消元将H化为系统形式，求生成矩阵G
% 输入参数：
%   H - m x n 校验矩阵
%   n - 码字长度
%   k - 信息位长度
%   m - 校验位长度
% 输出参数：
%   G        - k x n 生成矩阵，系统形式 [I_k | P']
%   col_perm - 列重排索引 (1xn)，info列在前k位，parity列在后m位

% 对H做列主元高斯消元
H_aug = H;
col_order = 1:n;                       % 记录列交换

for i = 1:m
    % 寻找第i行起、第i列起的主元
    pivot_found = false;
    for col = i:n
        for row = i:m
            if H_aug(row, col_order(col)) == 1
                % 行交换
                if row ~= i
                    H_aug([i, row], :) = H_aug([row, i], :);
                end
                % 列标记交换
                if col ~= i
                    col_order([i, col]) = col_order([col, i]);
                end
                pivot_found = true;
                break;
            end
        end
        if pivot_found
            break;
        end
    end

    if ~pivot_found
        continue;                      % 无主元，跳过（H可能非满秩）
    end

    % 用第i行消去其他行中该列的1
    for row = 1:m
        if row ~= i && H_aug(row, col_order(i)) == 1
            H_aug(row, :) = mod(H_aug(row, :) + H_aug(i, :), 2);
        end
    end
end

% col_order前m个为主元列(校验位)，后k个为自由列(信息位)
parity_cols = col_order(1:m);
info_cols = col_order(m+1:n);

% 列重排：信息列在前，校验列在后
col_perm = [info_cols, parity_cols];

% 提取P矩阵：对消元后的H_aug按[info, parity]顺序取列
H_rearranged = H_aug(:, col_perm);
P = H_rearranged(:, 1:k);             % m x k 矩阵

% 生成矩阵 G = [I_k | P']，标准系统形式
G = [eye(k), P.'];

end
