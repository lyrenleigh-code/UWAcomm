function [bits_out, iter_info] = eq_bem_turbo_fde(Y_freq, h_time_block_oracle_oracle, delays_sym, N_fft, noise_var, codec_params, num_outer_iter)
% 功能：BEM-Turbo迭代ICI消除频域均衡器
% 版本：V1.1.0（2026-04-19 标注 Oracle 警告，无调用方时保留供 baseline 对比）
% 输入：
%   Y_freq              - 频域接收信号 (1×N)
%   h_time_block_oracle_oracle - [ORACLE] 块内时变信道增益真实值 (P×N)，首轮迭代直接
%                         LS 分解为 BEM 系数。违反 CLAUDE.md §2（接收端禁用发射
%                         端参数），本函数因此仅作 oracle baseline 用。
%                         生产环境应改用 h_est_block1（由 ch_est_bem 生成）。
%   delays_sym    - 符号级时延 (1×P)
%   N_fft         - FFT点数
%   noise_var     - 噪声方差
%   codec_params  - 编解码参数 (.gen_polys, .constraint_len, .interleave_seed)
%   num_outer_iter- 外层BEM-Turbo迭代次数 (默认 3)
% 输出：
%   bits_out  - 译码比特
%   iter_info - 迭代信息（含每次BER追踪数据）
%
% ⚠️ Oracle 警告：
%   本函数当前**使用发射端真实信道** h_time_block_oracle_oracle 初始化 BEM 系数 +
%   推算 fd_est。num_outer_iter=1 时退化为完全 oracle 均衡器。
%   代码审查标记（2026-04-19）：CRITICAL Oracle 泄漏。
%   未来 fix：新增 h_bem_est 参数（来自 ch_est_bem），删除 oracle 路径。
%
% 备注：
%   BEM模型: h_p(n) = Σ_q c_{p,q}·b_q(n)，CE-BEM基函数
%   Q = 2·ceil(fd_est·T_block) + 1（自动估计，最少3）
%   迭代: BEM-MMSE均衡 → BCJR译码 → 判决引导LS重估BEM → 重构ICI矩阵
%   融合ICI消除和Turbo编码增益

if nargin < 7 || isempty(num_outer_iter), num_outer_iter = 3; end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

N = N_fft;
P = size(h_time_block_oracle, 1);
Y = Y_freq(:);

gen_polys = codec_params.gen_polys;
K = codec_params.constraint_len;
seed = codec_params.interleave_seed;
n_code = length(gen_polys);
M_coded = n_code * N;
[~, perm] = random_interleave(zeros(1, M_coded), seed);

%% ========== 1. BEM基函数构建 ========== %%
% 估计块内多普勒扩展（从h_time的变化率）
h_diff = diff(h_time_block_oracle, 1, 2);
fd_est = mean(abs(h_diff(:))) * N / (2*pi);
Q = max(2*ceil(fd_est * 1) + 1, 3);  % 至少3个基函数
Q = min(Q, 7);                        % 最多7个（防过拟合）

% CE-BEM基函数: b_q(n) = exp(j2π·(q-Q_half)·n/N)
Q_half = floor(Q/2);
n_vec = (0:N-1).';
B = zeros(N, Q);
for q = 1:Q
    B(:, q) = exp(1j * 2*pi * (q-1-Q_half) * n_vec / N) / sqrt(N);
end

