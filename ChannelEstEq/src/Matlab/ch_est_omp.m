function [h_est, H_est, support] = ch_est_omp(y, Phi, N, K_sparse)
% 功能：OMP（正交匹配追踪）稀疏信道估计
% 版本：V1.0.0
% 输入：
%   y        - 观测向量 (Mx1 或 1xM)
%   Phi      - 测量矩阵 (MxN)，如部分DFT矩阵
%   N        - 信道长度
%   K_sparse - 稀疏度（非零抽头数，默认 ceil(N/10)）
% 输出：
%   h_est   - 时域信道估计 (Nx1)
%   H_est   - 频域信道估计 (1xN)
%   support - 检测到的非零抽头位置 (1xK)
%
% 备注：
%   - OMP逐步选择与残差最相关的列，正交投影后更新残差
%   - 复杂度 O(K*M*N)，适合稀疏度已知的场景
%   - 稀疏度K未知时可用残差能量阈值替代

%% ========== 入参解析 ========== %%
if nargin < 4 || isempty(K_sparse), K_sparse = ceil(N/10); end
y = y(:);
[M, ~] = size(Phi);

%% ========== 参数校验 ========== %%
if isempty(y), error('观测向量不能为空！'); end
if length(y) ~= M, error('观测向量长度(%d)与测量矩阵行数(%d)不匹配！', length(y), M); end

%% ========== OMP算法 ========== %%
residual = y;
support = [];
h_est = zeros(N, 1);

for iter = 1:K_sparse
    % 计算残差与各列的相关
    correlations = abs(Phi' * residual);
    correlations(support) = 0;         % 已选列置零

    % 选择最大相关列
    [~, idx] = max(correlations);
    support = [support, idx]; %#ok<AGROW>

    % 正交投影：在已选列集合上做LS
    Phi_s = Phi(:, support);
    h_s = Phi_s \ y;                   % LS: (Phi_s'*Phi_s)^{-1} * Phi_s' * y

    % 更新残差
    residual = y - Phi_s * h_s;

    % 残差足够小时提前终止
    if norm(residual) / norm(y) < 1e-6
        break;
    end
end

%% ========== 组装输出 ========== %%
h_est(support) = h_s;
H_est = fft(h_est.', N);

end
