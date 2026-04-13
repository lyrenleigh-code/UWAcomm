function [symbols_out, info] = eq_rake(rx_chips, code, delays_chip, gains, num_symbols, opts)
% 功能：Rake接收机——多径合并（MRC/EGC）
% 版本：V1.0.0
% 输入：
%   rx_chips     - 接收码片序列 (1xM, 码片率采样)
%   code         - 扩频码 (1xL, ±1或0/1)
%   delays_chip  - 各径延迟 (1xP, 非负整数, 单位:码片)
%   gains        - 各径复数增益 (1xP)
%   num_symbols  - 待恢复符号数
%   opts         - 可选参数结构体
%     .combine   - 合并方式: 'mrc'(默认) / 'egc'
%     .offset    - 起始码片偏移 (默认0, 训练段后的数据起点)
% 输出：
%   symbols_out  - 合并后符号估计 (1xN)
%   info         - 诊断信息
%     .finger_out  - 各finger解扩输出 (PxN)
%     .snr_gain_db - Rake合并SNR增益 (dB)
%
% 备注：
%   MRC(最大比合并): w_p = conj(h_p), 最大化输出SNR
%   EGC(等增益合并): w_p = exp(-j*angle(h_p)), 等幅共相合并
%   要求: max(delays_chip) < L (码长), 否则存在符号间干扰

%% ========== 1. 入参解析 ========== %%
rx_chips = rx_chips(:).';
code = code(:).';
delays_chip = delays_chip(:).';
gains = gains(:).';

if nargin < 6, opts = struct(); end
if ~isfield(opts, 'combine'), opts.combine = 'mrc'; end
if ~isfield(opts, 'offset'), opts.offset = 0; end

%% ========== 2. 参数校验 ========== %%
L = length(code);
P = length(delays_chip);
if length(gains) ~= P
    error('gains长度(%d)须与delays_chip长度(%d)一致！', length(gains), P);
end
if any(delays_chip < 0)
    error('delays_chip须为非负整数！');
end

% 0/1码转±1
if all(code == 0 | code == 1)
    code = 2 * code - 1;
end

%% ========== 3. 各finger解扩 ========== %%
finger_out = zeros(P, num_symbols);

for p = 1:P
    d = delays_chip(p);
    for k = 1:num_symbols
        chip_start = opts.offset + (k-1)*L + d + 1;  % 1-based
        chip_end = chip_start + L - 1;
        if chip_end <= length(rx_chips) && chip_start >= 1
            block = rx_chips(chip_start:chip_end);
            finger_out(p, k) = sum(block .* code) / L;
        end
    end
end

%% ========== 4. 多径合并 ========== %%
switch lower(opts.combine)
    case 'mrc'
        % 最大比合并: w = conj(h), 输出 = sum(|h|^2) * x + noise
        weights = conj(gains(:));
        symbols_raw = weights.' * finger_out;
        norm_factor = sum(abs(gains).^2);
        if norm_factor > 0
            symbols_out = symbols_raw / norm_factor;
        else
            symbols_out = symbols_raw;
        end
    case 'egc'
        % 等增益合并: 共相后等权求和
        weights = exp(-1j * angle(gains(:)));
        symbols_out = (weights.' * finger_out) / P;
    otherwise
        error('不支持的合并方式: %s (支持: mrc/egc)', opts.combine);
end

%% ========== 5. 诊断信息 ========== %%
info.finger_out = finger_out;
info.combine = opts.combine;
info.num_fingers = P;
info.code_len = L;
info.snr_gain_db = 10*log10(sum(abs(gains).^2));

end
