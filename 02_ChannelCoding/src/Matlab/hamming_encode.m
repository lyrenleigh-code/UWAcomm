function [codeword, G, H] = hamming_encode(message, r)
% 功能：Hamming(2^r-1, 2^r-1-r)分组码编码
% 版本：V1.0.0
% 输入：
%   message     - 信息比特序列 (1xN logical/数值数组，N须为k的整数倍)
%               k = 2^r - 1 - r（每块信息比特数）
%   r           - 校验比特数 (正整数，默认 r=3 即 Hamming(7,4))
% 输出：
%   codeword    - 编码后比特序列 (1xM 数组，M = N/k * n)
%   G           - 生成矩阵 (k x n)
%   H           - 校验矩阵 (r x n)
%
% 备注：
%   - Hamming码可纠正1位错误，检测2位错误
%   - 码长 n = 2^r - 1，信息位 k = n - r，码率 R = k/n
%   - r=3: (7,4)码, R=0.571
%   - r=4: (15,11)码, R=0.733

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 2 || isempty(r)
    r = 3;                             % 默认 Hamming(7,4)
end
message = double(message(:).');        % 强制转行向量

n = 2^r - 1;                          % 码字长度
k = n - r;                            % 信息位长度

%% ========== 2. 严格参数校验 ========== %%
if isempty(message)
    error('输入信息比特不能为空！');
end
if r < 2 || r ~= floor(r)
    error('校验比特数r必须为>=2的正整数！');
end
if any(message ~= 0 & message ~= 1)
    error('输入信息必须为二进制比特(0或1)！');
end
if mod(length(message), k) ~= 0
    error('信息比特长度(%d)必须为k=%d的整数倍！请补零对齐。', length(message), k);
end

%% ========== 3. 构造校验矩阵H和生成矩阵G ========== %%
[G, H] = build_hamming_matrices(r, n, k);

%% ========== 4. 分块编码 ========== %%
num_blocks = length(message) / k;
codeword = zeros(1, num_blocks * n);

for b = 1:num_blocks
    idx_in  = (b-1)*k + 1 : b*k;
    idx_out = (b-1)*n + 1 : b*n;
    codeword(idx_out) = mod(message(idx_in) * G, 2);
end

end

% --------------- 辅助函数1：构造Hamming生成矩阵和校验矩阵 --------------- %
function [G, H] = build_hamming_matrices(r, n, k)
% BUILD_HAMMING_MATRICES 构造系统形式的Hamming码生成矩阵G和校验矩阵H
% 输入参数：
%   r - 校验比特数
%   n - 码字长度 (2^r - 1)
%   k - 信息位长度 (n - r)
% 输出参数：
%   G - 生成矩阵 (k x n)，系统形式 [I_k | P]
%   H - 校验矩阵 (r x n)，系统形式 [P' | I_r]

% 生成所有非零r位二进制列向量作为H的列
all_cols = zeros(r, n);
col_idx = 0;
for i = 1:2^r-1
    all_cols(:, i) = de2bi(i, r, 'left-msb').';
end

% 将H重排为系统形式 [P' | I_r]
% 单位阵列放在后r列（对应校验位位置）
identity_cols = [];                    % 单位阵对应的列索引
other_cols = [];                       % 非单位阵列的索引

for i = 1:n
    col = all_cols(:, i);
    if sum(col) == 1                   % 单位向量
        identity_cols = [identity_cols, i]; %#ok<AGROW>
    else
        other_cols = [other_cols, i];  %#ok<AGROW>
    end
end

% 按单位向量中1的位置排序
[~, sort_idx] = sort(arrayfun(@(c) find(all_cols(:,c)==1), identity_cols));
identity_cols = identity_cols(sort_idx);

% 系统形式H = [P' | I_r]
H = all_cols(:, [other_cols, identity_cols]);

% 提取子阵P'（H的前k列）
Pt = H(:, 1:k);

% 生成矩阵 G = [I_k | P]，其中 P = Pt'
G = [eye(k), Pt.'];

end
