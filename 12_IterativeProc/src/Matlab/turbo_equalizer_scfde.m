function [bits_out, iter_info] = turbo_equalizer_scfde(Y_freq, H_est, num_iter, noise_var, codec_params)
% 功能：SC-FDE Turbo均衡调度器——MMSE-FDE ⇌ 信道译码 迭代
% 版本：V1.0.0
% 输入：
%   Y_freq       - 频域接收信号 (1xN 或 KxN多块)
%   H_est        - 频域信道估计 (1xN)
%   num_iter     - Turbo迭代次数 (默认 4)
%   noise_var    - 噪声方差
%   codec_params - 编解码参数（可选，同turbo_equalizer_sctde）
% 输出：
%   bits_out  - 最终译码比特
%   iter_info - 迭代信息
%
% 备注：
%   SC-FDE Turbo迭代：
%   第1次：MMSE-FDE → IFFT → LLR → 解交织 → 译码
%   第2+次：译码LLR → 软符号 → FFT → 软干扰消除(频域) → MMSE-FDE → IFFT → LLR → 译码

%% ========== 入参 ========== %%
if nargin < 5 || isempty(codec_params)
    codec_params = struct('gen_polys',[171,133], 'constraint_len',7, 'interleaver_seed',0);
end
if nargin < 4 || isempty(noise_var), noise_var = 0.01; end
if nargin < 3 || isempty(num_iter), num_iter = 4; end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

H_est = H_est(:).';
N = length(H_est);

%% ========== Turbo迭代 ========== %%
iter_info.llr_per_iter = {};

for iter = 1:num_iter
    if iter == 1
        % 第1次：标准MMSE-FDE
        [x_hat, ~] = eq_mmse_fde(Y_freq, H_est, noise_var);
    else
        % 第2+次：软干扰消除 → MMSE-FDE
        soft_symbols = llr_to_symbol(LLR_decode_inter, 'qpsk');

        % 频域软干扰消除
        if isvector(Y_freq)
            X_soft = fft(soft_symbols(1:N));
            Y_clean = Y_freq(:).' - H_est .* X_soft + H_est .* fft(x_hat_prev);
            [x_hat, ~] = eq_mmse_fde(Y_clean, H_est, noise_var);
        else
            [x_hat, ~] = eq_mmse_fde(Y_freq, H_est, noise_var);
        end
    end

    x_hat_prev = x_hat;

    % 符号→LLR
    if isvector(x_hat)
        LLR_eq = symbol_to_llr(x_hat(:).', noise_var, 'qpsk');
    else
        LLR_eq = symbol_to_llr(reshape(x_hat.', 1, []), noise_var, 'qpsk');
    end

    % 解交织
    if codec_params.interleaver_seed >= 0
        perm = gen_perm(length(LLR_eq), codec_params.interleaver_seed);
        LLR_deinter = random_deinterleave(LLR_eq, perm);
    else
        LLR_deinter = LLR_eq;
    end

    % 译码
    [~, trellis] = conv_encode(zeros(1,10), codec_params.gen_polys, codec_params.constraint_len);
    [bits_decoded, ~] = viterbi_decode(LLR_deinter, trellis, 'soft');

    % 为下一次准备
    if iter < num_iter
        coded = conv_encode(bits_decoded, codec_params.gen_polys, codec_params.constraint_len);
        LLR_decode = (2*coded - 1) * 2 / max(noise_var, 1e-6);
        if codec_params.interleaver_seed >= 0
            [LLR_decode_inter, ~] = random_interleave(LLR_decode, codec_params.interleaver_seed);
        else
            LLR_decode_inter = LLR_decode;
        end
    end

    iter_info.llr_per_iter{iter} = LLR_eq;
end

bits_out = bits_decoded;
iter_info.num_iter = num_iter;

end

function perm = gen_perm(N, seed)
rng_state = rng; rng(seed);
perm = randperm(N);
rng(rng_state);
end
