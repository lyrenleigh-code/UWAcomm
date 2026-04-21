%% test_resample_doppler_error.m
% 功能：量化 comp_resample_spline 在不同 α 下的纯数值误差
% 目的：分离 resample 本身误差 vs estimator 误差 vs pipeline 误差
% 版本：V1.0.0（2026-04-21）
%
% 测试设计：
%   1. 解析合成 y(t) = s((1+α)·t)（无合成误差，与 resample 误差隔离）
%   2. 调用 comp_resample_spline(y, α_oracle, fs) 试图复原 s(t)
%   3. 比较 s_comp vs s_ref 的 NMSE / max_err / 时域误差分布
%
% 三类测试信号：
%   (A) 单频复指数 exp(j·2π·f0·t) — 测纯频率/相位保真
%   (B) LFM chirp exp(j·2π·(f0·t + 0.5·k·t²)) — 测扫频信号、peak 漂移
%   (C) 带限随机基带（QPSK after RRC）— 测实际通信信号
%
% 验证维度：
%   - α 对称性（+α vs -α 是否系统偏差）
%   - fast vs accurate 模式精度差异
%   - 尾部 vs 头部 误差分布（验证"尾部截断"猜想）
%   - 与 CP 精修阈值 2.44e-4 的绝对关系

clear functions; clear; close all; clc;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

% ---- 输出文件 ----
log_file = fullfile(this_dir, 'test_resample_doppler_error_results.txt');
if exist(log_file, 'file'), delete(log_file); end
diary(log_file); diary on;

fprintf('========================================\n');
fprintf('  comp_resample_spline 误差表征 V1.0.0\n');
fprintf('========================================\n\n');

%% ============ 1. 参数 ============
fs    = 48000;          % 采样率（与 SC-FDE 通带一致）
fc    = 12000;          % 载频（仅用于 LFM 合成参数，不做上下变频）
T_sig = 1.0;            % 测试信号时长 1 秒（足够长，避免边界主导）
N     = round(T_sig * fs);  % 48000 样本
t     = (0:N-1) / fs;   % 时间轴（从 0 开始，匹配 comp_resample_spline 约定）

% V2 改动：为 α<0（扩展）场景在 y 合成端留 capture margin，模拟真实 RX 捕获窗口
% 末端多采 |α_max|·N 样本（+500 余量），使 y 实际长度 N_rx > N
alpha_max_abs = max(abs([0, 1e-5, -1e-5, 1e-4, -1e-4, 5e-4, -5e-4, 1e-3, -1e-3, ...
                         3e-3, -3e-3, 1e-2, -1e-2, 3e-2, -3e-2, 5e-2, -5e-2, 7e-2, -7e-2]));
N_rx_margin = ceil(alpha_max_abs * N) + 500;    % ≈ 3860 样本
N_rx = N + N_rx_margin;                          % y 合成长度
t_rx = (0:N_rx-1) / fs;

% α 扫描点：对称布置，覆盖从小 α 到物理极限
alpha_list = [0, ...
              1e-5, -1e-5, ...
              1e-4, -1e-4, ...
              5e-4, -5e-4, ...
              1e-3, -1e-3, ...
              3e-3, -3e-3, ...
              1e-2, -1e-2, ...
              3e-2, -3e-2, ...
              5e-2, -5e-2, ...
              7e-2, -7e-2];

modes = {'fast', 'accurate'};

% CP 精修相位模糊阈值（blk_fft=1024, fc=12000, sym_rate=6000）
cp_thres = 1 / (2 * fc * 1024 / 6000);
fprintf('CP 精修阈值参考：%.3e\n\n', cp_thres);

%% ============ 2. 三类测试信号（长度扩展到 N_rx 覆盖 α<0 尾部） ============
% (A) 单频复指数 f0 = 1000 Hz 基带
f0_tone = 1000;
s_tone  = exp(1j * 2*pi * f0_tone * t_rx);

% (B) LFM chirp（基带）：f(t) = -B/2 + k·t
B_lfm   = 4000;                         % 4 kHz 带宽
k_chirp = B_lfm / T_sig;
s_lfm   = exp(1j * 2*pi * (-B_lfm/2 * t_rx + 0.5 * k_chirp * t_rx.^2));

