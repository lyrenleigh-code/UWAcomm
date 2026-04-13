%% analyze_otfs_ambiguity.m — OTFS脉冲模糊度函数分析
% Phase 1: 4种脉冲的2D模糊度函数对比
% 用法: cd到本目录后直接 run('analyze_otfs_ambiguity.m')

clc; close all;
fprintf('========================================\n');
fprintf('  OTFS 脉冲模糊度函数分析\n');
fprintf('========================================\n\n');

%% 参数
M = 32;          % 子块长度（与端到端一致）
fs = 48000;      % 采样率
N_tau = 63;      % 延迟维显示点数（2M-1=63）
N_nu = 256;      % 多普勒维FFT点数（8*M=256, 零填充提升分辨率）

% 候选脉冲
pulse_types = {'rect', 'tukey', 'rrc', 'hann', 'gaussian'};
pulse_labels = {'矩形', 'Tukey(0.3)', 'RRC(0.3)', 'Hann', '高斯'};
rolloffs = [0, 0.3, 0.3, 0, 0];
BTs = [0, 0, 0, 0, 0.3];

%% 逐脉冲分析
n_pulse = length(pulse_types);
all_metrics = cell(1, n_pulse);
all_chi = cell(1, n_pulse);
all_g = cell(1, n_pulse);

fprintf('--- 脉冲波形与模糊度指标 ---\n\n');
fprintf('  %-12s | %10s | %10s | %10s | %10s\n', ...
    '脉冲', 'tau_3dB(us)', 'nu_3dB(Hz)', 'PSL_tau(dB)', 'PSL_nu(dB)');
fprintf('  %s\n', repmat('-', 1, 58));

for pi = 1:n_pulse
    p_type = pulse_types{pi};
    p_params = struct();
    if rolloffs(pi) > 0, p_params.rolloff = rolloffs(pi); end
    if BTs(pi) > 0, p_params.BT = BTs(pi); end

    % 生成脉冲
    [g, g_info] = otfs_pulse(M, p_type, p_params);
    all_g{pi} = g;

    % 计算模糊度函数
    [chi, tau_ax, nu_ax, met] = otfs_ambiguity(g, fs, N_tau, N_nu);
    all_chi{pi} = chi;
    all_metrics{pi} = met;

    fprintf('  %-12s | %10.1f | %10.1f | %10.1f | %10.1f\n', ...
        pulse_labels{pi}, ...
        met.mainlobe_tau_3dB * 1e6, ...
        met.mainlobe_nu_3dB, ...
        met.peak_sidelobe_tau, ...
        met.peak_sidelobe_nu);
end

%% 不同rolloff的RRC对比
fprintf('\n--- Tukey窗 rolloff扫描 ---\n\n');
fprintf('  %-10s | %10s | %10s | %10s | %10s\n', ...
    'rolloff', 'tau_3dB(us)', 'nu_3dB(Hz)', 'PSL_tau(dB)', 'PSL_nu(dB)');
fprintf('  %s\n', repmat('-', 1, 56));

rolloff_sweep = [0.1, 0.2, 0.3, 0.5, 0.7, 1.0];
for ri = 1:length(rolloff_sweep)
    rp = struct('rolloff', rolloff_sweep(ri));
    [g_r, ~] = otfs_pulse(M, 'tukey', rp);
    [~, ~, ~, met_r] = otfs_ambiguity(g_r, fs, N_tau, N_nu);
    fprintf('  %-10.1f | %10.1f | %10.1f | %10.1f | %10.1f\n', ...
        rolloff_sweep(ri), ...
        met_r.mainlobe_tau_3dB * 1e6, ...
        met_r.mainlobe_nu_3dB, ...
        met_r.peak_sidelobe_tau, ...
        met_r.peak_sidelobe_nu);
end

