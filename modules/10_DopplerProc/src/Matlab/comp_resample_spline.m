function y_resampled = comp_resample_spline(y, alpha_est, fs, mode)
% 功能：三次样条重采样多普勒补偿
% 版本：V7.1.0（2026-04-22：α<0 尾部 auto-pad 消除 clamp 不对称）
% 输入：
%   y         - 接收信号 (1xN，实数或复数)
%   alpha_est - 估计的多普勒因子（正=靠近/压缩，与gen_uwa_channel一致）
%   fs        - 采样率 (Hz)
%   mode      - 运行模式（字符串，默认 'fast'）
%               'fast'     : Catmull-Rom局部三次样条（全向量化，C1连续）
%               'accurate' : 自然三次样条（Thomas算法全局求解，C2连续）
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   多普勒压缩(alpha>0): 接收信号r(m)=s(m*(1+alpha)), 补偿需在位置
%   n/(1+alpha)处采样以恢复s(n)。
%   V7改动：pos=(1:N)/(1+alpha)，正alpha直接传入即可补偿压缩。
%   （V6及之前为pos=(1:N)*(1+alpha)，需外部传-alpha，已废弃）
%   fast模式：Catmull-Rom局部4点插值，无for循环，速度快
%   accurate模式：全局三对角系统求解，C2连续（二阶导连续），精度最高
%
%   V7.1.0：α<0（扩展）时 pos 尾部 = N/(1-|α|) > N，原实现靠 clamp 到 N
%   使尾部 |α|·N 样本全被破坏，造成 -3e-2 下 NMSE 恶化 75 dB。新增 auto-pad：
%   当 pos_max > N 时，内部把 y 尾部 zero-pad 到覆盖 pos_max+4（插值余量），
%   调用方透明。参考 spec: 2026-04-22-resample-negative-alpha-asymmetry.md

%% ========== 入参 ========== %%
if nargin < 4 || isempty(mode), mode = 'fast'; end
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 新采样位置 ========== %%
pos = (1:N) / (1 + alpha_est);

%% ========== α<0 auto-pad：避免尾部 clamp 破坏 ========== %%
pos_max = max(pos);
if pos_max > N
    pad_right = ceil(pos_max - N) + 4;   % +4 给 Catmull-Rom/spline 边界留余量
    y = [y, zeros(1, pad_right)];
    N_eff = length(y);
else
    N_eff = N;
end

%% ========== 按模式选择算法 ========== %%
switch mode
    case 'fast'
        y_resampled = catmull_rom_vectorized(y, pos, N_eff);
    case 'accurate'
        if isreal(y)
            y_resampled = cubic_spline_interp(y, max(1, min(pos, N_eff)));
        else
            pos_clamped = max(1, min(pos, N_eff));
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
