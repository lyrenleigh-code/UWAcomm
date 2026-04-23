function benchmark_e2e_baseline(stage, varargin)
% 功能：E2E 时变信道基线 benchmark 主入口（五阶段 dispatch）
% 版本：V1.1.0（2026-04-23：C 阶段启用，5 体制 runner 加 bench_seed 注入）
%       V1.0.0（2026-04-19）
% 输入：
%   stage - 'A1' | 'A2' | 'A3' | 'B' | 'C' | 'D'
%   可选 name-value：
%     'schemes',  {...}    限制体制子集（默认 grid.schemes）
%     'profiles', {...}    限制 profile 子集（默认 {'custom6'}；exponential 需 runner 改造后启用）
%     'csv_path', char     覆盖默认 CSV 输出（默认 tests/bench_results/e2e_baseline_<stage>.csv）
%     'dry_run',  logical  true 则仅打印 combo 计划不实跑（默认 false）
%     'continue_on_error', logical  单点失败不中断（默认 true）
% 输出：
%   无（CSV 写到 csv_path）
%
% 备注：
%   - 阶段网格定义见 bench_grids.m
%   - fading_cfgs 构造见 bench_build_fading_cfgs.m（各体制列数不同）
%   - A2 自动跳过 OTFS（DD 框架不支持固定 α）
%   - B × OTFS 仍使用 test_otfs_timevarying.m runner（其支持 discrete/hybrid）
%   - 默认 profiles={'custom6'}：runner 实际不切换信道模型，exponential 记录为 meta 但数据等同 custom6
%     计划在后续 spec 扩展 runner 内部 bench_channel_profile→ch_params 切换

%% 1. 参数解析
p = inputParser;
p.addRequired('stage', @(s) ischar(s) && ismember(upper(s), {'A1','A2','A3','B','C','D'}));
p.addParameter('schemes', {}, @iscell);
p.addParameter('profiles', {}, @iscell);
p.addParameter('csv_path', '', @ischar);
p.addParameter('dry_run', false, @islogical);
p.addParameter('continue_on_error', true, @islogical);
p.addParameter('max_combos', Inf, @(x) isnumeric(x) && x > 0);
p.addParameter('snr_list', [], @isnumeric);
p.parse(stage, varargin{:});
stage = upper(p.Results.stage);

%% 2. 路径与依赖
this_dir = fileparts(mfilename('fullpath'));
bench_dir = fullfile(this_dir, 'bench_common');
addpath(bench_dir);

%% 3. 加载 grid
grids = bench_grids();
grid = grids.(stage);

%% 4. 应用体制 / profile 过滤
schemes = grid.schemes;
if ~isempty(p.Results.schemes)
    schemes = p.Results.schemes;
end

% 默认 profiles 仅 custom6（runner 未根据 bench_channel_profile 切换 ch_params）
if ~isempty(p.Results.profiles)
    profiles = p.Results.profiles;
elseif strcmp(stage, 'B')
    profiles = {};  % B 阶段 profile 由 channel_tag 代替
else
    profiles = {'custom6'};
end

%% 5. CSV 输出路径
if isempty(p.Results.csv_path)
    csv_dir = fullfile(this_dir, 'bench_results');
    if ~exist(csv_dir, 'dir'), mkdir(csv_dir); end
    csv_path = fullfile(csv_dir, sprintf('e2e_baseline_%s.csv', stage));
else
    csv_path = p.Results.csv_path;
end

%% 6. 构造 combo 列表
combos = build_combo_list(stage, grid, schemes, profiles);
% 可选 snr_list 覆盖（smoke test 用）
if ~isempty(p.Results.snr_list)
    for k = 1:numel(combos)
        combos(k).snr_list = p.Results.snr_list;
    end
end
% 可选 max_combos 截断
if numel(combos) > p.Results.max_combos
    fprintf('[INFO] 截断 combo: %d → %d (max_combos)\n', numel(combos), p.Results.max_combos);
    combos = combos(1:p.Results.max_combos);
end
total_pts = numel(combos);

fprintf('\n');
fprintf('============================================\n');
fprintf('  E2E Benchmark  Stage %s\n', stage);
fprintf('  Total combos    : %d\n', total_pts);
fprintf('  Schemes         : %s\n', strjoin(schemes, ', '));
if ~isempty(profiles)
    fprintf('  Profiles        : %s\n', strjoin(profiles, ', '));