% (C) 带限随机基带（QPSK 经 RRC，sym_rate=6000, sps=8）
rng(42);
sym_rate = 6000;
sps      = fs / sym_rate;              % 8
Nsym     = ceil(N_rx / sps) + 4;       % 扩展到 N_rx
syms_q   = (2*randi([0 1], 1, Nsym)-1) + 1j*(2*randi([0 1], 1, Nsym)-1);
syms_q   = syms_q / sqrt(2);
% 零阶保持 + lowpass 近似带限
s_rrc    = kron(syms_q, ones(1, sps));
% 简单 FIR lowpass（avoid dependency on comm toolbox）
cutoff   = sym_rate / fs;              % 归一化截止 0.125
h_lp     = fir1(64, cutoff);
s_rrc    = conv(s_rrc, h_lp, 'same');
s_rrc    = s_rrc(1:N_rx);              % 截断到 N_rx
s_rrc    = s_rrc / sqrt(mean(abs(s_rrc).^2));

signals = struct();
signals.tone = struct('ref', s_tone, 'name', '单频 f0=1kHz');
signals.lfm  = struct('ref', s_lfm,  'name', 'LFM chirp B=4kHz');
signals.rrc  = struct('ref', s_rrc,  'name', 'QPSK-RRC sps=8');

%% ============ 3. 解析合成接收信号 y(t) = s((1+α)·t) ============
% 对 (A)(B) 有解析形式；(C) 用高精度插值合成（reference）
% y 长度 = N_rx（模拟真实 RX 捕获窗口：TX 做了 tail_pad / RX 多采样），
% 叠加 V7.1 内部 auto-pad 后 -α 方向应恢复对称

synth_y = @(sig_name, alpha) synth_received(sig_name, alpha, t_rx, f0_tone, B_lfm, k_chirp, T_sig, s_rrc, fs, N_rx);

%% ============ 4. 循环测试 ============
results = struct();
for sig_idx = 1:length(fieldnames(signals))
    sig_fields = fieldnames(signals);
    sig_name = sig_fields{sig_idx};
    sig_info = signals.(sig_name);
    s_ref = sig_info.ref;

    fprintf('\n------- 信号 (%d/3): %s -------\n', sig_idx, sig_info.name);
    fprintf('%-10s | %-8s | %-12s | %-12s | %-12s | %-12s\n', ...
            'α', 'mode', 'NMSE (dB)', 'max|err|', 'head_RMS', 'tail_RMS');
    fprintf('%s\n', repmat('-', 1, 82));

    for m_idx = 1:length(modes)
        mode_str = modes{m_idx};
        nmse_all = nan(1, length(alpha_list));
        maxerr_all = nan(1, length(alpha_list));
        head_rms_all = nan(1, length(alpha_list));
        tail_rms_all = nan(1, length(alpha_list));

        for a_idx = 1:length(alpha_list)
            alpha_true = alpha_list(a_idx);

            % 合成接收信号（y(n) = s((1+α)·n)）
            try
                y_rx = synth_y(sig_name, alpha_true);
            catch ME
                fprintf('%-10.3e | %-8s | 合成失败: %s\n', alpha_true, mode_str, ME.message);
                continue;
            end

            % Oracle α 补偿
            s_comp = comp_resample_spline(y_rx, alpha_true, fs, mode_str);

            % 取有效比较区间（避开边界填充效应）
            edge_pad = 200;
            if length(s_comp) < 2*edge_pad + 100
                fprintf('%-10.3e | %-8s | 信号过短\n', alpha_true, mode_str);
                continue;
            end
            cmp_range = (edge_pad+1) : (min([length(s_comp), length(s_ref), N]) - edge_pad);

            err = s_comp(cmp_range) - s_ref(cmp_range);
            sig_pwr = mean(abs(s_ref(cmp_range)).^2);
            err_pwr = mean(abs(err).^2);
            nmse_db = 10*log10(err_pwr / sig_pwr);
            max_err = max(abs(err));

            % 头部 vs 尾部 RMS（各取 10% 区间）
            seg_len = max(100, floor(length(cmp_range)/10));
            head_seg = cmp_range(1:seg_len);
            tail_seg = cmp_range(end-seg_len+1:end);
            head_rms = sqrt(mean(abs(s_comp(head_seg) - s_ref(head_seg)).^2));
            tail_rms = sqrt(mean(abs(s_comp(tail_seg) - s_ref(tail_seg)).^2));

            nmse_all(a_idx)     = nmse_db;
            maxerr_all(a_idx)   = max_err;
            head_rms_all(a_idx) = head_rms;
            tail_rms_all(a_idx) = tail_rms;

            fprintf('%-+10.1e | %-8s | %+12.2f | %12.3e | %12.3e | %12.3e\n', ...
                    alpha_true, mode_str, nmse_db, max_err, head_rms, tail_rms);
        end

        % 保存
        results.(sig_name).(mode_str).alpha    = alpha_list;
        results.(sig_name).(mode_str).nmse     = nmse_all;
        results.(sig_name).(mode_str).maxerr   = maxerr_all;
        results.(sig_name).(mode_str).head_rms = head_rms_all;
        results.(sig_name).(mode_str).tail_rms = tail_rms_all;
    end
