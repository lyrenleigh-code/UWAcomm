%% main_sim_single.m — 单SNR点端到端仿真（6种体制）+ 可视化
% 版本：V2.0.0
% 功能：对全部6种通信体制在指定SNR下跑完整收发链路，输出BER + 柱状图 + 信道可视化

clc; close all;
fprintf('========================================\n');
fprintf('  UWAcomm 端到端仿真 — 单SNR点\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));

%% ========== 配置 ========== %%
schemes = {'SC-FDE', 'OFDM', 'SC-TDE', 'OTFS', 'DSSS', 'FH-MFSK'};
snr_db = 10;

fprintf('SNR = %d dB, 简化水声信道(多径时变+多普勒+AWGN)\n\n', snr_db);
fprintf('%-12s %10s %10s %12s %8s\n', '体制', 'infoBER%', 'N_info', '信道', '状态');
fprintf('%s\n', repmat('-', 1, 55));

ber_list = zeros(1, length(schemes));
status_list = cell(1, length(schemes));
ch_info_list = cell(1, length(schemes));
pass_count = 0;
fail_count = 0;

for si = 1:length(schemes)
    scheme = schemes{si};
    try
        % 参数配置
        params = sys_params(scheme, snr_db);

        % 发射
        rng(100 + si);
        [tx_signal, tx_info] = tx_chain(params);

        % 信道
        if isfield(tx_info, 'otfs_dd_mode') && tx_info.otfs_dd_mode
            % OTFS：信道在DD域施加（rx_otfs内部处理）
            rx_signal = tx_signal;  % 占位，实际信道在rx_otfs中
            n_p = length(params.channel.gains);
            ch_info = struct('num_paths', n_p, ...
                'delays_samp', round(params.channel.delays_s * params.channel.fs), ...
                'gains_init', params.channel.gains / sqrt(sum(abs(params.channel.gains).^2)), ...
                'noise_var', 0, 'fs', params.channel.fs, 'fading_type', 'static');
        else
            % 真实通带路径：OTFS real 与其他体制统一经过 gen_uwa_channel
            [rx_signal, ch_info] = gen_uwa_channel(tx_signal, params.channel);
        end
        ch_info_list{si} = ch_info;

        % 接收
        [bits_out, rx_info] = rx_chain(rx_signal, params, tx_info, ch_info);

        ber = rx_info.ber_info;
        ber_list(si) = ber;

        % 判断标准：BER < 0.1% 为通过
        if ber < 0.001
            status_list{si} = '通过';
            pass_count = pass_count + 1;
        else
            status_list{si} = '未达标';
            fail_count = fail_count + 1;
        end

        ch_desc = sprintf('%d径/%s', ch_info.num_paths, ch_info.fading_type);
        fprintf('%-12s %10.2f %10d %12s %8s\n', scheme, ber*100, params.N_info, ch_desc, status_list{si});

    catch e
        ber_list(si) = NaN;
        status_list{si} = '异常';
        fail_count = fail_count + 1;
        fprintf('%-12s %10s %10s %12s %8s\n', scheme, '—', '—', '—', '异常');
        fprintf('            错误: %s\n', e.message);
    end
end

fprintf('\n========================================\n');
fprintf('  仿真完成：%d 通过, %d 未达标/异常, 共 %d 项\n', pass_count, fail_count, length(schemes));
fprintf('========================================\n');

%% ==================== 可视化 ==================== %%

% --- Figure 1: BER柱状图 ---
figure('Name','端到端BER对比','Position',[100 400 800 400]);
colors_bar = [0.2 0.6 0.9; 0.2 0.8 0.4; 0.9 0.5 0.2; 0.6 0.2 0.8; 0.8 0.8 0.2; 0.9 0.3 0.3];
valid = ~isnan(ber_list);
b = bar(ber_list(valid) * 100);
b.FaceColor = 'flat';
for k = find(valid)
    idx = sum(valid(1:k));
    b.CData(idx,:) = colors_bar(k,:);
end
set(gca, 'XTickLabel', schemes(valid), 'FontSize', 12);
ylabel('信息比特BER (%)');
title(sprintf('6种体制端到端BER对比 (SNR=%ddB)', snr_db));
grid on;
% 在柱上标数值
valid_idx = find(valid);
for k = 1:length(valid_idx)
    text(k, ber_list(valid_idx(k))*100 + 1, ...
         sprintf('%.1f%%', ber_list(valid_idx(k))*100), ...
         'HorizontalAlignment','center', 'FontSize',10, 'FontWeight','bold');
end
% 20%通过线
hold on;
yline(0.1, 'r--', 'LineWidth', 1.5);
text(length(schemes(valid))+0.3, 0.5, '达标线0.1%', 'Color','r', 'FontSize',10);

% --- Figure 2: 信道冲激响应 ---
figure('Name','水声信道冲激响应','Position',[100 50 800 500]);
for si = 1:length(schemes)
    if isempty(ch_info_list{si}), continue; end
    ci = ch_info_list{si};
    subplot(2, 3, si);
    stem(ci.delays_samp, abs(ci.gains_init), 'filled', 'LineWidth', 1.5, 'Color', colors_bar(si,:));
    xlabel('时延(采样)'); ylabel('|h|');
    title(sprintf('%s (%s)', schemes{si}, ci.fading_type));
    grid on;
    xlim([-1, max(ci.delays_samp)+5]);
end
sgtitle(sprintf('各体制信道冲激响应 (SNR=%ddB)', snr_db), 'FontSize', 13);

fprintf('\n可视化完成（Figure 1: BER柱状图, Figure 2: 信道CIR）\n');
