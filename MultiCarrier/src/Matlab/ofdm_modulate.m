function [signal, params_out] = ofdm_modulate(freq_symbols, N, cp_len, cp_type)
% 功能：OFDM调制——频域符号经IFFT变换+CP/ZP插入生成时域信号
% 版本：V1.0.0
% 输入：
%   freq_symbols - 频域数据符号 (1xM 数组，M须为N的整数倍，按符号顺序排列)
%                  每N个符号组成一个OFDM符号
%   N            - FFT/IFFT点数（子载波数，正整数，建议2的幂，默认 256）
%   cp_len       - CP/ZP长度（采样点数，默认 N/4）
%   cp_type      - 前缀类型（'cp'循环前缀(默认) 或 'zp'补零）
% 输出：
%   signal     - 时域OFDM信号 (1xL 数组)
%   params_out - 参数结构体（供解调使用）
%       .N         : FFT点数
%       .cp_len    : CP/ZP长度
%       .cp_type   : 前缀类型
%       .num_symbols: OFDM符号数
%       .symbol_len : 每OFDM符号总长 (N + cp_len)
%
% 备注：
%   - CP模式：复制OFDM符号尾部cp_len个样本到头部
%   - ZP模式：在OFDM符号尾部补cp_len个零
%   - ZP-OFDM接收端需用重叠相加(overlap-add)或等效方法处理

%% ========== 1. 入参解析 ========== %%
if nargin < 4 || isempty(cp_type), cp_type = 'cp'; end
if nargin < 3 || isempty(cp_len), cp_len = floor(N/4); end
if nargin < 2 || isempty(N), N = 256; end
freq_symbols = freq_symbols(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(freq_symbols), error('频域符号不能为空！'); end
if N < 2, error('FFT点数N必须>=2！'); end
if cp_len < 0 || cp_len >= N, error('CP长度必须在[0, N)范围内！'); end
if ~ismember(cp_type, {'cp','zp'}), error('cp_type必须为 cp 或 zp！'); end
if mod(length(freq_symbols), N) ~= 0
    error('频域符号长度(%d)必须为N=%d的整数倍！', length(freq_symbols), N);
end

%% ========== 3. IFFT + CP/ZP插入 ========== %%
num_symbols = length(freq_symbols) / N;
symbol_len = N + cp_len;
signal = zeros(1, num_symbols * symbol_len);

for s = 1:num_symbols
    % 取当前OFDM符号的频域数据
    X = freq_symbols((s-1)*N+1 : s*N);

    % IFFT变换到时域
    x = ifft(X, N) * sqrt(N);         % 归一化：保持功率一致

    % 加CP或ZP
    if strcmp(cp_type, 'cp')
        x_with_prefix = [x(end-cp_len+1:end), x];   % 复制尾部
    else
        x_with_prefix = [x, zeros(1, cp_len)];       % 尾部补零
    end

    signal((s-1)*symbol_len+1 : s*symbol_len) = x_with_prefix;
end

%% ========== 4. 输出参数 ========== %%
params_out.N = N;
params_out.cp_len = cp_len;
params_out.cp_type = cp_type;
params_out.num_symbols = num_symbols;
params_out.symbol_len = symbol_len;

end
