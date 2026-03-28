function y_resampled = comp_resample_spline(y, alpha_est, fs, mode)
% 功能：三次样条重采样——支持快速模式和高精度模式
% 版本：V6.0.0
% 输入：
%   y         - 接收信号 (1xN，实数或复数)
%   alpha_est - 估计的多普勒因子
%   fs        - 采样率 (Hz)
%   mode      - 运行模式（字符串，默认 'fast'）
%               'fast'     : Catmull-Rom局部三次样条（全向量化，C1连续）
%               'accurate' : 自然三次样条（Thomas算法全局求解，C2连续）
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   fast模式：Catmull-Rom局部4点插值，无for循环，速度快
%   accurate模式：全局三对角系统求解，C2连续（二阶导连续），精度最高
%   两种模式均不调用MATLAB系统插值函数

%% ========== 入参 ========== %%
if nargin < 4 || isempty(mode), mode = 'fast'; end
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 新采样位置 ========== %%
pos = (1:N) * (1 + alpha_est);

%% ========== 按模式选择算法 ========== %%
switch mode
    case 'fast'
        y_resampled = catmull_rom_vectorized(y, pos, N);
    case 'accurate'
        if isreal(y)
            y_resampled = cubic_spline_interp(y, max(1, min(pos, N)));
        else
            pos_clamped = max(1, min(pos, N));
            y_resampled = cubic_spline_interp(real(y), pos_clamped) + ...
                          1j * cubic_spline_interp(imag(y), pos_clamped);
        end
    otherwise
        error('不支持的模式: %s！支持 fast/accurate', mode);
end

end

% --------------- Catmull-Rom向量化插值 --------------- %
function yq = catmull_rom_vectorized(y, pos, N)
pad = 2;
y_pad = [zeros(1, pad), y, zeros(1, pad)];

int_pos = floor(pos);
frac = pos - int_pos;

idx = int_pos + pad;
idx = max(2, min(idx, length(y_pad) - 2));

x0 = y_pad(idx - 1);
x1 = y_pad(idx);
x2 = y_pad(idx + 1);
x3 = y_pad(idx + 2);

a3 = 0.5 * (-x0 + 3*x1 - 3*x2 + x3);
a2 = 0.5 * (2*x0 - 5*x1 + 4*x2 - x3);
a1 = 0.5 * (-x0 + x2);
a0 = x1;

yq = ((a3 .* frac + a2) .* frac + a1) .* frac + a0;
end
