function app = p6_amc_demo_ui(opts)
%P6_AMC_DEMO_UI Interactive dashboard for Streaming P6 AMC policy results.
%
% Usage:
%   p6_amc_demo_ui()
%   app = p6_amc_demo_ui(struct('visible', 'off'));
%   app = p6_amc_demo_ui(struct('headless', true));

if nargin < 1 || ~isstruct(opts), opts = struct(); end

this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
tests_dir = fullfile(streaming_root, 'tests');
addpath(streaming_root);
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'amc'));
if exist('streaming_addpaths', 'file') == 2
    streaming_addpaths();
end

app = struct();
app.sys = sys_params_default();
app.tests_dir = tests_dir;
app.artifacts = load_artifacts(tests_dir);
app.default_scenario = getfield_def(opts, 'scenario', 'Business frame');
app.default_policy = getfield_def(opts, 'policy', 'AMC profile-aware');

if getfield_def(opts, 'headless', false)
    [app.detail, app.summary] = run_preview(app.default_scenario, ...
        app.default_policy, app.sys, app.artifacts);
    app.artifact_table = make_artifact_table(app.artifacts);
    return;
end

visible = getfield_def(opts, 'visible', 'on');
app.fig = uifigure('Name', 'Streaming P6 AMC Dashboard', ...
    'Position', [80 80 1320 820], 'Visible', visible, ...
    'Color', [0.07 0.09 0.11]);

main = uigridlayout(app.fig, [4 1]);
main.RowHeight = {64, 86, '1x', 230};
main.ColumnWidth = {'1x'};
main.Padding = [12 12 12 12];
main.RowSpacing = 10;
main.BackgroundColor = [0.07 0.09 0.11];

