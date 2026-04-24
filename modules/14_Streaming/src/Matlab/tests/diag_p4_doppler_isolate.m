function diag_p4_doppler_isolate()
% DIAG_P4_DOPPLER_ISOLATE  隔离诊断：只跑 TX→channel，不经 RX，看频谱峰位置
%
% 目的：验证 gen_doppler_channel V1.1 在 baseband 下的相位/频谱行为是否物理正确。
%       若此脚本判定 CHANNEL 对了 BER 仍崩，则问题在 RX 链路（非本修复范围）。
%
% 测试点（对应 4-20 α 诊断基线）：
%   α=0 / 5e-4 / 1e-3 / 2e-3
%   → 期望基带频谱能量峰在 fc·α = 0 / 6 / 12 / 24 Hz
%
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm\modules\14_Streaming\src\Matlab\tests');
%   clear functions; clear all;
%   diag_p4_doppler_isolate
%
% 输出：
%   diag_p4_doppler_isolate_results.txt
%   4 张频谱图（对应 4 个 α）
%   PASS/FAIL 判定：实测峰频率与 fc·α 偏差 < 0.5 Hz

clc; close all;
this_dir       = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
modules_root   = fileparts(fileparts(streaming_root));
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(modules_root, '10_DopplerProc', 'src', 'Matlab'));

