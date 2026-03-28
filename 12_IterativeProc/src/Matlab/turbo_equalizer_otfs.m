function [bits_out, iter_info] = turbo_equalizer_otfs(Y_dd, h_dd, path_info, N, M, num_iter, noise_var, codec_params)
% 功能：OTFS Turbo均衡调度器——MP均衡 ⇌ 信道译码 迭代
% 版本：V1.0.0
% 输入：
%   Y_dd         - 接收DD域帧 (NxM)
%   h_dd         - DD域信道响应 (NxM稀疏)
%   path_info    - 路径信息（由ch_est_otfs_dd生成）
%   N, M         - DD域格点尺寸
%   num_iter     - 外层Turbo迭代次数 (默认 3，每次内部MP迭代10次)
%   noise_var    - 噪声方差
%   codec_params - 编解码参数（可选）
% 输出：
%   bits_out  - 最终译码比特
%   iter_info - 迭代信息
%
% 备注：
%   OTFS Turbo迭代：
%   第1次：MP均衡(BP 10次) → 符号判决 → LLR → 解交织 → 译码
%   第2+次：译码LLR → 软符号 → 更新MP先验 → MP均衡 → LLR → 译码

%% ========== 入参 ========== %%
if nargin < 8 || isempty(codec_params)
    codec_params = struct('gen_polys',[171,133], 'constraint_len',7, 'interleaver_seed',0);
end
if nargin < 7 || isempty(noise_var), noise_var = 0.01; end
if nargin < 6 || isempty(num_iter), num_iter = 3; end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);  % QPSK

%% ========== Turbo迭代 ========== %%
iter_info.llr_per_iter = {};

for iter = 1:num_iter
    % MP均衡（内部BP迭代10次）
    mp_iters = 10;
    [x_hat_dd, LLR_dd] = eq_otfs_mp(Y_dd, h_dd, path_info, N, M, noise_var, mp_iters, constellation);

    % DD域符号→LLR序列
    x_hat_vec = reshape(x_hat_dd.', 1, []);
    LLR_eq = symbol_to_llr(x_hat_vec, noise_var, 'qpsk');

    % 解交织
    if codec_params.interleaver_seed >= 0
        perm = gen_perm_otfs(length(LLR_eq), codec_params.interleaver_seed);
        LLR_deinter = random_deinterleave(LLR_eq, perm);
    else
        LLR_deinter = LLR_eq;
    end

    % 译码
    [~, trellis] = conv_encode(zeros(1,10), codec_params.gen_polys, codec_params.constraint_len);
    [bits_decoded, ~] = viterbi_decode(LLR_deinter, trellis, 'soft');

    iter_info.llr_per_iter{iter} = LLR_eq;
end

bits_out = bits_decoded;
iter_info.num_iter = num_iter;

end

function perm = gen_perm_otfs(N, seed)
rng_state = rng; rng(seed);
perm = randperm(N);
rng(rng_state);
end
