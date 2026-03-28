function [filtered, filter_coeff] = match_filter(signal, sps, filter_type, rolloff, span)
% 功能：匹配滤波——接收端脉冲成形的匹配操作，最大化SNR
% 版本：V1.0.0
% 输入：
%   signal      - 接收基带信号 (1xM 复数/实数数组)
%   sps         - 每符号采样数 (须与发端一致，默认 8)
%   filter_type - 滤波器类型 (须与发端一致，默认 'rrc')
%   rolloff     - 滚降系数 (须与发端一致，默认 0.35)
%   span        - 滤波器截断长度 (符号数，默认 6)
% 输出：
%   filtered     - 滤波后信号 (1xM 数组，可下采样提取符号)
%   filter_coeff - 匹配滤波器系数 (时间反转的脉冲成形滤波器)
%
% 备注：
%   - 匹配滤波器 = 脉冲成形滤波器的时间反转共轭
%   - 对称滤波器（rc/rrc/rect/gauss）时间反转等于自身
%   - RRC发 + RRC收 = RC（零ISI，最优采样点无码间干扰）
%   - 滤波后需在最优采样点下采样：output(span*sps/2 + 1 : sps : end)

%% ========== 1. 入参解析 ========== %%
if nargin < 5 || isempty(span), span = 6; end
if nargin < 4 || isempty(rolloff), rolloff = 0.35; end
if nargin < 3 || isempty(filter_type), filter_type = 'rrc'; end
if nargin < 2 || isempty(sps), sps = 8; end
signal = signal(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(signal), error('输入信号不能为空！'); end

%% ========== 3. 生成匹配滤波器（与发端脉冲成形滤波器相同） ========== %%
dummy = 1;
[~, filter_coeff, ~] = pulse_shape(dummy, sps, filter_type, rolloff, span);

% 匹配滤波器 = 时间反转共轭（对称实数滤波器时等于自身）
filter_coeff = conj(fliplr(filter_coeff));

%% ========== 4. 匹配滤波 ========== %%
filtered = conv(signal, filter_coeff, 'same');

end
