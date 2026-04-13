function soft_symbols = llr_to_symbol(LLR, mod_type)
% 功能：LLR软信息转软符号估计（Turbo迭代中译码器→均衡器的接口）
% 版本：V1.0.0
% 输入：
%   LLR      - 比特LLR软信息 (1xM)，正值→bit 1
%   mod_type - 调制类型 ('qpsk'(默认)/'bpsk')
% 输出：
%   soft_symbols - 软符号估计 (1xK 复数)
%
% 备注：
%   - QPSK: s = (tanh(LLR_I/2) + j*tanh(LLR_Q/2)) / sqrt(2)
%   - BPSK: s = tanh(LLR/2)
%   - tanh(LLR/2)将LLR映射到[-1,+1]，表示软判决置信度
%   - |LLR|大→tanh接近±1→接近硬判决；|LLR|小→接近0→不确定

%% ========== 入参 ========== %%
if nargin < 2 || isempty(mod_type), mod_type = 'qpsk'; end
LLR = LLR(:).';

%% ========== 转换 ========== %%
switch mod_type
    case 'bpsk'
        soft_symbols = tanh(LLR / 2);

    case 'qpsk'
        th = tanh(LLR / 2);
        % I路用奇数位LLR，Q路用偶数位LLR
        soft_symbols = (th(1:2:end) + 1j * th(2:2:end)) / sqrt(2);

    otherwise
        error('不支持的调制类型: %s！支持 bpsk/qpsk', mod_type);
end

end
