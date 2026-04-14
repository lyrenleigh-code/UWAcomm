%% diag_otfs_papr.m — OTFS通带帧PAPR诊断
% 用法: 先运行test_otfs_timevarying.m生成vis_frame_tx, 然后run此脚本
% 输出: diag_otfs_papr_results.txt

clc;
fprintf('========================================\n');
fprintf('  OTFS帧 PAPR 诊断\n');
fprintf('========================================\n\n');

if ~exist('vis_frame_tx', 'var')
    error('未找到vis_frame_tx, 请先运行test_otfs_timevarying.m');
end

fs_pb = 36000;
L = length(vis_frame_tx);

%% 1. 峰值定位
[peak_val, peak_idx] = max(abs(vis_frame_tx));
rms_val = sqrt(mean(vis_frame_tx.^2));
papr_db = 20*log10(peak_val / rms_val);

fprintf('--- 整帧统计 ---\n');
fprintf('帧长: %d samples (%.1fms @%dHz)\n', L, L/fs_pb*1000, fs_pb);
fprintf('峰值: %.3f @ 样本%d (%.1fms, 占帧%.1f%%)\n', ...
    peak_val, peak_idx, peak_idx/fs_pb*1000, peak_idx/L*100);
fprintf('RMS: %.4f\n', rms_val);
fprintf('PAPR: %.2f dB\n\n', papr_db);

%% 2. Top 20 最大幅值及位置
[sorted_abs, sort_idx] = sort(abs(vis_frame_tx), 'descend');
fprintf('--- Top 20 最大幅值 ---\n');
fprintf('%-8s %-12s %-12s %-10s\n', 'Rank', '幅值', '位置(ms)', '占帧%');
fprintf('%s\n', repmat('-', 1, 42));
for k = 1:20
    fprintf('%-8d %-12.3f %-12.2f %-10.1f\n', ...
        k, sorted_abs(k), sort_idx(k)/fs_pb*1000, sort_idx(k)/L*100);
end
fprintf('\n');

%% 3. 幅值分布
pct_99 = prctile(abs(vis_frame_tx), 99);
pct_999 = prctile(abs(vis_frame_tx), 99.9);
med_val = median(abs(vis_frame_tx));
mean_abs = mean(abs(vis_frame_tx));
fprintf('--- 幅值分布 ---\n');
fprintf('中位数|amp|: %.4f\n', med_val);
fprintf('平均|amp|: %.4f\n', mean_abs);
fprintf('99%%分位数: %.4f\n', pct_99);
fprintf('99.9%%分位数: %.4f\n', pct_999);
fprintf('峰值/中位数: %.1fx\n', peak_val/med_val);
fprintf('峰值/99%%: %.1fx\n\n', peak_val/pct_99);

%% 4. 分段PAPR（根据V2.0帧结构估计）
% 假设标准参数: T_hfm=50ms, T_lfm=20ms, guard=5ms
L_hfm = round(0.05 * fs_pb);    % 1800
L_lfm = round(0.02 * fs_pb);    % 720
N_g = round(0.005 * fs_pb);     % 180
pos = 1;
seg_info = {...
    'HFM+',  pos, pos+L_hfm-1;  };  pos = pos + L_hfm + N_g;
seg_info(end+1,:) = {'HFM-',  pos, pos+L_hfm-1};  pos = pos + L_hfm + N_g;
seg_info(end+1,:) = {'LFM1',  pos, pos+L_lfm-1};  pos = pos + L_lfm + N_g;
seg_info(end+1,:) = {'LFM2',  pos, pos+L_lfm-1};  pos = pos + L_lfm + N_g;
seg_info(end+1,:) = {'OTFS',  pos, L};

fprintf('--- 分段PAPR ---\n');
fprintf('%-8s %-12s %-10s %-10s %-10s %-10s\n', '段', '位置(ms)', '长度', '峰值', 'RMS', 'PAPR(dB)');
fprintf('%s\n', repmat('-', 1, 62));
for si = 1:size(seg_info,1)
    sname = seg_info{si,1};
    ss = seg_info{si,2}; se = min(seg_info{si,3}, L);
    if ss > L, continue; end
    seg = vis_frame_tx(ss:se);
    sp = max(abs(seg));
    sr = sqrt(mean(seg.^2));
    if sr > 1e-10
        sp_db = 20*log10(sp/sr);
    else
        sp_db = 0;
    end
    fprintf('%-8s %-12.1f %-10d %-10.3f %-10.4f %-10.2f\n', ...
        sname, ss/fs_pb*1000, se-ss+1, sp, sr, sp_db);
end
fprintf('\n');

