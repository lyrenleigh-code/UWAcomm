function [fft_size, cp_len, num_blocks] = bench_get_fft_params(fd_hz)
% 功能：按 Jakes 最大多普勒 fd_hz 返回 SC-FDE / OFDM 的 FFT 配置
% 版本：V1.0.0（2026-04-19）
% 输入：
%   fd_hz - 最大 Doppler 频率（Hz）
% 输出：
%   fft_size / cp_len / num_blocks - 对应 runner fading_cfgs 第 5/6/7 列
%
% 备注：
%   分档策略参考 test_scfde_timevarying / test_ofdm_timevarying 原始定义：
%     fd ≤ 1Hz  → 1024 / 128 / 4   （准静态，长 FFT）
%     fd ≤ 5Hz  → 256  / 128 / 16  （中速）
%     fd > 5Hz  → 128  / 96  / 32  （快速）

if fd_hz <= 1
    fft_size = 1024; cp_len = 128; num_blocks = 4;
elseif fd_hz <= 5
    fft_size = 256;  cp_len = 128; num_blocks = 16;
else
    fft_size = 128;  cp_len = 96;  num_blocks = 32;
end

end
