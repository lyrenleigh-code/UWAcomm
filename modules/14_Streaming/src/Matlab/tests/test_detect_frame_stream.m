function test_detect_frame_stream()
% TEST_DETECT_FRAME_STREAM  单元测试：流式帧检测精度
%
% 验证 detect_frame_stream 在不同 SNR / 多径下的检测位置偏差
% 用法：
%   cd modules/14_Streaming/src/Matlab/tests
%   clear functions; clear all;
%   test_detect_frame_stream

this_dir   = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
modules_root   = fileparts(fileparts(fileparts(streaming_root)));
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(modules_root, '02_ChannelCoding','src', 'Matlab'));
addpath(fullfile(modules_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(modules_root, '04_Modulation',   'src', 'Matlab'));
addpath(fullfile(modules_root, '05_SpreadSpectrum','src','Matlab'));
addpath(fullfile(modules_root, '08_Sync',         'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform',     'src', 'Matlab'));

sys = sys_params_default();
pass_cnt = 0; fail_cnt = 0;

fprintf('========== test_detect_frame_stream ==========\n');

%% ---- 1. 生成标准帧（FH-MFSK body）----
N_info = 512;  rng(42);
bits = randi([0 1], 1, N_info);
[body_bb, ~] = modem_encode_fhmfsk(bits, sys);
[frame_bb, frame_meta] = assemble_physical_frame(body_bb, sys);
[tx_pb, ~] = upconvert(frame_bb, sys.fs, sys.fc);
tx_pb = real(tx_pb);
fprintf('帧长: %d 样本 (%.2fs), preamble: %d 样本\n', ...
    length(tx_pb), length(tx_pb)/sys.fs, length(frame_bb) - length(body_bb));

%% ---- 2. 多种场景测试 ----
scenarios = {
    'AWGN SNR=15dB',   15, 1,   10000;    % label, snr_db, ch_taps, fifo_prefix
    'AWGN SNR=5dB',     5, 1,   10000;
    'AWGN SNR=0dB',     0, 1,   10000;
    'AWGN SNR=-5dB',   -5, 1,   10000;
    'Multi-path SNR=15dB', 15, [1 0.5 0.3 0.2], 10000;
    'Multi-path SNR=5dB',   5, [1 0.5 0.3 0.2], 10000;
};

for si = 1:size(scenarios,1)
    label   = scenarios{si, 1};
    snr_db  = scenarios{si, 2};
    h_tap   = scenarios{si, 3};
    prefix  = scenarios{si, 4};

    % 基带信道
    frame_ch = conv(frame_bb, h_tap);
    frame_ch = frame_ch(1:length(frame_bb));
    [frame_pb, ~] = upconvert(frame_ch, sys.fs, sys.fc);
    frame_pb = real(frame_pb);

    % 加噪声（passband 实信号 AWGN）
    sig_pwr = mean(frame_pb.^2);
    nv = sig_pwr * 10^(-snr_db/10);
    frame_pb_noisy = frame_pb + sqrt(nv) * randn(size(frame_pb));

    % 构造 FIFO：前缀噪声 + 帧 + 后缀噪声
    pre  = sqrt(nv) * randn(1, prefix);
    post = sqrt(nv) * randn(1, 5000);
    fifo = [pre, frame_pb_noisy, post];
    fifo_write = length(fifo);
    fs_pos_gt = prefix + 1;   % 真值：帧 HFM+ 头

    % 调用检测
    det = detect_frame_stream(fifo, fifo_write, 0, sys);

    if det.found
        diff_samples = det.fs_pos - fs_pos_gt;
        status_ok = abs(diff_samples) <= 4;
        tag = '[PASS]'; if ~status_ok, tag = '[FAIL]'; end
        fprintf('  %s %s: diff=%+d samples, peak=%.1f, ratio=%.1f, conf=%.2f\n', ...
            tag, label, diff_samples, det.peak_val, det.peak_ratio, det.confidence);
        if status_ok, pass_cnt = pass_cnt+1; else, fail_cnt = fail_cnt+1; end
    else
        % 低 SNR 漏检是预期
        if snr_db <= -3
            fprintf('  [SKIP] %s: 漏检（预期，低 SNR）\n', label);
        else
            fprintf('  [FAIL] %s: 漏检（SNR 足够，不应漏）\n', label);
            fail_cnt = fail_cnt + 1;
        end
    end
end

fprintf('==============================================\n');
fprintf('Pass: %d  Fail: %d\n', pass_cnt, fail_cnt);
if fail_cnt > 0
    error('test_detect_frame_stream 失败: %d 项', fail_cnt);
end

end