%% 4.5 OTFS基带PAPR诊断（需要workspace中有otfs_signal变量）
fprintf('--- OTFS基带信号诊断 ---\n');
if exist('otfs_signal', 'var')
    bb_peak = max(abs(otfs_signal));
    bb_rms = sqrt(mean(abs(otfs_signal).^2));
    bb_papr = 20*log10(bb_peak / bb_rms);
    fprintf('otfs_signal (基带复信号): peak=%.3f, RMS=%.3f, PAPR=%.2fdB\n', ...
        bb_peak, bb_rms, bb_papr);
    % 基带峰值位置
    [~, bb_pk_idx] = max(abs(otfs_signal));
    fprintf('基带峰值位置: 样本%d (%.2fms @6kHz)\n', bb_pk_idx, bb_pk_idx/6000*1000);
end
if exist('dd_frame', 'var')
    [~, dd_pk_idx] = max(abs(dd_frame(:)));
    [dd_k, dd_l] = ind2sub(size(dd_frame), dd_pk_idx);
    fprintf('DD域峰值: %.3f @ (k=%d, l=%d), 其他元素中位数=%.3f\n', ...
        abs(dd_frame(dd_pk_idx)), dd_k, dd_l, median(abs(dd_frame(:))));
    % 统计DD域大值数量
    pilot_like = sum(abs(dd_frame(:)) > 10);
    fprintf('DD域 > 10 的元素数: %d (可能是pilot)\n', pilot_like);
end
fprintf('\n');

%% 5. 峰值附近波形（保存数据供可视化）
n1 = max(1, peak_idx-100);
n2 = min(L, peak_idx+100);
local_wave = vis_frame_tx(n1:n2);
local_t_ms = (n1:n2)/fs_pb*1000;

try
    figure('Name', 'PAPR诊断', 'Position', [100 100 1200 700]);
    subplot(2,2,1);
    plot((1:L)/fs_pb*1000, vis_frame_tx, 'b');
    hold on; plot(peak_idx/fs_pb*1000, vis_frame_tx(peak_idx), 'ro', 'MarkerSize', 8);
    xlabel('时间(ms)'); ylabel('幅度'); title('整帧(红圈=峰值位置)'); grid on;

    subplot(2,2,2);
    plot(local_t_ms, local_wave, 'b.-'); hold on;
    plot(peak_idx/fs_pb*1000, vis_frame_tx(peak_idx), 'ro', 'MarkerSize', 10);
    xlabel('时间(ms)'); ylabel('幅度'); title('峰值±100样本'); grid on;

    subplot(2,2,3);
    histogram(abs(vis_frame_tx), 100);
    xlabel('|amp|'); ylabel('count'); title('幅值直方图'); grid on;
    set(gca, 'YScale', 'log');

    subplot(2,2,4);
    stem(1:20, sorted_abs(1:20), 'r', 'filled');
    xlabel('Rank'); ylabel('幅值'); title('Top 20最大幅值'); grid on;
catch; end

%% 6. 保存诊断结果
result_file = fullfile(fileparts(mfilename('fullpath')), 'diag_otfs_papr_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'OTFS帧PAPR诊断\n');
fprintf(fid, '帧长=%d, 峰值=%.3f @ 样本%d (%.1fms), RMS=%.4f, PAPR=%.2fdB\n', ...
    L, peak_val, peak_idx, peak_idx/fs_pb*1000, rms_val, papr_db);
fprintf(fid, '\nTop 20:\n');
for k = 1:20
    fprintf(fid, '  %d: %.3f @ %.2fms\n', k, sorted_abs(k), sort_idx(k)/fs_pb*1000);
end
% OTFS基带诊断
fprintf(fid, '\nOTFS基带信号:\n');
if exist('otfs_signal', 'var')
    bb_peak2 = max(abs(otfs_signal));
    bb_rms2 = sqrt(mean(abs(otfs_signal).^2));
    bb_papr2 = 20*log10(bb_peak2 / bb_rms2);
    fprintf(fid, '  otfs_signal: peak=%.3f, RMS=%.3f, PAPR=%.2fdB\n', bb_peak2, bb_rms2, bb_papr2);
end
if exist('dd_frame', 'var')
    dd_max = max(abs(dd_frame(:)));
    dd_med = median(abs(dd_frame(:)));
    pilot_like2 = sum(abs(dd_frame(:)) > 10);
    fprintf(fid, '  DD域: max=%.3f, median=%.3f, 大值(>10)=%d个\n', dd_max, dd_med, pilot_like2);
end

fprintf(fid, '\n分段:\n');
for si = 1:size(seg_info,1)
    sname = seg_info{si,1};
    ss = seg_info{si,2}; se = min(seg_info{si,3}, L);
    if ss > L, continue; end
    seg = vis_frame_tx(ss:se);
    sp = max(abs(seg));
    sr = sqrt(mean(seg.^2));
    if sr > 1e-10, sp_db = 20*log10(sp/sr); else, sp_db = 0; end
    fprintf(fid, '  %s: %.1fms, peak=%.3f, RMS=%.4f, PAPR=%.2fdB\n', ...
        sname, ss/fs_pb*1000, sp, sr, sp_db);
end
fclose(fid);
fprintf('结果已保存: %s\n', result_file);
