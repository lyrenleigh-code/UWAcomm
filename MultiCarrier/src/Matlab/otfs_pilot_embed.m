function [dd_frame, pilot_pos, guard_mask, data_indices] = otfs_pilot_embed(data_symbols, N, M, pilot_config)
% 功能：OTFS DD域嵌入导频——单脉冲导频+保护区+数据
% 版本：V1.0.0
% 输入：
%   data_symbols - 数据符号 (1xK 向量)
%   N            - 多普勒格点数
%   M            - 时延格点数
%   pilot_config - 导频配置结构体（可选）
%       .pilot_k     : 导频多普勒索引 (默认 ceil(N/2))
%       .pilot_l     : 导频时延索引 (默认 ceil(M/2))
%       .pilot_value : 导频值 (默认 1)
%       .guard_k     : 多普勒方向保护格点数 (默认 2)
%       .guard_l     : 时延方向保护格点数 (默认 2)
% 输出：
%   dd_frame     - NxM DD域帧（含导频+保护+数据）
%   pilot_pos    - 导频位置 [k, l]
%   guard_mask   - NxM 逻辑矩阵（1=保护/导频区，0=数据区）
%   data_indices - 数据格点线性索引

%% ========== 1. 入参解析 ========== %%
if nargin < 4 || isempty(pilot_config), pilot_config = struct(); end
if ~isfield(pilot_config, 'pilot_k'), pilot_config.pilot_k = ceil(N/2); end
if ~isfield(pilot_config, 'pilot_l'), pilot_config.pilot_l = ceil(M/2); end
if ~isfield(pilot_config, 'pilot_value'), pilot_config.pilot_value = 1; end
if ~isfield(pilot_config, 'guard_k'), pilot_config.guard_k = 2; end
if ~isfield(pilot_config, 'guard_l'), pilot_config.guard_l = 2; end

pk = pilot_config.pilot_k;
pl = pilot_config.pilot_l;
gk = pilot_config.guard_k;
gl = pilot_config.guard_l;
pv = pilot_config.pilot_value;

%% ========== 2. 构建保护区掩模 ========== %%
guard_mask = false(N, M);

% 导频位置周围的保护区（矩形）
for dk = -gk:gk
    for dl = -gl:gl
        kk = mod(pk - 1 + dk, N) + 1;
        ll = mod(pl - 1 + dl, M) + 1;
        guard_mask(kk, ll) = true;
    end
end

%% ========== 3. 确定数据格点 ========== %%
data_indices = find(~guard_mask);
num_data_slots = length(data_indices);

%% ========== 4. 参数校验 ========== %%
if isempty(data_symbols), error('数据符号不能为空！'); end
if length(data_symbols) > num_data_slots
    warning('数据符号(%d)超过可用格点(%d)，截断！', length(data_symbols), num_data_slots);
    data_symbols = data_symbols(1:num_data_slots);
elseif length(data_symbols) < num_data_slots
    data_symbols = [data_symbols(:).', zeros(1, num_data_slots - length(data_symbols))];
end

%% ========== 5. 组装DD域帧 ========== %%
dd_frame = zeros(N, M);

% 放置导频
dd_frame(pk, pl) = pv;

% 保护区填零（默认已是零）

% 放置数据
dd_frame(data_indices) = data_symbols;

%% ========== 6. 输出 ========== %%
pilot_pos = [pk, pl];

end
