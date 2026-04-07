function [h_tv, info] = ch_est_bem_dd(rx, training, sym_delays, fd_est, sym_rate, noise_var, h_init, dd_opts)
% 功能：判决辅助迭代BEM信道估计（DD-BEM）
% 版本：V1.0.0
% 输入：
%   rx         - 接收信号 (1×N, [训练段|数据段])
%   training   - 训练序列 (1×T)
%   sym_delays - 各径时延 (1×P)
%   fd_est     - 多普勒频率估计 (Hz)
%   sym_rate   - 符号率 (Hz)
%   noise_var  - 噪声方差
%   h_init     - 初始信道估计 (P×N, 可由ch_est_bem提供; 空则内部计算)
%   dd_opts    - 可选参数结构体
%       .num_iter    : DD迭代次数 (默认 3)
%       .dd_step     : DD导频采样间隔 (默认 3)
%       .bem_type    : BEM基函数类型 (默认 'ce')
%       .blk_size    : FDE块大小 (默认 256)
%       .constellation : 星座点 (默认 QPSK)
% 输出：
%   h_tv  - 最终时变信道估计 (P×N)
%   info  - 估计信息
%       .nmse_per_iter : 每次迭代的导频残差NMSE
%       .M_per_iter    : 每次迭代的观测数
%       .Q             : BEM阶数
%       .num_dd_iter   : 实际DD迭代次数
%
% 备注：
%   流程: 初始BEM → FDE块均衡 → 硬判决 → 扩展导频 → 重估BEM → 迭代
%   适用于仅有训练段导频、数据区无显式导频的场景
%   判决正确率越高，DD增益越大

%% ========== 1. 入参解析 ========== %%
if nargin < 8 || isempty(dd_opts), dd_opts = struct(); end
if ~isfield(dd_opts, 'num_iter'),      dd_opts.num_iter = 3; end
if ~isfield(dd_opts, 'dd_step'),       dd_opts.dd_step = 3; end
if ~isfield(dd_opts, 'bem_type'),      dd_opts.bem_type = 'ce'; end
if ~isfield(dd_opts, 'blk_size'),      dd_opts.blk_size = 256; end
if ~isfield(dd_opts, 'constellation'), dd_opts.constellation = [1+1j,1-1j,-1+1j,-1-1j]/sqrt(2); end

rx = rx(:).';
training = training(:).';
N = length(rx);
T = length(training);
P = length(sym_delays);
max_d = max(sym_delays);
constellation = dd_opts.constellation;
blk = dd_opts.blk_size;

%% ========== 2. 参数校验 ========== %%
if N <= T, error('接收信号长度(%d)须大于训练长度(%d)!', N, T); end
if P < 1, error('至少需要1条径!'); end

%% ========== 3. 构建训练导频观测 ========== %%
[obs_y0, obs_x0, obs_t0] = build_obs(rx, training, sym_delays, P, max_d, T, N);

%% ========== 4. 初始BEM估计 ========== %%
if isempty(h_init)
    [h_tv,~,inf0] = ch_est_bem(obs_y0(:), obs_x0, obs_t0(:), N, sym_delays, fd_est, sym_rate, noise_var, dd_opts.bem_type);
    Q = inf0.Q;
else
    h_tv = h_init;
    Q = 0;
end

info.nmse_per_iter = [];
info.M_per_iter = length(obs_y0);

%% ========== 5. DD迭代精化 ========== %%
x_known = zeros(1, N);
x_known(1:T) = training;

for dd_it = 1:dd_opts.num_iter
    % 5a: FDE块均衡（用当前h_tv）
    N_data = N - T;
    N_blks = floor(N_data / blk);
    for bi = 1:N_blks
        bs = T + (bi-1)*blk + 1;
        be = bs + blk - 1;
        if be > N, break; end
        mid = bs + round(blk/2);
        mid = min(mid, N);
        hm = h_tv(:, mid);
        htd = zeros(1, blk);
        for p=1:P
            if sym_delays(p)+1 <= blk
                htd(sym_delays(p)+1) = hm(p);
            end
        end
        H_blk = fft(htd);
        Y_blk = fft(rx(bs:be));
        X_eq = Y_blk .* conj(H_blk) ./ (abs(H_blk).^2 + noise_var);
        x_eq = ifft(X_eq);
        for k = 1:blk
            [~, idx] = min(abs(x_eq(k) - constellation));
            x_known(bs+k-1) = constellation(idx);
        end
    end
    % 剩余符号
    for n = T+N_blks*blk+1:N
        x_known(n) = constellation(1);
    end

    % 5b: 扩展导频观测（训练+DD）
    obs_y_dd = obs_y0(:);
    obs_x_dd = obs_x0;
    obs_t_dd = obs_t0(:);
    for n = T+max_d+1 : dd_opts.dd_step : N
        xv = zeros(1, P);
        for p = 1:P
            idx = n - sym_delays(p);
            if idx >= 1 && idx <= N
                xv(p) = x_known(idx);
            end
        end
        if any(xv ~= 0)
            obs_y_dd(end+1) = rx(n);
            obs_x_dd = [obs_x_dd; xv];
            obs_t_dd(end+1) = n;
        end
    end

    % 5c: 重估BEM
    [h_tv, ~, inf_dd] = ch_est_bem(obs_y_dd(:), obs_x_dd, obs_t_dd(:), N, sym_delays, fd_est, sym_rate, noise_var, dd_opts.bem_type);
    if Q == 0, Q = inf_dd.Q; end

    info.nmse_per_iter(dd_it) = inf_dd.nmse_residual;
    info.M_per_iter(dd_it+1) = length(obs_y_dd);
end

info.Q = Q;
info.num_dd_iter = dd_opts.num_iter;

end

% --------------- 辅助函数：构建训练观测 --------------- %
function [obs_y, obs_x, obs_t] = build_obs(rx, tr, delays, P, max_d, T, ~)
    obs_y = []; obs_x = []; obs_t = [];
    for n = max_d+1:T
        xv = zeros(1, P);
        for p = 1:P
            idx = n - delays(p);
            if idx >= 1
                xv(p) = tr(idx);
            end
        end
        obs_y(end+1) = rx(n);
        obs_x = [obs_x; xv];
        obs_t(end+1) = n;
    end
end
