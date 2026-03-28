function Le_eq = soft_demapper(x_tilde, mu, nv_tilde, La_eq, mod_type)
% 功能：SISO均衡器软解映射——输出编码比特级外信息LLR
% 版本：V1.0.0
% 输入：
%   x_tilde   - 均衡后时域符号 (1×N)
%   mu        - 等效增益 (实数标量，来自eq_mmse_ic_fde)
%   nv_tilde  - 等效噪声方差 (实数标量)
%   La_eq     - 编码比特先验LLR (1×2N for QPSK, 首次迭代全0)
%   mod_type  - 调制类型 ('qpsk'(默认) / 'bpsk')
% 输出：
%   Le_eq     - 编码比特外信息LLR (1×2N for QPSK)
%               正值→bit 1
%
% 备注：
%   等效AWGN模型：x̃ = μ·x + ñ
%   QPSK外信息公式：
%     Lp(I) = 4·μ/σ²_ñ · Re(x̃)/√2       后验
%     Le(I) = Lp(I) - La(I)               外信息 = 后验 - 先验
%   关键：减去先验La，避免信息自我强化

%% ========== 入参 ========== %%
if nargin < 5 || isempty(mod_type), mod_type = 'qpsk'; end
x_tilde = x_tilde(:).';
N = length(x_tilde);

mu = max(real(mu), 1e-8);
nv_tilde = max(real(nv_tilde), 1e-10);

% 缩放因子
scale = 2 * mu / nv_tilde;

%% ========== 计算外信息LLR ========== %%
switch mod_type
    case 'bpsk'
        % x̃ = μ·(±1) + ñ，我们的映射: bit=1→-1, bit=0→+1，取负
        Lp = -scale * real(x_tilde);
        if isempty(La_eq), La_eq = zeros(1, N); end
        La_eq = La_eq(:).';
        if length(La_eq) < N
            La_eq = [La_eq, zeros(1, N - length(La_eq))];
        end
        Le_eq = Lp - La_eq(1:N);

    case 'qpsk'
        % x̃ = μ·(b_I + j·b_Q)/√2 + ñ
        % 我们的QPSK映射: bit=1→-1/√2, bit=0→+1/√2，所以取负
        Lp_I = -scale * sqrt(2) * real(x_tilde);
        Lp_Q = -scale * sqrt(2) * imag(x_tilde);

        % 交织后验LLR（I/Q交替排列）
        Lp = zeros(1, 2*N);
        Lp(1:2:end) = Lp_I;
        Lp(2:2:end) = Lp_Q;

        % 先验
        M_coded = 2 * N;
        if isempty(La_eq), La_eq = zeros(1, M_coded); end
        La_eq = La_eq(:).';
        if length(La_eq) < M_coded
            La_eq = [La_eq, zeros(1, M_coded - length(La_eq))];
        end

        % 外信息 = 后验 - 先验
        Le_eq = Lp - La_eq(1:M_coded);

    otherwise
        error('不支持的调制类型: %s', mod_type);
end

end
