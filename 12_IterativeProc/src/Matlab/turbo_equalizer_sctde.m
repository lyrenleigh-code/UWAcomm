function [bits_out, iter_info] = turbo_equalizer_sctde(rx, h_est, training, num_iter, eq_params, codec_params)
% 功能：SC-TDE Turbo均衡调度器——PTR → 线性/DFE ⇌ 卷积译码 迭代
% 版本：V1.0.0
% 输入：
%   rx           - 接收信号 (1xN 或 MxN多通道)
%   h_est        - 信道估计 (1xL 或 MxL多通道)
%   training     - 训练序列 (1xT 已知符号)
%   num_iter     - Turbo迭代次数 (默认 3)
%   eq_params    - 均衡器参数（可选）
%       .num_ff    : 前馈阶数 (默认 21)
%       .num_fb    : 反馈阶数 (默认 10)
%       .lambda    : RLS遗忘因子 (默认 0.998)
%       .pll       : PLL参数结构体
%   codec_params - 编解码参数（可选）
%       .gen_polys      : 卷积码生成多项式 (默认 [171,133])
%       .constraint_len : 约束长度 (默认 7)
%       .interleaver_seed: 交织种子 (默认 0)
% 输出：
%   bits_out  - 最终译码比特 (1xK)
%   iter_info - 迭代信息结构体
%       .ber_per_iter : 各次迭代BER（需提供参考比特）
%       .llr_per_iter : 各次迭代LLR
%       .num_iter     : 实际迭代次数
%
% 备注：
%   Turbo均衡流程（参考Turbo Equalization工程）：
%   第1次：PTR(可选) → 线性RLS(+PLL) → LLR → 解交织 → 卷积译码
%   第2+次：译码LLR → 软符号(tanh) → 交织 → 干扰消除 → DFE(RLS+PLL) → LLR → 解交织 → 译码

%% ========== 入参解析 ========== %%
if nargin < 6 || isempty(codec_params)
    codec_params = struct('gen_polys',[171,133], 'constraint_len',7, 'interleaver_seed',0);
end
if nargin < 5 || isempty(eq_params)
    eq_params = struct('num_ff',21, 'num_fb',10, 'lambda',0.998, ...
                       'pll', struct('enable',true,'Kp',0.01,'Ki',0.005));
end
if nargin < 4 || isempty(num_iter), num_iter = 3; end

% 添加依赖模块路径
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

%% ========== PTR预处理（多通道时） ========== %%
if size(rx, 1) > 1
    % 多通道：PTR聚焦
    [rx_ptr, ~] = eq_ptrm(rx, h_est);
    h_ptr = h_est(1,:);                % PTR后等效为单通道
else
    rx_ptr = rx(:).';
    h_ptr = h_est(:).';
end

%% ========== Turbo迭代 ========== %%
iter_info.llr_per_iter = {};
LLR_decode_prev = [];
LLR_prior_info = [];                   % SISO译码的先验（首次为空=全0）

for iter = 1:num_iter
    %% 均衡
    if iter == 1
        % 第1次：线性RLS（无反馈信息）
        [LLR_eq, x_hat, nv] = eq_linear_rls(rx_ptr, training, ...
            eq_params.num_ff, eq_params.lambda, eq_params.pll);
    else
        % 第2+次：用译码软符号做干扰消除 → DFE
        soft_symbols = llr_to_symbol(LLR_decode_inter, 'qpsk');

        % 干扰消除
        rx_ic = interference_cancel(rx_ptr, soft_symbols, h_ptr);

        % DFE均衡（利用软反馈）
        [LLR_eq, x_hat, nv] = eq_dfe(rx_ic, h_ptr, training, ...
            eq_params.num_ff, eq_params.num_fb, eq_params.lambda, eq_params.pll);
    end

    %% 解交织
    if ~isempty(codec_params.interleaver_seed) && codec_params.interleaver_seed >= 0
        LLR_deinter = random_deinterleave(LLR_eq, ...
            gen_interleaver_perm(length(LLR_eq), codec_params.interleaver_seed));
    else
        LLR_deinter = LLR_eq;
    end

    %% SISO译码（BCJR MAP算法，输出外信息）
    [LLR_ext, LLR_post] = siso_decode_conv(LLR_deinter, LLR_prior_info, ...
                                            codec_params.gen_polys, codec_params.constraint_len);

    % 硬判决（最终输出用）
    bits_decoded = double(LLR_post > 0);

    %% 为下一次迭代准备：外信息→重编码→交织→软符号
    if iter < num_iter
        % 用外信息（而非后验）重编码为编码比特LLR
        % 外信息→信息比特软值→重编码展开为编码比特
        n_rate = length(codec_params.gen_polys);
        N_info_bits = length(LLR_ext);

        % 将信息比特外信息展开为编码比特LLR
        % 简化：每个信息比特的外信息复制n次（对应n个编码比特）
        LLR_coded_ext = zeros(1, N_info_bits * n_rate);
        for b = 1:N_info_bits
            LLR_coded_ext((b-1)*n_rate+1 : b*n_rate) = LLR_ext(b);
        end

        % 加上尾比特（外信息=0）
        tail_len = length(LLR_deinter) - length(LLR_coded_ext);
        if tail_len > 0
            LLR_coded_ext = [LLR_coded_ext, zeros(1, tail_len)];
        end

        % 交织
        if ~isempty(codec_params.interleaver_seed) && codec_params.interleaver_seed >= 0
            [LLR_decode_inter, ~] = random_interleave(LLR_coded_ext, codec_params.interleaver_seed);
        else
            LLR_decode_inter = LLR_coded_ext;
        end

        % 更新先验（下一次SISO译码的先验 = 本次均衡器的外信息经解交织）
        LLR_prior_info = LLR_ext;
    end

    iter_info.llr_per_iter{iter} = LLR_eq;
    iter_info.x_hat_per_iter{iter} = x_hat;
    iter_info.noise_var_per_iter(iter) = nv;
end

%% ========== 输出 ========== %%
bits_out = bits_decoded;
iter_info.num_iter = num_iter;

end

% --------------- 辅助：生成交织置换 --------------- %
function perm = gen_interleaver_perm(N, seed)
rng_state = rng;
rng(seed);
perm = randperm(N);
rng(rng_state);
end
