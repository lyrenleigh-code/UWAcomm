function [timing_offset, ted_output] = timing_fine(signal, sps, method)
% 功能：细定时同步——估计符号采样时刻的分数间隔偏移
% 版本：V1.0.0
% 输入：
%   signal - 匹配滤波后的基带信号 (1xM 复数/实数数组，每符号sps个采样)
%   sps    - 每符号采样数 (正整数，须>=2)
%   method - 定时误差检测算法 (字符串，默认 'gardner')
%            'gardner' : Gardner算法（非数据辅助，需sps>=2）
%            'mm'      : Mueller-Muller算法（数据辅助，需判决反馈）
%            'earlylate': 超前-滞后门定时
% 输出：
%   timing_offset - 估计的定时偏移 (采样数，分数值，范围 [-sps/2, sps/2))
%   ted_output    - 定时误差检测器(TED)的逐符号输出 (1xK 数组)
%
% 备注：
%   - Gardner TED: e(k) = Re{y(kT+T/2) * [conj(y(kT)) - conj(y((k+1)T))]}
%     不需要判决信息，适合突发传输
%   - Mueller-Muller TED: e(k) = Re{d*(k-1)*y(k) - d*(k)*y(k-1)}
%     需要判决d(k)，收敛后精度更高
%   - 超前-滞后门: e(k) = |y(kT+δ)|^2 - |y(kT-δ)|^2
%     简单但需要较高过采样率

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(method), method = 'gardner'; end
signal = signal(:).';
M = length(signal);

%% ========== 2. 参数校验 ========== %%
if isempty(signal), error('输入信号不能为空！'); end
if sps < 2, error('每符号采样数sps必须>=2！'); end

%% ========== 3. 定时误差检测 ========== %%
switch method
    case 'gardner'
        ted_output = gardner_ted(signal, sps);

    case 'mm'
        ted_output = mm_ted(signal, sps);

    case 'earlylate'
        ted_output = earlylate_ted(signal, sps);

    otherwise
        error('不支持的定时算法: %s！支持 gardner/mm/earlylate', method);
end

%% ========== 4. 估计平均定时偏移 ========== %%
% 取TED输出的均值作为定时偏移估计（适用于恒定偏移场景）
% 正值表示采样偏晚，负值表示偏早
avg_error = mean(ted_output);

% 归一化到采样间隔
timing_offset = avg_error * sps / (2*pi);
timing_offset = mod(timing_offset + sps/2, sps) - sps/2;  % 限制范围

end

% --------------- 辅助函数1：Gardner定时误差检测器 --------------- %
function ted = gardner_ted(signal, sps)
% GARDNER_TED 非数据辅助定时误差检测
% e(k) = Re{y(kT+T/2) * [conj(y(kT)) - conj(y((k+1)T))]}

half_sps = round(sps / 2);
num_sym = floor((length(signal) - sps) / sps);
ted = zeros(1, num_sym);

for k = 1:num_sym
    idx_curr = (k-1)*sps + 1;         % 当前符号采样点
    idx_mid = idx_curr + half_sps;     % 中间点
    idx_next = idx_curr + sps;         % 下一符号采样点

    if idx_next > length(signal), break; end

    y_curr = signal(idx_curr);
    y_mid = signal(idx_mid);
    y_next = signal(idx_next);

    ted(k) = real(y_mid * (conj(y_curr) - conj(y_next)));
end

ted = ted(1:k-1);

end

% --------------- 辅助函数2：Mueller-Muller定时误差检测器 --------------- %
function ted = mm_ted(signal, sps)
% MM_TED 数据辅助定时误差检测（使用硬判决作为数据估计）
% e(k) = Re{d*(k-1)*y(k) - d*(k)*y(k-1)}

num_sym = floor(length(signal) / sps);
ted = zeros(1, max(num_sym-1, 0));

% 下采样获取符号采样值和判决
sym_samples = signal(1:sps:num_sym*sps);
decisions = sign(real(sym_samples));    % BPSK硬判决

for k = 2:num_sym
    y_curr = sym_samples(k);
    y_prev = sym_samples(k-1);
    d_curr = decisions(k);
    d_prev = decisions(k-1);

    ted(k-1) = real(conj(d_prev) * y_curr - conj(d_curr) * y_prev);
end

end

% --------------- 辅助函数3：超前-滞后门定时误差检测器 --------------- %
function ted = earlylate_ted(signal, sps)
% EARLYLATE_TED 超前-滞后门定时
% e(k) = |y(kT+delta)|^2 - |y(kT-delta)|^2, delta = 1 sample

num_sym = floor((length(signal) - 2) / sps);
ted = zeros(1, num_sym);

for k = 1:num_sym
    idx = (k-1)*sps + 1;
    idx_early = max(idx - 1, 1);
    idx_late = min(idx + 1, length(signal));

    ted(k) = abs(signal(idx_late))^2 - abs(signal(idx_early))^2;
end

end
