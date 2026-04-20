%% test_bench_common.m — bench_common 工具自测
% 覆盖：bench_grids / bench_channel_profiles / bench_init_row /
%       bench_format_row / bench_append_csv / bench_turbo_iter_log /
%       bench_nmse_tool
% 版本：V1.0.0（2026-04-19）

clc; close all;
addpath(fileparts(mfilename('fullpath')));

pass_count = 0; fail_count = 0;
results = {};

fprintf('\n============================================\n');
fprintf('  bench_common 工具自测\n');
fprintf('============================================\n\n');

%% ===== T1: bench_grids 返回五阶段且规模正确 =====
try
    grids = bench_grids();
    assert(isfield(grids,'A1') && isfield(grids,'A2') && isfield(grids,'A3') && ...
           isfield(grids,'B')  && isfield(grids,'C'), '字段缺失');
    assert(grids.A1.expected_pts == 360, 'A1 规模 = %d（应为 360）', grids.A1.expected_pts);
    assert(grids.A2.expected_pts == 240, 'A2 规模 = %d（应为 240）', grids.A2.expected_pts);
    assert(grids.A3.expected_pts == 288, 'A3 规模 = %d（应为 288）', grids.A3.expected_pts);
    assert(grids.B.expected_pts  == 120, 'B 规模 = %d（应为 120）',  grids.B.expected_pts);
    assert(grids.C.expected_pts  == 270, 'C 规模 = %d（应为 270）',  grids.C.expected_pts);
    pass_count = pass_count + 1; results{end+1} = 'T1 bench_grids 五阶段规模 ✓';
catch ME
    fail_count = fail_count + 1; results{end+1} = sprintf('T1 ✗ %s', ME.message);
end

%% ===== T2: bench_channel_profiles 覆盖 6 种 profile =====
try
    names = {'custom6','exponential','disc-5Hz','hyb-K20','hyb-K10','hyb-K5'};
    base = struct('fs', 48000);
    for k = 1:numel(names)
        p = bench_channel_profiles(names{k}, base);
        assert(isfield(p, 'fs'), 'fs 缺失 for %s', names{k});
    end
    % 未知 profile 应抛错
    try
        bench_channel_profiles('bad-name', base);
        error('应抛错但未抛出');
    catch
        % expected
    end
    pass_count = pass_count + 1; results{end+1} = 'T2 bench_channel_profiles 6 profile ✓';
catch ME
    fail_count = fail_count + 1; results{end+1} = sprintf('T2 ✗ %s', ME.message);
end

%% ===== T3: bench_init_row 固定字段顺序 =====
try
    row = bench_init_row('A1', 'SC-FDE');
    expected = {'timestamp','matlab_ver','stage','scheme','profile', ...
                'fd_hz','doppler_rate','snr_db','seed','ber_coded', ...
                'ber_uncoded','nmse_db','sync_tau_err','frame_detected', ...
                'turbo_final_iter','runtime_s'};
    got = fieldnames(row);
    assert(numel(got) == numel(expected), '字段数 %d vs 预期 %d', numel(got), numel(expected));
    for k = 1:numel(expected)
        assert(strcmp(got{k}, expected{k}), ...
               '字段顺序 %d: %s vs %s', k, got{k}, expected{k});
    end
    assert(strcmp(row.stage,'A1') && strcmp(row.scheme,'SC-FDE'));
    pass_count = pass_count + 1; results{end+1} = 'T3 bench_init_row 字段顺序 ✓';
catch ME
    fail_count = fail_count + 1; results{end+1} = sprintf('T3 ✗ %s', ME.message);
end

%% ===== T4: bench_format_row 处理数值/NaN/字符串/逗号 =====
try
    row = bench_init_row('A1','SC-FDE');
    row.profile = 'custom,6';  % 含逗号测试
    row.fd_hz = 5.0;
    row.snr_db = 10;
    row.ber_coded = 0.012345;
    row.frame_detected = true;
    [hdr, val] = bench_format_row(row);
    assert(contains(hdr, 'fd_hz'));
    assert(contains(val, '"custom,6"'));  % 逗号 → 双引号包裹
    assert(contains(val, 'NaN'));          % 未填字段为 NaN
    assert(contains(val, '0.012345'));
    pass_count = pass_count + 1; results{end+1} = 'T4 bench_format_row 特殊值 ✓';
