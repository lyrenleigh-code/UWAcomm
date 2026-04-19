function [h_tap, label] = p3_channel_tap(sch, sys, preset)
% 功能：按体制 + UI 预设构造基带信道冲激响应
% 版本：V1.0.0（2026-04-17，从 p3_demo_ui 抽出）
% 用法：[h_tap, label] = p3_channel_tap(sch, sys, preset)
% 输入：
%   sch    体制名：'SC-FDE' | 'OFDM' | 'SC-TDE' | 'DSSS' | 'OTFS' | 'FH-MFSK'
%   sys    系统参数（需各 scheme 子结构的 sym_delays/chip_delays/gains_raw/sps）
%   preset 信道预设字符串（来自 UI 下拉）：
%            'AWGN (无多径)' / '6径 标准水声' / '6径 深衰减' / '3径 短时延'
% 输出：
%   h_tap  信道冲激响应（在 body_bb 的采样率下）
%   label  描述标签字符串，UI 显示用
% 备注：
%   采样率映射：
%     - DSSS:  body_bb 速率 = chip_rate * sps, 时延以码片为单位 → × sps
%     - OTFS:  body_bb 速率 = sym_rate, 时延以 DD 格点（= 1/sym_rate 样本）→ 1:1
%     - 其他:  body_bb 速率 = sym_rate * sps（RRC 成形后）, 时延以符号为单位 → × sps

    if startsWith(preset, 'AWGN')
        h_tap = 1; label = 'AWGN'; return;
    end

    % DSSS / OTFS 使用各自专属时延格点（不受 preset 影响）
    if strcmp(sch, 'DSSS')
        chip_d = sys.dsss.chip_delays;
        gains  = sys.dsss.gains_raw;
        gains  = gains / sqrt(sum(abs(gains).^2));
        delays_samp = chip_d * sys.dsss.sps;
        h_tap = zeros(1, max(delays_samp) + 1);
        for p = 1:length(delays_samp)
            h_tap(delays_samp(p)+1) = gains(p);
        end
        label = sprintf('DSSS 5径, %d 抽头', length(h_tap));
        return;
    elseif strcmp(sch, 'OTFS')
        sym_d  = sys.otfs.sym_delays;
        gains  = sys.otfs.gains_raw;
        delays_samp = sym_d;  % 1:1 映射
        h_tap = zeros(1, max(delays_samp) + 1);
        for p = 1:length(delays_samp)
            h_tap(delays_samp(p)+1) = gains(p);
        end
        h_tap = h_tap / norm(h_tap);
        label = sprintf('OTFS 5径, %d 抽头', length(h_tap));
        return;
    elseif ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE'})
        sps_use = sys.sps;
    else
        sps_use = sys.fhmfsk.samples_per_sym / 8;
    end

    % 按 preset 选抽头
    if contains(preset, '6径 标准')
        sym_d = [0, 5, 15, 40, 60, 90];
        gains = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
                 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
    elseif contains(preset, '6径 深衰减')
        sym_d = [0, 5, 15, 40, 60, 90];
        gains = [0.4, 0.7*exp(1j*0.5), 0.6*exp(1j*1.2), ...
                 0.5*exp(1j*1.8), 0.4*exp(1j*2.4), 0.3*exp(1j*2.9)];
    elseif contains(preset, '3径 短时延')
        sym_d = [0, 5, 15];
        gains = [1, 0.5*exp(1j*0.8), 0.3*exp(1j*1.6)];
    else
        sym_d = 0; gains = 1;
    end

    delays_samp = round(sym_d * sps_use);
    h_tap = zeros(1, max(delays_samp) + 1);
    for p = 1:length(delays_samp)
        h_tap(delays_samp(p)+1) = h_tap(delays_samp(p)+1) + gains(p);
    end
    h_tap = h_tap / norm(h_tap);
    label = sprintf('%s, %d 抽头', preset, length(h_tap));
end
