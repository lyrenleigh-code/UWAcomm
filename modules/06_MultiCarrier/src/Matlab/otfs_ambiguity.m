function [chi, tau_axis, nu_axis, metrics] = otfs_ambiguity(g, fs, N_tau, N_nu)
% 功能：计算脉冲的2D模糊度函数（Ambiguity Function）
% 版本：V1.1.0 — FFT方法替代逐点sinc插值，零填充提升分辨率
% 输入：
%   g      - 1×M 脉冲波形（时域）
%   fs     - 采样率 (Hz)（默认1→归一化轴）
%   N_tau  - 延迟维显示点数（默认 2*M-1）
%   N_nu   - 多普勒维FFT点数（默认 8*M, 零填充提升频率分辨率）
% 输出：
%   chi      - N_nu × N_tau 模糊度函数矩阵（归一化峰值=1）
%   tau_axis - 延迟轴（秒），长度 N_tau
%   nu_axis  - 多普勒轴（Hz），长度 N_nu
%   metrics  - 量化指标结构体
%     .mainlobe_tau_3dB  : 延迟维 -3dB 主瓣宽度（秒）
%     .mainlobe_nu_3dB   : 多普勒维 -3dB 主瓣宽度（Hz）
%     .peak_sidelobe_tau : 零多普勒切面最高旁瓣（dB）
%     .peak_sidelobe_nu  : 零延迟切面最高旁瓣（dB）
%
% 原理：
%   对每个整数延迟 k，计算:
%     R_k[n] = g[n] * conj(g[n-k])   (n-k超出范围时为0)
%   然后对 R_k 做零填充FFT得到多普勒维:
%     chi(nu, k) = |FFT_Nnu{ R_k[n] }|
%   FFT方法比逐点计算快 O(M) 倍

%% ========== 1. 入参解析 ========== %%
g = g(:).';
M = length(g);
if nargin < 4 || isempty(N_nu), N_nu = 8 * M; end
if nargin < 3 || isempty(N_tau), N_tau = 2*M - 1; end
if nargin < 2 || isempty(fs), fs = 1; end

%% ========== 2. 延迟范围 ========== %%
% 整数延迟: -(M-1) ~ +(M-1)
k_max = M - 1;
k_vec = -k_max : k_max;  % 2M-1个延迟点
tau_axis_full = k_vec / fs;

%% ========== 3. FFT方法计算模糊度函数 ========== %%
chi_full = zeros(N_nu, length(k_vec));

for ki = 1:length(k_vec)
    k = k_vec(ki);

    % 构造 R_k[n] = g[n] * conj(g[n-k])
    % g[n-k] 需要 n-k 在 [0, M-1] 范围内
    R_k = zeros(1, M);
    for n = 0:M-1
        n_shifted = n - k;
        if n_shifted >= 0 && n_shifted < M
            R_k(n+1) = g(n+1) * conj(g(n_shifted+1));
        end
    end

    % 零填充FFT → 多普勒维
    spectrum = fftshift(abs(fft(R_k, N_nu)));
    chi_full(:, ki) = spectrum;
end

% 归一化峰值=1
chi_full = chi_full / max(chi_full(:));

%% ========== 4. 轴定义 ========== %%
nu_axis = linspace(-fs/2, fs/2, N_nu);

% 如果需要降采样延迟维到 N_tau 点
if N_tau < length(k_vec)
    idx = round(linspace(1, length(k_vec), N_tau));
    chi = chi_full(:, idx);
    tau_axis = tau_axis_full(idx);
else
    chi = chi_full;
    tau_axis = tau_axis_full;
    N_tau = length(k_vec);
end

%% ========== 5. 量化指标 ========== %%
metrics = struct();

% 零多普勒切面 (nu≈0)
[~, nu0_idx] = min(abs(nu_axis));
cut_tau = chi(nu0_idx, :);
[metrics.peak_sidelobe_tau, metrics.mainlobe_tau_3dB] = analyze_cut(cut_tau, tau_axis);

% 零延迟切面 (tau≈0)
[~, tau0_idx] = min(abs(tau_axis));
cut_nu = chi(:, tau0_idx).';
[metrics.peak_sidelobe_nu, metrics.mainlobe_nu_3dB] = analyze_cut(cut_nu, nu_axis);

end

% --------------- 辅助函数 --------------- %
function [psl_db, width_3dB] = analyze_cut(cut, axis)
% 分析一维切面: 峰值旁瓣电平 + -3dB宽度
cut = cut(:).';
axis = axis(:).';

[peak_val, peak_idx] = max(cut);
if peak_val < 1e-15
    psl_db = -100; width_3dB = 0; return;
end
cut_norm = cut / peak_val;

% -3dB 宽度
above_3dB = cut_norm >= 1/sqrt(2);
transitions = diff([0, above_3dB, 0]);
starts = find(transitions == 1);
stops = find(transitions == -1) - 1;
if isempty(starts) || isempty(stops)
    width_3dB = 0;
else
    % 找包含峰值的连续区间
    for si = 1:length(starts)
        if starts(si) <= peak_idx && stops(si) >= peak_idx
            width_3dB = abs(axis(stops(si)) - axis(starts(si)));
            break;
        end
    end
    if ~exist('width_3dB','var'), width_3dB = 0; end
end

% 峰值旁瓣: 主瓣外最高点
% 找主瓣边界（从峰值向两侧找第一个上升点 = 旁瓣开始）
left_bound = peak_idx;
while left_bound > 1 && cut_norm(left_bound-1) <= cut_norm(left_bound)
    left_bound = left_bound - 1;
end
% 继续往左找到第一个极小值
while left_bound > 1 && cut_norm(left_bound-1) >= cut_norm(left_bound)
    left_bound = left_bound - 1;
end

right_bound = peak_idx;
while right_bound < length(cut_norm) && cut_norm(right_bound+1) <= cut_norm(right_bound)
    right_bound = right_bound + 1;
end
while right_bound < length(cut_norm) && cut_norm(right_bound+1) >= cut_norm(right_bound)
    right_bound = right_bound + 1;
end

sidelobe = [cut_norm(1:left_bound), cut_norm(right_bound:end)];
if isempty(sidelobe) || max(sidelobe) < 1e-15
    psl_db = -100;
else
    psl_db = 20*log10(max(sidelobe));
end
end
