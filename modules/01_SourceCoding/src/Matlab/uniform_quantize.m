function [indices, levels, quantized_signal] = uniform_quantize(signal, num_bits, val_range)
% 功能：对连续信号进行均匀量化，输出量化索引、量化电平和量化后信号
% 版本：V1.0.0
% 输入：
%   signal      - 待量化的连续信号 (任意尺寸数值数组)
%   num_bits    - 量化比特数 (正整数，如 8 表示256级量化)
%   val_range   - 量化范围 [xmin, xmax] (1x2 数组)
%                 超出范围的信号值将被截断到边界
% 输出：
%   indices     - 量化索引 (与signal同尺寸，取值 0 ~ 2^num_bits-1)
%   levels      - 全部量化电平值 (1 x 2^num_bits 数组)
%   quantized_signal - 量化后的信号 (与signal同尺寸，取值为对应量化电平)
%
% 备注：
%   - 采用中点量化策略：每个量化区间的代表值取区间中点
%   - 量化区间：delta = (xmax - xmin) / L，L = 2^num_bits
%   - 量化电平：level_k = xmin + (k + 0.5) * delta，k = 0,1,...,L-1
%   - 量化噪声功率（均匀分布信号）：delta^2 / 12

%% ========== 1. 入参解析与初始化 ========== %%
xmin = val_range(1);                   % 量化下界
xmax = val_range(2);                   % 量化上界
L = 2^num_bits;                        % 量化级数
delta = (xmax - xmin) / L;            % 量化步长

%% ========== 2. 严格参数校验 ========== %%
if isempty(signal)
    error('输入信号不能为空！');
end
if ~isnumeric(signal)
    error('输入信号必须为数值类型！');
end
if ~isnumeric(num_bits) || num_bits < 1 || num_bits ~= floor(num_bits)
    error('量化比特数必须为正整数！');
end
if num_bits > 32
    warning('量化比特数 %d 过大，可能导致内存不足！', num_bits);
end
if length(val_range) ~= 2
    error('val_range必须为 [xmin, xmax] 形式的1x2数组！');
end
if xmin >= xmax
    error('val_range(1) 必须小于 val_range(2)！当前值：[%.4f, %.4f]', xmin, xmax);
end

%% ========== 3. 信号截断 ========== %%
% 超出量化范围的信号截断到边界
clipped = signal;
num_over  = sum(signal(:) > xmax);
num_under = sum(signal(:) < xmin);
if num_over > 0 || num_under > 0
    warning('有 %d 个样本超出量化上界、%d 个样本低于量化下界，已截断处理。', ...
            num_over, num_under);
end
clipped(clipped > xmax) = xmax - eps;  % 防止 xmax 被映射到 L
clipped(clipped < xmin) = xmin;

%% ========== 4. 量化计算 ========== %%
% 计算量化索引：index = floor((x - xmin) / delta)
indices = floor((clipped - xmin) / delta);
indices(indices >= L) = L - 1;         % 安全截断（防止浮点误差导致越界）
indices(indices < 0) = 0;

%% ========== 5. 生成量化电平表 ========== %%
levels = xmin + ((0:L-1) + 0.5) * delta;  % 各级量化中点值

%% ========== 6. 量化后信号重建 ========== %%
quantized_signal = levels(indices + 1);    % 索引映射到量化电平（MATLAB下标从1起）

end
