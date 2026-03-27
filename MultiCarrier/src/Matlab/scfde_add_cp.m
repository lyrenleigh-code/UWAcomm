function [signal, params_out] = scfde_add_cp(data_symbols, block_size, cp_len)
% 功能：SC-FDE分块CP插入——将数据分块，每块添加循环前缀
% 版本：V1.0.0
% 输入：
%   data_symbols - 数据符号序列 (1xN 数组)
%   block_size   - 每块数据长度 (正整数，默认 256)
%   cp_len       - CP长度 (正整数，默认 block_size/4)
% 输出：
%   signal     - 加CP后的时域信号 (1xL)
%   params_out - 参数结构体
%       .block_size  : 块大小
%       .cp_len      : CP长度
%       .num_blocks  : 数据块数
%       .pad_len     : 补零数
%
% 备注：
%   - SC-FDE每块 = [CP | 数据块]，CP为数据块尾部的拷贝
%   - 不足一块的数据自动补零
%   - 接收端去CP后对每块做FFT→MMSE均衡→IFFT

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(cp_len), cp_len = floor(block_size/4); end
if nargin < 2 || isempty(block_size), block_size = 256; end
data_symbols = data_symbols(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(data_symbols), error('数据符号不能为空！'); end
if block_size < 2, error('块大小必须>=2！'); end
if cp_len < 0, error('CP长度不能为负！'); end

%% ========== 3. 分块+补零 ========== %%
N = length(data_symbols);
num_blocks = ceil(N / block_size);
pad_len = num_blocks * block_size - N;
data_padded = [data_symbols, zeros(1, pad_len)];

%% ========== 4. 每块加CP ========== %%
block_with_cp = block_size + cp_len;
signal = zeros(1, num_blocks * block_with_cp);

for b = 1:num_blocks
    block = data_padded((b-1)*block_size+1 : b*block_size);
    % CP = 数据块尾部cp_len个样本
    cp = block(end-cp_len+1:end);
    signal((b-1)*block_with_cp+1 : b*block_with_cp) = [cp, block];
end

%% ========== 5. 输出参数 ========== %%
params_out.block_size = block_size;
params_out.cp_len = cp_len;
params_out.num_blocks = num_blocks;
params_out.pad_len = pad_len;

end
