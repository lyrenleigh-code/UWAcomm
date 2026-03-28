function reconstructed = uniform_dequantize(indices, num_bits, val_range)
% 功能：根据量化索引和量化参数，反量化重建连续信号
% 版本：V1.0.0
% 输入：
%   indices     - 量化索引 (任意尺寸数值数组，取值 0 ~ 2^num_bits-1)
%   num_bits    - 量化比特数 (正整数，必须与编码端一致)
%   val_range   - 量化范围 [xmin, xmax] (1x2 数组，必须与编码端一致)
% 输出：
%   reconstructed - 反量化重建的信号 (与indices同尺寸)
%
% 备注：
%   - 重建值为对应量化区间的中点：x_hat = xmin + (index + 0.5) * delta
%   - num_bits 和 val_range 必须与 uniform_quantize 编码时的参数完全一致
%   - 量化误差（重建值与原始值之差）的均方值约为 delta^2/12

%% ========== 1. 入参解析与初始化 ========== %%
xmin = val_range(1);                   % 量化下界
xmax = val_range(2);                   % 量化上界
L = 2^num_bits;                        % 量化级数
delta = (xmax - xmin) / L;            % 量化步长

%% ========== 2. 严格参数校验 ========== %%
if isempty(indices)
    error('输入量化索引不能为空！');
end
if ~isnumeric(indices)
    error('量化索引必须为数值类型！');
end
if any(indices(:) < 0)
    error('量化索引不能为负数！最小值为 %d', min(indices(:)));
end
if any(indices(:) >= L)
    error('量化索引超出范围！最大允许值为 %d，实际最大值为 %d', L-1, max(indices(:)));
end
if any(indices(:) ~= floor(indices(:)))
    error('量化索引必须为整数！');
end
if ~isnumeric(num_bits) || num_bits < 1 || num_bits ~= floor(num_bits)
    error('量化比特数必须为正整数！');
end
if length(val_range) ~= 2
    error('val_range必须为 [xmin, xmax] 形式的1x2数组！');
end
if xmin >= xmax
    error('val_range(1) 必须小于 val_range(2)！当前值：[%.4f, %.4f]', xmin, xmax);
end

%% ========== 3. 反量化重建 ========== %%
% 重建值 = 量化区间中点
reconstructed = xmin + (double(indices) + 0.5) * delta;

end