end

%% ============ 5. 对称性 / tail 漂移分析 ============
fprintf('\n========================================\n');
fprintf('  对称性分析 (+α vs -α, accurate 模式)\n');
fprintf('========================================\n');
fprintf('%-10s | %-10s | %-10s | %-10s\n', ...
        '|α|', 'NMSE(+α)', 'NMSE(-α)', 'diff(dB)');
fprintf('%s\n', repmat('-', 1, 48));

for sig_idx = 1:3
    sig_fields = fieldnames(signals);
    sig_name = sig_fields{sig_idx};
    fprintf('\n[%s]\n', signals.(sig_name).name);
    for a_idx = 2:2:length(alpha_list)   % 正 α 索引
        alpha_pos = alpha_list(a_idx);
        alpha_neg_idx = find(abs(alpha_list - (-alpha_pos)) < 1e-12, 1);
        if isempty(alpha_neg_idx), continue; end

        nmse_p = results.(sig_name).accurate.nmse(a_idx);
        nmse_n = results.(sig_name).accurate.nmse(alpha_neg_idx);
        fprintf('%-10.3e | %+10.2f | %+10.2f | %+10.2f\n', ...
                abs(alpha_pos), nmse_p, nmse_n, nmse_p - nmse_n);
    end
end

%% ============ 6. 与 CP 阈值对比 ============
fprintf('\n========================================\n');
fprintf('  关键阈值参考\n');
fprintf('========================================\n');
fprintf('CP 精修相位模糊阈值        α_thres = %.3e\n', cp_thres);
fprintf('若 resample NMSE 体现出的等效残余 α > 阈值，则 CP 精修会卷绕\n\n');

% 估计 "等效残余 α" 粗略公式：NMSE ≈ -20·log10(2π·fc·α_res·T)
% 反推 α_res_effective = 10^(NMSE_dB/20) / (2π·fc·T_sig)
fprintf('%-10s | %-10s | %-12s | %-12s | %-12s\n', ...
        'α_true', 'NMSE(dB)', 'α_res(est)', '> 阈值？', 'BER 风险');
fprintf('%s\n', repmat('-', 1, 64));
for a_idx = 1:length(alpha_list)
    nmse = results.rrc.accurate.nmse(a_idx);
    if isnan(nmse), continue; end
    alpha_res_eff = 10^(nmse/20) / (2*pi*fc*T_sig);
    flag = '';
    if abs(alpha_res_eff) > cp_thres
        flag = '✗ 卷绕风险';
    else
        flag = '✓ 在阈值内';
    end
    fprintf('%-+10.1e | %+10.2f | %12.3e | %-12s | \n', ...
            alpha_list(a_idx), nmse, alpha_res_eff, flag);
end

