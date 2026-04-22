%% test_resample_roundtrip_nodoppler.m
% 功能：通带 resample 往返（无多普勒）诊断测试
% 版本：V1.0.0
% 日期：2026-04-22
% 目的：隔离 MATLAB 原生 resample 函数的往返损耗，排除所有其他因素
%       检查 `resample(rx,1530,1500) → resample(*,1500,1530)`（净比例 1.000）
%       在无多普勒、静态多径、SNR=10dB 条件下，是否引入可观 BER
%
% 参考 spec：specs/active/2026-04-22-resample-roundtrip-nodoppler-test.md
% 骨架基于：common/main_sim_single.m

clc; close all;
fprintf('========================================================\n');
fprintf('  通带 resample 往返诊断测试（无多普勒，SNR=10dB）\n');
fprintf('  ratio: 1550/1500 → 1500/1550（净比例 1.000，单向 ≈3.33%%）\n');
fprintf('========================================================\n\n');

%% ========== 路径与依赖 ========== %%
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))));
common_dir = fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common');
addpath(common_dir);
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));

%% ========== 配置 ========== %%
% 跳过 OTFS（DD 占位路径，无通带 resample 意义；per feedback_uwacomm_skip_otfs）
schemes = {'SC-FDE', 'OFDM', 'SC-TDE', 'DSSS', 'FH-MFSK'};
snr_db  = 10;
p_up    = 1550;   % resample 上采样比分子
q_up    = 1500;   % resample 上采样比分母（ratio = p/q ≈ 1.0333）
% 往返第二步：ratio = q_up/p_up ≈ 0.9677

fprintf('SNR = %d dB, 信道: 5径静态多径（无多普勒）\n', snr_db);
fprintf('Resample: resample(rx,%d,%d) → resample(*,%d,%d)\n\n', ...
    p_up, q_up, q_up, p_up);

fprintf('%-10s %12s %12s %10s %8s\n', '体制', 'BER基线%', 'BER往返%', 'Δ(pp)', '判定');
fprintf('%s\n', repmat('-', 1, 60));

ber_base  = zeros(1, length(schemes));
ber_rt    = zeros(1, length(schemes));
status_list = cell(1, length(schemes));

% 存储一个体制的波形用于可视化（默认 SC-FDE）
viz_scheme = 'SC-FDE';
viz_rx_base = [];
viz_rx_rt   = [];
viz_params  = [];

for si = 1:length(schemes)
    scheme = schemes{si};
    try
        %% ---- 参数配置 ----
        params = sys_params(scheme, snr_db);
        % 安全兜底：确保无多普勒
        params.channel.doppler_rate  = 0;
        params.channel.fading_type   = 'static';
        params.channel.fading_fd_hz  = 0;

        %% ---- 发射 ----
        rng(100 + si);
        [tx_signal, tx_info] = tx_chain(params);

        %% ---- 信道（同一次 rng 序列给 baseline 和 roundtrip） ----
        % 注意：gen_uwa_channel 内部含 randn 噪声，为了 baseline / roundtrip 噪声
        %       实现一致，先固定 rng 再两次调用会重复噪声；这里采用同一条通路：
        %       先跑一次 channel，得到 rx_signal 后，往返 resample 与否作为分支。
        rng(200 + si);
        [rx_signal, ch_info] = gen_uwa_channel(tx_signal, params.channel);

        %% ---- Baseline：不做 resample ----
        rng(300 + si);  % 隔离 rx_chain 内部随机（turbo/decoder 用到 randn 时可重复）
        [bits_base, rx_info_base] = rx_chain(rx_signal, params, tx_info, ch_info);
        ber_base(si) = rx_info_base.ber_info;

        %% ---- Roundtrip：对同一 rx_signal 做往返 resample ----
        rx_rs_up   = resample(rx_signal, p_up, q_up);
        rx_rs_back = resample(rx_rs_up, q_up, p_up);

        % 长度对齐（以原 rx_signal 为锚）
        N_anchor = length(rx_signal);
        if length(rx_rs_back) > N_anchor
            rx_rt = rx_rs_back(1:N_anchor);
        elseif length(rx_rs_back) < N_anchor
            rx_rt = [rx_rs_back, zeros(1, N_anchor - length(rx_rs_back))];
        else
            rx_rt = rx_rs_back;
        end

        rng(300 + si);  % 与 baseline 使用相同随机序列，保证公平对比
        [bits_rt, rx_info_rt] = rx_chain(rx_rt, params, tx_info, ch_info);
        ber_rt(si) = rx_info_rt.ber_info;

        %% ---- 判定 ----
        delta_pct = (ber_rt(si) - ber_base(si)) * 100;
        if abs(delta_pct) < 0.5
            status_list{si} = '通过';
        elseif abs(delta_pct) < 5
            status_list{si} = '退化';
        else
            status_list{si} = '崩坏';
        end

        fprintf('%-10s %12.3f %12.3f %10.3f %8s\n', ...
            scheme, ber_base(si)*100, ber_rt(si)*100, delta_pct, status_list{si});

        %% ---- 记录可视化数据 ----
        if strcmpi(scheme, viz_scheme)
            viz_rx_base = rx_signal;
            viz_rx_rt   = rx_rt;
            viz_params  = params;
        end

    catch e
        ber_base(si) = NaN;
        ber_rt(si)   = NaN;
        status_list{si} = '异常';
        fprintf('%-10s %12s %12s %10s %8s\n', scheme, '—', '—', '—', '异常');
        fprintf('          错误: %s\n', e.message);
    end