%% ========== 2. 初始BEM系数估计（从oracle h_time） ========== %%
% 对每条路径: h_p(n) ≈ B·c_p → c_p = B\h_p (LS)
C = zeros(P, Q);  % C(p,q)
for p = 1:P
    C(p,:) = (B \ h_time_block_oracle(p,:).').';
end

iter_info.ber_per_iter = [];
bits_out = [];

%% ========== 3. BEM-Turbo迭代 ========== %%
for outer = 1:num_outer_iter
    % 3a. 从BEM系数构建ICI矩阵
    H_tv = build_ici_from_bem(C, B, delays_sym, N);

    % 3b. MMSE均衡
    X_hat = (H_tv' * H_tv + noise_var * eye(N)) \ (H_tv' * Y);

    % 3c. 频域→时域→LLR（符号取负，匹配BCJR约定）
    x_hat = ifft(X_hat).';
    LLR = zeros(1, 2*N);
    LLR(1:2:end) = -2*sqrt(2) * real(x_hat) / noise_var;
    LLR(2:2:end) = -2*sqrt(2) * imag(x_hat) / noise_var;

    % 3d. 解交织 → BCJR译码
    LLR_trunc = LLR(1:min(length(LLR), M_coded));
    if length(LLR_trunc) < M_coded
        LLR_trunc = [LLR_trunc, zeros(1, M_coded-length(LLR_trunc))];
    end
    Le_deint = random_deinterleave(LLR_trunc, perm);
    Le_deint = max(min(Le_deint, 30), -30);
    [~, Lpost_info, Lpost_coded] = siso_decode_conv(Le_deint, [], gen_polys, K);
    bits_out = double(Lpost_info > 0);

    % 3e. 判决引导：重建发射信号 → LS重估BEM系数
    if outer < num_outer_iter
        coded_re = conv_encode(bits_out, gen_polys, K);
        coded_re = coded_re(1:M_coded);
        inter_re = random_interleave(coded_re, seed);
        x_re = bits2qpsk(inter_re);
        x_re = x_re(1:N);
        X_re = fft(x_re(:));

        % LS重估：Y = H_tv·X_re → 对每条路径每个BEM基，求c
        % 简化：从时域重建信道 h_hat_p(n) = y(n) / x_re(n) 在各路径投影
        % 更精确：用频域最小二乘
        C_new = estimate_bem_coeffs(Y, X_re, B, delays_sym, N, noise_var);
        % 阻尼更新防振荡
        damping = 0.5;
        C = damping * C_new + (1-damping) * C;
    end

    iter_info.ber_per_iter(outer) = mean(Lpost_info > 0);  % 占位，实际BER在外部算
end

end

%% ========== 辅助函数：从BEM系数构建ICI矩阵 ========== %%
function H_tv = build_ici_from_bem(C, B, delays, N)
    P = size(C, 1);
    Q = size(C, 2);
    H_tv = zeros(N, N);
    n_vec = (0:N-1).';

    for p = 1:P
        d = delays(min(p, length(delays)));
        % 时变频响: H_p(l,n) = h_p(n)·exp(-j2πl·d/N)
        % h_p(n) = B·c_p = Σ_q c_{p,q}·b_q(n)
        % H_tv(k,l) += (1/N)·Σ_n h_p(n)·exp(-j2πld/N)·exp(-j2π(k-l)n/N)
        %            = Σ_q c_{p,q}·exp(-j2πld/N)·(1/N)·Σ_n b_q(n)·exp(-j2π(k-l)n/N)
        % 令 Ψ_q(k,l) = (1/N)·Σ_n b_q(n)·exp(-j2π(k-l)n/N)
        % 对CE-BEM: b_q(n) = exp(j2π(q-Q_half)n/N)/√N
        % Ψ_q(k,l) = δ(k-l-(q-Q_half)) / √N  （只在k-l=q-Q_half时非零）

        Q_half = floor(Q/2);
        phase_delay = exp(-1j * 2*pi * (0:N-1).' * d / N);

        for q = 1:Q
            shift = q - 1 - Q_half;  % k - l = shift
            for l = 0:N-1
                k = mod(l + shift, N);
                H_tv(k+1, l+1) = H_tv(k+1, l+1) + ...
                    C(p,q) * phase_delay(l+1) / sqrt(N);
            end
        end
    end
end

%% ========== 辅助函数：判决引导BEM系数LS估计 ========== %%
function C_new = estimate_bem_coeffs(Y, X_re, B, delays, N, noise_var)
    P = length(delays);
    Q = size(B, 2);
    Q_half = floor(Q/2);
    C_new = zeros(P, Q);

    % 对每条路径，在频域构建观测方程并LS求解
    % Y(k) ≈ Σ_p Σ_q c_{p,q} · X_re(k-shift_q) · exp(-j2π(k-shift_q)d_p/N) / √N
    % 整理为线性方程: Y = A·c → c = (A'A+λI)\A'Y

    % 构建回归矩阵A (N × P*Q)
    A = zeros(N, P*Q);
    for p = 1:P
        d = delays(min(p, length(delays)));
        phase = exp(-1j * 2*pi * (0:N-1).' * d / N);
        for q = 1:Q
            shift = q - 1 - Q_half;
            col_idx = (p-1)*Q + q;
            for k = 0:N-1
                l = mod(k - shift, N);
                A(k+1, col_idx) = X_re(l+1) * phase(l+1) / sqrt(N);
            end
        end
    end

    % 正则化LS
    lambda = noise_var * 0.1;
    c_vec = (A'*A + lambda*eye(P*Q)) \ (A'*Y);
    C_new = reshape(c_vec, Q, P).';
end
