function y = poly_resample(x, p, q, varargin)
% POLY_RESAMPLE 多相 FIR 重采样（与 MATLAB resample 等价，自逆匹配对）
%
% 功能：对信号 x 做多相 FIR 重采样，输出长度 ≈ length(x) * p / q
% 自逆性质：对同一 L/beta 参数，poly_resample(poly_resample(x, p, q), q, p) ≈ x
% 算法：Kaiser 加窗 sinc 抗混叠 LPF + upsample/filter/downsample
%       与 MATLAB `resample` 同架构（fir1-Kaiser polyphase）
%
% 输入：
%   x       - 输入信号 (1xN，实数或复数)
%   p, q    - 整数比率（p/q = 输出速率 / 输入速率）
%   可选：
%     'L', n    - FIR 半长系数（default 10，与 MATLAB resample 默认一致）
%     'beta', b - Kaiser 窗参数（default 5.0）
%
% 输出：
%   y - 重采样信号 (1xM，M = ceil(length(x)*p/q) 经 gcd 化简后)
%
% 使用场景（匹配对）：
%   Channel  Doppler 仿真：s_doppler = poly_resample(s,  q, p)   % 压缩 1/(1+α)
%   RX       Doppler 补偿：rx_comp   = poly_resample(rx, p, q)   % 拉伸 (1+α)
%   其中 [p,q] = rat(1+α, 1e-10)，两者形成严格匹配对
%
% 版本：V1.0.0（2026-04-22）

%% 参数解析
L = 10;
beta = 5.0;
for kv = 1:2:length(varargin)
    switch lower(varargin{kv})
        case 'l',    L    = varargin{kv+1};
        case 'beta', beta = varargin{kv+1};
        otherwise
            error('poly_resample: 未知参数 %s', varargin{kv});
    end
end

%% 入参校验
if ~isscalar(p) || ~isscalar(q) || p < 1 || q < 1 || ...
        p ~= round(p) || q ~= round(q)
    error('poly_resample: p 和 q 必须是正整数');
end
if isempty(x), error('poly_resample: 输入信号不能为空'); end
x = x(:).';

%% GCD 化简
g = gcd(p, q);
p = p / g;
q = q / g;

%% 平凡情况
if p == 1 && q == 1
    y = x;
    return;
end

N = length(x);
M = max(p, q);

%% FIR 抗混叠滤波器设计（Kaiser 加窗 sinc）
% N_h 奇数确保 delay 对称
N_h = 2 * L * M + 1;
n_tap = -(N_h-1)/2 : (N_h-1)/2;
h_ideal = sinc(n_tap / M);              % 理想 LPF cutoff = 1/M（归一化到 upsample 速率）
w = kaiser(N_h, beta).';                 % Kaiser 窗
h = h_ideal .* w;
h = h * p / sum(h);                      % 归一化：总增益 = p（补偿 upsample 零插值）

%% Step 1：upsample by p（插零）
x_up = zeros(1, N * p);
x_up(1:p:end) = x;

%% Step 2：filter（含 delay 对齐，两端零扩展后 'valid' 卷积）
delay = (N_h - 1) / 2;
x_ext = [zeros(1, delay), x_up, zeros(1, delay)];
y_full = conv(x_ext, h, 'valid');        % 长度 = N*p

%% Step 3：downsample by q
y = y_full(1:q:end);

end
