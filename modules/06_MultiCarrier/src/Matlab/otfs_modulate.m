function [signal, params_out] = otfs_modulate(dd_symbols, N, M, cp_len, method)
% 功能：OTFS调制——DD域符号经延迟→频率转换+ISFFT+Heisenberg变换生成时域信号
% 版本：V3.0.0 — Per-sub-block CP + DD域修正(V2.0)
% 输入：
%   dd_symbols - DD域数据符号 (NxM 矩阵 或 1x(N*M) 向量)
%                N=多普勒维度(行), M=时延维度(列)
%   N          - 多普勒格点数（OFDM符号数，默认 8）
%   M          - 时延格点数（子载波数，默认 32）
%   cp_len     - 整帧CP长度（采样点数，默认 M/4）
%   method     - 实现方式（'dft'标准DFT(默认) 或 'zak' Zak域实现）
% 输出：
%   signal     - 时域OTFS帧信号 (1xL 数组，含整帧CP)
%   params_out - 参数结构体
%       .N, .M, .cp_len, .method
%       .X_tf      : 时频域信号 (NxM，ISFFT输出)
%       .total_len : 信号总长
%
% 备注：
%   - V2.0变更：x_dd第二维现在是真实时延索引l（与物理延迟对应），
%     内部先做行FFT(延迟→频率)再进ISFFT+Heisenberg。
%     数学上行FFT与Heisenberg的行IFFT相消，净效果等价于：
%     s(n,l) = (1/√N) * Σ_k x_dd(k,l) * exp(j2πnk/N)
%     即仅做多普勒维IFFT，时延维直接映射到时域。
%   - 整帧CP：覆盖最大时延扩展
%   - 信道延迟d在DD域表现为时延维位移（非相位旋转）

%% ========== 1. 入参解析 ========== %%
if nargin < 5 || isempty(method), method = 'dft'; end
if nargin < 4 || isempty(cp_len), cp_len = floor(M/4); end
if nargin < 3 || isempty(M), M = 32; end
if nargin < 2 || isempty(N), N = 8; end

% 将向量转为矩阵
if isvector(dd_symbols)
    dd_symbols = reshape(dd_symbols(:), N, M);
end

%% ========== 2. 参数校验 ========== %%
if isempty(dd_symbols), error('DD域符号不能为空！'); end
[rows, cols] = size(dd_symbols);
if rows ~= N || cols ~= M
    error('DD域符号尺寸(%dx%d)与N=%d,M=%d不匹配！', rows, cols, N, M);
end

%% ========== 3. OTFS调制 ========== %%
switch method
    case 'dft'
        [signal_no_cp, X_tf] = otfs_mod_dft(dd_symbols, N, M);
    case 'zak'
        [signal_no_cp, X_tf] = otfs_mod_zak(dd_symbols, N, M);
    otherwise
        error('不支持的方法: %s！支持 dft/zak', method);
end

%% ========== 4. 添加CP ========== %%
% Per-sub-block CP: 每个子块(M样本)独立加CP
% 优势: 信道在每子块内精确循环卷积 → BCCB结构成立 → LMMSE/UAMP精确
% 代价: N*cp_len样本开销 (vs 帧CP仅cp_len)
signal = zeros(1, N * (M + cp_len));
for n = 1:N
    sub_block = signal_no_cp((n-1)*M+1 : n*M);
    offset = (n-1) * (M + cp_len);
    signal(offset+1 : offset+cp_len) = sub_block(end-cp_len+1 : end);  % CP
    signal(offset+cp_len+1 : offset+cp_len+M) = sub_block;              % 数据
end

%% ========== 5. 输出参数 ========== %%
params_out.N = N;
params_out.M = M;
params_out.cp_len = cp_len;
params_out.method = method;
params_out.X_tf = X_tf;
params_out.total_len = length(signal);

end

% --------------- 辅助函数1：标准DFT方法 --------------- %
function [s, X_tf] = otfs_mod_dft(x_dd, N, M)
% Step 0: 延迟→频率（行方向FFT）
% x_dd(k,l)在真实DD域，需转到(k,m)多普勒-频率域供后续处理
x_df = zeros(N, M);
for k = 1:N
    x_df(k, :) = fft(x_dd(k, :)) / sqrt(M);
end

% Step 1: ISFFT: 沿多普勒维度(列方向)做N点IFFT
X_tf = zeros(N, M);
for m = 1:M
    X_tf(:, m) = ifft(x_df(:, m)) * sqrt(N);
end

% Step 2: Heisenberg变换：对每个时隙n，将M个子载波做M点IFFT得时域片段
% 注：Step0的行FFT与此处行IFFT相消，净效果 = 仅多普勒维IFFT
s = zeros(1, N * M);
for n = 1:N
    s_n = ifft(X_tf(n, :)) * sqrt(M);
    s((n-1)*M+1 : n*M) = s_n;
end
end

% --------------- 辅助函数2：Zak域方法 --------------- %
function [s, X_tf] = otfs_mod_zak(x_dd, N, M)
% Zak变换实现：先延迟→频率，再二维IFFT
% 延迟→频率（行方向FFT）
x_df = fft(x_dd, [], 2) / sqrt(M);

% 二维IFFT：同时完成ISFFT和Heisenberg
s_matrix = ifft2(x_df) * sqrt(N * M);

% 拼接各时隙为时域信号
s = reshape(s_matrix.', 1, []);

% 提取中间的时频域结果（仅列方向IFFT = ISFFT），供输出
X_tf = zeros(N, M);
for m = 1:M
    X_tf(:, m) = ifft(x_df(:, m)) * sqrt(N);
end
end
