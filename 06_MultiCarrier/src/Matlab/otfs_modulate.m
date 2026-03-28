function [signal, params_out] = otfs_modulate(dd_symbols, N, M, cp_len, method)
% 功能：OTFS调制——DD域符号经ISFFT+Heisenberg变换生成时域信号
% 版本：V1.0.0
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
%   - 标准DFT方法：X_tf = ISFFT(x_dd) → s(t) = Heisenberg(X_tf)
%     ISFFT: X[n,m] = (1/sqrt(N)) * sum_k x_dd[k,m]*exp(j2π*nk/N)
%     Heisenberg: 对每个n，做M点IFFT得时域片段，拼接成帧
%   - Zak方法：直接在Zak域构造，数学等价但结构不同
%   - 整帧CP：覆盖最大时延扩展

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

%% ========== 4. 添加整帧CP ========== %%
signal = [signal_no_cp(end-cp_len+1:end), signal_no_cp];

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
% ISFFT: 沿多普勒维度(行方向)做N点IFFT
X_tf = zeros(N, M);
for m = 1:M
    X_tf(:, m) = ifft(x_dd(:, m)) * sqrt(N);
end

% Heisenberg变换：对每个时隙n，将M个子载波做M点IFFT得时域片段
s = zeros(1, N * M);
for n = 1:N
    s_n = ifft(X_tf(n, :)) * sqrt(M);
    s((n-1)*M+1 : n*M) = s_n;
end
end

% --------------- 辅助函数2：Zak域方法 --------------- %
function [s, X_tf] = otfs_mod_zak(x_dd, N, M)
% Zak变换实现：二维IFFT = ISFFT(列方向) + Heisenberg(行方向) 一步完成
% ifft2 = IFFT_col(Doppler维) + IFFT_row(时延维)
% 结果直接是时域信号矩阵，无需再做Heisenberg IFFT

% 二维IFFT：同时完成ISFFT和Heisenberg
s_matrix = ifft2(x_dd) * sqrt(N * M);

% 拼接各时隙为时域信号
s = reshape(s_matrix.', 1, []);

% 提取中间的时频域结果（仅列方向IFFT = ISFFT），供输出
X_tf = zeros(N, M);
for m = 1:M
    X_tf(:, m) = ifft(x_dd(:, m)) * sqrt(N);
end
end
