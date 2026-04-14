function [dd_frame, pilot_info, guard_mask, data_indices] = otfs_pilot_embed(data_symbols, N, M, pilot_config)
% 功能：OTFS DD域导频嵌入——支持5种导频方案
% 版本：V2.1.0 — 新增delay_guard: 排除l<max_delay区域(消除帧CP β因子)
% 输入：
%   data_symbols - 数据符号 (1xK 向量)
%   N            - 多普勒格点数
%   M            - 时延格点数
%   pilot_config - 导频配置结构体
%       .mode        : 导频模式（默认'impulse'）
%                      'impulse'     - 单脉冲+矩形保护区（经典方案）
%                      'multi_pulse' - 多脉冲（多个位置放导频）
%                      'superimposed'- 叠加导频（导频叠加在数据上）
%                      'sequence'    - 序列导频（ZC序列替代脉冲）
%                      'adaptive'    - 保护区自适应（根据信道扩展调整）
%       .pilot_value : 导频幅度 (默认 1)
%       .guard_k     : 多普勒保护格点数 (默认 2)
%       .guard_l     : 时延保护格点数 (默认 2)
%       === 单脉冲/自适应模式 ===
%       .pilot_k     : 导频多普勒索引 (默认 ceil(N/2))
%       .pilot_l     : 导频时延索引 (默认 ceil(M/2))
%       === 多脉冲模式 ===
%       .pilot_positions : Px2矩阵，每行[k,l]为一个导频位置
%       === 叠加模式 ===
%       .pilot_power : 导频功率缩放因子 (默认 0.2，即数据功率的20%)
%       === 序列模式 ===
%       .seq_type    : 序列类型 ('zc'(默认) 或 'random')
%       .seq_root    : ZC序列根索引 (默认 1)
%       === 自适应模式 ===
%       .max_delay_spread   : 最大时延扩展（格点数，默认 3）
%       .max_doppler_spread : 最大多普勒扩展（格点数，默认 2）
% 输出：
%   dd_frame     - NxM DD域帧
%   pilot_info   - 导频信息结构体（供信道估计使用）
%       .mode, .positions, .values, .guard_mask 等
%   guard_mask   - NxM 逻辑矩阵（1=保护/导频区，0=数据区）
%   data_indices - 数据格点线性索引
%
% 备注：
%   5种模式对比：
%   impulse     : 最简单，单点大功率，估计简单，频谱效率低
%   multi_pulse : 多观测点，抗噪声更好，适合多径丰富信道
%   superimposed: 不占独立格点，频谱效率最高，需迭代消除干扰
%   sequence    : ZC序列低PAPR，估计精度高，复杂度稍增
%   adaptive    : 保护区随信道扩展自适应，兼顾效率和可靠性

%% ========== 1. 入参解析与默认值 ========== %%
if nargin < 4 || isempty(pilot_config), pilot_config = struct(); end
if ~isfield(pilot_config, 'mode'), pilot_config.mode = 'impulse'; end
if ~isfield(pilot_config, 'pilot_value'), pilot_config.pilot_value = 1; end
if ~isfield(pilot_config, 'guard_k'), pilot_config.guard_k = 2; end
if ~isfield(pilot_config, 'guard_l'), pilot_config.guard_l = 2; end
if ~isfield(pilot_config, 'pilot_k'), pilot_config.pilot_k = ceil(N/2); end
if ~isfield(pilot_config, 'pilot_l'), pilot_config.pilot_l = ceil(M/2); end

%% ========== 2. 参数校验 ========== %%
if isempty(data_symbols), error('数据符号不能为空！'); end

