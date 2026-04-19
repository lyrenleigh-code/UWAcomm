function [bits_out, iter_info] = turbo_equalizer_scfde_crossblock(Y_freq_blocks, H_est_blocks, num_iter, noise_var, codec_params)
% 功能：SC-FDE/OFDM 跨块Turbo均衡——多块LMMSE-IC ⇌ 跨块BCJR + DD信道更新
% 版本：V1.0.0
% 输入：
%   Y_freq_blocks - cell(1×N_blocks)，每块的频域接收信号 (1×N_fft)
%   H_est_blocks  - cell(1×N_blocks)，每块的频域信道估计 (1×N_fft)
%   num_iter      - Turbo迭代次数 (默认 6)
%   noise_var     - 噪声方差 σ²_w
%   codec_params  - 编解码参数结构体
%       .gen_polys      : 生成多项式 (默认 [7,5])
%       .constraint_len : 约束长度 (默认 3)
%       .interleave_seed: 交织种子 (默认 7)
%       .decode_mode    : 'max-log'(默认) / 'log-map' / 'sova'
% 输出：
%   bits_out  - 最终硬判决信息比特 (1×N_info)
%   iter_info - 迭代详情
%       .ber_per_iter : 每次迭代的BER（若提供参考比特）
%       .num_iter     : 实际迭代次数
%
% 备注：
%   跨块编码：编码一次→分块均衡→LLR拼接→跨块BCJR译码→反馈各块
%   DD信道更新：iter≥2且置信度够时，用软符号重估各块H_est
%   适用于SC-FDE和OFDM（频域MMSE处理相同）

%% ========== 入参 ========== %%
if nargin < 5 || isempty(codec_params), codec_params = struct(); end
if ~isfield(codec_params, 'gen_polys'),      codec_params.gen_polys = [7,5]; end
if ~isfield(codec_params, 'constraint_len'),  codec_params.constraint_len = 3; end
if ~isfield(codec_params, 'interleave_seed'), codec_params.interleave_seed = 7; end
if ~isfield(codec_params, 'decode_mode'),     codec_params.decode_mode = 'max-log'; end
if nargin < 4 || isempty(noise_var), noise_var = 0.01; end
if nargin < 3 || isempty(num_iter), num_iter = 6; end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

gen_polys = codec_params.gen_polys;
K = codec_params.constraint_len;
seed = codec_params.interleave_seed;
n_code = length(gen_polys);

N_blocks = length(Y_freq_blocks);
blk_fft = length(Y_freq_blocks{1});
M_per_blk = 2 * blk_fft;           % QPSK: 2 bits/symbol
M_total = M_per_blk * N_blocks;
nv_eq = max(noise_var, 1e-10);

% 生成交织置换
[~, perm] = random_interleave(zeros(1, M_total), seed);

%% ========== 初始化 ========== %%
x_bar_blks = cell(1, N_blocks);
var_x_blks = ones(1, N_blocks);
H_cur_blocks = H_est_blocks;
for bi = 1:N_blocks, x_bar_blks{bi} = zeros(1, blk_fft); end
La_dec_info = [];
bits_decoded = [];
iter_info.num_iter = num_iter;

%% ========== Turbo迭代 ========== %%
for titer = 1:num_iter
    %% 1. Per-block LMMSE-IC → LLR
    LLR_all = zeros(1, M_total);
    for bi = 1:N_blocks
        [x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq_blocks{bi}, ...
            H_cur_blocks{bi}, x_bar_blks{bi}, var_x_blks(bi), nv_eq);
        Le_eq_blk = soft_demapper(x_tilde, mu, nv_tilde, zeros(1, M_per_blk), 'qpsk');
        LLR_all((bi-1)*M_per_blk+1 : bi*M_per_blk) = Le_eq_blk;
    end

    %% 2. 跨块解交织 + BCJR
    Le_eq_deint = random_deinterleave(LLR_all, perm);
    Le_eq_deint = max(min(Le_eq_deint, 30), -30);

    if strcmpi(codec_params.decode_mode, 'sova')
        [Le_dec_info, Lpost_info, Lpost_coded] = sova_decode_conv(Le_eq_deint, La_dec_info, gen_polys, K);
    else
        [Le_dec_info, Lpost_info, Lpost_coded] = siso_decode_conv(Le_eq_deint, La_dec_info, gen_polys, K, codec_params.decode_mode);
    end
    bits_decoded = double(Lpost_info > 0);
    La_dec_info = Le_dec_info;     % 译码器信息比特外信息 → 下轮 BCJR 先验

    %% 3. 反馈 + DD信道更新
    if titer < num_iter
        Lpost_inter = random_interleave(Lpost_coded, seed);
        if length(Lpost_inter) < M_total
            Lpost_inter = [Lpost_inter, zeros(1, M_total - length(Lpost_inter))];
        else
            Lpost_inter = Lpost_inter(1:M_total);
        end
        for bi = 1:N_blocks
            coded_blk = Lpost_inter((bi-1)*M_per_blk+1 : bi*M_per_blk);
            [x_bar_blks{bi}, var_x_raw] = soft_mapper(coded_blk, 'qpsk');
            var_x_blks(bi) = max(var_x_raw, nv_eq);

            % DD信道更新（置信度足够时）
            if titer >= 2 && var_x_blks(bi) < 0.5
                X_bar = fft(x_bar_blks{bi});
                H_dd_raw = Y_freq_blocks{bi} .* conj(X_bar) ./ (abs(X_bar).^2 + nv_eq);
                H_cur_blocks{bi} = H_dd_raw;  % 全频点更新
            end
        end
    end
end

bits_out = bits_decoded;

end
