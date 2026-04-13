function [bits_out, iter_info] = turbo_equalizer_sctde(rx, h_est, training, num_iter, snr_or_nv, eq_params, codec_params)
% 功能：SC-TDE Turbo均衡——DFE(iter1)+软ISI消除(iter2+) ⇌ BCJR(SISO) 外信息迭代
% 版本：V8.0.0
% 输入：
%   rx           - 接收信号 (1×N 或 MxN多通道)
%   h_est        - 时域信道估计 (1×L 或 MxL多通道)
%   training     - 训练序列已知符号 (1×T 复数)
%   num_iter     - Turbo迭代次数 (默认 5)
%   snr_or_nv    - 信噪比(dB)或噪声方差：
%                  >0 且 ≤100 视为 SNR(dB)，自动转换 noise_var = 10^(-SNR/10)
%                  ≤0 或 >100 视为噪声方差 σ²_w
%                  （默认 10 dB）
%   eq_params    - 均衡器参数结构体
%       .num_ff  : 前馈滤波器阶数 (默认 21)
%       .num_fb  : 反馈滤波器阶数 (默认 10)
%       .lambda  : RLS遗忘因子 (默认 0.998)
%       .pll     : PLL参数 (默认 enable=true, Kp=0.01, Ki=0.005)
%   codec_params - 编解码参数结构体
%       .gen_polys      : 生成多项式 (默认 [7,5])
%       .constraint_len : 约束长度 (默认 3)
%       .interleave_seed: 交织种子 (默认 7)
% 输出：
%   bits_out  - 最终硬判决信息比特 (1×N_info)
%   iter_info - 迭代详情结构体
%       .x_hat_per_iter : cell(1×num_iter)，每次均衡输出（含训练+数据）
%       .llr_per_iter   : cell(1×num_iter)，每次数据段LLR
%       .num_iter       : 实际迭代次数
%
% 备注：
%   V8改进：
%   1. iter1: eq_dfe(num_ff, num_fb, h_est初始化) 替代 eq_linear_rls(num_fb=0)
%      - DFE反馈抽头覆盖长时延ISI（num_fb应≥max_delay）
%      - h_est用于DFE权重初始化（MMSE匹配滤波）
%   2. iter2+: 软ISI消除 + 单抽头ZF（用h_est，同V7）
%   3. SISO(BCJR)译码 + soft_mapper反馈
%   4. LLR符号修正：取负（QPSK: bit=1→Re<0）

%% ========== 入参 ========== %%
if nargin < 7 || isempty(codec_params), codec_params = struct(); end
if ~isfield(codec_params, 'gen_polys'),      codec_params.gen_polys = [7,5]; end
if ~isfield(codec_params, 'constraint_len'),  codec_params.constraint_len = 3; end
if ~isfield(codec_params, 'interleave_seed'), codec_params.interleave_seed = 7; end
if ~isfield(codec_params, 'decode_mode'),     codec_params.decode_mode = 'max-log'; end
if nargin < 6 || isempty(eq_params)
    eq_params = struct('num_ff',21, 'num_fb',10, 'lambda',0.998, ...
                       'pll', struct('enable',true,'Kp',0.01,'Ki',0.005));
end
if nargin < 5 || isempty(snr_or_nv), snr_or_nv = 10; end
if nargin < 4 || isempty(num_iter), num_iter = 5; end

if snr_or_nv > 0 && snr_or_nv <= 100
    noise_var = 10^(-snr_or_nv / 10);
else
    noise_var = abs(snr_or_nv);
end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

gen_polys = codec_params.gen_polys;
K = codec_params.constraint_len;
seed = codec_params.interleave_seed;

%% ========== PTR预处理 ========== %%
if size(rx, 1) > 1
    [rx_ptr, ~] = eq_ptrm(rx, h_est);
    h_ptr = h_est(1,:);
else
    rx_ptr = rx(:).';
    h_ptr = h_est(:).';
end

T = length(training);
N_data_sym = length(rx_ptr) - T;
n_code = length(gen_polys);
M_coded = 2 * N_data_sym;    % QPSK: 2 bits/symbol

% 生成交织置换
[~, perm] = random_interleave(zeros(1, M_coded), seed);

%% ========== 初始化 ========== %%
iter_info.x_hat_per_iter = {};
iter_info.llr_per_iter = {};
nv_ref = [];
x_bar_data = [];
bits_decoded = [];

%% ========== Turbo迭代 ========== %%
for iter = 1:num_iter
    %% 1. 均衡
    if iter == 1
        % 第1次：DFE（h_est初始化，num_fb覆盖长时延ISI）
        [LLR_eq_raw, x_hat, nv_est] = eq_dfe(rx_ptr, h_ptr, training, ...
            eq_params.num_ff, eq_params.num_fb, eq_params.lambda, eq_params.pll);
        LLR_eq = -LLR_eq_raw;  % 符号修正
        h0 = h_ptr(1);         % 主径增益
        nv_zf = nv_est;        % 基准噪声
    else
        % 第2+次：软ISI消除 + 单抽头ZF（不重新训练RLS，避免错误传播）
        full_est = zeros(1, length(rx_ptr));
        full_est(1:T) = training;
        n_fill = min(length(x_bar_data), N_data_sym);
        if n_fill > 0
            full_est(T+1:T+n_fill) = x_bar_data(1:n_fill);
        end

        % ISI消除（仅数据段）
        isi_full = conv(full_est, h_ptr);
        isi_full = isi_full(1:length(rx_ptr));
        self_sig = h0 * full_est;
        rx_ic = rx_ptr;
        rx_ic(T+1:end) = rx_ptr(T+1:end) - isi_full(T+1:end) + self_sig(T+1:end);

        % 单抽头ZF：IC后残余信道≈h(0)，直接除以h(0)
        x_hat = zeros(size(rx_ptr));
        x_hat(1:T) = training;  % 训练段保留
        x_hat(T+1:end) = rx_ic(T+1:end) / h0;

        % LLR计算（符号取负 + 用nv_zf/|h0|²作为等效噪声）
        data_eq = x_hat(T+1:end);
        nv_post = nv_zf / abs(h0)^2;
        LLR_eq = zeros(1, 2*length(data_eq));
        LLR_eq(1:2:end) = -2*sqrt(2) * real(data_eq) / nv_post;
        LLR_eq(2:2:end) = -2*sqrt(2) * imag(data_eq) / nv_post;
    end

    %% 2. 解交织 → SISO译码
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

    %% 3. 反馈：后验 → 交织 → soft_mapper → 软符号（含置信度门控）
    if iter < num_iter
        % 置信度门控：BCJR输出不可靠时跳过IC
        avg_confidence = mean(abs(Lpost_info));
        if avg_confidence > 1.0
            Lpost_coded_inter = random_interleave(Lpost_coded, seed);
            if length(Lpost_coded_inter) < M_coded
                Lpost_coded_inter = [Lpost_coded_inter, zeros(1, M_coded-length(Lpost_coded_inter))];
            else
                Lpost_coded_inter = Lpost_coded_inter(1:M_coded);
            end
            [x_bar_data, ~] = soft_mapper(Lpost_coded_inter, 'qpsk');
        end
        % avg_confidence ≤ 1.0 时保留上一轮x_bar_data（或空=不IC）
    end

    %% 4. 记录
    iter_info.x_hat_per_iter{iter} = x_hat;
    iter_info.llr_per_iter{iter} = LLR_eq;
end

bits_out = bits_decoded;
iter_info.num_iter = num_iter;

end
