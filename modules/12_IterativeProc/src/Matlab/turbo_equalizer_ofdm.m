function [bits_out, iter_info] = turbo_equalizer_ofdm(Y_freq, H_est, num_iter, snr_or_nv, codec_params)
% 功能：OFDM Turbo均衡——MMSE-IC(SISO) ⇌ BCJR(SISO) 外信息迭代
% 版本：V7.0.0
% 输入：
%   Y_freq       - 频域接收信号 (1×N)
%   H_est        - 频域信道估计 (1×N)
%   num_iter     - Turbo迭代次数 (默认 5)
%   snr_or_nv    - 信噪比(dB)或噪声方差：
%                  >0 且 ≤100 视为 SNR(dB)，自动转换 noise_var = 10^(-SNR/10)
%                  ≤0 或 >100 视为噪声方差 σ²_w
%                  （默认 10 dB）
%   codec_params - 编解码参数结构体
%       .gen_polys      : 生成多项式 (默认 [7,5])
%       .constraint_len : 约束长度 (默认 3)
%       .interleave_seed: 交织种子 (默认 7)
% 输出：
%   bits_out  - 最终硬判决信息比特 (1×N_info)
%   iter_info - 迭代详情结构体
%       .x_hat_per_iter : cell(1×num_iter)，每次迭代均衡输出符号
%       .llr_per_iter   : cell(1×num_iter)，每次迭代外信息LLR
%       .num_iter       : 实际迭代次数
%
% 备注：
%   LMMSE-IC均衡 + BCJR(SISO)译码，外信息迭代
%   x̃ = x̄ + IFFT(G·(Y - H·X̄))，G = σ²_x·H*/(σ²_x|H|²+σ²_w)
%   OFDM与SC-FDE共用相同的频域Turbo均衡架构

%% ========== 入参 ========== %%
if nargin < 5 || isempty(codec_params)
    codec_params = struct();
end
if ~isfield(codec_params, 'gen_polys'),      codec_params.gen_polys = [7,5]; end
if ~isfield(codec_params, 'constraint_len'),  codec_params.constraint_len = 3; end
if ~isfield(codec_params, 'interleave_seed'), codec_params.interleave_seed = 7; end
if ~isfield(codec_params, 'decode_mode'),     codec_params.decode_mode = 'max-log'; end
if nargin < 4 || isempty(snr_or_nv), snr_or_nv = 10; end
if nargin < 3 || isempty(num_iter), num_iter = 5; end

if snr_or_nv > 0 && snr_or_nv <= 100
    noise_var = 10^(-snr_or_nv / 10);
else
    noise_var = abs(snr_or_nv);
end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

H_est = H_est(:).';
N = length(H_est);
Y_freq = Y_freq(:).';

gen_polys = codec_params.gen_polys;
K = codec_params.constraint_len;
seed = codec_params.interleave_seed;
n_code = length(gen_polys);
M_coded = n_code * N;

[~, perm] = random_interleave(zeros(1, M_coded), seed);

%% ========== 初始化 ========== %%
x_bar = zeros(1, N);
var_x = 1;
La_eq = zeros(1, M_coded);
La_dec_info = [];
bits_decoded = [];

iter_info.x_hat_per_iter = {};
iter_info.llr_per_iter = {};

%% ========== Turbo迭代 ========== %%
for iter = 1:num_iter
    [x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var);
    Le_eq = soft_demapper(x_tilde, mu, nv_tilde, La_eq, 'qpsk');
    Le_eq_deint = random_deinterleave(Le_eq, perm);
    Le_eq_deint = max(min(Le_eq_deint, 30), -30);

    if strcmpi(codec_params.decode_mode, 'sova')
        [Le_dec_info, Lpost_info, Lpost_coded] = sova_decode_conv( ...
            Le_eq_deint, La_dec_info, gen_polys, K);
    else
        [Le_dec_info, Lpost_info, Lpost_coded] = siso_decode_conv( ...
            Le_eq_deint, La_dec_info, gen_polys, K, codec_params.decode_mode);
    end

    bits_decoded = double(Lpost_info > 0);

    if iter < num_iter
        Lpost_coded_inter = random_interleave(Lpost_coded, seed);
        [x_bar, var_x_raw] = soft_mapper(Lpost_coded_inter, 'qpsk');
        var_x = max(var_x_raw, noise_var);

        La_eq = zeros(size(Le_eq));
    end

    iter_info.x_hat_per_iter{iter} = x_tilde(:).';
    iter_info.llr_per_iter{iter} = Le_eq;
end

bits_out = bits_decoded;
iter_info.num_iter = num_iter;

end