%% ========== 3. 按模式生成导频帧 ========== %%
switch pilot_config.mode
    case 'impulse'
        [dd_frame, pilot_info, guard_mask, data_indices] = ...
            embed_impulse(data_symbols, N, M, pilot_config);

    case 'multi_pulse'
        [dd_frame, pilot_info, guard_mask, data_indices] = ...
            embed_multi_pulse(data_symbols, N, M, pilot_config);

    case 'superimposed'
        [dd_frame, pilot_info, guard_mask, data_indices] = ...
            embed_superimposed(data_symbols, N, M, pilot_config);

    case 'sequence'
        [dd_frame, pilot_info, guard_mask, data_indices] = ...
            embed_sequence(data_symbols, N, M, pilot_config);

    case 'adaptive'
        [dd_frame, pilot_info, guard_mask, data_indices] = ...
            embed_adaptive(data_symbols, N, M, pilot_config);

    otherwise
        error('不支持的导频模式: %s！支持 impulse/multi_pulse/superimposed/sequence/adaptive', ...
              pilot_config.mode);
end

end

%% =====================================================================
%  辅助函数
%% =====================================================================

% --------------- 1. 单脉冲嵌入导频 --------------- %
function [dd, info, gmask, didx] = embed_impulse(data, N, M, cfg)
pk = cfg.pilot_k; pl = cfg.pilot_l;
gk = cfg.guard_k; gl = cfg.guard_l;
pv = cfg.pilot_value;

gmask = build_guard_mask(N, M, [pk, pl], gk, gl);

% 延迟保护区：排除 l < delay_guard 的列（消除帧CP跨子块β因子）
if isfield(cfg, 'delay_guard') && cfg.delay_guard > 0
    for l_dg = 1:min(cfg.delay_guard, M)
        gmask(:, l_dg) = true;
    end
end

didx = find(~gmask);

data_padded = pad_data(data, length(didx));
dd = zeros(N, M);
dd(pk, pl) = pv;
dd(didx) = data_padded;

info.mode = 'impulse';
info.positions = [pk, pl];
info.values = pv;
info.guard_mask = gmask;
end

% --------------- 2. 多脉冲导频 --------------- %
function [dd, info, gmask, didx] = embed_multi_pulse(data, N, M, cfg)
if ~isfield(cfg, 'pilot_positions')
    % 默认4个脉冲：四象限各一个
    cfg.pilot_positions = [
        ceil(N/4),   ceil(M/4);
        ceil(N/4),   ceil(3*M/4);
        ceil(3*N/4), ceil(M/4);
        ceil(3*N/4), ceil(3*M/4)];
end
positions = cfg.pilot_positions;
P = size(positions, 1);
gk = cfg.guard_k; gl = cfg.guard_l;
pv = cfg.pilot_value;

% 合并所有导频的保护区
gmask = false(N, M);
for p = 1:P
    gmask = gmask | build_guard_mask(N, M, positions(p,:), gk, gl);
end

didx = find(~gmask);
data_padded = pad_data(data, length(didx));

dd = zeros(N, M);
for p = 1:P
    dd(positions(p,1), positions(p,2)) = pv;
end
dd(didx) = data_padded;

info.mode = 'multi_pulse';
info.positions = positions;
info.values = pv * ones(P, 1);
info.guard_mask = gmask;
end

% --------------- 3. 叠加导频 --------------- %
function [dd, info, gmask, didx] = embed_superimposed(data, N, M, cfg)
if ~isfield(cfg, 'pilot_power'), cfg.pilot_power = 0.2; end

% 叠加模式无保护区，所有格点都放数据
gmask = false(N, M);
didx = find(~gmask);  % 全部格点
data_padded = pad_data(data, N*M);

dd = zeros(N, M);
dd(:) = data_padded;

% 生成叠加导频（全格点已知图案，功率缩放）
rng_state = rng; rng(0);
pilot_pattern = (2*randi([0,1],N,M) - 1) * sqrt(cfg.pilot_power);
rng(rng_state);

dd = dd + pilot_pattern;              % 导频叠加在数据上

