function [bits, info] = modem_decode(body_bb, scheme, sys, meta)
% 功能：统一 modem 解码入口（按 scheme 分发）
% 版本：V1.0.0（P3.1）
% 输入：
%   body_bb - 1×M 基带 body（已由外层完成 LFM 对齐 + Doppler 补偿）
%   scheme  - 体制名
%   sys     - 系统参数
%   meta    - TX 侧 modem_encode 产出的元数据
% 输出：
%   bits - 1×N 解码信息比特
%   info - struct：
%       .estimated_snr      dB（decoder 内部估计，若未估则为 NaN）
%       .estimated_ber      估计 BER（基于 LLR 置信度，若不可用为 NaN）
%       .turbo_iter         Turbo 实际迭代数（不做 Turbo 的体制为 0）
%       .convergence_flag   0=未收敛 / 1=CRC 或 LLR 判据判定收敛
%       （外加体制特定诊断字段）

[bits, info] = modem_dispatch('decode', scheme, body_bb, sys, meta);

% 统一字段兜底
if ~isfield(info, 'estimated_snr'),    info.estimated_snr = NaN; end
if ~isfield(info, 'estimated_ber'),    info.estimated_ber = NaN; end
if ~isfield(info, 'turbo_iter'),       info.turbo_iter = 0; end
if ~isfield(info, 'convergence_flag'), info.convergence_flag = 0; end
info.scheme = scheme;

end
