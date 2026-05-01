function test_p4_jakes_channel_smoke()
% TEST_P4_JAKES_CHANNEL_SMOKE  P4 Jakes 信道接入冒烟测试
%
% 验证 p4_demo_ui channel 段分发逻辑（spec 2026-04-28-p4-jakes-channel-integration）：
%   C1 'static (恒定)' → gen_doppler_channel 路径可用（α=0 + 多径 conv）
%   C2 'slow (Jakes 慢衰落)' fd=2Hz → gen_uwa_channel 时变多径，h_time(:,1) ≠ h_time(:,end)
%   C3 'fast (Jakes 快衰落)' fd=10Hz → 时变标准差 > C2
%
% 测试范围：直接调底层信道函数（绕过 UI on_transmit），不组装物理帧
%
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm-claude\modules\14_Streaming\src\Matlab\tests');
%   clear functions; clear all;
%   diary('test_p4_jakes_channel_smoke_results.txt');
%   run('test_p4_jakes_channel_smoke.m');
%   diary off;
%
% 参考：specs/active/2026-04-28-p4-jakes-channel-integration.md

%% 0. 路径注册
this_dir       = fileparts(mfilename('fullpath'));      % .../14_Streaming/src/Matlab/tests
streaming_root = fileparts(this_dir);                    % .../14_Streaming/src/Matlab
mod14_root     = fileparts(fileparts(streaming_root));   % .../modules/14_Streaming
modules_root   = fileparts(mod14_root);                  % .../modules
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(modules_root, '10_DopplerProc',   'src', 'Matlab'));
addpath(fullfile(modules_root, '13_SourceCode',    'src', 'Matlab', 'common'));

pass = 0; fail = 0;
fprintf('========== P4 Jakes 信道接入冒烟测试 ==========\n');

%% 通用 fixture
fs    = 48000;
fc    = 12000;
N_tx  = 8192;
% 简化 6 径：[0, 2, 5, 10, 18, 28] 符号 × sps=4 = [0, 8, 20, 40, 72, 112] 样本
delays_samp = [0, 8, 20, 40, 72, 112];
delays_s    = delays_samp / fs;
gains       = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
               0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains       = gains / sqrt(sum(abs(gains).^2));   % 单位功率归一
paths       = struct('delays', delays_s, 'gains', gains);

% 简化 frame_bb：随机 QPSK 符号上采样
rng(42);
N_sym = N_tx / 4;
sym = (2*randi([0 1], 1, N_sym) - 1) + 1j*(2*randi([0 1], 1, N_sym) - 1);
sym = sym / sqrt(2);
frame_bb = zeros(1, N_tx);
frame_bb(1:4:end) = sym;
frame_bb = filter(ones(1,4), 1, frame_bb);   % 简化矩形脉冲
frame_bb = frame_bb / sqrt(mean(abs(frame_bb).^2));   % 归一

%% C1 — 'static (恒定)' fd=0 路径（gen_doppler_channel）
try
    fading_str = 'static (恒定)';
    assert(startsWith(fading_str, 'static'), 'C1: dispatch precondition');

    % 模拟 UI static 路径调用
    h_tap = zeros(1, max(delays_samp) + 1);
    for p = 1:length(delays_samp)
        h_tap(delays_samp(p)+1) = gains(p);
    end
    frame_mp = conv(frame_bb, h_tap);
    frame_mp = frame_mp(1:N_tx);
    tv = struct('enable', false, 'model', 'constant', ...
                'drift_rate', 0, 'jitter_std', 0);
    paths_single = struct('delays', 0, 'gains', 1);
    [frame_ch_raw, ch_info] = gen_doppler_channel( ...
        frame_mp, fs, 0, paths_single, Inf, tv, fc);
    L_bb = N_tx;
    if length(frame_ch_raw) >= L_bb
        frame_ch_c1 = frame_ch_raw(1:L_bb);
    else
        frame_ch_c1 = [frame_ch_raw, zeros(1, L_bb - length(frame_ch_raw))];
    end

    assert(length(frame_ch_c1) == L_bb, 'C1: frame_ch 长度 %d ≠ %d', length(frame_ch_c1), L_bb);
    assert(any(abs(frame_ch_c1) > 0), 'C1: frame_ch 全零');
    assert(isfield(ch_info, 'alpha_true'), 'C1: ch_info.alpha_true missing');

    fprintf('[PASS] C1 static fd=0 → gen_doppler_channel（输出长度 %d，alpha_true const）\n', L_bb);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C1 static: %s\n', ME.message);
    fail = fail + 1;
