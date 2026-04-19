function [flag, extra] = decode_convergence(Lpost_info, bits_prev, bits_cur)
% DECODE_CONVERGENCE  统一的 Turbo 解码收敛判据
%
% 功能：给定最后一轮后验 LLR 以及可选的前后两轮硬判决比特，按三选一判据返回
%       收敛标记（对齐 2026-04-17 SC-FDE V2.1.0 修复）。
%       三选一：
%         A. median(|Lpost|) > 5 — 高 SNR 置信场景
%         B. bits_prev == bits_cur — 硬判决稳定（LLR scale 偏小但判决一致）
%         C. mean(|Lpost| > 1.5) > 0.70 — 高置信 LLR 占比阈值（兜底）
% 版本：V1.0.0（2026-04-19 从 modem_decode_scfde.m V2.1.0 抽出）
% 输入：
%   Lpost_info  — 1×N 后验信息比特 LLR
%   bits_prev   — 上一轮硬判决（可空 [] → 判据 B 跳过）
%   bits_cur    — 当前轮硬判决
% 输出：
%   flag        — 0/1 收敛标志
%   extra       — struct 含诊断字段：
%                 .med_llr, .frac_confident, .hard_stable（bool）

if nargin < 2, bits_prev = []; end
if nargin < 3, bits_cur  = []; end

abs_llr = abs(Lpost_info);
med_llr = median(abs_llr);
frac_confident = mean(abs_llr > 1.5);

hard_stable = false;
if ~isempty(bits_prev) && ~isempty(bits_cur) && ...
   length(bits_prev) == length(bits_cur)
    hard_stable = isequal(bits_prev, bits_cur);
end

flag = double(med_llr > 5 || hard_stable || frac_confident > 0.70);

extra.med_llr        = med_llr;
extra.frac_confident = frac_confident;
extra.hard_stable    = hard_stable;

end
