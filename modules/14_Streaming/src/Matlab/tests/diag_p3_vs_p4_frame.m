function diag_p3_vs_p4_frame()
% DIAG_P3_VS_P4_FRAME  复现 on_transmit 信道段：P3 原算法 vs P4 V1.1 样本级对比
%
% 在 constant α（tv.enable=false）条件下，两条路径应产生「几乎一致」的 frame_ch。
% 若差异大 → 集成层还有 bug；若差异小（数值误差） → 问题在 RX decode。
%
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm\modules\14_Streaming\src\Matlab\tests');
%   clear functions; clear all;
%   diag_p3_vs_p4_frame
%
% 输出：
%   diag_p3_vs_p4_frame_results.txt
%   diag_p3_vs_p4_frame.png（时域+谱对比）

clc; close all;
this_dir       = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
modules_root   = fileparts(fileparts(streaming_root));
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(modules_root, '10_DopplerProc', 'src', 'Matlab'));

diary_file = fullfile(this_dir, 'diag_p3_vs_p4_frame_results.txt');
if exist(diary_file, 'file'), delete(diary_file); end
diary(diary_file);
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('========================================\n');
fprintf('  P3 vs P4 frame_ch 侧对比  %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('========================================\n\n');

sys = sys_params_default();
fs = sys.fs;  fc = sys.fc;

% 用固定 seed 的随机基带信号代表 frame_bb（无须跑 modem_encode）
rng(42);
N = 8192;
frame_bb = (randn(1, N) + 1j*randn(1, N)) / sqrt(2);

alphas = [0, 5e-4, 1e-3, 2e-3];
presets = {'AWGN (无多径)', '6径 标准水声'};

fprintf('固定 seed=42, N=%d 基带高斯复信号，tv.enable=false（常 α）\n', N);
fprintf('fs=%d fc=%d\n\n', fs, fc);

figure('Name', 'P3 vs P4 frame_ch 对比', 'Position', [100 80 1400 800]);
plot_idx = 0;

pass_total = 0; fail_total = 0;

for ip = 1:length(presets)
    preset = presets{ip};
    [h_tap, paths, lbl] = p4_channel_tap('SC-FDE', sys, preset);
    fprintf('--- preset: %s ---\n', lbl);

    for ia = 1:length(alphas)
        alpha = alphas(ia);
        dop_hz = alpha * fc;

        %% P3 原算法（from p3_demo_ui.m on_transmit L856-875 备份）
        frame_p3 = conv(frame_bb, h_tap);
        frame_p3 = frame_p3(1:N);
        if abs(dop_hz) > 1e-3
            frame_p3_r = comp_resample_spline(frame_p3, alpha);
            if length(frame_p3_r) > length(frame_p3)
                frame_p3 = frame_p3_r(1:length(frame_p3));
            else
                frame_p3 = [frame_p3_r, zeros(1, length(frame_p3)-length(frame_p3_r))];
            end
            t_vec = (0:length(frame_p3)-1) / fs;
            frame_p3 = frame_p3 .* exp(1j * 2*pi * dop_hz * t_vec);
        end

        %% P4 V1.2（conv→gen_doppler_channel with single-path，匹配 P3 顺序）
        tv_off = struct('enable', false, 'model', 'constant', 'drift_rate', 0, 'jitter_std', 0);
        frame_mp = conv(frame_bb, h_tap);
        frame_mp = frame_mp(1:length(frame_bb));
        paths_single = struct('delays', 0, 'gains', 1);
        [frame_p4_raw, info_p4] = gen_doppler_channel( ...
            frame_mp, fs, alpha, paths_single, Inf, tv_off, fc);
        L_bb = length(frame_bb);
        if length(frame_p4_raw) >= L_bb
            frame_p4 = frame_p4_raw(1:L_bb);
        else
            frame_p4 = [frame_p4_raw, zeros(1, L_bb - length(frame_p4_raw))];
        end

        %% 比较
        len_match = length(frame_p3) == length(frame_p4);
        rms_err = norm(frame_p3 - frame_p4) / norm(frame_p3);
        rms_db = 20*log10(rms_err + 1e-20);
        pwr_p3 = mean(abs(frame_p3).^2);
        pwr_p4 = mean(abs(frame_p4).^2);
        pwr_ratio_db = 10*log10(pwr_p4 / pwr_p3);

        % 频谱相关系数
        F_p3 = fft(frame_p3);
        F_p4 = fft(frame_p4);
        corr_spec = abs(F_p3(:)' * F_p4(:)) / (norm(F_p3) * norm(F_p4));

        is_ok = rms_err < 0.1 && abs(pwr_ratio_db) < 0.5;
        if is_ok, pass_total = pass_total + 1; else, fail_total = fail_total + 1; end

        fprintf('  α=%.1e (dop=%5.1fHz) | len_match=%d | RMS err=%.3e (%.1fdB) | pwr ratio=%+.2fdB | |<F3,F4>|=%.4f | %s\n', ...
            alpha, dop_hz, len_match, rms_err, rms_db, pwr_ratio_db, corr_spec, ...
            tern(is_ok));

        %% 绘图（只画 6径 标准水声 的 4 个 α）
        if ip == 2
            plot_idx = plot_idx + 1;
            subplot(2, 4, plot_idx);
            n_show = min(1000, N);
            plot(real(frame_p3(1:n_show)), 'b-', 'LineWidth', 0.8); hold on;
            plot(real(frame_p4(1:n_show)), 'r--', 'LineWidth', 0.8);
            title(sprintf('Re α=%.1e RMS=%.2e', alpha, rms_err));
            if plot_idx == 1, legend('P3', 'P4', 'Location', 'best'); end
            grid on;

            subplot(2, 4, plot_idx + 4);
            Nfft = 2048;
            f_ax = (-Nfft/2:Nfft/2-1) / Nfft * fs;
            F3 = fftshift(20*log10(abs(fft(frame_p3, Nfft)) + 1e-9));
            F4 = fftshift(20*log10(abs(fft(frame_p4, Nfft)) + 1e-9));
            plot(f_ax, F3, 'b-', 'LineWidth', 0.8); hold on;
            plot(f_ax, F4, 'r--', 'LineWidth', 0.8);
            title(sprintf('|FFT| α=%.1e', alpha));
            xlim([-3000 3000]); xlabel('Hz'); ylabel('dB');
            grid on;
        end
    end
    fprintf('\n');
end

fig_path = fullfile(this_dir, 'diag_p3_vs_p4_frame.png');
saveas(gcf, fig_path);

fprintf('========================================\n');
fprintf('  侧对比总结\n');
fprintf('========================================\n');
fprintf('PASS: %d   FAIL: %d   (PASS 阈值：RMS<0.1 且 功率差<0.5dB)\n', pass_total, fail_total);
fprintf('频谱图：%s\n', fig_path);
fprintf('日志:   %s\n\n', diary_file);

fprintf('诊断解读：\n');
fprintf('  · 若 α=0 的 RMS 已经 > 0.01，说明 constant 模式下 P4 与 P3 在"无多普勒基线"上就有差异\n');
fprintf('    → 问题在 conv vs gen_doppler_channel 的多径处理，或 t_stretched 起点\n');
fprintf('  · 若 α=0 对齐但 α>0 后 RMS 快速增大，可能是 phase / resample 方向仍有 1-样本级偏移\n');
fprintf('    → 此时 RX 同步 best_off 可能补救，也可能崩\n');
fprintf('  · 若所有 α RMS 都很小（<1e-3）→ P4 生成的信号本身和 P3 基本等价，问题在 RX decode\n');
fprintf('    → 下一步走 "RX 侧 α 估计 / alpha_cp 假设"，本脚本帮不上\n');

end

function s = tern(ok)
    if ok, s = 'PASS'; else, s = 'FAIL'; end
end
