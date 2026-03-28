function [bits_out, iter_info] = turbo_equalizer_otfs(Y_dd, h_dd, path_info, N, M, num_iter, snr_or_nv, codec_params)
% 功能：OTFS Turbo均衡——DD域MP(BP)均衡 ⇌ BCJR(SISO) 外信息迭代
% 版本：V3.0.0
% 输入：
%   Y_dd         - 接收DD域帧 (NxM 复数)
%   h_dd         - DD域信道响应 (NxM 稀疏)
%   path_info    - 路径信息结构体
%       .num_paths   : 路径数
%       .delay_idx   : 时延索引 (1xP)
%       .doppler_idx : 多普勒索引 (1xP)
%       .gain        : 复增益 (1xP)
%   N, M         - DD域格点尺寸（多普勒×时延）
%   num_iter     - 外层Turbo迭代次数 (默认 3)
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
%       .x_hat_per_iter : cell(1×num_iter)，每次MP均衡输出(1D向量)
%       .llr_per_iter   : cell(1×num_iter)，每次LLR
%       .num_iter       : 实际迭代次数
%
% 备注：
%   V3改进（对齐P0+P1架构）：
%   1. SISO(BCJR)译码器替代Viterbi
%   2. soft_mapper生成DD域软符号先验（含QPSK符号反转修复）
%   3. 交织/解交织纳入迭代环路
%   4. LLR符号修正：MP输出取负（我们的QPSK: bit=1→Re<0）
%   5. 双层迭代：外层Turbo(SISO) × 内层MP(BP 10次)

%% ========== 入参 ========== %%
if nargin < 8 || isempty(codec_params), codec_params = struct(); end
if ~isfield(codec_params, 'gen_polys'),      codec_params.gen_polys = [7,5]; end
if ~isfield(codec_params, 'constraint_len'),  codec_params.constraint_len = 3; end
if ~isfield(codec_params, 'interleave_seed'), codec_params.interleave_seed = 7; end
if ~isfield(codec_params, 'decode_mode'),     codec_params.decode_mode = 'max-log'; end
if nargin < 7 || isempty(snr_or_nv), snr_or_nv = 10; end
if nargin < 6 || isempty(num_iter), num_iter = 3; end

if snr_or_nv > 0 && snr_or_nv <= 100
    noise_var = 10^(-snr_or_nv / 10);
else
    noise_var = abs(snr_or_nv);
end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
gen_polys = codec_params.gen_polys;
K = codec_params.constraint_len;
seed = codec_params.interleave_seed;
n_code = length(gen_polys);
n_dd = N * M;
M_coded = 2 * n_dd;              % QPSK: 2 bits/symbol

% 生成交织置换
[~, perm] = random_interleave(zeros(1, M_coded), seed);

%% ========== 初始化 ========== %%
iter_info.x_hat_per_iter = {};
iter_info.llr_per_iter = {};
prior_mean = [];
prior_var = [];
bits_decoded = [];

%% ========== Turbo外层迭代 ========== %%
for iter = 1:num_iter
    %% 1. MP均衡（内层BP 10次）
    mp_iters = 10;
    [x_hat_dd, ~, x_mean_dd] = eq_otfs_mp(Y_dd, h_dd, path_info, N, M, ...
        noise_var, mp_iters, constellation, prior_mean, prior_var);

    %% 2. DD域符号→LLR（用软估计x_mean，非硬判决x_hat）
    x_hat_vec = reshape(x_mean_dd.', 1, []);
    % LLR符号取负（我们的QPSK: bit=1→Re<0，BCJR需正=bit1）
    LLR_eq = zeros(1, 2*length(x_hat_vec));
    LLR_eq(1:2:end) = -2*sqrt(2) * real(x_hat_vec) / noise_var;
    LLR_eq(2:2:end) = -2*sqrt(2) * imag(x_hat_vec) / noise_var;

    %% 3. 解交织 → SISO译码
    LLR_eq_trunc = LLR_eq(1:min(length(LLR_eq), M_coded));
    if length(LLR_eq_trunc) < M_coded
        LLR_eq_trunc = [LLR_eq_trunc, zeros(1, M_coded - length(LLR_eq_trunc))];
    end
    Le_eq_deint = random_deinterleave(LLR_eq_trunc, perm);
    Le_eq_deint = max(min(Le_eq_deint, 30), -30);

    if strcmpi(codec_params.decode_mode, 'sova')
        [~, Lpost_info, Lpost_coded] = sova_decode_conv(Le_eq_deint, [], gen_polys, K);
    else
        [~, Lpost_info, Lpost_coded] = siso_decode_conv(Le_eq_deint, [], gen_polys, K, codec_params.decode_mode);
    end
    bits_decoded = double(Lpost_info > 0);

    %% 4. 反馈：后验 → 交织 → soft_mapper → DD域先验
    if iter < num_iter
        Lpost_coded_inter = random_interleave(Lpost_coded, seed);
        if length(Lpost_coded_inter) < M_coded
            Lpost_coded_inter = [Lpost_coded_inter, zeros(1, M_coded-length(Lpost_coded_inter))];
        else
            Lpost_coded_inter = Lpost_coded_inter(1:M_coded);
        end
        [x_bar_vec, var_x_raw] = soft_mapper(Lpost_coded_inter, 'qpsk');
        var_x = max(var_x_raw, noise_var);

        % 1D → NxM DD域
        dd_vec_dec = zeros(1, n_dd);
        n_fill = min(length(x_bar_vec), n_dd);
        dd_vec_dec(1:n_fill) = x_bar_vec(1:n_fill);
        prior_mean = reshape(dd_vec_dec, M, N).';
        prior_var = var_x * ones(N, M);
    end

    %% 5. 记录
    iter_info.x_hat_per_iter{iter} = x_hat_vec;
    iter_info.llr_per_iter{iter} = LLR_eq;
end

bits_out = bits_decoded;
iter_info.num_iter = num_iter;

end
