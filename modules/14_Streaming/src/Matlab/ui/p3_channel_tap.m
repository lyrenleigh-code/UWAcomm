function [h_tap, label] = p3_channel_tap(sch, sys, preset)
% 功能：按体制 + UI 预设构造基带信道冲激响应
% 版本：V2.0.0（2026-04-19 OTFS preset 生效 + h_tap @ fs 采样率统一）
% 用法：[h_tap, label] = p3_channel_tap(sch, sys, preset)
% 输入：
%   sch    体制名
%   sys    系统参数
%   preset 信道预设：'AWGN' / '6径 标准水声' / '6径 深衰减' / '3径 短时延'
% 输出：
%   h_tap  信道冲激响应（在 body_bb 的采样率下）
%   label  描述标签
% 备注：
%   采样率映射：
%     - DSSS:  body_bb @ chip_rate * sps_dsss, 时延 × sps_dsss
%     - OTFS:  body_bb @ fs (V2.0 RRC 上采样后), 时延 × sps（对齐其他体制）
%     - 其他:  body_bb @ sym_rate * sps（RRC 成形），时延 × sps

    if startsWith(preset, 'AWGN')
        h_tap = 1; label = 'AWGN'; return;
    end

    % DSSS 专属时延（chip 级）
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
        % OTFS 多径应限制在 cp_len 符号内，否则跨 sub-block 污染
        sps_use = sys.sps;
        cp_max = sys.otfs.cp_len - 4;   % 留 4 符号 safety margin
        if contains(preset, '6径 标准')
            sym_d = [0, 2, 5, 10, 18, 28];  % DD 格点 0~28, 内 cp=32
            gains = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
                     0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
        elseif contains(preset, '6径 深衰减')
            sym_d = [0, 2, 5, 10, 18, 28];
            gains = [0.4, 0.7*exp(1j*0.5), 0.6*exp(1j*1.2), ...
                     0.5*exp(1j*1.8), 0.4*exp(1j*2.4), 0.3*exp(1j*2.9)];
        elseif contains(preset, '3径 短时延')
            sym_d = [0, 2, 5];
            gains = [1, 0.5*exp(1j*0.8), 0.3*exp(1j*1.6)];
        else
            sym_d = 0; gains = 1;
        end
        sym_d = min(sym_d, cp_max);
        delays_samp = round(sym_d * sps_use);
        h_tap = zeros(1, max(delays_samp) + 1);
        for p = 1:length(delays_samp)
            h_tap(delays_samp(p)+1) = h_tap(delays_samp(p)+1) + gains(p);
        end
        h_tap = h_tap / norm(h_tap);
        label = sprintf('%s (OTFS DD ≤%d), %d 抽头', preset, cp_max, length(h_tap));
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