build_header(main);
build_metrics(main);
build_plots(main);
build_tables(main);
refresh_view();

    function build_header(parent)
        top = uigridlayout(parent, [1 7]);
        top.Layout.Row = 1;
        top.ColumnWidth = {'1x', 145, 230, 110, 130, 120, 170};
        top.ColumnSpacing = 10;
        top.Padding = [12 8 12 8];
        top.BackgroundColor = [0.10 0.13 0.16];

        title = uilabel(top, 'Text', 'Streaming P6 AMC Dashboard', ...
            'FontSize', 22, 'FontWeight', 'bold', ...
            'FontColor', [0.79 0.93 1.00]);
        title.Layout.Column = 1;

        uilabel(top, 'Text', 'Scenario', 'FontColor', [0.70 0.77 0.82], ...
            'HorizontalAlignment', 'right');
        app.scenario_dd = uidropdown(top, ...
            'Items', {'Business frame', 'Stateful 32-frame', 'High-Doppler DSSS scan'}, ...
            'Value', app.default_scenario, 'ValueChangedFcn', @(~,~) refresh_view());
        app.scenario_dd.Layout.Column = 3;

        uilabel(top, 'Text', 'Policy', 'FontColor', [0.70 0.77 0.82], ...
            'HorizontalAlignment', 'right');
        app.policy_dd = uidropdown(top, ...
            'Items', {'AMC default', 'AMC profile-aware', ...
                      'AMC safe fastDSSS', 'Fixed OFDM', 'Fixed DSSS-sps3'}, ...
            'Value', app.default_policy, 'ValueChangedFcn', @(~,~) refresh_view());
        app.policy_dd.Layout.Column = 5;

        app.run_btn = uibutton(top, 'push', 'Text', 'Run preview', ...
            'FontWeight', 'bold', 'BackgroundColor', [0.08 0.45 0.78], ...
            'FontColor', 'white', 'ButtonPushedFcn', @(~,~) refresh_view());
        app.run_btn.Layout.Column = 6;

        app.status_lbl = uilabel(top, 'Text', 'Ready', ...
            'FontColor', [0.55 0.90 0.70], 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center');
        app.status_lbl.Layout.Column = 7;
    end

    function build_metrics(parent)
        box = uigridlayout(parent, [1 6]);
        box.Layout.Row = 2;
        box.ColumnWidth = repmat({'1x'}, 1, 6);
        box.ColumnSpacing = 10;
        box.Padding = [0 0 0 0];
        box.BackgroundColor = [0.07 0.09 0.11];

        names = {'Mean utility', 'Mean BER', 'Outage', 'Goodput', ...
                 'Switches', 'Profile note'};
        fields = {'utility', 'ber', 'outage', 'goodput', 'switches', 'note'};
        for k = 1:numel(names)
            p = uipanel(box, 'BackgroundColor', [0.10 0.13 0.16], ...
                'BorderType', 'line', 'ForegroundColor', [0.35 0.45 0.55]);
            p.Layout.Column = k;
            g = uigridlayout(p, [2 1]);
            g.RowHeight = {24, '1x'};
            g.Padding = [10 7 10 8];
            g.BackgroundColor = [0.10 0.13 0.16];
            uilabel(g, 'Text', names{k}, 'FontSize', 11, ...
                'FontColor', [0.63 0.70 0.76]);
            value = uilabel(g, 'Text', '-', 'FontSize', 18, ...
                'FontWeight', 'bold', 'FontColor', [0.91 0.96 1.00]);
            value.Layout.Row = 2;
            app.metric.(fields{k}) = value;
        end
    end

    function build_plots(parent)
        pane = uigridlayout(parent, [1 2]);
        pane.Layout.Row = 3;
        pane.ColumnWidth = {'1.1x', '1x'};
        pane.ColumnSpacing = 10;
        pane.BackgroundColor = [0.07 0.09 0.11];

        app.ax_mode = uiaxes(pane);
        app.ax_mode.Layout.Column = 1;
        style_uiaxes(app.ax_mode);
        title(app.ax_mode, 'Selected mode/profile timeline');

        app.ax_metric = uiaxes(pane);
        app.ax_metric.Layout.Column = 2;
        style_uiaxes(app.ax_metric);
        title(app.ax_metric, 'BER and utility preview');
    end

    function build_tables(parent)
        tabs = uitabgroup(parent);
        tabs.Layout.Row = 4;

        t1 = uitab(tabs, 'Title', 'Frame decisions');
        g1 = uigridlayout(t1, [1 1]);
        app.detail_tbl = uitable(g1);
        app.detail_tbl.Layout.Row = 1;

        t2 = uitab(tabs, 'Title', 'Regression artifacts');
        g2 = uigridlayout(t2, [1 1]);
        app.artifact_tbl = uitable(g2);
        app.artifact_tbl.Layout.Row = 1;
    end

    function refresh_view()
        try
            scenario = app.scenario_dd.Value;
            policy = app.policy_dd.Value;
            [detail, summary] = run_preview(scenario, policy, app.sys, app.artifacts);
            app.detail = detail;
            app.summary = summary;

            app.metric.utility.Text = sprintf('%.3f', summary.mean_utility);
            app.metric.ber.Text = sprintf('%.3g', summary.mean_ber);
            app.metric.outage.Text = sprintf('%d/%d', ...
                summary.outage_frames, height(detail));
            app.metric.goodput.Text = sprintf('%.3f', summary.mean_goodput);
            app.metric.switches.Text = sprintf('%d', summary.switches);
            app.metric.note.Text = summary.note;

            app.detail_tbl.Data = detail;
            app.artifact_tbl.Data = make_artifact_table(app.artifacts);
            plot_detail(app.ax_mode, app.ax_metric, detail);
            app.status_lbl.Text = 'Updated';
            app.status_lbl.FontColor = [0.55 0.90 0.70];
        catch ME
            app.status_lbl.Text = ME.identifier;
            app.status_lbl.FontColor = [1.00 0.48 0.45];
            rethrow(ME);
        end
    end
end

% -------------------------------------------------------------------------
function [detail, summary] = run_preview(scenario_name, policy_name, sys, artifacts)

timeline = make_timeline(scenario_name);
policy = make_policy(policy_name, sys);
grid = artifacts.profile_grid;
state = struct();

N = numel(timeline);
frame = zeros(N, 1);
segment = cell(N, 1);
snr_db = zeros(N, 1);
fd_hz = zeros(N, 1);
seed = zeros(N, 1);
target = cell(N, 1);
selected = cell(N, 1);
profile = cell(N, 1);
reason = cell(N, 1);
ber = nan(N, 1);
goodput = nan(N, 1);
utility = nan(N, 1);

for k = 1:N
    q = timeline{k};
    frame(k) = q.frame_idx;
    segment{k} = q.label;
    snr_db(k) = q.snr_est_db;
    fd_hz(k) = q.doppler_hz;
    seed(k) = q.seed;

    switch policy.kind
        case 'amc'
            [decision, state] = mode_selector(q, state, sys, policy.opts);
            decision = apply_ui_profile_guard(decision, q, policy);
            target{k} = decision_to_candidate(decision.target_scheme, ...
                decision.target_profile);
            selected{k} = decision_to_candidate(decision.selected_scheme, ...
                decision.selected_profile);
            profile{k} = decision.selected_profile;
            reason{k} = decision.hold_reason;
        case 'fixed'
            target{k} = policy.candidate;
            selected{k} = policy.candidate;
            profile{k} = policy.profile;
            reason{k} = 'fixed';
        otherwise
            error('p6_amc_demo_ui: unknown policy kind "%s"', policy.kind);
    end

    m = metric_for_candidate(grid, q, selected{k}, profile{k}, artifacts);
    ber(k) = m.ber;
    goodput(k) = m.goodput;
    utility(k) = m.utility;
end

detail = table(frame, segment, snr_db, fd_hz, seed, target, selected, ...
    profile, reason, ber, goodput, utility);

summary = struct();
summary.mean_utility = mean_omitnan(utility);
summary.mean_ber = mean_omitnan(ber);
summary.mean_goodput = mean_omitnan(goodput);
summary.outage_frames = sum(ber > 5.0e-2);
summary.switches = count_switches(selected);
summary.note = policy.note;

end

% -------------------------------------------------------------------------
function timeline = make_timeline(name)

switch name
    case 'Business frame'
        specs = { ...
            seg('static-20', 20, 0, 4), ...
            seg('low-15-fd1', 15, 1, 4), ...
            seg('high-20-fd5', 20, 5, 4), ...
            seg('final-static-20', 20, 0, 4)};
    case 'Stateful 32-frame'
        specs = { ...
            seg('static-20', 20, 0, 4), ...
            seg('low-15-fd1', 15, 1, 4), ...
            seg('low-15-fd2', 15, 2, 4), ...
            seg('high-15-fd5', 15, 5, 4), ...
            seg('static-20', 20, 0, 4), ...
            seg('low-15-fd1', 15, 1, 4), ...
            seg('high-20-fd5', 20, 5, 4), ...
            seg('final-static-20', 20, 0, 4)};
    case 'High-Doppler DSSS scan'
        specs = { ...
            seg('fd3-snr15', 15, 3, 3), ...
            seg('fd3-snr20', 20, 3, 3), ...
            seg('fd5-snr15', 15, 5, 3), ...
            seg('fd5-snr20', 20, 5, 3)};
    otherwise
        error('p6_amc_demo_ui: unknown scenario "%s"', name);
end

timeline = {};
idx = 0;
for s = 1:numel(specs)
    spec = specs{s};
    for k = 1:spec.count
        idx = idx + 1;
        seed = 1 + mod(k - 1, 2);
        timeline{end + 1} = make_q(idx, spec.name, spec.snr, spec.fd, seed); %#ok<AGROW>
    end
end

end

% -------------------------------------------------------------------------
function s = seg(name, snr_db, fd_hz, count)

s = struct('name', name, 'snr', snr_db, 'fd', fd_hz, 'count', count);

end

% -------------------------------------------------------------------------
function q = make_q(frame_idx, label, snr_db, fd_hz, seed)

delay_s = delay_for_fd(fd_hz);
sync_peak = sync_for_state(snr_db, fd_hz);
q = struct();
q.frame_idx = frame_idx;
q.label = label;
q.snr_est_db = snr_db;
q.sync_peak = sync_peak;
q.delay_spread_s = delay_s;
q.doppler_hz = fd_hz;
q.seed = seed;
q.quality_db = snr_db - max(fd_hz - 1, 0) - 0.5 * delay_s * 1e3;
q.ber_est = min(0.5, 0.5 * exp(-max(snr_db, 0) / 3) + ...
    0.005 * max(fd_hz - 1, 0));
q.fer_est = min(1, q.ber_est * 10);
q.valid = true;

end

% -------------------------------------------------------------------------
function delay_s = delay_for_fd(fd_hz)

if fd_hz <= 0
    delay_s = 0.3e-3;
elseif fd_hz < 3
    delay_s = 0.8e-3;
else
    delay_s = 1.3e-3;
end

end

% -------------------------------------------------------------------------
function sync_peak = sync_for_state(snr_db, fd_hz)

sync_peak = 0.92 - 0.025 * max(20 - snr_db, 0) - 0.025 * max(fd_hz - 1, 0);
sync_peak = max(0.30, min(0.95, sync_peak));

end

% -------------------------------------------------------------------------
function policy = make_policy(name, sys)

base = struct('cooldown_frames', 3, 'degrade_hysteresis_db', 2, ...
    'improve_hysteresis_db', 5, 'low_doppler_hz', 0.75, ...
    'high_doppler_hz', 3, 'large_delay_s', 1.0e-3, ...
    'recovery_hysteresis_db', 4);

policy = struct('name', name, 'kind', 'amc', 'opts', base, ...
    'note', 'default');

switch name
    case 'AMC default'
        policy.note = 'legacy';
    case 'AMC profile-aware'
        policy.opts.enable_profile_aware = true;
        policy.note = 'SCFDE pilot profile';
    case 'AMC safe fastDSSS'
        policy.opts.enable_profile_aware = true;
        policy.opts.enable_dsss_fast_profile = true;
        policy.opts.dsss_profile_sps = 3;
        policy.opts.low_doppler_scheme = 'DSSS';
        policy.opts.high_doppler_scheme = 'OTFS';
        policy.dsss_fast_guard_hz = 3;
        policy.note = 'sps3 guarded';
    case 'Fixed OFDM'
        policy.kind = 'fixed';
        policy.candidate = 'OFDM';
        policy.profile = 'OFDM-default';
        policy.note = 'fixed';
    case 'Fixed DSSS-sps3'
        policy.kind = 'fixed';
        policy.candidate = 'DSSS-sps3';
        policy.profile = 'DSSS-sps3';
        policy.params = dsss_fast_params(sys, 3);
        policy.note = 'fixed fast';
    otherwise
        error('p6_amc_demo_ui: unknown policy "%s"', name);
end

end

% -------------------------------------------------------------------------
function decision = apply_ui_profile_guard(decision, q, policy)

if isfield(policy, 'dsss_fast_guard_hz') && ...
        strcmp(decision.selected_scheme, 'DSSS') && ...
        strncmp(decision.selected_profile, 'DSSS-sps', 8) && ...
        abs(q.doppler_hz) >= policy.dsss_fast_guard_hz
    decision.selected_profile = 'DSSS-default';
    decision.profile_params = struct();
    decision.profile_reason = 'ui_high_doppler_fast_dsss_guard';
    decision.profile_throughput_ratio = 1.0;
end

end

% -------------------------------------------------------------------------
function params = dsss_fast_params(sys, sps)

rolloff = sys.dsss.rolloff;
chip_rate = sys.fs / sps;
params = struct('dsss', struct('sps', sps, 'rolloff', rolloff, ...
    'chip_rate', chip_rate, 'total_bw', chip_rate * (1 + rolloff)));

end

% -------------------------------------------------------------------------
function candidate = decision_to_candidate(scheme, profile)

if strcmp(scheme, 'SC-FDE')
    if strncmp(profile, 'SC-FDE-pilot', 12)
        candidate = profile;
    else
        candidate = 'SC-FDE-legacy';
    end
elseif strcmp(scheme, 'DSSS') && strncmp(profile, 'DSSS-sps', 8)
    candidate = profile;
else
    candidate = scheme;
end

end

% -------------------------------------------------------------------------
function m = metric_for_candidate(grid, q, candidate, profile, artifacts)

candidate_for_grid = candidate;
fast_dsss = strcmp(candidate, 'DSSS-sps3') || strcmp(profile, 'DSSS-sps3');
if fast_dsss
    candidate_for_grid = 'DSSS';
end

idx = false(height(grid), 1);
if height(grid) > 0
    cands = table_text_col(grid, 'candidate');
    idx = strcmp(cands, candidate_for_grid) & ...
        abs(grid.snr_db - q.snr_est_db) < 1e-9 & ...
        abs(grid.fd_hz - q.doppler_hz) < 1e-9 & ...
        grid.seed == q.seed;
end

if any(idx)
    row = grid(find(idx, 1, 'first'), :);
    m.ber = row.ber;
    m.goodput = row.goodput;
    m.utility = row.utility;
else
    m = fallback_metric(candidate_for_grid, q);
end

if fast_dsss
    ratio = 102.905379753902 / 86.2469117316763;
    m.goodput = min(1.2, m.goodput * ratio);
    m.utility = max(0, m.goodput * (1 - 2 * min(m.ber, 0.5)));
    if abs(q.doppler_hz) >= 3 && height(artifacts.dsss_high) > 0
        m.ber = dsss_fast_high_ber(artifacts.dsss_high, q);
        m.utility = max(0, m.goodput * (1 - 2 * min(m.ber, 0.5)));
    end
end

end

% -------------------------------------------------------------------------
function ber = dsss_fast_high_ber(tbl, q)

profiles = table_text_col(tbl, 'profile');
idx = strcmp(profiles, 'DSSS-sps3') & ...
    abs(tbl.fd_hz - q.doppler_hz) < 1e-9 & ...
    abs(tbl.snr_db - q.snr_est_db) < 1e-9;
if any(idx)
    row = tbl(find(idx, 1, 'first'), :);
    ber = min(0.5, 1 - row.success_rate);
else
    ber = 0.35;
end

end

% -------------------------------------------------------------------------
function m = fallback_metric(candidate, q)

switch candidate
    case 'OFDM'
        eff = 1.00;
    case 'OTFS'
        eff = 0.72;
    case {'DSSS', 'DSSS-sps3'}
        eff = 0.32;
    case {'SC-FDE-legacy', 'SC-FDE'}
        eff = 0.78;
    case 'SC-FDE-pilot128'
        eff = 0.39;
    otherwise
        eff = 0.18;
end
ber = min(0.5, 0.5 * exp(-max(q.snr_est_db, 0) / 3) + ...
    0.05 * max(q.doppler_hz - 2, 0));
m.ber = ber;
m.goodput = eff * max(0, 1 - ber);
m.utility = max(0, m.goodput * (1 - 2 * min(ber, 0.5)));

end

% -------------------------------------------------------------------------
function artifacts = load_artifacts(tests_dir)

artifacts = struct();
artifacts.profile_grid = read_table_if_exists(fullfile(tests_dir, ...
    'p6_amc_profile_multisnr_grid.csv'));
artifacts.timeline_summary = read_table_if_exists(fullfile(tests_dir, ...
    'p6_amc_profile_timeline_summary.csv'));
artifacts.business_summary = read_table_if_exists(fullfile(tests_dir, ...
    'p6_business_frame_candidate_summary.csv'));
artifacts.dsss_rate = read_table_if_exists(fullfile(tests_dir, ...
    'p6_dsss_rate_profiles.csv'));
artifacts.dsss_high = read_table_if_exists(fullfile(tests_dir, ...
    'p6_dsss_fast_high_doppler_summary.csv'));
artifacts.alpha_refine_raw = read_table_if_exists(fullfile(tests_dir, ...
    'p6_ui_phy_alpha_refine_raw.csv'));

end

% -------------------------------------------------------------------------
function tbl = read_table_if_exists(path)

if exist(path, 'file') == 2
    import_opts = detectImportOptions(path, 'FileType', 'text', ...
        'Delimiter', ',', 'TextType', 'char', ...
        'VariableNamingRule', 'preserve');
    tbl = readtable(path, import_opts);
else
    tbl = table();
end

end

% -------------------------------------------------------------------------
function tbl = make_artifact_table(artifacts)

name = {};
metric = {};
value = {};

if height(artifacts.timeline_summary) > 0
    pol = table_text_col(artifacts.timeline_summary, 'policy');
    for k = 1:height(artifacts.timeline_summary)
        name{end + 1, 1} = pol{k}; %#ok<AGROW>
        metric{end + 1, 1} = 'timeline utility/BER/outage'; %#ok<AGROW>
        value{end + 1, 1} = sprintf('%.3f / %.3g / %d', ...
            artifacts.timeline_summary.mean_utility(k), ...
            artifacts.timeline_summary.mean_ber(k), ...
            artifacts.timeline_summary.outage_frames(k)); %#ok<AGROW>
    end
end

if height(artifacts.business_summary) > 0
    pol = table_text_col(artifacts.business_summary, 'policy');
    for k = 1:height(artifacts.business_summary)
        name{end + 1, 1} = pol{k}; %#ok<AGROW>
        metric{end + 1, 1} = 'business ok/capacity'; %#ok<AGROW>
        value{end + 1, 1} = sprintf('%d/%d, %.2f bps', ...
            artifacts.business_summary.ok_frames(k), ...
            artifacts.business_summary.total_frames(k), ...
            artifacts.business_summary.capacity_bps(k)); %#ok<AGROW>
    end
end

if height(artifacts.dsss_rate) > 0
    prof = table_text_col(artifacts.dsss_rate, 'profile');
    for k = 1:height(artifacts.dsss_rate)
        name{end + 1, 1} = prof{k}; %#ok<AGROW>
        metric{end + 1, 1} = 'full-frame DSSS rate'; %#ok<AGROW>
        value{end + 1, 1} = sprintf('%.2f bps, decoded=%d', ...
            artifacts.dsss_rate.capacity_bps(k), ...
            artifacts.dsss_rate.decoded_ok(k)); %#ok<AGROW>
    end
end

if height(artifacts.dsss_high) > 0
    profs = unique(table_text_col(artifacts.dsss_high, 'profile'), 'stable');
    for p = 1:numel(profs)
        idx = strcmp(table_text_col(artifacts.dsss_high, 'profile'), profs{p});
        ok = sum(artifacts.dsss_high.ok_frames(idx));
        total = sum(artifacts.dsss_high.total_frames(idx));
        payload_fail = sum(artifacts.dsss_high.payload_fail(idx));
        header_fail = sum(artifacts.dsss_high.header_fail(idx));
        name{end + 1, 1} = profs{p}; %#ok<AGROW>
        metric{end + 1, 1} = 'high-Doppler success/fail'; %#ok<AGROW>
        value{end + 1, 1} = sprintf('%d/%d, header=%d payload=%d', ...
            ok, total, header_fail, payload_fail); %#ok<AGROW>
    end
end

if height(artifacts.alpha_refine_raw) > 0
    schemes = unique(table_text_col(artifacts.alpha_refine_raw, 'scheme'), 'stable');
    modes = unique(table_text_col(artifacts.alpha_refine_raw, 'comp_mode'), 'stable');
    ber_pct = 100 * table_numeric_col(artifacts.alpha_refine_raw, 'ber');
    sync_found = table_numeric_col(artifacts.alpha_refine_raw, 'sync_found');
    decode_ok = table_numeric_col(artifacts.alpha_refine_raw, 'decode_ok');
    for s = 1:numel(schemes)
        for m = 1:numel(modes)
            idx = strcmp(table_text_col(artifacts.alpha_refine_raw, 'scheme'), schemes{s}) & ...
                strcmp(table_text_col(artifacts.alpha_refine_raw, 'comp_mode'), modes{m});
            if ~any(idx)
                continue;
            end
            name{end + 1, 1} = sprintf('%s %s', schemes{s}, ...
                alpha_mode_display(modes{m})); %#ok<AGROW>
            metric{end + 1, 1} = 'UI alpha avg/max BER'; %#ok<AGROW>
            value{end + 1, 1} = sprintf('%.3g%% / %.3g%%, n=%d, fail=%d/%d, oracle=no', ...
                mean_omitnan(ber_pct(idx)), max_omitnan(ber_pct(idx)), sum(idx), ...
                sum(sync_found(idx) == 0), sum(decode_ok(idx) == 0)); %#ok<AGROW>
        end
    end
end

if isempty(name)
    name = {'No artifacts'};
    metric = {'Run P6 tests'};
    value = {'No CSV files found'};
end

tbl = table(name, metric, value);

end

% -------------------------------------------------------------------------
function plot_detail(ax_mode, ax_metric, detail)

cla(ax_mode);
cla(ax_metric);
style_uiaxes(ax_mode);
style_uiaxes(ax_metric);

frames = detail.frame;
selected = table_text_col(detail, 'selected');
ids = zeros(height(detail), 1);
labels = unique(selected, 'stable');
for k = 1:numel(labels)
    ids(strcmp(selected, labels{k})) = k;
end
stairs(ax_mode, frames, ids, 'LineWidth', 2.0, 'Color', [0.30 0.72 0.95]);
ylim(ax_mode, [0.5, max(1.5, numel(labels) + 0.5)]);
yticks(ax_mode, 1:numel(labels));
yticklabels(ax_mode, labels);
xlabel(ax_mode, 'Frame');
ylabel(ax_mode, 'Mode/profile');
grid(ax_mode, 'on');
title(ax_mode, 'Selected mode/profile timeline');

yyaxis(ax_metric, 'left');
semilogy(ax_metric, frames, max(detail.ber, 1e-5), '-o', ...
    'LineWidth', 1.5, 'Color', [1.00 0.53 0.35]);
ylabel(ax_metric, 'BER');
ylim(ax_metric, [1e-5, 1]);

yyaxis(ax_metric, 'right');
plot(ax_metric, frames, detail.utility, '-s', ...
    'LineWidth', 1.5, 'Color', [0.45 0.88 0.58]);
ylabel(ax_metric, 'Utility');
ylim(ax_metric, [0, 1.05]);
xlabel(ax_metric, 'Frame');
grid(ax_metric, 'on');
title(ax_metric, 'BER and utility preview');

end

% -------------------------------------------------------------------------
function style_uiaxes(ax)

ax.Color = [0.10 0.13 0.16];
ax.XColor = [0.78 0.84 0.89];
ax.YColor = [0.78 0.84 0.89];
ax.GridColor = [0.30 0.37 0.43];
ax.MinorGridColor = [0.18 0.24 0.29];
ax.FontName = 'Consolas';

end

% -------------------------------------------------------------------------
function c = table_text_col(tbl, name)

var_name = find_table_var(tbl, name);
v = tbl.(var_name);
if isstring(v)
    c = cellstr(v);
elseif iscell(v)
    c = v;
elseif iscategorical(v)
    c = cellstr(v);
else
    c = cellstr(string(v));
end

end

% -------------------------------------------------------------------------
function c = table_numeric_col(tbl, name)

var_name = find_table_var(tbl, name);
v = tbl.(var_name);
if isnumeric(v) || islogical(v)
    c = double(v);
else
    c = str2double(string(v));
end

end

% -------------------------------------------------------------------------
function var_name = find_table_var(tbl, name)

vars = tbl.Properties.VariableNames;
idx = strcmp(vars, name);
if ~any(idx)
    idx = strcmpi(vars, name);
end
if ~any(idx)
    clean_vars = regexprep(vars, '^\xEF\xBB\xBF', '');
    idx = strcmp(clean_vars, name) | strcmpi(clean_vars, name);
end
if ~any(idx)
    error('p6_amc_demo_ui: missing table variable "%s"', name);
end
var_name = vars{find(idx, 1, 'first')};

end

% -------------------------------------------------------------------------
function label = alpha_mode_display(mode)

if strcmp(mode, 'ui_est')
    label = 'ui-est';
elseif strcmp(mode, 'quality_search')
    label = 'quality-search';
else
    label = mode;
end

end

% -------------------------------------------------------------------------
function n = count_switches(values)

n = 0;
for k = 2:numel(values)
    if ~strcmp(values{k}, values{k - 1})
        n = n + 1;
    end
end

end

% -------------------------------------------------------------------------
function m = max_omitnan(x)

x = x(isfinite(x));
if isempty(x)
    m = NaN;
else
    m = max(x);
end

end

% -------------------------------------------------------------------------
function m = mean_omitnan(x)

x = x(isfinite(x));
if isempty(x)
    m = NaN;
else
    m = mean(x);
end

end

% -------------------------------------------------------------------------
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname) && ~isempty(s.(fname))
    v = s.(fname);
else
    v = default;
end

end