%% 可视化
try
    % Figure 1: 脉冲波形 + 频谱
    figure('Name', '脉冲波形与频谱', 'NumberTitle', 'off', 'Position', [50 50 1200 400]);
    colors = {'b', 'r', 'g', 'm', 'c'};
    t_ax = (0:M-1) / fs * 1e3;  % ms
    f_ax = (-M/2:M/2-1) * fs / M / 1e3;  % kHz

    subplot(1,2,1);
    for pi = 1:n_pulse
        plot(t_ax, abs(all_g{pi}), colors{pi}, 'LineWidth', 1.2); hold on;
    end
    xlabel('时间 (ms)'); ylabel('|g(t)|');
    title('脉冲波形'); legend(pulse_labels); grid on;

    subplot(1,2,2);
    for pi = 1:n_pulse
        G_f = fftshift(abs(fft(all_g{pi}))) / sqrt(M);
        plot(f_ax, 20*log10(max(G_f, 1e-6)), colors{pi}, 'LineWidth', 1.2); hold on;
    end
    xlabel('频率 (kHz)'); ylabel('|G(f)| (dB)');
    title('脉冲频谱'); legend(pulse_labels); grid on;
    ylim([-40 5]);

    % Figure 2: 2D 模糊度函数等高线
    figure('Name', '2D模糊度函数', 'NumberTitle', 'off', 'Position', [50 500 1400 900]);
    [~, tau_ax_plot, nu_ax_plot, ~] = otfs_ambiguity(all_g{1}, fs, N_tau, N_nu);
    tau_ax_us = tau_ax_plot * 1e6;  % us

    n_rows = ceil(n_pulse / 3);
    for pi = 1:n_pulse
        subplot(n_rows, 3, pi);
        chi_db = 20*log10(max(all_chi{pi}, 1e-6));
        imagesc(tau_ax_us, nu_ax_plot, chi_db);
        colorbar; caxis([-40 0]);
        xlabel('延迟 (us)'); ylabel('多普勒 (Hz)');
        title(sprintf('%s', pulse_labels{pi}));
        set(gca, 'YDir', 'normal');
    end
    colormap(jet);

    % Figure 3: 切面对比
    figure('Name', '模糊度切面对比', 'NumberTitle', 'off', 'Position', [50 100 1200 400]);

    % 零多普勒切面
    subplot(1,2,1);
    [~, nu0] = min(abs(nu_ax_plot));
    for pi = 1:n_pulse
        cut = 20*log10(max(all_chi{pi}(nu0, :), 1e-6));
        plot(tau_ax_us, cut, colors{pi}, 'LineWidth', 1.2); hold on;
    end
    xlabel('延迟 (us)'); ylabel('|chi| (dB)');
    title('零多普勒切面 chi(tau, 0)'); legend(pulse_labels); grid on;
    ylim([-40 0]);

    % 零延迟切面
    subplot(1,2,2);
    [~, tau0] = min(abs(tau_ax_plot));
    for pi = 1:n_pulse
        cut = 20*log10(max(all_chi{pi}(:, tau0), 1e-6));
        plot(nu_ax_plot, cut, colors{pi}, 'LineWidth', 1.2); hold on;
    end
    xlabel('多普勒 (Hz)'); ylabel('|chi| (dB)');
    title('零延迟切面 chi(0, nu)'); legend(pulse_labels); grid on;
    ylim([-40 0]);

    fprintf('\n可视化完成 (3张图)\n');
catch e
    fprintf('\n可视化失败: %s\n', e.message);
end

%% 保存结果
result_file = fullfile(fileparts(mfilename('fullpath')), 'analyze_otfs_ambiguity_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'OTFS Ambiguity Function Analysis (M=%d, fs=%d)\n\n', M, fs);
for pi = 1:n_pulse
    m = all_metrics{pi};
    fprintf(fid, '%s: tau_3dB=%.1fus, nu_3dB=%.1fHz, PSL_tau=%.1fdB, PSL_nu=%.1fdB\n', ...
        pulse_labels{pi}, m.mainlobe_tau_3dB*1e6, m.mainlobe_nu_3dB, ...
        m.peak_sidelobe_tau, m.peak_sidelobe_nu);
end
fclose(fid);
fprintf('\n结果已保存: %s\n', result_file);
