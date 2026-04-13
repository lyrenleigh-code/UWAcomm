function LLR = symbol_to_llr(symbols, noise_var, mod_type)
% 功能：均衡后符号转LLR软信息（均衡器→译码器的接口）
% 版本：V1.0.0
% 输入：
%   symbols   - 均衡后复数符号 (1xK)
%   noise_var - 均衡后噪声方差
%   mod_type  - 调制类型 ('qpsk'(默认)/'bpsk')
% 输出：
%   LLR - 比特LLR (1xM)，正值→bit 1
%
% 备注：
%   - QPSK LLR: LLR_I = 2*sqrt(2)*Re(s)/σ², LLR_Q = 2*sqrt(2)*Im(s)/σ²
%   - BPSK LLR: LLR = 2*Re(s)/σ²

%% ========== 入参 ========== %%
if nargin < 3 || isempty(mod_type), mod_type = 'qpsk'; end
if nargin < 2 || isempty(noise_var), noise_var = 0.1; end
symbols = symbols(:).';
noise_var = max(noise_var, 1e-10);

%% ========== 转换 ========== %%
switch mod_type
    case 'bpsk'
        LLR = 2 * real(symbols) / noise_var;

    case 'qpsk'
        K = length(symbols);
        LLR = zeros(1, 2*K);
        LLR(1:2:end) = 2 * sqrt(2) * real(symbols) / noise_var;
        LLR(2:2:end) = 2 * sqrt(2) * imag(symbols) / noise_var;

    otherwise
        error('不支持的调制类型: %s', mod_type);
end

end
