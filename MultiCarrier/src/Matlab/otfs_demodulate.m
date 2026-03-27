function [dd_symbols, Y_tf] = otfs_demodulate(signal, N, M, cp_len, method)
% 功能：OTFS解调——去整帧CP + Wigner变换 + SFFT恢复DD域符号
% 版本：V1.0.0
% 输入：
%   signal  - 接收时域信号 (1xL 数组，含整帧CP)
%   N       - 多普勒格点数（须与调制端一致）
%   M       - 时延格点数（须与调制端一致）
%   cp_len  - 整帧CP长度（须与调制端一致）
%   method  - 实现方式（'dft' 或 'zak'，须与调制端一致，默认'dft'）
% 输出：
%   dd_symbols - DD域符号 (NxM 复数矩阵)
%   Y_tf       - 时频域信号 (NxM，Wigner变换输出)

%% ========== 1. 入参解析 ========== %%
if nargin < 5 || isempty(method), method = 'dft'; end
signal = signal(:).';

%% ========== 2. 去整帧CP ========== %%
if length(signal) >= cp_len + N*M
    signal_no_cp = signal(cp_len+1 : cp_len + N*M);
else
    warning('信号长度不足，截断处理！');
    signal_no_cp = signal(cp_len+1 : end);
    signal_no_cp = [signal_no_cp, zeros(1, N*M - length(signal_no_cp))];
end

%% ========== 3. Wigner变换（Heisenberg逆变换） ========== %%
Y_tf = zeros(N, M);
for n = 1:N
    if (n-1)*M+M <= length(signal_no_cp)
        r_n = signal_no_cp((n-1)*M+1 : n*M);
    else
        r_n = zeros(1, M);
    end
    Y_tf(n, :) = fft(r_n) / sqrt(M);
end

%% ========== 4. SFFT（沿多普勒维度做FFT） ========== %%
switch method
    case 'dft'
        dd_symbols = zeros(N, M);
        for m = 1:M
            dd_symbols(:, m) = fft(Y_tf(:, m)) / sqrt(N);
        end
    case 'zak'
        dd_symbols = fft2(Y_tf) / sqrt(N * M);
    otherwise
        error('不支持的方法: %s', method);
end

end
