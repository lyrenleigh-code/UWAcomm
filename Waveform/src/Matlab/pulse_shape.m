function [shaped_signal, filter_coeff, t_filter] = pulse_shape(symbols, sps, filter_type, rolloff, span)
% 功能：脉冲成形滤波——将符号序列上采样并进行脉冲成形
% 版本：V1.0.0
% 输入：
%   symbols     - 符号序列 (1xN 复数/实数数组)
%   sps         - 每符号采样数 (正整数，即上采样因子，默认 8)
%   filter_type - 滤波器类型 (字符串，默认 'rrc')
%                 'rc'   : 升余弦 (Raised Cosine)
%                 'rrc'  : 根升余弦 (Root Raised Cosine)
%                 'rect' : 矩形脉冲
%                 'gauss': 高斯脉冲
%   rolloff     - 滚降系数 (0~1，rc/rrc用，默认 0.35)
%                 高斯脉冲时为 BT 积（带宽×符号周期，默认 0.5）
%   span        - 滤波器截断长度 (符号数，默认 6，总长 = span*sps+1)
% 输出：
%   shaped_signal - 成形后的基带信号 (1xM 数组)
%   filter_coeff  - 滤波器系数 (1xL 数组，归一化为单位能量)
%   t_filter      - 滤波器时间轴 (1xL 数组，单位：符号周期)
%
% 备注：
%   - 上采样：符号间插入 sps-1 个零
%   - RRC成形后需在收端再做RRC匹配滤波，两者级联等效为RC（零ISI）
%   - 矩形脉冲为最简单的零阶保持
%   - 高斯脉冲用于GMSK等恒包络调制

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 5 || isempty(span), span = 6; end
if nargin < 4 || isempty(rolloff), rolloff = 0.35; end
if nargin < 3 || isempty(filter_type), filter_type = 'rrc'; end
if nargin < 2 || isempty(sps), sps = 8; end
symbols = symbols(:).';

%% ========== 2. 严格参数校验 ========== %%
if isempty(symbols), error('符号序列不能为空！'); end
if sps < 1 || sps ~= floor(sps), error('sps必须为正整数！'); end
if ~ismember(filter_type, {'rc','rrc','rect','gauss'})
    error('filter_type必须为 rc/rrc/rect/gauss！');
end
if (strcmp(filter_type,'rc') || strcmp(filter_type,'rrc')) && (rolloff < 0 || rolloff > 1)
    error('滚降系数必须在[0,1]范围内！');
end

%% ========== 3. 生成滤波器系数 ========== %%
half_len = span * sps / 2;
t_idx = -half_len : half_len;
t_filter = t_idx / sps;               % 时间轴（符号周期为单位）
L = length(t_idx);

switch filter_type
    case 'rc'
        filter_coeff = rc_filter(t_filter, rolloff);
    case 'rrc'
        filter_coeff = rrc_filter(t_filter, rolloff);
    case 'rect'
        filter_coeff = zeros(1, L);
        filter_coeff(abs(t_filter) <= 0.5) = 1;
    case 'gauss'
        BT = rolloff;                 % 高斯脉冲用BT积
        alpha = sqrt(log(2)/2) / BT;
        filter_coeff = sqrt(2*pi) * alpha * exp(-2 * (pi * alpha * t_filter).^2);
end

% 归一化为单位能量
filter_coeff = filter_coeff / sqrt(sum(filter_coeff.^2));

%% ========== 4. 上采样 + 滤波 ========== %%
N = length(symbols);
upsampled = zeros(1, N * sps);
upsampled(1:sps:end) = symbols;

shaped_signal = conv(upsampled, filter_coeff, 'same');

end

% --------------- 辅助函数1：升余弦滤波器 --------------- %
function h = rc_filter(t, beta)
h = zeros(size(t));
for k = 1:length(t)
    tk = t(k);
    if tk == 0
        h(k) = 1;
    elseif beta > 0 && abs(abs(tk) - 1/(2*beta)) < 1e-10
        h(k) = beta/2 * sin(pi/(2*beta));
    else
        h(k) = sinc(tk) .* cos(pi*beta*tk) ./ (1 - (2*beta*tk)^2);
    end
end
end

% --------------- 辅助函数2：根升余弦滤波器 --------------- %
function h = rrc_filter(t, beta)
h = zeros(size(t));
for k = 1:length(t)
    tk = t(k);
    if tk == 0
        h(k) = 1 - beta + 4*beta/pi;
    elseif beta > 0 && abs(abs(tk) - 1/(4*beta)) < 1e-10
        h(k) = beta/sqrt(2) * ((1+2/pi)*sin(pi/(4*beta)) + (1-2/pi)*cos(pi/(4*beta)));
    else
        h(k) = (sin(pi*tk*(1-beta)) + 4*beta*tk.*cos(pi*tk*(1+beta))) ...
               ./ (pi*tk.*(1-(4*beta*tk)^2));
    end
end
end
