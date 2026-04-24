function [h_tap, paths, label] = p4_channel_tap(sch, sys, preset)
% 功能：按体制 + UI 预设构造基带信道冲激响应 + gen_doppler_channel 所需 paths 结构
% 版本：V3.0.0（2026-04-22 P4 新增 paths 返回：delays[秒] + gains；供 gen_doppler_channel 使用）
% 用法：[h_tap, paths, label] = p4_channel_tap(sch, sys, preset)
% 输入：
%   sch    体制名
%   sys    系统参数
%   preset 信道预设：'AWGN' / '6径 标准水声' / '6径 深衰减' / '3径 短时延'
% 输出：
%   h_tap  信道冲激响应（在 body_bb 的采样率下，离散 stem 可视化用）
%   paths  struct:
%          .delays  1xP 各径时延（秒，@ sys.fs 采样率）
%          .gains   1xP 各径复增益（归一化）
%   label  描述标签
% 备注：
%   所有体制 body_bb 都运行在 sys.fs（48 kHz）下（DSSS chip_rate*sps=fs, OTFS V2.0 RRC 上采样，
%   其他 sym_rate*sps=fs）。故 delays_samp / sys.fs 即为秒，paths 可直接喂 gen_doppler_channel。

    if startsWith(preset, 'AWGN')
        h_tap = 1;
        paths = struct('delays', 0, 'gains', 1);
        label = 'AWGN';
        return;
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
        paths = struct('delays', delays_samp / sys.fs, 'gains', gains);
        label = sprintf('DSSS 5径, %d 抽头', length(h_tap));
        return;
    elseif strcmp(sch, 'OTFS')
        sps_use = sys.sps;
        cp_max = sys.otfs.cp_len - 4;
        if contains(preset, '6径 标准')
            sym_d = [0, 2, 5, 10, 18, 28];
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
        h_norm = norm(h_tap);
        h_tap = h_tap / h_norm;
        paths = struct('delays', delays_samp / sys.fs, 'gains', gains / h_norm);
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
    h_norm = norm(h_tap);
    h_tap = h_tap / h_norm;
    paths = struct('delays', delays_samp / sys.fs, 'gains', gains / h_norm);
    label = sprintf('%s, %d 抽头', preset, length(h_tap));
end
