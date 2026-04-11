function [h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M)
% 功能：OTFS DD域嵌入导频信道估计——从接收DD域帧提取稀疏路径参数
% 版本：V2.0.0 — 自动检测Doppler扩展程度，动态调整阈值
%   静态信道(Doppler ratio<10%): 3σ严格阈值 → 稀疏5径
%   时变信道(Doppler ratio>10%): 1σ宽松阈值 → 捕获扩散Doppler云
% 输入：
%   Y_dd       - 接收DD域帧 (NxM 复数矩阵)
%   pilot_info - 导频信息（由 otfs_pilot_embed 生成）
%   N          - 多普勒格点数
%   M          - 时延格点数
% 输出：
%   h_dd      - DD域信道响应矩阵 (NxM，稀疏)
%   path_info - 路径信息结构体
%       .delay_idx    : 时延索引 l_i (1xP)
%       .doppler_idx  : 多普勒索引 k_i (1xP)
%       .gain         : 复增益 h_i (1xP)
%       .num_paths    : 检测到的路径数
%       .doppler_ratio: Doppler能量扩展比(0=静态, >0.1=时变)
%       .noise_floor  : 估计噪底
%       .threshold    : 实际使用的阈值
%
% 备注：
%   V2.0变更：
%   1. 自动检测Doppler扩展：计算dk=0 vs dk≠0的能量比
%   2. 静态→3σ阈值(稀疏), 时变→1σ阈值(捕获扩散)
%   3. 新增输出字段: doppler_ratio, noise_floor, threshold

%% ========== 参数解析 ========== %%
if ~isfield(pilot_info, 'positions') || isempty(pilot_info.positions)
    error('导频信息缺少positions字段！');
end

pk = pilot_info.positions(1, 1);
pl = pilot_info.positions(1, 2);

if isfield(pilot_info, 'values') && ~isempty(pilot_info.values)
    pv = pilot_info.values(1);
else
    pv = 1;
end

%% ========== 提取保护区范围 ========== %%
gk = 2; gl = 2;
if isfield(pilot_info, 'guard_mask')
    gmask = pilot_info.guard_mask;
    [gk_idx, ~] = find(gmask);
    if ~isempty(gk_idx)
        gk = max(abs(gk_idx - pk));
        % gl: 只取正延迟方向的最大偏移
        for dl_scan = 0:M-1
            ll_scan = mod(pl - 1 + dl_scan, M) + 1;
            if ~gmask(pk, ll_scan) && dl_scan > 0
                gl = dl_scan - 1;
                break;
            end
            if dl_scan == M-1, gl = M-1; end
        end
    end
end

%% ========== 噪底估计 + Doppler扩展检测 ========== %%
% 1. 收集保护区归一化响应
guard_abs = [];
for dk_t = -gk:gk
    for dl_t = 0:gl
        if dk_t == 0 && dl_t == 0, continue; end
        kk_t = mod(pk - 1 + dk_t, N) + 1;
        ll_t = mod(pl - 1 + dl_t, M) + 1;
        guard_abs = [guard_abs, abs(Y_dd(kk_t, ll_t) / pv)]; %#ok<AGROW>
    end
end
noise_floor = median(guard_abs);

% 2. Doppler扩展检测：直达径位置(dl=0)的dk=0 vs dk≠0能量
E_dk0 = abs(Y_dd(pk, pl) / pv)^2;
E_dk_other = 0;
for dk_d = [-gk:-1, 1:gk]
    kk_d = mod(pk - 1 + dk_d, N) + 1;
    E_dk_other = E_dk_other + abs(Y_dd(kk_d, pl) / pv)^2;
end
doppler_ratio = E_dk_other / max(E_dk0 + E_dk_other, 1e-20);

% 3. 动态阈值
pilot_response_norm = abs(Y_dd(pk, pl) / pv);
if doppler_ratio > 0.1
    % 时变信道: 宽松阈值(1σ)，捕获Doppler扩散
    threshold = max(1.0 * noise_floor, pilot_response_norm * 0.005);
else
    % 静态信道: 严格阈值(3σ)，稀疏检测
    threshold = max(3.0 * noise_floor, pilot_response_norm * 0.01);
end

%% ========== 信道估计 ========== %%
h_dd = zeros(N, M);
delays = [];
dopplers = [];
gains = [];

for dk = -gk:gk
    for dl = 0:gl  % 物理时延非负
        if dk == 0 && dl == 0, continue; end
        kk = mod(pk - 1 + dk, N) + 1;
        ll = mod(pl - 1 + dl, M) + 1;

        val = Y_dd(kk, ll) / pv;
        if abs(val) > threshold
            h_dd(kk, ll) = val;
            delays = [delays, dl]; %#ok<AGROW>
            dopplers = [dopplers, dk]; %#ok<AGROW>
            gains = [gains, val]; %#ok<AGROW>
        end
    end
end

% 导频位置（直达径）
h_dd(pk, pl) = Y_dd(pk, pl) / pv;
delays = [0, delays];
dopplers = [0, dopplers];
gains = [Y_dd(pk, pl)/pv, gains];

%% ========== 路径信息 ========== %%
path_info.delay_idx = delays;
path_info.doppler_idx = dopplers;
path_info.gain = gains;
path_info.num_paths = length(gains);
path_info.doppler_ratio = doppler_ratio;
path_info.noise_floor = noise_floor;
path_info.threshold = threshold;

end