end

fprintf('\n========================================================\n');
fprintf('  判定标准：|Δ|<0.5pp 通过 / <5pp 退化 / ≥5pp 崩坏\n');
fprintf('========================================================\n');

%% ========== 保存结果 TXT ==========
out_dir = fullfile(fileparts(mfilename('fullpath')), 'diag_results_resample_rt');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
txt_path = fullfile(out_dir, 'resample_roundtrip_results.txt');
fid = fopen(txt_path, 'w');
fprintf(fid, 'Resample Roundtrip Diagnostic (SNR=%d dB, no Doppler)\n', snr_db);
fprintf(fid, 'ratio: %d/%d -> %d/%d\n\n', p_up, q_up, q_up, p_up);
fprintf(fid, '%-10s %12s %12s %10s %8s\n', 'scheme', 'BER_base%', 'BER_rt%', 'dPP', 'status');
for si = 1:length(schemes)
    fprintf(fid, '%-10s %12.4f %12.4f %10.4f %8s\n', ...
        schemes{si}, ber_base(si)*100, ber_rt(si)*100, ...
        (ber_rt(si)-ber_base(si))*100, status_list{si});
end
fclose(fid);
fprintf('\n结果已保存：%s\n', txt_path);

%% ========== 可视化 ========== %%
try
    % --- Fig 1：baseline vs roundtrip BER 柱状图 ---
    figure('Name','Resample往返 BER 对比','Position',[100 400 900 420]);
    data = [ber_base; ber_rt]' * 100;
    b = bar(data);
    b(1).FaceColor = [0.2 0.6 0.9];
    b(2).FaceColor = [0.9 0.4 0.2];
    set(gca, 'XTickLabel', schemes, 'FontSize', 11);
    ylabel('信息比特 BER (%)');
    title(sprintf('Resample 往返损耗（SNR=%d dB，无多普勒）', snr_db));
    legend({'Baseline（无 resample）', ...
        sprintf('往返 resample %d/%d', p_up, q_up)}, ...
        'Location', 'best');
    grid on;

    % 标注每柱数值
    for k = 1:length(schemes)
        text(k-0.15, ber_base(k)*100+0.3, sprintf('%.2f', ber_base(k)*100), ...
            'HorizontalAlignment','center','FontSize',9);
        text(k+0.15, ber_rt(k)*100+0.3,   sprintf('%.2f', ber_rt(k)*100), ...
            'HorizontalAlignment','center','FontSize',9,'Color',[0.7 0.1 0.1]);
    end

    % --- Fig 2：SC-FDE rx_signal 原始 vs 往返 时/频域对比 ---
    if ~isempty(viz_rx_base)
        figure('Name',sprintf('%s 信号波形对比 (时/频)', viz_scheme), ...
               'Position',[100 50 1000 600]);

        N_show = min(400, length(viz_rx_base));
        fs_pb  = viz_params.fs_passband;

        subplot(2,2,1);
        plot(real(viz_rx_base(1:N_show)), 'b-'); hold on;
        plot(real(viz_rx_rt(1:N_show)),   'r--');
        xlabel('样本'); ylabel('Re\{rx\}');
        title('时域（实部，前 400 样本）');
        legend('Baseline','往返 resample'); grid on;

        subplot(2,2,2);
        err = viz_rx_rt(1:length(viz_rx_base)) - viz_rx_base;
        plot(real(err(1:N_show)), 'k-');
        xlabel('样本'); ylabel('误差实部');
        title(sprintf('误差（RMSE=%.4g）', sqrt(mean(abs(err).^2))));
        grid on;

        subplot(2,2,3);
        Nf = 2^nextpow2(length(viz_rx_base));
        f = (0:Nf-1) * fs_pb / Nf - fs_pb/2;
        X0 = fftshift(abs(fft(viz_rx_base, Nf)));
        X1 = fftshift(abs(fft(viz_rx_rt,  Nf)));
        plot(f/1000, 20*log10(X0+eps), 'b-'); hold on;
        plot(f/1000, 20*log10(X1+eps), 'r--');
        xlabel('频率 (kHz)'); ylabel('|FFT| (dB)');
        title('频域幅度谱');
        legend('Baseline','往返 resample'); grid on;
        xlim([-fs_pb/2 fs_pb/2]/1000);

        subplot(2,2,4);
        plot(f/1000, 20*log10(X1+eps) - 20*log10(X0+eps), 'k-');
        xlabel('频率 (kHz)'); ylabel('差值 (dB)');
        title('频域差值（往返 − baseline）');
        grid on; xlim([-fs_pb/2 fs_pb/2]/1000);

        sgtitle(sprintf('%s：通带 resample 往返前后对比', viz_scheme), ...
            'FontSize', 12);
    end

    fprintf('\n可视化完成（Fig 1: BER对比, Fig 2: %s 波形对比）\n', viz_scheme);
catch e_viz
    fprintf('\n⚠ 可视化异常：%s\n', e_viz.message);
end
