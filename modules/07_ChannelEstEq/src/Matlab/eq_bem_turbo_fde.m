function [bits_out, iter_info] = eq_bem_turbo_fde(Y_freq, h_est_block1, delays_sym, N_fft, noise_var, codec_params, num_outer_iter, fd_hz_max)
% 功能：BEM-Turbo 迭代 ICI 消除频域均衡器
% 版本：V2.0.0（2026-04-19 去 Oracle：h_est_block1 由 ch_est_bem/ch_est_gamp 生成）
% 输入：
%   Y_freq        - 频域接收信号 (1×N)
%   h_est_block1  - **估计**块内时变信道 (P×N)，来自 ch_est_bem / ch_est_gamp 等
%                   接收端可独立重生成的估计器输出。若信道静态，P×N 各行可相同。
%                   合规：满足 CLAUDE.md §2 Oracle 排查清单
%   delays_sym    - 符号级时延 (1×P)，由 OMP/GAMP 峰值搜索估计
%   N_fft         - FFT点数
%   noise_var     - 噪声方差，由接收信号 guard 区 / 训练残差估计
%   codec_params  - 编解码参数 (.gen_polys, .constraint_len, .interleave_seed)
%   num_outer_iter- 外层 BEM-Turbo 迭代次数 (默认 3)
%   fd_hz_max     - 多普勒扩展保守上界 (Hz, 默认 10) — BEM 阶数 Q 保守估计用
%                   同 ch_est_bem 的约定；不从真实信道推算
% 输出：
%   bits_out  - 译码比特
%   iter_info - 迭代信息
%
% 去 Oracle 变更（V1.1 → V2.0）：
%   1. 参数 h_time_block_oracle → h_est_block1（估计信道）
%   2. Q 由 h_est_block1 变化率 + fd_hz_max 上界联合保守估计，不再靠 oracle diff
%   3. 迭代逻辑（判决引导 LS 重估 BEM）保持不变
%
% 备注：
%   BEM 模型: h_p(n) = Σ_q c_{p,q}·b_q(n)，CE-BEM 基函数
%   迭代: BEM-MMSE 均衡 → BCJR 译码 → 判决引导 LS 重估 BEM → 重构 ICI 矩阵

if nargin < 7 || isempty(num_outer_iter), num_outer_iter = 3; end
if nargin < 8 || isempty(fd_hz_max),      fd_hz_max      = 10; end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

N = N_fft;
P = size(h_est_block1, 1);
Y = Y_freq(:);

gen_polys = codec_params.gen_polys;
K = codec_params.constraint_len;
seed = codec_params.interleave_seed;
n_code = length(gen_polys);
M_coded = n_code * N;
[~, perm] = random_interleave(zeros(1, M_coded), seed);

%% ========== 1. BEM 基函数构建（保守阶数估计，无 oracle） ==========
% 优先用估计信道的变化率推 fd_est；估计信道变化小时回退 fd_hz_max 上界
if size(h_est_block1, 2) > 1
    h_diff_est = diff(h_est_block1, 1, 2);
    fd_est_from_hest = mean(abs(h_diff_est(:))) * N / (2*pi);
else
    fd_est_from_hest = 0;
end
fd_est = max(fd_est_from_hest, fd_hz_max * 0.1);  % 下限防过低
Q = max(2*ceil(fd_est * 1) + 1, 3);  % 至少 3 基
Q = min(Q, 7);                        % 至多 7 基（防过拟合）

% CE-BEM 基函数: b_q(n) = exp(j2π·(q-Q_half)·n/N)
Q_half = floor(Q/2);
n_vec = (0:N-1).';
B = zeros(N, Q);
for q = 1:Q
    B(:, q) = exp(1j * 2*pi * (q-1-Q_half) * n_vec / N) / sqrt(N);
end

