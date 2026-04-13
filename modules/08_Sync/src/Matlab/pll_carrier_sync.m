function [r_pll, phi_track, info] = pll_carrier_sync(r, mod_order, Kp, Ki)
% 功能：决策导向锁相环（DD-PLL）载波同步——逐符号相位跟踪与补偿
% 版本：V1.0.0
% 输入：
%   r         - 均衡后的符号序列 (1xN 复数)
%   mod_order - 调制阶数 (2=BPSK, 4=QPSK, 默认 4)
%   Kp        - 比例增益 (默认 0.01)
%   Ki        - 积分增益 (默认 0.005)
% 输出：
%   r_pll     - 相位补偿后的符号 (1xN 复数)
%   phi_track - 相位跟踪轨迹 (1xN rad)
%   info      - 附加信息
%       .phase_error : 逐符号相位误差 (1xN)
%       .freq_est    : 逐符号频偏估计 (1xN Hz，需除以符号率)
%
% 原理：
%   相位误差: e[n] = Im(r_pll[n] · conj(d̂[n]))
%   积分器:   φ_acc[n+1] = φ_acc[n] + Ki·e[n]
%   校正量:   φ_corr[n] = Kp·e[n] + φ_acc[n]
%   补偿:     r_pll[n] = r[n] · exp(-j·φ_track[n])

%% ========== 1. 入参解析 ========== %%
if nargin < 4 || isempty(Ki), Ki = 0.005; end
if nargin < 3 || isempty(Kp), Kp = 0.01; end
if nargin < 2 || isempty(mod_order), mod_order = 4; end
r = r(:).';
N = length(r);

%% ========== 2. 参数校验 ========== %%
if isempty(r), error('输入信号不能为空！'); end

%% ========== 3. DD-PLL跟踪 ========== %%
phi_track = zeros(1, N);
phase_error = zeros(1, N);
r_pll = zeros(1, N, 'like', 1j);
phi_acc = 0;

for n = 1:N
    % 相位补偿
    r_pll(n) = r(n) * exp(-1j * phi_track(n));

    % 硬判决
    d_hat = hard_decision(r_pll(n), mod_order);

    % 相位误差检测
    phase_error(n) = imag(r_pll(n) * conj(d_hat));

    % PI环路滤波
    phi_acc = phi_acc + Ki * phase_error(n);
    phi_corr = Kp * phase_error(n) + phi_acc;

    % 更新下一时刻
    if n < N
        phi_track(n+1) = phi_track(n) + phi_corr;
    end
end

%% ========== 4. 输出 ========== %%
info.phase_error = phase_error;
info.freq_est = diff([0, phi_track]) / (2*pi);  % 归一化频偏

end

% --------------- 辅助函数：硬判决 --------------- %
function d = hard_decision(y, mod_order)
switch mod_order
    case 2
        d = sign(real(y));
        if d == 0, d = 1; end
    case 4
        d = (sign(real(y)) + 1j*sign(imag(y))) / sqrt(2);
    otherwise
        d = (sign(real(y)) + 1j*sign(imag(y))) / sqrt(2);
end
end