info.mode = 'superimposed';
info.pilot_pattern = pilot_pattern;   % 收端需要此图案做干扰消除
info.pilot_power = cfg.pilot_power;
info.positions = [];
info.values = [];
info.guard_mask = gmask;
end

% --------------- 4. 序列导频 --------------- %
function [dd, info, gmask, didx] = embed_sequence(data, N, M, cfg)
if ~isfield(cfg, 'seq_type'), cfg.seq_type = 'zc'; end
if ~isfield(cfg, 'seq_root'), cfg.seq_root = 1; end
pk = cfg.pilot_k; pl = cfg.pilot_l;
gk = cfg.guard_k; gl = cfg.guard_l;

% 序列长度=2gl+1, 充分CAZAC覆盖
seq_len = 2*gl + 1;
switch cfg.seq_type
    case 'zc'
        if seq_len < 2, seq_len = 3; end
        seq = exp(-1j * pi * cfg.seq_root * (0:seq_len-1) .* (1:seq_len) / seq_len);
    case 'random'
        rng_state = rng; rng(cfg.seq_root);
        seq = (2*randi([0,1],1,seq_len) - 1) + 1j*(2*randi([0,1],1,seq_len) - 1);
        seq = seq / sqrt(2);
        rng(rng_state);
    otherwise
        error('不支持的序列类型: %s', cfg.seq_type);
end
seq = seq * cfg.pilot_value;

% 保护区: cols [pl-gl, pl+gl]（仅pilot占用范围）
gmask = false(N, M);
pilot_cols = mod(pl - 1 + (-gl:gl), M) + 1;
for dk = -gk:gk
    kk = mod(pk - 1 + dk, N) + 1;
    gmask(kk, pilot_cols) = true;
end

didx = find(~gmask);
data_padded = pad_data(data, length(didx));

dd = zeros(N, M);
for i = 1:seq_len
    ll = pilot_cols(i);
    dd(pk, ll) = seq(i);
end
dd(didx) = data_padded;

info.mode = 'sequence';
info.positions = [pk * ones(seq_len,1), pilot_cols(:)];
info.values = seq(:);
info.seq_type = cfg.seq_type;
info.guard_mask = gmask;
info.seq_len = seq_len;
end

% --------------- 5. 保护区自适应导频 --------------- %
function [dd, info, gmask, didx] = embed_adaptive(data, N, M, cfg)
if ~isfield(cfg, 'max_delay_spread'), cfg.max_delay_spread = 3; end
if ~isfield(cfg, 'max_doppler_spread'), cfg.max_doppler_spread = 2; end
pk = cfg.pilot_k; pl = cfg.pilot_l;
pv = cfg.pilot_value;

% 保护区大小 = 信道扩展 + 1（余量）
gl_adapt = cfg.max_delay_spread + 1;
gk_adapt = cfg.max_doppler_spread + 1;

gmask = build_guard_mask(N, M, [pk, pl], gk_adapt, gl_adapt);
didx = find(~gmask);
data_padded = pad_data(data, length(didx));

dd = zeros(N, M);
dd(pk, pl) = pv;
dd(didx) = data_padded;

info.mode = 'adaptive';
info.positions = [pk, pl];
info.values = pv;
info.guard_k = gk_adapt;
info.guard_l = gl_adapt;
info.max_delay_spread = cfg.max_delay_spread;
info.max_doppler_spread = cfg.max_doppler_spread;
info.guard_mask = gmask;
end

% --------------- 通用：构建矩形保护区掩模 --------------- %
function gmask = build_guard_mask(N, M, center, gk, gl)
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

% --------------- 通用：数据补零对齐 --------------- %
function data_out = pad_data(data, target_len)
data = data(:).';
if length(data) > target_len
    warning('数据符号(%d)超过可用格点(%d)，截断！', length(data), target_len);
    data_out = data(1:target_len);
elseif length(data) < target_len
    data_out = [data, zeros(1, target_len - length(data))];
else
    data_out = data;
end
end
