function freq_symbols = ofdm_demodulate(signal, N, cp_len, cp_type)
% 功能：OFDM解调——去CP/ZP + FFT恢复频域符号
% 版本：V1.0.0
% 输入：
%   signal  - 时域OFDM信号 (1xL 数组)
%   N       - FFT点数（须与调制端一致）
%   cp_len  - CP/ZP长度（须与调制端一致）
%   cp_type - 前缀类型 ('cp' 或 'zp'，须与调制端一致，默认'cp')
% 输出：
%   freq_symbols - 恢复的频域符号 (1xM 数组)
%
% 备注：
%   - CP模式：直接丢弃前cp_len个样本，对剩余N个样本做FFT
%   - ZP模式：overlap-add方法将尾部cp_len样本叠加到头部后做FFT

%% ========== 1. 入参解析 ========== %%
if nargin < 4 || isempty(cp_type), cp_type = 'cp'; end
signal = signal(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(signal), error('输入信号不能为空！'); end
symbol_len = N + cp_len;
if mod(length(signal), symbol_len) ~= 0
    warning('信号长度(%d)不是符号长度(%d)的整数倍，截断处理！', length(signal), symbol_len);
end

%% ========== 3. 去CP/ZP + FFT ========== %%
num_symbols = floor(length(signal) / symbol_len);
freq_symbols = zeros(1, num_symbols * N);

for s = 1:num_symbols
    block = signal((s-1)*symbol_len+1 : s*symbol_len);

    if strcmp(cp_type, 'cp')
        % CP模式：丢弃前cp_len个样本
        x = block(cp_len+1 : end);
    else
        % ZP模式：overlap-add（尾部cp_len叠加到头部）
        x_data = block(1:N);
        x_tail = block(N+1:end);
        x = x_data;
        x(1:cp_len) = x(1:cp_len) + x_tail;
    end

    % FFT变换到频域
    X = fft(x, N) / sqrt(N);          % 归一化与调制端一致

    freq_symbols((s-1)*N+1 : s*N) = X;
end

end
