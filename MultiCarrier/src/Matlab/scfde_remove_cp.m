function [freq_blocks, time_blocks] = scfde_remove_cp(signal, block_size, cp_len)
% 功能：SC-FDE去CP + 分块FFT——接收端前处理
% 版本：V1.0.0
% 输入：
%   signal     - 接收信号 (1xL 数组)
%   block_size - 每块数据长度（须与发端一致）
%   cp_len     - CP长度（须与发端一致）
% 输出：
%   freq_blocks - 频域块矩阵 (num_blocks x block_size 复数矩阵)
%                 每行为一个块的FFT结果，供MMSE均衡使用
%   time_blocks - 时域块矩阵 (num_blocks x block_size)
%                 去CP后的原始时域块
%
% 备注：
%   - 去CP后每块做FFT，得到频域信号 Y[k] = H[k]*X[k] + W[k]
%   - 后续模块7用MMSE均衡：X_hat[k] = H*[k]/(|H[k]|^2+sigma^2) * Y[k]

%% ========== 1. 入参解析 ========== %%
signal = signal(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(signal), error('输入信号不能为空！'); end
block_with_cp = block_size + cp_len;
num_blocks = floor(length(signal) / block_with_cp);
if num_blocks < 1, error('信号长度不足一个块！'); end

%% ========== 3. 去CP + FFT ========== %%
freq_blocks = zeros(num_blocks, block_size);
time_blocks = zeros(num_blocks, block_size);

for b = 1:num_blocks
    block_full = signal((b-1)*block_with_cp+1 : b*block_with_cp);

    % 去CP（丢弃前cp_len个样本）
    block_data = block_full(cp_len+1 : end);
    time_blocks(b, :) = block_data;

    % FFT
    freq_blocks(b, :) = fft(block_data, block_size);
end

end