end

%% C2 — 'slow (Jakes 慢衰落)' fd=2Hz 路径（gen_uwa_channel）
try
    fading_str = 'slow (Jakes 慢衰落)';
    assert(~startsWith(fading_str, 'static'), 'C2: dispatch precondition');

    fd_jakes = 2;
    ch_params = struct( ...
        'fs',            fs, ...
        'num_paths',     length(paths.delays), ...
        'delay_profile', 'custom', ...
        'delays_s',      paths.delays, ...
        'gains',         paths.gains, ...
        'doppler_rate',  0, ...           % 纯 Jakes 测试，无 bulk α
        'fading_type',   'slow', ...
        'fading_fd_hz',  fd_jakes, ...
        'snr_db',        Inf, ...
        'seed',          1234 );
    [frame_ch_c2, ch_info_c2] = gen_uwa_channel(frame_bb, ch_params);

    assert(any(abs(frame_ch_c2) > 0), 'C2: frame_ch 全零');
    assert(isfield(ch_info_c2, 'h_time'), 'C2: ch_info.h_time missing（Jakes 时变信道矩阵）');
    h_time = ch_info_c2.h_time;
    assert(size(h_time, 1) == length(paths.delays), ...
        'C2: h_time 行数 %d ≠ 多径数 %d', size(h_time, 1), length(paths.delays));
    % 时变性：第一列与最后一列应有差异
    diff_norm = norm(h_time(:,1) - h_time(:,end)) / norm(h_time(:,1));
    assert(diff_norm > 1e-3, 'C2: h_time 列差异 %.2e 太小（应 > 1e-3 表征 Jakes 时变）', diff_norm);
    std_c2 = mean(std(h_time, 0, 2) ./ (mean(abs(h_time), 2) + eps));

    fprintf('[PASS] C2 slow Jakes fd=2Hz → gen_uwa_channel（h_time %d×%d，列差 %.3e，时变 std/mean=%.3f）\n', ...
        size(h_time,1), size(h_time,2), diff_norm, std_c2);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C2 slow Jakes: %s\n', ME.message);
    fail = fail + 1;
end

%% C3 — 'fast (Jakes 快衰落)' fd=10Hz 路径
try
    fd_jakes = 10;
    ch_params = struct( ...
        'fs',            fs, ...
        'num_paths',     length(paths.delays), ...
        'delay_profile', 'custom', ...
        'delays_s',      paths.delays, ...
        'gains',         paths.gains, ...
        'doppler_rate',  0, ...
        'fading_type',   'fast', ...
        'fading_fd_hz',  fd_jakes, ...
        'snr_db',        Inf, ...
        'seed',          1234 );
    [frame_ch_c3, ch_info_c3] = gen_uwa_channel(frame_bb, ch_params);

    assert(any(abs(frame_ch_c3) > 0), 'C3: frame_ch 全零');
    h_time = ch_info_c3.h_time;
    diff_norm_c3 = norm(h_time(:,1) - h_time(:,end)) / norm(h_time(:,1));
    std_c3 = mean(std(h_time, 0, 2) ./ (mean(abs(h_time), 2) + eps));
    % fast (fd=10) 时变性应 > slow (fd=2)
    if exist('std_c2', 'var')
        assert(std_c3 > std_c2 * 1.2, ...
            'C3: fast Jakes 时变 std/mean=%.3f 应明显大于 slow %.3f', std_c3, std_c2);
        fprintf('[PASS] C3 fast Jakes fd=10Hz → 时变 std/mean=%.3f > slow %.3f（C2 比对 1.2× 阈值）\n', ...
            std_c3, std_c2);
    else
        fprintf('[PASS] C3 fast Jakes fd=10Hz → 时变 std/mean=%.3f（C2 失败无法对比）\n', std_c3);
    end
    pass = pass + 1;
catch ME
    fprintf('[FAIL] C3 fast Jakes: %s\n', ME.message);
    fail = fail + 1;
end

%% 汇总
fprintf('\n========== 总结 ==========\n');
fprintf('PASS: %d / %d\n', pass, pass + fail);
fprintf('FAIL: %d\n', fail);
if fail == 0
    fprintf('[ALL PASS] Jakes 信道接入底层调用通过\n');
    fprintf('下一步：UI 实测 SC-FDE static SNR=15 + slow Jakes fd=2Hz，看 BER\n');
else
    fprintf('[HAS FAIL] %d 个 case 失败，需排查\n', fail);
end
end