%% ============ 7. 可视化 ============
try
    % Figure 1: NMSE vs α（三类信号，accurate 模式，对称性）
    f1 = figure('Name','Resample NMSE vs α','Position',[100 100 900 600]);
    sig_fields = fieldnames(signals);
    for i = 1:3
        sname = sig_fields{i};
        subplot(3,1,i);
        semilogx(abs(alpha_list(2:end)), results.(sname).accurate.nmse(2:end), 'o-', 'LineWidth', 1.5);
        hold on;
        % 分 +α / -α
        pos_mask = alpha_list > 0;
        neg_mask = alpha_list < 0;
        semilogx(alpha_list(pos_mask), results.(sname).accurate.nmse(pos_mask), 'bo-', 'LineWidth', 2, 'DisplayName','+α');
        semilogx(abs(alpha_list(neg_mask)), results.(sname).accurate.nmse(neg_mask), 'rx--', 'LineWidth', 2, 'DisplayName','-α');
        grid on;
        xlabel('|α|'); ylabel('NMSE (dB)');
        title(sprintf('%s — Resample NMSE', signals.(sname).name));
        legend('show', 'Location','northwest');
    end
    saveas(f1, fullfile(this_dir, 'test_resample_nmse_vs_alpha.png'));

    % Figure 2: 尾部 vs 头部 RMS（看尾部漂移）
    f2 = figure('Name','Head vs Tail RMS','Position',[120 120 900 600]);
    for i = 1:3
        sname = sig_fields{i};
        subplot(3,1,i);
        loglog(abs(alpha_list(2:end)), results.(sname).accurate.head_rms(2:end), 'bo-'); hold on;
        loglog(abs(alpha_list(2:end)), results.(sname).accurate.tail_rms(2:end), 'rx--');
        grid on;
        xlabel('|α|'); ylabel('RMS');
        title(sprintf('%s — Head vs Tail RMS', signals.(sname).name));
        legend('Head (前10%)', 'Tail (后10%)', 'Location','northwest');
    end
    saveas(f2, fullfile(this_dir, 'test_resample_head_tail.png'));

    % Figure 3: α=+3e-2 vs α=-3e-2 误差时域波形（QPSK-RRC）
    f3 = figure('Name','Error waveform ±3e-2','Position',[140 140 900 500]);
    y_p = synth_y('rrc', +3e-2);
    y_n = synth_y('rrc', -3e-2);
    s_p = comp_resample_spline(y_p, +3e-2, fs, 'accurate');
    s_n = comp_resample_spline(y_n, -3e-2, fs, 'accurate');
    L = min([length(s_p), length(s_n), length(s_rrc)]);
    err_p = s_p(1:L) - s_rrc(1:L);
    err_n = s_n(1:L) - s_rrc(1:L);
    t_ms = (0:L-1)/fs*1000;
    plot(t_ms, abs(err_p), 'b', 'LineWidth', 1); hold on;
    plot(t_ms, abs(err_n), 'r', 'LineWidth', 1);
    grid on;
    xlabel('t (ms)'); ylabel('|error|');
    title('QPSK-RRC resample 误差时域（α=±3e-2）');
    legend('α=+3e-2', 'α=-3e-2');
    saveas(f3, fullfile(this_dir, 'test_resample_err_waveform.png'));

    fprintf('\n图已保存：\n  test_resample_nmse_vs_alpha.png\n  test_resample_head_tail.png\n  test_resample_err_waveform.png\n');
catch ME
    fprintf('\n[警告] 可视化失败：%s\n', ME.message);
end

fprintf('\n========================================\n');
fprintf('  测试完成\n');
fprintf('========================================\n');
diary off;


%% ============ 辅助函数 ============
function y = synth_received(sig_name, alpha, t, f0, B_lfm, k_chirp, T_sig, s_rrc, fs, N_y)
% 合成接收信号 y(n) = s((1+α)·n/fs)，长度 N_y
% 单频/LFM 有解析形式（无合成误差），RRC 用高精度 spline 合成

switch sig_name
    case 'tone'
        % s(t) = exp(j·2π·f0·t), y(n) = exp(j·2π·f0·(1+α)·t_n)
        y = exp(1j * 2*pi * f0 * (1+alpha) * t(1:N_y));

    case 'lfm'
        t_eff = (1+alpha) * t(1:N_y);
        y = exp(1j * 2*pi * (-B_lfm/2 * t_eff + 0.5 * k_chirp * t_eff.^2));

    case 'rrc'
        % 从长度 N_rx 的 s_rrc 上取 pos = (1:N_y)·(1+α)
        pos_query = (1:N_y) * (1 + alpha);
        pos_query = max(1, min(pos_query, length(s_rrc)));
        y = interp1(1:length(s_rrc), s_rrc, pos_query, 'spline', 0);

    otherwise
        error('未知信号类型: %s', sig_name);
end

end
