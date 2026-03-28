function [data_indices, guard_mask, num_data] = otfs_get_data_indices(N, M, pilot_config)
% 功能：获取OTFS DD域数据格点索引（去除导频和保护区）
% 版本：V2.0.0 — 支持5种导频模式
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
if ~isfield(pilot_config, 'mode'), pilot_config.mode = 'impulse'; end
if ~isfield(pilot_config, 'pilot_k'), pilot_config.pilot_k = ceil(N/2); end
if ~isfield(pilot_config, 'pilot_l'), pilot_config.pilot_l = ceil(M/2); end
if ~isfield(pilot_config, 'guard_k'), pilot_config.guard_k = 2; end
if ~isfield(pilot_config, 'guard_l'), pilot_config.guard_l = 2; end

%% ========== 2. 按模式构建保护区掩模 ========== %%
switch pilot_config.mode
    case 'impulse'
        guard_mask = build_guard(N, M, [pilot_config.pilot_k, pilot_config.pilot_l], ...
                                 pilot_config.guard_k, pilot_config.guard_l);

    case 'multi_pulse'
        if ~isfield(pilot_config, 'pilot_positions')
            pilot_config.pilot_positions = [ceil(N/4),ceil(M/4); ceil(N/4),ceil(3*M/4);
                                            ceil(3*N/4),ceil(M/4); ceil(3*N/4),ceil(3*M/4)];
        end
        guard_mask = false(N, M);
        for p = 1:size(pilot_config.pilot_positions, 1)
            guard_mask = guard_mask | build_guard(N, M, pilot_config.pilot_positions(p,:), ...
                                                   pilot_config.guard_k, pilot_config.guard_l);
        end

    case 'superimposed'
        guard_mask = false(N, M);      % 叠加模式无保护区

    case 'sequence'
        gl = pilot_config.guard_l;
        gk = pilot_config.guard_k;
        pk = pilot_config.pilot_k;
        pl = pilot_config.pilot_l;
        pilot_cols = mod(pl - 1 + (-gl:gl), M) + 1;
        guard_mask = false(N, M);
        for dk = -gk:gk
            kk = mod(pk - 1 + dk, N) + 1;
            guard_mask(kk, pilot_cols) = true;
        end

    case 'adaptive'
        if ~isfield(pilot_config, 'max_delay_spread'), pilot_config.max_delay_spread = 3; end
        if ~isfield(pilot_config, 'max_doppler_spread'), pilot_config.max_doppler_spread = 2; end
        gl_a = pilot_config.max_delay_spread + 1;
        gk_a = pilot_config.max_doppler_spread + 1;
        guard_mask = build_guard(N, M, [pilot_config.pilot_k, pilot_config.pilot_l], gk_a, gl_a);

    otherwise
        guard_mask = build_guard(N, M, [pilot_config.pilot_k, pilot_config.pilot_l], ...
                                 pilot_config.guard_k, pilot_config.guard_l);
end

%% ========== 3. 数据格点 ========== %%
data_indices = find(~guard_mask);
num_data = length(data_indices);

end

% --------------- 辅助函数 --------------- %
function gmask = build_guard(N, M, center, gk, gl)
gmask = false(N, M);
pk = center(1); pl = center(2);
for dk = -gk:gk
    for dl = -gl:gl
        kk = mod(pk - 1 + dk, N) + 1;
        ll = mod(pl - 1 + dl, M) + 1;
        gmask(kk, ll) = true;
    end
end
end
