function [h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M)
% 功能：OTFS DD域嵌入导频信道估计——从接收DD域帧提取稀疏路径参数
% 版本：V1.0.0
% 输入：
%   Y_dd       - 接收DD域帧 (NxM 复数矩阵)
%   pilot_info - 导频信息（由 otfs_pilot_embed 生成）
%   N          - 多普勒格点数
%   M          - 时延格点数
% 输出：
%   h_dd      - DD域信道响应矩阵 (NxM，稀疏)
%   path_info - 路径信息结构体数组
%       .delay_idx    : 时延索引 l_i
%       .doppler_idx  : 多普勒索引 k_i
%       .gain         : 复增益 h_i
%       .num_paths    : 检测到的路径数
%
% 备注：
%   - 嵌入导频估计：h_i = Y_dd[k_p+k_i, l_p+l_i] / pilot_value
%   - 在保护区内搜索非零响应即为信道路径

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

%% ========== 提取保护区响应 ========== %%
gk = 2; gl = 2;
if isfield(pilot_info, 'guard_mask')
    gmask = pilot_info.guard_mask;
    [gk_idx, gl_idx] = find(gmask);
    if ~isempty(gk_idx)
        gk = max(abs(gk_idx - pk));
        gl = max(abs(gl_idx - pl));
    end
end

%% ========== 信道估计 ========== %%
h_dd = zeros(N, M);
delays = [];
dopplers = [];
gains = [];

threshold = max(abs(Y_dd(:))) * 0.05;  % 5%幅度门限

for dk = -gk:gk
    for dl = -gl:gl
        if dk == 0 && dl == 0, continue; end  % 跳过导频本身
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

% 导频位置本身（直达径）
h_dd(pk, pl) = Y_dd(pk, pl) / pv;
delays = [0, delays];
dopplers = [0, dopplers];
gains = [Y_dd(pk, pl)/pv, gains];

%% ========== 路径信息 ========== %%
path_info.delay_idx = delays;
path_info.doppler_idx = dopplers;
path_info.gain = gains;
path_info.num_paths = length(gains);

end
