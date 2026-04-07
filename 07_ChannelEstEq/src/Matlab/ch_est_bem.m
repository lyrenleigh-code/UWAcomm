function [h_tv, c_bem, info] = ch_est_bem(y_obs, x_known, obs_times, N_total, delays, fd_est, sym_rate, noise_var, bem_type)
% 功能：BEM基扩展时变信道估计——从散布导频联合估计时变CIR
% 版本：V1.0.0
% 输入：
%   y_obs     - 导频位置的接收值 (Mx1 复数)
%   x_known   - 导频位置的已知发送符号矩阵 (MxP, 每行P径对应的发送符号)
%              x_known(i,p) = x(obs_times(i) - delays(p))，不存在时填0
%   obs_times - 导频位置在帧中的时刻索引 (Mx1, 1-based)
%   N_total   - 帧总符号数（用于BEM基函数归一化）
%   delays    - 各径符号级时延 (1xP)
%   fd_est    - 估计的最大多普勒频率 (Hz)
%   sym_rate  - 符号率 (Hz)
%   noise_var - 噪声方差 (默认 0.01)
%   bem_type  - BEM基函数类型 (字符串, 默认 'ce')
%               'ce'  : 复指数基(CE-BEM), b_q(n) = exp(j2πqn/N)
%               'poly': 多项式基(P-BEM), b_q(n) = (n/N)^q
%               'dct' : 离散余弦基(DCT-BEM), b_q(n) = cos(πq(2n-1)/2N)
% 输出：
%   h_tv      - 重构的时变信道 (P×N_total, 各径各时刻的增益)
%   c_bem     - BEM系数向量 ((P*Q)×1)
%   info      - 估计信息结构体
%       .Q        : BEM阶数
%       .bem_type : 基函数类型
%       .nmse     : 估计残差NMSE (dB)
%       .cond_num : 观测矩阵条件数
%
% 备注：
%   BEM模型: h_p(n) = Σ_{q=0}^{Q-1} c_{p,q} · b_q(n)
%   将时变信道参数化为Q个基函数的线性组合，转为静态参数估计
%   Q选择: Q = max(Q_min, 2·ceil(fd·T_frame)+Q_margin)
%   CE-BEM精度最高但有Gibbs效应; P-BEM适合短窗; DCT-BEM边界效应小
%   观测方程: y(i) = Σ_p Σ_q c_{p,q} · b_q(t_i) · x(t_i - d_p) + noise
%   LS解: c = (Φ'Φ + σ²I)^{-1} Φ'y (MMSE正则化)

%% ========== 1. 入参解析与默认值 ========== %%
if nargin < 9 || isempty(bem_type), bem_type = 'ce'; end
if nargin < 8 || isempty(noise_var), noise_var = 0.01; end

y_obs = y_obs(:);
obs_times = obs_times(:);
M = length(y_obs);
P = length(delays);

%% ========== 2. 参数校验 ========== %%
if isempty(y_obs), error('观测向量不能为空！'); end
if size(x_known,1) ~= M, error('x_known行数(%d)须与观测数(%d)一致！', size(x_known,1), M); end
if size(x_known,2) ~= P, error('x_known列数(%d)须与径数(%d)一致！', size(x_known,2), P); end

%% ========== 3. BEM阶数确定 ========== %%
T_frame = N_total / sym_rate;
Q_min = 5;       % 最小阶数（确保频率分辨率）
Q_margin = 3;    % 余量（超采样多普勒带宽）
Q = max(Q_min, 2*ceil(fd_est * T_frame) + Q_margin);

% 确保未知数不超过观测数的一半（过拟合保护）
while P * Q > M / 2 && Q > Q_min
    Q = Q - 1;
end

%% ========== 4. 生成BEM基函数 ========== %%
% q_range: 基函数索引
switch lower(bem_type)
    case 'ce'
        % CE-BEM: b_q(n) = exp(j·2π·q·n/N)
        q_range = -(Q-1)/2 : (Q-1)/2;
        gen_basis = @(n, q) exp(1j * 2 * pi * q * n / N_total);
    case 'poly'
        % P-BEM: b_q(n) = (n/N)^q, q=0,1,...,Q-1
        q_range = 0 : Q-1;
        gen_basis = @(n, q) (n / N_total).^q;
    case 'dct'
        % DCT-BEM: b_q(n) = cos(π·q·(2n-1)/(2N)), q=0,1,...,Q-1
        q_range = 0 : Q-1;
        gen_basis = @(n, q) cos(pi * q * (2*n - 1) / (2*N_total));
    otherwise
        error('不支持的BEM类型: %s！支持 ce/poly/dct', bem_type);
end

%% ========== 5. 构建观测矩阵 Φ ========== %%
% 观测模型: y(i) = Σ_p Σ_q c_{p,q} · b_q(t_i) · x_known(i,p) + noise
% Φ 矩阵: M × (P*Q)
% c 向量: [c_{1,1},...,c_{1,Q}, c_{2,1},...,c_{P,Q}]
Phi = zeros(M, P * Q);
for ii = 1:M
    t_i = obs_times(ii);
    for p = 1:P
        for qi = 1:Q
            q = q_range(qi);
            basis_val = gen_basis(t_i, q);
            col = (p-1)*Q + qi;
            Phi(ii, col) = x_known(ii, p) * basis_val;
        end
    end
end

%% ========== 6. MMSE正则化LS估计BEM系数 ========== %%
lambda_reg = noise_var * eye(P * Q);
c_bem = (Phi' * Phi + lambda_reg) \ (Phi' * y_obs);

%% ========== 7. 重构全时刻时变信道 ========== %%
h_tv = zeros(P, N_total);
for n = 1:N_total
    for p = 1:P
        val = 0;
        for qi = 1:Q
            q = q_range(qi);
            val = val + c_bem((p-1)*Q + qi) * gen_basis(n, q);
        end
        h_tv(p, n) = val;
    end
end

%% ========== 8. 估计质量信息 ========== %%
y_recon = Phi * c_bem;
residual = y_obs - y_recon;
nmse = 10 * log10(sum(abs(residual).^2) / sum(abs(y_obs).^2));

info.Q = Q;
info.bem_type = bem_type;
info.nmse_residual = nmse;
info.cond_num = cond(Phi' * Phi + lambda_reg);
info.P = P;
info.N_total = N_total;
info.M_obs = M;

end
