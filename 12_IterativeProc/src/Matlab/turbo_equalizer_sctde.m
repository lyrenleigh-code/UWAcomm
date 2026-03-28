function [bits_out, iter_info] = turbo_equalizer_sctde(rx, h_est, training, num_iter, eq_params, codec_params)
% 功能：SC-TDE Turbo均衡——参考Turbo Equalization工程实现
% 版本：V3.0.0
% 输入：
%   rx, h_est, training, num_iter, eq_params, codec_params
% 输出：
%   bits_out  - 最终硬判决比特
%   iter_info - 迭代详细信息
%
% 备注：
%   信息流（参考Turbo Equalization工程）：
%   第1次: 线性RLS(+PLL) → LLR → 解交织 → Viterbi → 硬比特
%   第2+次: tanh(LLR_decode/2)→软符号→交织→干扰消除→DFE(+PLL)→LLR→解交织→Viterbi
%   关键：软符号用tanh(LLR/2)而非硬判决，提供可靠度梯度

%% ========== 入参 ========== %%
if nargin < 6 || isempty(codec_params)
    codec_params = struct('gen_polys',[7,5], 'constraint_len',3);
end
if nargin < 5 || isempty(eq_params)
    eq_params = struct('num_ff',21, 'num_fb',10, 'lambda',0.998, ...
                       'pll', struct('enable',true,'Kp',0.01,'Ki',0.005));
end
if nargin < 4 || isempty(num_iter), num_iter = 3; end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

%% ========== PTR预处理 ========== %%
if size(rx, 1) > 1
    [rx_ptr, ~] = eq_ptrm(rx, h_est);
    h_ptr = h_est(1,:);
else
    rx_ptr = rx(:).';
    h_ptr = h_est(:).';
end

%% ========== 初始化 ========== %%
iter_info.ber_per_iter = [];
iter_info.mse_per_iter = [];
iter_info.x_hat_per_iter = {};
iter_info.llr_per_iter = {};
LLR_feedback = [];                     % 译码后LLR（用于生成软符号）

%% ========== Turbo迭代 ========== %%
for iter = 1:num_iter
    %% 均衡
    if iter == 1
        % 第1次：线性RLS（无先验反馈）
        [LLR_eq, x_hat, nv] = eq_linear_rls(rx_ptr, training, ...
            eq_params.num_ff, eq_params.lambda, eq_params.pll);
    else
        % 第2+次：用软符号做干扰消除后DFE
        % 核心：tanh(LLR/2) 产生软符号（参考LLRtoSymbol.m）
        soft_sym = llr_to_symbol(LLR_feedback, 'qpsk');

        % 干扰消除
        rx_ic = interference_cancel(rx_ptr, soft_sym, h_ptr);

        % DFE均衡
        [LLR_eq, x_hat, nv] = eq_dfe(rx_ic, h_ptr, training, ...
            eq_params.num_ff, eq_params.num_fb, eq_params.lambda, eq_params.pll);
    end

    %% 译码
    % 构建trellis
    [~, trellis] = conv_encode(zeros(1, 10), codec_params.gen_polys, codec_params.constraint_len);

    % Viterbi软判决译码
    [bits_decoded, ~] = viterbi_decode(LLR_eq, trellis, 'soft');

    %% 为下一次迭代准备软反馈
    if iter < num_iter
        % 重编码硬比特 → 编码比特
        coded_hard = conv_encode(bits_decoded, codec_params.gen_polys, codec_params.constraint_len);

        % 用均衡LLR的可靠度加权编码比特 → 软LLR
        % LLR_feedback = sign(coded) * |LLR_eq的平均可靠度|
        % 更好的方式：直接用均衡器LLR（它已经是编码比特级别的）
        LLR_feedback = LLR_eq;         % 均衡器输出LLR直接作为反馈
    end

    %% 记录
    iter_info.llr_per_iter{iter} = LLR_eq;
    iter_info.x_hat_per_iter{iter} = x_hat;
end

bits_out = bits_decoded;
iter_info.num_iter = num_iter;

end
