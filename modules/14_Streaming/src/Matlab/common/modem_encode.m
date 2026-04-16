function [body_bb, meta] = modem_encode(bits, scheme, sys)
% 功能：统一 modem 编码入口（按 scheme 分发）
% 版本：V1.0.0（P3.1）
% 输入：
%   bits   - 1×N 信息比特（已含 header + payload + crc，由上游组装好）
%   scheme - 体制名（见 modem_dispatch）
%   sys    - 系统参数（sys.fs/fc + 各体制子结构 sys.fhmfsk / sys.scfde / ...）
% 输出：
%   body_bb - 1×M 基带复信号（不含 HFM/LFM，交由 assemble_physical_frame 拼帧）
%   meta    - TX 侧元数据，供对应 modem_decode 使用

[body_bb, meta] = modem_dispatch('encode', scheme, bits, sys);

% 统一附加字段
meta.scheme   = scheme;
meta.N_info_in = length(bits);

end