else
    fprintf('  Channel set     : %s\n', strjoin(grid.channel_set, ', '));
end
fprintf('  CSV             : %s\n', csv_path);
fprintf('============================================\n\n');

if p.Results.dry_run
    fprintf('【DRY-RUN】combo 列表（前 min(20,total) 项）：\n');
    for k = 1:min(20, total_pts)
        fprintf('  [%3d] %-8s | %-10s | ', k, combos(k).scheme, combos(k).profile);
        if ~isnan(combos(k).fd_hz)
            fprintf('fd=%-5g ', combos(k).fd_hz);
        end
        if ~isnan(combos(k).doppler_rate)
            fprintf('α=%-7g ', combos(k).doppler_rate);
        end
        if ~isempty(combos(k).channel_tag)
            fprintf('ch=%s ', combos(k).channel_tag);
        end
        fprintf('| snr=%s\n', mat2str(combos(k).snr_list));
    end
    if total_pts > 20
        fprintf('  ... (剩余 %d 项省略)\n', total_pts - 20);
    end
    return;
end

%% 7. 先清理旧 CSV（覆盖写）
if exist(csv_path, 'file')
    fprintf('[INFO] 删除旧 CSV: %s\n', csv_path);
    delete(csv_path);
end

%% 8. 遍历执行
start_time = tic;
pass_cnt = 0; fail_cnt = 0;
fail_log = {};

for k = 1:total_pts
    c = combos(k);
    t0 = tic;
    label_parts = {c.scheme, c.profile};
    if ~isnan(c.fd_hz),        label_parts{end+1} = sprintf('fd=%g', c.fd_hz); end
    if ~isnan(c.doppler_rate), label_parts{end+1} = sprintf('α=%g', c.doppler_rate); end
    if ~isempty(c.channel_tag), label_parts{end+1} = c.channel_tag; end
    label = strjoin(label_parts, ' | ');
    fprintf('[%3d/%d] %s\n', k, total_pts, label);

    try
        bench_run_single(stage, c.scheme, c.profile, c.snr_list, ...
                         c.fading_cfgs, c.seed, csv_path, c.runner_path);
        pass_cnt = pass_cnt + 1;
        fprintf('         ✓ pass (%.1fs)\n', toc(t0));
    catch ME
        fail_cnt = fail_cnt + 1;
        fail_log{end+1} = sprintf('[%d] %s: %s', k, label, ME.message); %#ok<AGROW>
        fprintf('         ✗ %s\n', ME.message);
        if ~p.Results.continue_on_error
            rethrow(ME);
        end
    end
end

%% 9. 汇总
total_time = toc(start_time);
fprintf('\n');
fprintf('============================================\n');
fprintf('  Stage %s 汇总\n', stage);
fprintf('  Pass     : %d\n', pass_cnt);
fprintf('  Fail     : %d\n', fail_cnt);
fprintf('  Runtime  : %.1f min (%.1f s)\n', total_time / 60, total_time);
fprintf('  CSV      : %s\n', csv_path);
fprintf('============================================\n');
if fail_cnt > 0
    fprintf('\n失败明细：\n');
    for k = 1:numel(fail_log)
        fprintf('  %s\n', fail_log{k});
    end
end

end

% ============ 子函数 ============

function combos = build_combo_list(stage, grid, schemes, profiles)
% 返回 struct 数组，每元素代表一个单点 combo（runner 将跑一次）
combos = struct('scheme', {}, 'profile', {}, 'snr_list', {}, ...
                'fading_cfgs', {}, 'seed', {}, 'runner_path', {}, ...
                'fd_hz', {}, 'doppler_rate', {}, 'channel_tag', {});

