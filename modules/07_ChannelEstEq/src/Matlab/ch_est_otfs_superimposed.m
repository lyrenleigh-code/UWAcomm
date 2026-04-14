function [h_dd, path_info] = ch_est_otfs_superimposed(Y_dd, pilot_info, N, M, opts)
% 功能：OTFS DD域叠加导频信道估计（superimposed pilot）
% 版本：V1.0.0
% 输入：
%   Y_dd       - 接收DD域帧 (NxM 复数)
%   pilot_info - 导频信息（由 otfs_pilot_embed mode='superimposed' 生成）
%     .mode = 'superimposed'
%     .pilot_pattern : NxM 已知pilot图案
%     .pilot_power   : pilot功率系数
%   N, M       - OTFS维度
%   opts       - 可选参数
%     .guard_k : Doppler搜索范围 (默认2)
%     .guard_l : Delay搜索范围 (默认10)
%     .pk, .pl : h_dd存储参考位置 (默认 ceil(N/2), ceil(M/2))
%     .iter    : 迭代次数 (默认1, 非迭代单次相关)
% 输出：
%   h_dd       - DD域信道响应 (NxM, 稀疏)
%   path_info  - 路径信息
%
% 原理：
%   TX: x_dd = data + pilot_pattern (所有DD位置都叠加)
%   RX: Y_dd = channel(x_dd) = channel(data) + channel(pilot)
%
%   交叉相关:
%     C[dk, dl] = sum Y_dd * conj(circshift(pilot_pattern, [dk, dl]))
%     h[dk, dl] = C[dk, dl] / sum|pilot|^2
%
%   问题: data是未知随机信号, 相关时作为干扰进入。
%   处理: 迭代消除data（可选）

%% ========== 1. 参数解析 ========== %%
if nargin < 5, opts = struct(); end
if ~isfield(opts, 'guard_k'), opts.guard_k = 2; end
if ~isfield(opts, 'guard_l'), opts.guard_l = 10; end
if ~isfield(opts, 'pk'), opts.pk = ceil(N/2); end
if ~isfield(opts, 'pl'), opts.pl = ceil(M/2); end
if ~isfield(opts, 'iter'), opts.iter = 1; end

if ~strcmp(pilot_info.mode, 'superimposed')
    error('ch_est_otfs_superimposed仅支持superimposed模式, 当前=%s', pilot_info.mode);
end

pilot_pattern = pilot_info.pilot_pattern;
gk = opts.guard_k;
gl = opts.guard_l;
pk = opts.pk;
pl = opts.pl;

%% ========== 2. 交叉相关信道估计 ========== %%
pilot_energy = sum(abs(pilot_pattern(:)).^2);

% 对所有搜索范围计算相关 C[dk, dl]
corr_matrix = zeros(2*gk+1, gl+1);
for dk = -gk:gk
    for dl = 0:gl
        shifted = circshift(pilot_pattern, [dk, dl]);
        corr_matrix(dk+gk+1, dl+1) = sum(Y_dd(:) .* conj(shifted(:)));
    end
end
h_matrix = corr_matrix / pilot_energy;  % [2*gk+1, gl+1]

%% ========== 3. 噪底估计（搜索范围外的相关值）========== %%
% 取 dk 远离信道范围的行，估计data干扰+噪声
noise_vals = [];
for dk_n = [-gk-3, -gk-2, gk+2, gk+3]
    if abs(dk_n) < N/2
        for dl_n = 0:gl
            shifted = circshift(pilot_pattern, [dk_n, dl_n]);
            c_n = sum(Y_dd(:) .* conj(shifted(:))) / pilot_energy;
            noise_vals = [noise_vals, abs(c_n)];
        end
    end
end
if isempty(noise_vals)
    noise_floor = median(abs(h_matrix(:))) * 0.1;
else
    noise_floor = median(noise_vals);
end

%% ========== 4. 阈值筛选 ========== %%
main_peak = max(abs(h_matrix(:)));
threshold = max(3.0 * noise_floor, main_peak * 0.05);

h_dd = zeros(N, M);
delays = [];
dopplers = [];
gains = [];

