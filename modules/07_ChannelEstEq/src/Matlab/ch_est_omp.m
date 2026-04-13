function [h_est, H_est, support] = ch_est_omp(y, Phi, N, K_sparse, noise_var)
% 功能：OMP（正交匹配追踪）稀疏信道估计
% 版本：V1.1.0
% 输入：
%   y         - 观测向量 (Mx1 或 1xM)
%   Phi       - 测量矩阵 (MxN)，如部分DFT矩阵
%   N         - 信道长度
%   K_sparse  - 稀疏度上限（非零抽头数，默认 ceil(N/10)）
%               设为0或[]时使用自适应停止准则
%   noise_var - 噪声方差（可选，用于自适应残差停止准则）
%               提供时：当 ||residual||^2 < M*noise_var*threshold_factor 停止
%               不提供时：使用固定K_sparse次迭代
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
if nargin < 5, noise_var = []; end
if nargin < 4 || isempty(K_sparse) || K_sparse == 0
    K_sparse = ceil(N/10);             % 默认上限
    adaptive_stop = true;
else
    adaptive_stop = ~isempty(noise_var);
end
y = y(:);
[M, ~] = size(Phi);

% 自适应停止阈值
if ~isempty(noise_var)
    residual_threshold = M * noise_var * 1.2;  % 1.2倍余量
else
    residual_threshold = 0;
end

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

    % 停止准则
    res_energy = norm(residual)^2;
    if adaptive_stop && residual_threshold > 0
        % 自适应：残差能量降到噪声水平时停止
        if res_energy < residual_threshold
            break;
        end
    else
        % 固定：残差相对能量极小时停止
        if res_energy / norm(y)^2 < 1e-10
            break;
        end
    end
end

%% ========== 组装输出 ========== %%
h_est(support) = h_s;
H_est = fft(h_est.', N);

end
