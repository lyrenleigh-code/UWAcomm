function [start_idx, peak_val, corr_out] = sync_detect(received, preamble, threshold, params)
% 功能：粗同步检测——匹配滤波寻找前导码起始位置
% 版本：V2.0.0
% 输入：
%   received  - 接收信号 (1xM 实数/复数数组)
%   preamble  - 前导码（参考信号，由gen_lfm/gen_hfm/gen_zc_seq/gen_barker生成）
%   threshold - 检测门限 (0~1，归一化相关峰值门限，默认 0.5)
%   params    - 可选参数结构体 (V2.0新增)
%       .method  : 检测方法 (默认 'correlate')
%                  'correlate' : 标准滑动互相关（V1.0行为）
%                  'doppler'   : 二维时延-多普勒补偿搜索（时变信道）
%       .fs      : 采样率 (Hz，doppler方法必须)
%       .fd_max  : 最大多普勒频移 (Hz，默认 50)
%       .num_fd  : 多普勒频率搜索网格数 (默认 21)
% 输出：
%   start_idx - 检测到的前导起始位置索引 (标量，0表示未检测到)
%   peak_val  - 归一化相关峰值 (0~1)
%   corr_out  - 完整的归一化相关输出 (1x(M-L+1) 数组)
%              doppler方法时为最优多普勒频率下的相关输出
%
% 备注：
%   - V2.0新增doppler方法：扫描多普勒频率网格，对每个候选频偏做补偿相关
%     公式：argmax_k max_f |Σ r(n+k)·s*(n)·exp(-j2πfnTs)|²
%   - 标准correlate方法保持V1.0行为不变（向后兼容）
%   - 多个峰超过门限时返回最大峰位置

%% ========== 1. 入参解析 ========== %%
if nargin < 4 || isempty(params), params = struct(); end
if nargin < 3 || isempty(threshold), threshold = 0.5; end
if ~isfield(params, 'method'), params.method = 'correlate'; end
received = received(:).';
preamble = preamble(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(received), error('接收信号不能为空！'); end
if isempty(preamble), error('前导码不能为空！'); end
L = length(preamble);
M = length(received);
if L > M, error('前导码长度(%d)大于接收信号长度(%d)！', L, M); end

%% ========== 3. 同步检测 ========== %%
switch params.method
    case 'correlate'
        corr_out = sliding_corr(received, preamble, L, M);

    case 'doppler'
        if ~isfield(params, 'fs'), error('doppler方法需要params.fs！'); end
        if ~isfield(params, 'fd_max'), params.fd_max = 50; end
        if ~isfield(params, 'num_fd'), params.num_fd = 21; end
        corr_out = doppler_compensated_corr(received, preamble, L, M, ...
                       params.fs, params.fd_max, params.num_fd);

    otherwise
        error('不支持的检测方法: %s！支持 correlate/doppler', params.method);
end

%% ========== 4. 峰值检测 ========== %%
[peak_val, peak_pos] = max(corr_out);

if peak_val >= threshold
    start_idx = peak_pos;
else
    start_idx = 0;
    warning('同步检测未超过门限(峰值=%.3f, 门限=%.3f)！', peak_val, threshold);
end

end

% --------------- 辅助函数1：标准滑动归一化互相关 --------------- %
function corr_out = sliding_corr(received, preamble, L, M)

num_corr = M - L + 1;
corr_out = zeros(1, num_corr);
preamble_energy = sum(abs(preamble).^2);

for n = 1:num_corr
    segment = received(n : n+L-1);
    segment_energy = sum(abs(segment).^2);

    if segment_energy < 1e-20
        corr_out(n) = 0;
    else
        corr_out(n) = abs(sum(segment .* conj(preamble))) / ...
                      sqrt(segment_energy * preamble_energy);
    end
end

end

% --------------- 辅助函数2：多普勒补偿二维搜索 --------------- %
function corr_out = doppler_compensated_corr(received, preamble, L, M, fs, fd_max, num_fd)
% 二维时延-多普勒搜索：
%   argmax_k max_f |Σ r(n+k)·s*(n)·exp(-j2πf·n/fs)|²

num_corr = M - L + 1;
fd_grid = linspace(-fd_max, fd_max, num_fd);
n_vec = (0:L-1);
Ts = 1 / fs;

preamble_energy = sum(abs(preamble).^2);

% 对每个多普勒频率计算补偿后的相关
corr_all = zeros(num_fd, num_corr);
for fi = 1:num_fd
    comp = exp(-1j * 2 * pi * fd_grid(fi) * n_vec * Ts);
    preamble_comp = preamble .* comp;

    for n = 1:num_corr
        segment = received(n : n+L-1);
        segment_energy = sum(abs(segment).^2);

        if segment_energy < 1e-20
            corr_all(fi, n) = 0;
        else
            corr_all(fi, n) = abs(sum(segment .* conj(preamble_comp))) / ...
                              sqrt(segment_energy * preamble_energy);
        end
    end
end

% 取每个时延点上所有多普勒频率的最大值
corr_out = max(corr_all, [], 1);

end
