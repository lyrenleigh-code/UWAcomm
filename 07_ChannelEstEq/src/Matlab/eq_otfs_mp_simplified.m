function [x_hat] = eq_otfs_mp_simplified(Y_dd, h_dd, path_info, N, M, noise_var, max_iter)
% 功能：OTFS简化MP均衡器——基于MMSE的低复杂度近似
% 版本：V1.0.0
% 输入：
%   与 eq_otfs_mp 相同（无需constellation参数）
% 输出：
%   x_hat - DD域均衡后符号估计 (NxM)
%
% 备注：
%   - 简化版：用MMSE线性滤波替代完整BP迭代
%   - 复杂度 O(P*NM) vs 完整版 O(iter*P*NM*Q)
%   - 精度略低但速度快一个数量级

%% ========== 入参 ========== %%
if nargin < 7 || isempty(max_iter), max_iter = 5; end
if nargin < 6 || isempty(noise_var), noise_var = 0.01; end

P = path_info.num_paths;
delays = path_info.delay_idx;
dopplers = path_info.doppler_idx;
gains = path_info.gain;

%% ========== 逐格点MMSE均衡 ========== %%
x_hat = zeros(N, M);

for k = 1:N
    for l = 1:M
        y_obs = Y_dd(k, l);

        % 计算等效信道增益和干扰
        h_eff = 0;
        interference = 0;
        for p = 1:P
            kx = mod(k - 1 - dopplers(p), N) + 1;
            lx = mod(l - 1 - delays(p), M) + 1;

            if kx == k && lx == l
                h_eff = h_eff + gains(p);
            else
                interference = interference + gains(p) * x_hat(kx, lx);
            end
        end

        % MMSE估计
        y_clean = y_obs - interference;
        x_hat(k, l) = conj(h_eff) / (abs(h_eff)^2 + noise_var) * y_clean;
    end
end

% 多次迭代（SIC方式）
for iter = 2:max_iter
    x_prev = x_hat;
    for k = 1:N
        for l = 1:M
            y_obs = Y_dd(k, l);
            h_eff = 0;
            interference = 0;
            for p = 1:P
                kx = mod(k - 1 - dopplers(p), N) + 1;
                lx = mod(l - 1 - delays(p), M) + 1;
                if kx == k && lx == l
                    h_eff = h_eff + gains(p);
                else
                    interference = interference + gains(p) * x_prev(kx, lx);
                end
            end
            y_clean = y_obs - interference;
            x_hat(k, l) = conj(h_eff) / (abs(h_eff)^2 + noise_var) * y_clean;
        end
    end
end

end
