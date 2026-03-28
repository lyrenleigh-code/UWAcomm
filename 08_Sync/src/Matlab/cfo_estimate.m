function [cfo_hz, cfo_norm] = cfo_estimate(received, preamble, fs, method)
% 功能：载波频偏(CFO)粗估计
% 版本：V1.0.0
% 输入：
%   received - 接收信号 (1xM 复数数组，须已粗同步对齐)
%   preamble - 前导码参考信号 (1xL 复数数组)
%   fs       - 采样率 (Hz)
%   method   - 估计方法 (字符串，默认 'correlate')
%              'correlate' : 互相关相位法（利用已知前导码）
%              'schmidl'   : Schmidl-Cox法（利用前导码的重复结构）
%              'cp'        : CP相关法（利用CP与数据的重复，用于OFDM）
% 输出：
%   cfo_hz   - 频偏估计值 (Hz)
%   cfo_norm - 归一化频偏 (相对于子载波间隔或采样率)
%
% 备注：
%   - 'correlate'法：将接收到的前导码与本地参考互相关，从相位差提取频偏
%     估计范围：±fs/2，精度取决于前导码长度
%   - 'schmidl'法：前导码需有两段重复结构（如 [A, A]），
%     CFO = angle(sum(r(n+N/2)*conj(r(n)))) / (pi*N/fs)
%     估计范围：±fs/N（半子载波）
%   - 'cp'法：利用OFDM符号CP与尾部相同，类似Schmidl但用CP

%% ========== 1. 入参解析 ========== %%
if nargin < 4 || isempty(method), method = 'correlate'; end
received = received(:).';
preamble = preamble(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(received), error('接收信号不能为空！'); end
if fs <= 0, error('采样率必须为正数！'); end

%% ========== 3. CFO估计 ========== %%
switch method
    case 'correlate'
        % 互相关相位法
        L = min(length(preamble), length(received));
        rx_seg = received(1:L);
        ref_seg = preamble(1:L);

        % 将信号分成两半，比较相位旋转
        half = floor(L / 2);
        corr1 = sum(rx_seg(1:half) .* conj(ref_seg(1:half)));
        corr2 = sum(rx_seg(half+1:2*half) .* conj(ref_seg(half+1:2*half)));

        % 两半之间的相位差 = CFO * 时间差
        phase_diff = angle(corr2 * conj(corr1));
        time_diff = half / fs;
        cfo_hz = phase_diff / (2 * pi * time_diff);

    case 'schmidl'
        % Schmidl-Cox法：前导码需有重复结构 [A, A]
        L = length(preamble);
        half = floor(L / 2);

        if length(received) < L
            error('接收信号长度不足以包含完整前导码！');
        end

        % 前后两半互相关
        r = received(1:L);
        P = sum(r(half+1:L) .* conj(r(1:half)));
        phase_diff = angle(P);
        cfo_hz = phase_diff * fs / (2 * pi * half);

    case 'cp'
        % CP相关法（用于OFDM，前导码=CP+数据，CP是数据尾部的拷贝）
        L = length(preamble);
        % 假设前导码前1/4为CP
        cp_len = floor(L / 4);
        data_len = L - cp_len;

        if length(received) < L
            error('接收信号长度不足！');
        end

        r = received(1:L);
        % CP段与对应数据尾段的互相关
        P = sum(r(1:cp_len) .* conj(r(data_len+1:L)));
        phase_diff = angle(P);
        cfo_hz = phase_diff * fs / (2 * pi * data_len);

    otherwise
        error('不支持的CFO估计方法: %s！支持 correlate/schmidl/cp', method);
end

cfo_norm = cfo_hz / fs;

end