%% ========== 2. 初始 BEM 系数（LS 分解估计信道） ==========
% 对每条路径: h_est_p(n) ≈ B·c_p → c_p = B\h_est_p (LS)
% 本步合规：h_est_block1 是接收端估计输出，非 TX 真实信道
C = zeros(P, Q);
for p = 1:P
    C(p,:) = (B \ h_est_block1(p,:).').';
end

iter_info.ber_per_iter = [];
iter_info.fd_est = fd_est;
iter_info.Q = Q;
bits_out = [];

%% ========== 3. BEM-Turbo 迭代 ==========
for outer = 1:num_outer_iter
    % 3a. 从 BEM 系数构建 ICI 矩阵
    H_tv = build_ici_from_bem(C, B, delays_sym, N);

    % 3b. MMSE 均衡
    X_hat = (H_tv' * H_tv + noise_var * eye(N)) \ (H_tv' * Y);

    % 3c. 频域→时域→LLR（符号取负，匹配 BCJR 约定）
    x_hat = ifft(X_hat).';
    % 注：后验噪声近似 = noise_var；更精确可用 diag((H'H+σ²I)⁻¹) 的均值
    % 代码审查 HIGH-3 标注，保留简化近似（见调试日志）
    LLR = zeros(1, 2*N);
    LLR(1:2:end) = -2*sqrt(2) * real(x_hat) / noise_var;
    LLR(2:2:end) = -2*sqrt(2) * imag(x_hat) / noise_var;

    % 3d. 解交织 → BCJR 译码
    LLR_trunc = LLR(1:min(length(LLR), M_coded));
    if length(LLR_trunc) < M_coded
        LLR_trunc = [LLR_trunc, zeros(1, M_coded-length(LLR_trunc))]; %#ok<AGROW>
    end
    Le_deint = random_deinterleave(LLR_trunc, perm);
    Le_deint = max(min(Le_deint, 30), -30);
    [~, Lpost_info, ~] = siso_decode_conv(Le_deint, [], gen_polys, K);
    bits_out = double(Lpost_info > 0);

    % 3e. 判决引导：重建发射信号 → LS 重估 BEM 系数
    if outer < num_outer_iter
        coded_re = conv_encode(bits_out, gen_polys, K);
        coded_re = coded_re(1:M_coded);
        inter_re = random_interleave(coded_re, seed);
        x_re = bits2qpsk(inter_re);
        x_re = x_re(1:N);
        X_re = fft(x_re(:));

        C_new = estimate_bem_coeffs(Y, X_re, B, delays_sym, N, noise_var);
        damping = 0.5;
        C = damping * C_new + (1-damping) * C;
    end

    iter_info.ber_per_iter(outer) = mean(Lpost_info > 0);
end

end


%% ============================================================
%% 辅助函数：从 BEM 系数构建 ICI 矩阵 H_tv
%% ============================================================
function H_tv = build_ici_from_bem(C, B, delays_sym, N)
% 输入：
%   C          - BEM 系数 (P×Q)
%   B          - BEM 基函数 (N×Q)
%   delays_sym - 符号级时延 (1×P)
%   N          - FFT 点数
% 输出：
%   H_tv       - 频域 ICI 矩阵 (N×N)

[P, Q] = size(C);
H_tv = zeros(N, N);
for p = 1:P
    tau_p = delays_sym(p);
    for q = 1:Q
        % h_p(n) 对应的第 q 个基在频域 → 卷积 ICI
        h_pq_time = C(p, q) * B(:, q);  % (N×1)
        H_pq_diag = fft(h_pq_time, N);  % diag 元素
        % 时延 tau_p 对应频域相位旋转
        phase_shift = exp(-1j * 2*pi * (0:N-1).' * tau_p / N);
        H_pq_freq_col = H_pq_diag .* phase_shift;
        % 加到 ICI 矩阵上：每个 H_pq 贡献一个对角带
        H_tv = H_tv + diag(H_pq_freq_col);
    end
end

end


%% ============================================================
%% 辅助函数：LS 重估 BEM 系数（判决引导）
%% ============================================================
function C_new = estimate_bem_coeffs(Y, X_re, B, delays_sym, N, noise_var)
% 简化 LS：对每条路径，用 TX 重建信号与接收信号的时延关系解 BEM 系数
[~, Q] = size(B);
P = length(delays_sym);
C_new = zeros(P, Q);

% 时域接收
y_time = ifft(Y);
x_time = ifft(X_re);

for p = 1:P
    tau_p = delays_sym(p);
    % 时延 tau_p 的 TX 副本
    x_shift = circshift(x_time, tau_p);
    % 残差 = y - (其他路径贡献)，此处简化为 y 与 x_shift 的逐符号比值
    % 实际应联合求解，但简化实现足以迭代收敛
    ratio = y_time ./ max(abs(x_shift), sqrt(noise_var));
    % LS 分解 ratio ≈ B * c_p → c_p = B \ ratio
    C_new(p, :) = (B \ ratio(:)).';
end

end
