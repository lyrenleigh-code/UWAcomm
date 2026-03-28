function [cfo_hz, cfo_norm] = cfo_estimate(received, preamble, fs, method)
% 功能：载波频偏(CFO)粗估计（调用模块10 DopplerProc的估计算法）
% 版本：V2.0.0
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
%   cfo_norm - 归一化频偏 (相对于采样率)
%
% 备注：
%   - v2.0重构：'cp'方法调用10_DopplerProc/est_doppler_cp
%   - 'correlate'和'schmidl'保留本地实现（不涉及多普勒因子α）
%   - CFO与多普勒的关系：cfo ≈ α × fc，本函数专注于频偏(Hz)

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
        % 互相关相位法（本地实现，简单高效）
        L = min(length(preamble), length(received));
        rx_seg = received(1:L);
        ref_seg = preamble(1:L);

        half = floor(L / 2);
        corr1 = sum(rx_seg(1:half) .* conj(ref_seg(1:half)));
        corr2 = sum(rx_seg(half+1:2*half) .* conj(ref_seg(half+1:2*half)));

        phase_diff = angle(corr2 * conj(corr1));
        time_diff = half / fs;
        cfo_hz = phase_diff / (2 * pi * time_diff);

    case 'schmidl'
        % Schmidl-Cox法（本地实现）
        L = length(preamble);
        half = floor(L / 2);

        if length(received) < L
            error('接收信号长度不足以包含完整前导码！');
        end

        r = received(1:L);
        P = sum(r(half+1:L) .* conj(r(1:half)));
        phase_diff = angle(P);
        cfo_hz = phase_diff * fs / (2 * pi * half);

    case 'cp'
        % CP自相关法——调用模块10的est_doppler_cp
        % 需要N_fft和N_cp参数，从前导码长度推算
        L = length(preamble);
        N_cp = floor(L / 5);          % 假设CP占1/5
        N_fft = L - N_cp;

        [alpha_est, ~] = est_doppler_cp(received, N_fft, N_cp, true);

        % α转CFO：cfo ≈ α × fs（近似，精确值需要载频fc）
        cfo_hz = alpha_est * fs;

    otherwise
        error('不支持的CFO估计方法: %s！支持 correlate/schmidl/cp', method);
end

cfo_norm = cfo_hz / fs;

end
