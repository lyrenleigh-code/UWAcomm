function [x_bar, var_x] = soft_mapper(L_posterior, mod_type)
% 功能：后验LLR→软符号估计+残余方差（Turbo迭代反馈用）
% 版本：V1.0.0
% 输入：
%   L_posterior - 编码比特后验LLR (1×2N for QPSK)
%                正值→bit 1
%   mod_type    - 调制类型 ('qpsk'(默认) / 'bpsk')
% 输出：
%   x_bar  - 软符号估计 E[x|Lpost] (1×N 复数)
%   var_x  - 残余方差 E[|x|²|Lpost] - |x̄|² (标量)
%
% 备注：
%   QPSK: x̄[n] = (tanh(L_I/2) + j·tanh(L_Q/2)) / √2
%          σ²_x = 1 - mean(|x̄|²)
%   与llr_to_symbol.m功能相同，额外输出σ²_x供MMSE-IC权重使用

%% ========== 入参 ========== %%
if nargin < 2 || isempty(mod_type), mod_type = 'qpsk'; end
L_posterior = L_posterior(:).';

%% ========== LLR截断（防止var_x→0导致MMSE退化） ========== %%
LLR_CLIP = 8;  % |tanh(4)|≈0.999 → var_x_min ≈ 0.02
L_posterior = max(min(L_posterior, LLR_CLIP), -LLR_CLIP);

%% ========== 软符号映射 ========== %%
switch mod_type
    case 'bpsk'
        % 我们的映射: bit=1→-1, bit=0→+1，BCJR正LLR=bit1，所以取负
        x_bar = -tanh(L_posterior / 2);
        var_x = max(1 - mean(x_bar.^2), 0.01);

    case 'qpsk'
        % 我们的映射: bit=1→-1/√2, bit=0→+1/√2，取负还原星座方向
        th = -tanh(L_posterior / 2);
        x_bar = (th(1:2:end) + 1j * th(2:2:end)) / sqrt(2);
        var_x = max(1 - mean(abs(x_bar).^2), 0.01);

    otherwise
        error('不支持的调制类型: %s', mod_type);
end

end
