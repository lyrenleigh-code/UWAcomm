function [data_indices, guard_mask, num_data] = otfs_get_data_indices(N, M, pilot_config)
% 功能：获取OTFS DD域数据格点索引（去除导频和保护区）
% 版本：V1.0.0
% 输入：
%   N            - 多普勒格点数
%   M            - 时延格点数
%   pilot_config - 导频配置（须与otfs_pilot_embed一致）
% 输出：
%   data_indices - 数据格点线性索引 (1xK)
%   guard_mask   - NxM 保护区掩模
%   num_data     - 可用数据格点总数

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(pilot_config), pilot_config = struct(); end
if ~isfield(pilot_config, 'pilot_k'), pilot_config.pilot_k = ceil(N/2); end
if ~isfield(pilot_config, 'pilot_l'), pilot_config.pilot_l = ceil(M/2); end
if ~isfield(pilot_config, 'guard_k'), pilot_config.guard_k = 2; end
if ~isfield(pilot_config, 'guard_l'), pilot_config.guard_l = 2; end

%% ========== 2. 构建保护区掩模 ========== %%
guard_mask = false(N, M);
pk = pilot_config.pilot_k;
pl = pilot_config.pilot_l;
gk = pilot_config.guard_k;
gl = pilot_config.guard_l;

for dk = -gk:gk
    for dl = -gl:gl
        kk = mod(pk - 1 + dk, N) + 1;
        ll = mod(pl - 1 + dl, M) + 1;
        guard_mask(kk, ll) = true;
    end
end

%% ========== 3. 数据格点 ========== %%
data_indices = find(~guard_mask);
num_data = length(data_indices);

end
