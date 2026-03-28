function [bits_out, iter_info] = turbo_equalizer_ofdm(Y_freq, H_est, num_iter, noise_var, codec_params)
% 功能：OFDM Turbo均衡——MMSE-FDE + 软干扰消除 ⇌ 译码
% 版本：V1.0.0
% 输入：
%   Y_freq       - 频域接收信号 (1xN 或 KxN多符号)
%   H_est        - 频域信道估计 (1xN)
%   num_iter     - 迭代次数 (默认 3)
%   noise_var    - 噪声方差
%   codec_params - 编码参数
% 输出：
%   bits_out  - 译码比特
%   iter_info - 迭代信息（含BER/MSE跟踪）
%
% 备注：
%   OFDM迭代均衡：
%   第1次: MMSE-FDE → LLR → Viterbi
%   第2+次: tanh(LLR/2)→软符号→FFT→频域软干扰消除→MMSE→LLR→Viterbi
%   OFDM的优势：频域均衡+干扰消除都在频域，计算高效

%% ========== 入参 ========== %%
if nargin < 5 || isempty(codec_params)
    codec_params = struct('gen_polys',[7,5], 'constraint_len',3);
end
if nargin < 4 || isempty(noise_var), noise_var = 0.01; end
if nargin < 3 || isempty(num_iter), num_iter = 3; end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

H_est = H_est(:).';
N = length(H_est);

%% ========== 初始化 ========== %%
iter_info.x_hat_per_iter = {};
iter_info.llr_per_iter = {};
LLR_feedback = [];

%% ========== Turbo迭代 ========== %%
for iter = 1:num_iter
    if iter == 1
        % 第1次：标准MMSE-FDE
        [x_hat, ~] = eq_mmse_fde(Y_freq, H_est, noise_var);
    else
        % 第2+次：软干扰消除 → MMSE
        soft_sym = llr_to_symbol(LLR_feedback, 'qpsk');

        % 频域软干扰消除
        if isvector(Y_freq)
            n_sym = min(length(soft_sym), N);
            X_soft = fft([soft_sym(1:n_sym), zeros(1, max(0, N-n_sym))]);
            X_prev = fft([x_hat_prev(1:min(length(x_hat_prev),N)), zeros(1, max(0, N-length(x_hat_prev)))]);

            % 残余信号 = 接收 - 软估计 + 当前估计
            Y_clean = Y_freq(:).' - H_est .* X_soft + H_est .* X_prev;
            [x_hat, ~] = eq_mmse_fde(Y_clean, H_est, noise_var);
        else
            [x_hat, ~] = eq_mmse_fde(Y_freq, H_est, noise_var);
        end
    end

    if isvector(x_hat)
        x_hat_prev = x_hat(:).';
    else
        x_hat_prev = reshape(x_hat.', 1, []);
    end

    % LLR
    LLR_eq = symbol_to_llr(x_hat_prev, noise_var, 'qpsk');

    % 译码
    [~, trellis] = conv_encode(zeros(1,10), codec_params.gen_polys, codec_params.constraint_len);
    [bits_decoded, ~] = viterbi_decode(LLR_eq, trellis, 'soft');

    % 软反馈
    if iter < num_iter
        LLR_feedback = LLR_eq;
    end

    iter_info.x_hat_per_iter{iter} = x_hat_prev;
    iter_info.llr_per_iter{iter} = LLR_eq;
end

bits_out = bits_decoded;
iter_info.num_iter = num_iter;

end
