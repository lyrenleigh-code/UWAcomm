function [interleaved, num_rows, num_cols, pad_len] = block_interleave(data, num_rows, num_cols)
% 功能：块交织器——按行写入矩阵、按列读出，将突发错误打散
% 版本：V1.0.0
% 输入：
%   data      - 待交织的数据序列 (1xN 数值数组)
%   num_rows  - 交织矩阵行数 (正整数，可选)
%   num_cols  - 交织矩阵列数 (正整数，可选)
%              若均未指定：自动计算近似方阵
%              若仅指定num_rows：自动计算 num_cols = ceil(N/num_rows)
%              若均指定：num_rows * num_cols 须 >= N，不足部分补零
% 输出：
%   interleaved - 交织后的数据序列 (1x(num_rows*num_cols) 数组)
%   num_rows    - 实际使用的行数（供解交织使用）
%   num_cols    - 实际使用的列数（供解交织使用）
%   pad_len     - 补零个数（供解交织时截断使用）
%
% 备注：
%   - 写入顺序：按行从左到右、从上到下
%   - 读出顺序：按列从上到下、从左到右
%   - 交织深度 = num_rows，突发错误被分散到 num_rows 个不同位置

%% ========== 1. 入参解析与初始化 ========== %%
data = data(:).';                      % 强制转行向量
N = length(data);

%% ========== 2. 严格参数校验 ========== %%
if isempty(data)
    error('输入数据不能为空！');
end

%% ========== 3. 确定交织矩阵尺寸 ========== %%
if nargin < 2 || isempty(num_rows)
    if nargin < 3 || isempty(num_cols)
        % 两者均未指定：自动计算近似方阵
        num_rows = ceil(sqrt(N));
        num_cols = ceil(N / num_rows);
    else
        % 仅指定 num_cols
        num_rows = ceil(N / num_cols);
    end
elseif nargin < 3 || isempty(num_cols)
    % 仅指定 num_rows
    num_cols = ceil(N / num_rows);
end

if num_rows < 1 || num_rows ~= floor(num_rows)
    error('num_rows必须为正整数！');
end
if num_cols < 1 || num_cols ~= floor(num_cols)
    error('num_cols必须为正整数！');
end

total = num_rows * num_cols;
if total < N
    error('num_rows(%d) * num_cols(%d) = %d < 数据长度(%d)！', ...
          num_rows, num_cols, total, N);
end

%% ========== 4. 补零并写入矩阵 ========== %%
pad_len = total - N;
data_padded = [data, zeros(1, pad_len)];

% 按行写入矩阵
matrix = reshape(data_padded, num_cols, num_rows).';

%% ========== 5. 按列读出 ========== %%
interleaved = matrix(:).';             % 按列展开（MATLAB默认列优先）

end
