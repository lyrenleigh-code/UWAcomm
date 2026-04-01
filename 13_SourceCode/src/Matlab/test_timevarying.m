%% test_timevarying.m — 时变信道端到端测试
% 对比static/slow/fast三种衰落 × 6种体制的BER
% 版本：V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  时变信道端到端测试\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '12_IterativeProc', 'src', 'Matlab'));

schemes = {'SC-FDE', 'OFDM', 'SC-TDE', 'OTFS', 'DSSS', 'FH-MFSK'};
fading_types = {'static', 'slow', 'fast'};
fd_hz = [0, 1, 5];  % 对应各衰落类型的最大多普勒频移
snr_db = 15;         % 较高SNR，隔离时变效应

ber_matrix = zeros(length(schemes), length(fading_types));

fprintf('SNR = %d dB, 5径信道, 整数符号时延\n\n', snr_db);
fprintf('%-12s', '体制');
for fi = 1:length(fading_types)
    fprintf('%12s', fading_types{fi});
end
fprintf('\n%s\n', repmat('-', 1, 12+12*length(fading_types)));

for si = 1:length(schemes)
    scheme = schemes{si};
    fprintf('%-12s', scheme);

    for fi = 1:length(fading_types)
        try
            rng(100 + si + fi*10);
            params = sys_params(scheme, snr_db);

            % 设置时变信道参数
            params.channel.fading_type = fading_types{fi};
            params.channel.fading_fd_hz = fd_hz(fi);

            % 发射
            [tx_signal, tx_info] = tx_chain(params);

            % 信道
            if isfield(tx_info, 'otfs_dd_mode') && tx_info.otfs_dd_mode
                % OTFS DD域：时变体现为多普勒维度的扩展
                n_p = length(params.channel.gains);
                ch_info = struct('num_paths', n_p, ...
                    'delays_samp', round(params.channel.delays_s * params.channel.fs), ...
                    'gains_init', params.channel.gains / sqrt(sum(abs(params.channel.gains).^2)), ...
                    'noise_var', 0, 'fs', params.channel.fs, 'fading_type', fading_types{fi});
                rx_signal = tx_signal;
            else
                [rx_signal, ch_info] = gen_uwa_channel(tx_signal, params.channel);
            end

            % 接收
            [bits_out, rx_info] = rx_chain(rx_signal, params, tx_info, ch_info);
            ber = rx_info.ber_info;

        catch e
            ber = NaN;
        end

        ber_matrix(si, fi) = ber;
        if isnan(ber)
            fprintf('%12s', '异常');
        else
            fprintf('%11.2f%%', ber*100);
        end
    end
    fprintf('\n');
end

%% ========== 可视化 ========== %%
figure('Name','时变信道BER对比','Position',[100 200 900 450]);
colors = lines(length(schemes));
bar_data = ber_matrix * 100;
bar_data(isnan(bar_data)) = 0;

b = bar(bar_data);
for k = 1:length(fading_types)
    b(k).DisplayName = fading_types{k};
end
set(gca, 'XTickLabel', schemes, 'FontSize', 11);
ylabel('infoBER (%)');
title(sprintf('时变信道BER对比 (SNR=%ddB, 5径, fd=[%s] Hz)', snr_db, num2str(fd_hz)));
legend('Location','best');
grid on;

% 第二张图：各衰落类型分panel
figure('Name','时变信道详细对比','Position',[100 50 1000 350]);
for fi = 1:length(fading_types)
    subplot(1,3,fi);
    valid = ~isnan(ber_matrix(:,fi));
    bar_vals = ber_matrix(valid, fi) * 100;
    b2 = bar(bar_vals);
    b2.FaceColor = colors(fi,:);
    set(gca, 'XTickLabel', schemes(valid), 'FontSize', 9);
    ylabel('BER (%)');
    title(sprintf('%s (fd=%dHz)', fading_types{fi}, fd_hz(fi)));
    grid on;
    ylim([0, max(max(bar_vals)+5, 1)]);
end
sgtitle(sprintf('SNR=%ddB 各衰落类型BER', snr_db));

fprintf('\n可视化完成\n');