diary_file = fullfile(this_dir, 'diag_p4_doppler_isolate_results.txt');
if exist(diary_file, 'file'), delete(diary_file); end
diary(diary_file);
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('========================================\n');
fprintf('  P4 Doppler 隔离诊断  %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('========================================\n\n');

sys = sys_params_default();
fs = sys.fs;  fc = sys.fc;
fprintf('系统：fs=%d Hz, fc=%d Hz, fs/fc=%g\n', fs, fc, fs/fc);

% 诊断 A：MATLAB 函数缓存识别
fprintf('\n[A] 检查 gen_doppler_channel 版本\n');
fprintf('    which -all:\n');
which_list = which('gen_doppler_channel', '-all');
if ischar(which_list), which_list = {which_list}; end
for k = 1:length(which_list)
    fprintf('      %d) %s\n', k, which_list{k});
end
if length(which_list) > 1
    fprintf(2, '    ⚠ 多个副本：优先级以第 1 个为准，可能掩盖 V1.1 修复！\n');
end
% 看文件是否含 V1.1 关键词
gen_path = which_list{1};
gen_src = fileread(gen_path);
is_v11 = contains(gen_src, 'V1.1') && contains(gen_src, 'fc = []');
fprintf('    V1.1 关键字在被调用文件中：%s\n', tern(is_v11));

% 诊断 B：单音频谱（避免 RX 干扰）
fprintf('\n[B] 单音频谱测试（基带 DC 输入，观测相位旋转频率）\n');

alphas = [0, 5e-4, 1e-3, 2e-3];
N = 16384;
s_dc = ones(1, N) + 1j*zeros(1, N);  % 基带 DC，输出频谱 = 纯相位旋转
paths0 = struct('delays', 0, 'gains', 1);
tv_off = struct('enable', false);

pass_b = 0; fail_b = 0;
figure('Name', 'P4 Doppler Isolation (DC baseband → FFT)', 'Position', [100 100 1200 700]);
for k = 1:length(alphas)
    a = alphas(k);
    [r_v11, ~] = gen_doppler_channel(s_dc, fs, a, paths0, Inf, tv_off, fc);
    warning('off', 'gen_doppler_channel:NoFc');
    [r_v10, ~] = gen_doppler_channel(s_dc, fs, a, paths0, Inf, tv_off);      % 旧路径
    warning('on', 'gen_doppler_channel:NoFc');

    % FFT 取峰（单边谱，分辨率 fs/N ≈ 2.93 Hz）
    f_axis = (-N/2 : N/2-1) * fs / N;
    F_v11 = fftshift(fft(r_v11(1:N)) / N);
    F_v10 = fftshift(fft(r_v10(1:N)) / N);

    [~, i11] = max(abs(F_v11));  f_peak_v11 = f_axis(i11);
    [~, i10] = max(abs(F_v10));  f_peak_v10 = f_axis(i10);

    f_expect_v11 = fc * a;         % 物理正确
    f_expect_v10 = fs * a;         % V1.0 bug 下的期望
    err_v11 = abs(f_peak_v11 - f_expect_v11);
    err_v10 = abs(f_peak_v10 - f_expect_v10);

    ok = err_v11 < 0.5 * fs/N;  % FFT 分辨率容差
    fprintf('  α=%.1e | V1.1 峰=%+6.2f Hz (期望 %+.2f) | V1.0 峰=%+6.2f Hz (期望 %+.2f) | %s\n', ...
        a, f_peak_v11, f_expect_v11, f_peak_v10, f_expect_v10, tern(ok));
    if ok, pass_b = pass_b + 1; else, fail_b = fail_b + 1; end

    % 绘图
    subplot(2, 2, k);
    plot(f_axis, 20*log10(abs(F_v11)+1e-9), 'b-', 'LineWidth', 1.5); hold on;
    plot(f_axis, 20*log10(abs(F_v10)+1e-9), 'r--', 'LineWidth', 1.0);
    xline(f_expect_v11, 'g:', 'fc·α');
    xline(f_expect_v10, 'r:', 'fs·α');
    xlim([-60 60]);
    xlabel('Hz'); ylabel('|FFT| (dB)');
    title(sprintf('α=%.1e  fc·α=%.1fHz  fs·α=%.1fHz', a, f_expect_v11, f_expect_v10));
    legend('V1.1 (with fc)', 'V1.0 (no fc)', 'Location', 'south');
    grid on;
end
fig_path = fullfile(this_dir, 'diag_p4_doppler_isolate.png');
saveas(gcf, fig_path);
fprintf('\n  频谱图已保存：%s\n', fig_path);

% 诊断 C：t_stretched 起点对齐（α=0 应与 t_orig 完全对齐）
fprintf('\n[C] t_stretched 起点对齐测试（α=0 应无时移）\n');
s_imp = zeros(1, 256); s_imp(1) = 1;    % impulse at n=1
[r_imp, ~] = gen_doppler_channel(s_imp, fs, 0, paths0, Inf, tv_off, fc);
[~, i_peak] = max(abs(r_imp));
fprintf('  α=0 + impulse at n=1 → 输出峰在 n=%d（期望 1）%s\n', ...
    i_peak, tern(i_peak == 1));

% 诊断 D：paths 结构从 p4_channel_tap 往 gen_doppler_channel 的 roundtrip
fprintf('\n[D] p4_channel_tap → paths roundtrip\n');
[h_tap, paths, lbl] = p4_channel_tap('SC-FDE', sys, '6径 标准水声');
fprintf('  preset: %s (%d 径)\n', lbl, length(paths.delays));
fprintf('  delays (秒):  '); fprintf('%.2e ', paths.delays); fprintf('\n');
fprintf('  gains mag:    '); fprintf('%.3f ', abs(paths.gains)); fprintf('\n');
fprintf('  h_tap长度:    %d\n', length(h_tap));
% 验证 delay × fs 能还原 h_tap 的离散位置
delay_samp_recovered = round(paths.delays * fs);
h_tap_recover = zeros(1, max(delay_samp_recovered)+1);
for p = 1:length(delay_samp_recovered)
    h_tap_recover(delay_samp_recovered(p)+1) = h_tap_recover(delay_samp_recovered(p)+1) + paths.gains(p);
end
roundtrip_err = max(abs(h_tap - h_tap_recover));
fprintf('  roundtrip err (max |h_orig - h_recovered|): %.3e %s\n', ...
    roundtrip_err, tern(roundtrip_err < 1e-10));

%% 总结
fprintf('\n========================================\n');
fprintf('  诊断总结\n');
fprintf('========================================\n');
fprintf('  [A] V1.1 关键字在源：%s  (路径 %s)\n', tern(is_v11), gen_path);
fprintf('  [B] 频谱峰定位：%d PASS / %d FAIL (共 %d α)\n', pass_b, fail_b, length(alphas));
fprintf('  [C] α=0 冲激对齐：%s\n', tern(i_peak == 1));
fprintf('  [D] paths roundtrip：%s\n', tern(roundtrip_err < 1e-10));

fprintf('\n解读：\n');
if ~is_v11
    fprintf(2, '  [A] FAIL 说明 MATLAB 可能 cache 了旧版本；跑 `clear functions; rehash` 后重来\n');
end
if fail_b > 0
    fprintf(2, '  [B] FAIL 说明 gen_doppler_channel 相位公式有问题；看 PNG 图，V1.1 蓝线峰应在 fc·α\n');
end
if i_peak ~= 1
    fprintf(2, '  [C] FAIL 说明 t_stretched 对齐仍有 1 样本偏移，可能影响 RX 同步\n');
end
fprintf('\n如 [B] 所有点都 PASS → gen_doppler_channel 本身已对，问题转向 RX decode 链路（modem_decode_scfde / alpha_cp / pipeline 诊断）\n');
fprintf('日志: %s\n', diary_file);

end

function s = tern(ok)
    if ok, s = 'PASS'; else, s = 'FAIL'; end
end