catch ME
    fail_count = fail_count + 1; results{end+1} = sprintf('T4 ✗ %s', ME.message);
end

%% ===== T5: bench_append_csv 首次写 header + 追加 =====
try
    tmp = [tempname, '.csv'];
    row1 = bench_init_row('A1','SC-FDE');
    row1.profile = 'custom6'; row1.fd_hz = 0; row1.snr_db = 10; row1.ber_coded = 0;
    bench_append_csv(tmp, row1);
    row2 = bench_init_row('A1','OFDM');
    row2.profile = 'custom6'; row2.fd_hz = 5; row2.snr_db = 10; row2.ber_coded = 0.05;
    bench_append_csv(tmp, row2);

    fid = fopen(tmp, 'r');
    content = fread(fid, inf, 'uint8=>char').';
    fclose(fid);
    lines = splitlines(strtrim(content));
    assert(numel(lines) == 3, '行数 %d（应为 3：1 header + 2 data）', numel(lines));
    assert(contains(lines{1}, 'scheme'), 'header 缺少列名');
    assert(contains(lines{2}, 'SC-FDE'));
    assert(contains(lines{3}, 'OFDM'));
    delete(tmp);
    pass_count = pass_count + 1; results{end+1} = 'T5 bench_append_csv header+append ✓';
catch ME
    fail_count = fail_count + 1; results{end+1} = sprintf('T5 ✗ %s', ME.message);
end

%% ===== T6: bench_turbo_iter_log 长表写入 =====
try
    tmp = [tempname, '.csv'];
    main = bench_init_row('A1','SC-FDE');
    main.profile = 'custom6'; main.fd_hz = 1; main.snr_db = 10;
    main.seed = 42; main.doppler_rate = 0;
    for it = 1:3
        bench_turbo_iter_log(tmp, main, it, 0.1 / it);
    end
    fid = fopen(tmp, 'r');
    content = fread(fid, inf, 'uint8=>char').';
    fclose(fid);
    lines = splitlines(strtrim(content));
    assert(numel(lines) == 4, '行数 %d（应 1 header + 3 data）', numel(lines));
    assert(contains(lines{1}, 'iter'));
    assert(contains(lines{1}, 'ber_at_iter'));
    delete(tmp);
    pass_count = pass_count + 1; results{end+1} = 'T6 bench_turbo_iter_log 长表 ✓';
catch ME
    fail_count = fail_count + 1; results{end+1} = sprintf('T6 ✗ %s', ME.message);
end

%% ===== T7: bench_nmse_tool 基本语义 =====
try
    % 伪造 3 径 h_true 静态 + 完美 h_est → NMSE = -Inf（但应返回非常负的值）
    N = 1000;
    h_true = zeros(3, N);
    h_true(1,:) = 0.8;
    h_true(2,:) = 0.5 * exp(1j*0.3);
    h_true(3,:) = 0.3 * exp(1j*1.2);
    % 完美 h_est = 中点列
    h_est_perfect = h_true(:, N/2);
    opts = struct('type','time_sparse','delays_samp',[0 10 30]);
    nmse_perfect = bench_nmse_tool(h_est_perfect, h_true, opts);
    assert(nmse_perfect < -100 || nmse_perfect == -Inf, ...
           '完美估计 NMSE = %.2f dB（应 << 0）', nmse_perfect);

    % 全零估计 → NMSE = 10log10(1) = 0
    h_est_zero = zeros(3, 1);
    nmse_zero = bench_nmse_tool(h_est_zero, h_true, opts);
    assert(abs(nmse_zero - 0) < 1e-6, '零估计 NMSE = %.2f dB（应 0）', nmse_zero);

    % 空输入 → NaN
    nmse_empty = bench_nmse_tool([], h_true, opts);
    assert(isnan(nmse_empty));

    pass_count = pass_count + 1; results{end+1} = 'T7 bench_nmse_tool 语义 ✓';
catch ME
    fail_count = fail_count + 1; results{end+1} = sprintf('T7 ✗ %s', ME.message);
end

%% ===== 汇总 =====
fprintf('\n============================================\n');
fprintf('  自测结果: %d 通过 / %d 失败\n', pass_count, fail_count);
fprintf('============================================\n');
for k = 1:numel(results)
    fprintf('  %s\n', results{k});
end
fprintf('\n');

if fail_count > 0
    error('test_bench_common:HasFailures', '有 %d 项失败', fail_count);
end
