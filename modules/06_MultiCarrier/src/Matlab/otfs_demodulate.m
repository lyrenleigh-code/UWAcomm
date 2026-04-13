function [dd_symbols, Y_tf] = otfs_demodulate(signal, N, M, cp_len, method)
% 功能：OTFS解调——去per-sub-block CP + Wigner变换 + SFFT + 恢复DD域符号
% 版本：V4.0.0 — 与V3.0解调逻辑相同（RX不做窗补偿，窗效应由均衡器处理）
% 输入：
%   signal  - 接收时域信号 (1xL 数组，含per-sub-block CP)
%   N       - 多普勒格点数（须与调制端一致）
%   M       - 时延格点数（须与调制端一致）
%   cp_len  - CP长度（须与调制端一致）
%   method  - 实现方式（'dft' 或 'zak'，默认'dft'）
% 输出：
%   dd_symbols - DD域符号 (NxM 复数矩阵)
%   Y_tf       - 时频域信号 (NxM，Wigner变换输出)
%
% 备注：
%   TX端脉冲成形(pulse_type)和CP窗化(cp_window)的效应：
%   - CP窗化: 丢弃CP时一并移除，RX无需处理
%   - 数据脉冲成形: 窗效应纳入等效信道，由eq_otfs_lmmse补偿
%   因此解调器与V3.0完全相同，无需知道TX使用了哪种脉冲

%% ========== 1. 入参解析 ========== %%
if nargin < 5 || isempty(method), method = 'dft'; end
signal = signal(:).';

%% ========== 2. 去Per-sub-block CP ========== %%
sub_size = M + cp_len;
total_expected = N * sub_size;
signal_no_cp = zeros(1, N * M);
for n = 1:N
    offset = (n-1) * sub_size;
    if offset + sub_size <= length(signal)
        sub_with_cp = signal(offset+1 : offset+sub_size);
    else
        sub_with_cp = [signal(offset+1:end), zeros(1, sub_size - (length(signal)-offset))];
    end
    signal_no_cp((n-1)*M+1 : n*M) = sub_with_cp(cp_len+1 : end);  % 去CP取数据
end

%% ========== 3. Wigner + SFFT ========== %%
switch method
    case 'dft'
        % 分步实现：Wigner(行FFT) → SFFT(列FFT) → 频率→延迟(行IFFT)
        Y_tf = zeros(N, M);
        for n = 1:N
            if (n-1)*M+M <= length(signal_no_cp)
                r_n = signal_no_cp((n-1)*M+1 : n*M);
            else
                r_n = zeros(1, M);
            end
            Y_tf(n, :) = fft(r_n) / sqrt(M);   % Wigner：行FFT
        end
        % SFFT：列FFT → 得到多普勒-频率域
        dd_freq = zeros(N, M);
        for m = 1:M
            dd_freq(:, m) = fft(Y_tf(:, m)) / sqrt(N);
        end
        % 频率→延迟：行方向IFFT → 得到真实DD域(多普勒×时延)
        dd_symbols = zeros(N, M);
        for k = 1:N
            dd_symbols(k, :) = ifft(dd_freq(k, :)) * sqrt(M);
        end

    case 'zak'
        % 二维FFT得到多普勒-频率域，再行IFFT转延迟域
        r_matrix = reshape(signal_no_cp(1:N*M), M, N).';  % NxM矩阵
        dd_freq = fft2(r_matrix) / sqrt(N * M);
        % 频率→延迟：行方向IFFT
        dd_symbols = zeros(N, M);
        for k = 1:N
            dd_symbols(k, :) = ifft(dd_freq(k, :)) * sqrt(M);
        end
        % 提取中间时频域结果供输出
        Y_tf = zeros(N, M);
        for n = 1:N
            r_n = signal_no_cp((n-1)*M+1 : n*M);
            Y_tf(n, :) = fft(r_n) / sqrt(M);
        end

    otherwise
        error('不支持的方法: %s', method);
end

end