for dk = -gk:gk
    for dl = 0:gl
        h_est = h_matrix(dk+gk+1, dl+1);
        if abs(h_est) > threshold
            k_out = mod(pk - 1 + dk, N) + 1;
            l_out = mod(pl - 1 + dl, M) + 1;
            h_dd(k_out, l_out) = h_est;
            delays = [delays, dl];
            dopplers = [dopplers, dk];
            gains = [gains, h_est];
        end
    end
end

%% ========== 5. 迭代数据消除（SPUC: Superimposed Pilot Update w/ Cancellation）%%
% 原理: 初始估计受data干扰 → 用当前h推断data → 从Y减data贡献 → 重估h
for iter = 2:opts.iter
    % 1. 当前h构成 DD 域信道矩阵（origin-centered, 供2D FFT用）
    h_origin = zeros(N, M);
    for p_idx = 1:length(gains)
        dk_p = dopplers(p_idx);
        dl_p = delays(p_idx);
        kk_o = mod(dk_p, N) + 1;
        ll_o = mod(dl_p, M) + 1;
        h_origin(kk_o, ll_o) = gains(p_idx);
    end

    % 2. BCCB 2D-FFT对角化
    D = fft2(h_origin);

    % 3. MMSE正则化参数 = noise_var / signal_var（per-cell，不经过fft放大）
    % Y_cell_var = mean(|Y|²), 近似 = sum(|h|²)*P_x + nv
    % P_x = var(data + pilot) = 1 + pilot_power（QPSK功率1，pilot叠加）
    P_x = 1 + pilot_info.pilot_power;
    Y_cell_var = mean(abs(Y_dd(:)).^2);
    h_power = sum(abs(gains).^2);
    nv_Y_est = max(Y_cell_var - h_power * P_x, 1e-6);
    % MMSE W = conj(H) / (|H|² + σ²/P_x)
    reg_mmse = nv_Y_est / P_x;

    % 4. MMSE均衡得到 x̂ ≈ data + pilot_pattern
    Y_freq = fft2(Y_dd);
    W = conj(D) ./ (abs(D).^2 + reg_mmse);
    X_hat_freq = Y_freq .* W;
    x_hat = ifft2(X_hat_freq);

    % 5. 数据估计 = x̂ - pilot_pattern, 硬判决到QPSK
    data_hat = x_hat - pilot_pattern;
    data_hard = (sign(real(data_hat)) + 1j*sign(imag(data_hat))) / sqrt(2);

    % 6. 重构data贡献, 从Y中减去 → 留下pilot响应+噪声
    data_hard_freq = fft2(data_hard);
    Y_data_hat = ifft2(data_hard_freq .* D);
    Y_pilot_clean = Y_dd - Y_data_hat;

    % 7. 用Y_pilot_clean重估h（data干扰已大幅消除）
    corr_matrix = zeros(2*gk+1, gl+1);
    for dk = -gk:gk
        for dl = 0:gl
            shifted = circshift(pilot_pattern, [dk, dl]);
            corr_matrix(dk+gk+1, dl+1) = sum(Y_pilot_clean(:) .* conj(shifted(:)));
        end
    end
    h_matrix = corr_matrix / pilot_energy;

    % 8. 更新路径集（保持原阈值）
    delays = []; dopplers = []; gains = [];
    h_dd = zeros(N, M);
    for dk = -gk:gk
        for dl = 0:gl
            h_est = h_matrix(dk+gk+1, dl+1);
            if abs(h_est) > threshold
                k_out = mod(pk - 1 + dk, N) + 1;
                l_out = mod(pl - 1 + dl, M) + 1;
                h_dd(k_out, l_out) = h_est;
                delays = [delays, dl];
                dopplers = [dopplers, dk];
                gains = [gains, h_est];
            end
        end
    end
end

%% ========== 6. 输出路径信息 ========== %%
path_info.delay_idx = delays;
path_info.doppler_idx = dopplers;
path_info.gain = gains;
path_info.num_paths = length(gains);
path_info.noise_floor = noise_floor;
path_info.threshold = threshold;

end
