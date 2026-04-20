function y_out = comp_resample_matlab(y, alpha_est, fs, mode)
% 功能：用 MATLAB 系统自带 resample 做 α 补偿（多相滤波 + 抗混叠）
% 版本：V1.0.0（2026-04-20）
% 对应诊断：比较 spline 插值 vs 多相 FIR 重采样的 α 补偿精度
%
% 输入：
%   y         - 1×N 复数信号
%   alpha_est - 标量，估计多普勒因子（正=压缩，与 gen_uwa_channel/comp_resample_spline 同）
%   fs        - 采样率（Hz，当前实现未用，保留接口一致）
%   mode      - char，'default'（10 阶 Kaiser）或 'highorder'（自定义）
% 输出：
%   y_out     - 1×N 补偿后信号（输出长度等于输入长度）
%
% 备注：
%   MATLAB resample(y, P, Q) 通过 [P, Q] = rat(1+α) 得有理近似：
%     - resample(y, P, Q) 将采样率变为原 fs·P/Q，等价于时间轴伸缩 P/Q 倍
%     - 对 α>0（压缩），需要拉伸 (1+α) 倍，P/Q = 1+α
%   复数信号分实虚部独立重采样后重组

if nargin < 4 || isempty(mode), mode = 'default'; end
if isempty(y), error('输入信号不能为空'); end
y = y(:).';
N = length(y);

if abs(alpha_est) < 1e-10
    y_out = y;
    return;
end

% 有理分数近似 (1+α)，容差 1e-8 足够 α ∈ [1e-4, 1e-1]
[P, Q] = rat(1 + alpha_est, 1e-8);

switch lower(mode)
    case 'default'
        % MATLAB 默认 10 阶 Kaiser 多相滤波
        if isreal(y)
            y_long = resample(y, P, Q);
        else
            y_long = resample(real(y), P, Q) + 1j * resample(imag(y), P, Q);
        end
    case 'highorder'
        % 高阶 FIR（50 阶 Kaiser β=10）更强抗混叠
        N_order = 50;
        if isreal(y)
            y_long = resample(y, P, Q, N_order, 10);
        else
            y_long = resample(real(y), P, Q, N_order, 10) + ...
                     1j * resample(imag(y), P, Q, N_order, 10);
        end
    otherwise
        error('未知 mode: %s', mode);
end

% 裁切 / 补零到原始长度
if length(y_long) >= N
    y_out = y_long(1:N);
else
    y_out = [y_long, zeros(1, N - length(y_long))];
end

end