for i = 1:numel(schemes)
    scheme = schemes{i};

    % A2 / D 跳过 OTFS（DD 框架不适配固定 α）
    if ismember(stage, {'A2','D'}) && strcmpi(scheme, 'OTFS')
        fprintf('[SKIP] %s × OTFS（DD 框架不支持固定 α）\n', stage);
        continue;
    end

    switch stage
        case 'A1'
            for j = 1:numel(profiles)
                for f = 1:numel(grid.fd_hz_list)
                    fd = grid.fd_hz_list(f);
                    cs = struct('fd_hz', fd);
                    combos(end+1) = make_combo(stage, scheme, profiles{j}, ...
                                               grid.snr_list, cs, grid.seed); %#ok<AGROW>
                end
            end

        case {'A2', 'D'}
            for j = 1:numel(profiles)
                for a = 1:numel(grid.doppler_rate_list)
                    alpha = grid.doppler_rate_list(a);
                    cs = struct('doppler_rate', alpha);
                    combos(end+1) = make_combo(stage, scheme, profiles{j}, ...
                                               grid.snr_list, cs, grid.seed); %#ok<AGROW>
                end
            end

        case 'A3'
            for j = 1:numel(profiles)
                for f = 1:numel(grid.fd_hz_list)
                    for a = 1:numel(grid.doppler_rate_list)
                        fd = grid.fd_hz_list(f);
                        alpha = grid.doppler_rate_list(a);
                        cs = struct('fd_hz', fd, 'doppler_rate', alpha);
                        combos(end+1) = make_combo(stage, scheme, profiles{j}, ...
                                                   grid.snr_list, cs, grid.seed); %#ok<AGROW>
                    end
                end
            end

        case 'B'
            for c = 1:numel(grid.channel_set)
                tag = grid.channel_set{c};
                cs = struct('channel_tag', tag);
                combos(end+1) = make_combo(stage, scheme, tag, ...
                                           grid.snr_list, cs, grid.seed); %#ok<AGROW>
            end

        case 'C'
            % 多 seed 帧检测率（2026-04-23 启用）：schemes × profiles × fd_hz × seeds
            % snr_list 整体传入（不迭代），每 combo 单 seed
            % 预期点数: 6×3×3×5 = 270（依 bench_grids.m grid.C）
            for j = 1:numel(profiles)
                for f = 1:numel(grid.fd_hz_list)
                    for s = 1:numel(grid.seeds)
                        fd = grid.fd_hz_list(f);
                        seed_v = grid.seeds(s);
                        cs = struct('fd_hz', fd);
                        combos(end+1) = make_combo(stage, scheme, profiles{j}, ...
                                                   grid.snr_list, cs, seed_v); %#ok<AGROW>
                    end
                end
            end
    end
end

end

function c = make_combo(stage, scheme, profile, snr_list, combo_spec, seed)
c = struct();
c.scheme = scheme;
c.profile = profile;
c.snr_list = snr_list;
c.seed = seed;
c.fading_cfgs = bench_build_fading_cfgs(stage, scheme, combo_spec);
c.runner_path = resolve_runner(stage, scheme);
c.fd_hz        = get_field_or(combo_spec, 'fd_hz', NaN);
c.doppler_rate = get_field_or(combo_spec, 'doppler_rate', NaN);
c.channel_tag  = get_field_or(combo_spec, 'channel_tag', '');
end

function runner_path = resolve_runner(stage, scheme)
% A1/A2/A3 → test_*_timevarying.m
% B        → test_*_discrete_doppler.m（OTFS 例外，仍用 timevarying）
this_dir = fileparts(mfilename('fullpath'));

use_discrete = strcmp(stage, 'B') && ~strcmpi(scheme, 'OTFS');
suffix = '_timevarying';
if use_discrete
    suffix = '_discrete_doppler';
end

switch upper(scheme)
    case 'SC-FDE'
        subdir = 'SC-FDE'; fname = ['test_scfde'  suffix '.m'];
    case 'OFDM'
        subdir = 'OFDM';   fname = ['test_ofdm'   suffix '.m'];
    case 'SC-TDE'
        subdir = 'SC-TDE'; fname = ['test_sctde'  suffix '.m'];
    case 'OTFS'
        subdir = 'OTFS';   fname = 'test_otfs_timevarying.m';
    case 'DSSS'
        subdir = 'DSSS';   fname = ['test_dsss'   suffix '.m'];
    case 'FH-MFSK'
        subdir = 'FH-MFSK'; fname = ['test_fhmfsk' suffix '.m'];
    otherwise
        error('resolve_runner:UnknownScheme', '未知体制: %s', scheme);
end
runner_path = fullfile(this_dir, subdir, fname);
if ~exist(runner_path, 'file')
    error('resolve_runner:RunnerNotFound', 'Runner 不存在: %s', runner_path);
end
end

function v = get_field_or(s, f, default)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = default;
end
end
