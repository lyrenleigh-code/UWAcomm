function deinterleaved = block_deinterleave(data, num_rows, num_cols, pad_len)
% 功能：块解交织器——块交织的逆操作，按列写入矩阵、按行读出
% 版本：V1.0.0
% 输入：
%   data      - 待解交织的数据序列 (1xM 数组，M = num_rows * num_cols)
%   num_rows  - 交织矩阵行数 (正整数，须与交织时一致)
%   num_cols  - 交织矩阵列数 (正整数，须与交织时一致)
%   pad_len   - 交织时补零个数 (非负整数，默认0)
% 输出：
%   deinterleaved - 解交织后的数据序列 (1xN 数组，N = M - pad_len)
%
% 备注：
%   - 写入顺序：按列从上到下、从左到右（交织读出的逆操作）
%   - 读出顺序：按行从左到右、从上到下（交织写入的逆操作）

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 4 || isempty(pad_len)
    pad_len = 0;
end
data = data(:).';

%% ========== 2. 严格参数校验 ========== %%
if isempty(data)
    error('输入数据不能为空！');
end
if num_rows < 1 || num_cols < 1
    error('num_rows和num_cols必须为正整数！');
end
if length(data) ~= num_rows * num_cols
    error('数据长度(%d)必须等于 num_rows(%d)*num_cols(%d)=%d！', ...
          length(data), num_rows, num_cols, num_rows*num_cols);
end
if pad_len < 0 || pad_len >= num_rows * num_cols
    error('pad_len(%d)无效！', pad_len);
end

%% ========== 3. 按列写入矩阵 ========== %%
matrix = reshape(data, num_rows, num_cols);

%% ========== 4. 按行读出并去除补零 ========== %%
row_read = matrix.';                   % 转置后按列展开等于按行读出
deinterleaved = row_read(:).';

% 去除末尾补零
if pad_len > 0
    deinterleaved = deinterleaved(1:end - pad_len);
end

end
