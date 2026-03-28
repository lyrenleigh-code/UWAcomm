%% test_sync.m
% 功能：同步+帧组装模块单元测试
% 版本：V1.0.0
% 运行方式：>> run('test_sync.m')

clc; close all;
fprintf('========================================\n');
fprintf('  同步+帧组装模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

%% ==================== 一、同步序列生成 ==================== %%
fprintf('--- 1. 同步序列生成 ---\n\n');

%% 1.1 LFM信号
try
    fs = 48000; dur = 0.01;
    [sig, t] = gen_lfm(fs, dur, 8000, 16000);
    assert(length(sig) == round(fs*dur), 'LFM长度不正确');
    assert(isreal(sig), 'LFM应为实信号');

    fprintf('[通过] 1.1 LFM | 长度=%d, 带宽=8kHz\n', length(sig));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 LFM | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.2 HFM信号
try
    [sig, t] = gen_hfm(fs, dur, 8000, 16000);
    assert(length(sig) == round(fs*dur), 'HFM长度不正确');

    fprintf('[通过] 1.2 HFM | 长度=%d, Doppler不变性\n', length(sig));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 HFM | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.3 Zadoff-Chu序列
try
    [seq, ~] = gen_zc_seq(127, 3);
    assert(length(seq) == 127, 'ZC长度不正确');
    assert(all(abs(abs(seq) - 1) < 1e-10), 'ZC应为恒模');

    % 周期自相关检验
    acorr = ifft(fft(seq) .* conj(fft(seq)));
    peak = abs(acorr(1));
    sidelobe = max(abs(acorr(2:end)));
    assert(sidelobe / peak < 0.01, 'ZC自相关旁瓣过高');

    fprintf('[通过] 1.3 ZC(127,3) | 恒模, 旁瓣/峰值=%.4f\n', sidelobe/peak);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.3 ZC | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.4 Barker码
try
    [code13, ~] = gen_barker(13);
    assert(length(code13) == 13, 'Barker-13长度不正确');

    % 非周期自相关旁瓣 <= 1
    acorr = xcorr(code13);
    peak = max(acorr);
    sidelobes = acorr; sidelobes(length(code13)) = 0;
    assert(max(abs(sidelobes)) <= 1 + 1e-6, 'Barker旁瓣应<=1');

    fprintf('[通过] 1.4 Barker(13) | 旁瓣最大=%.4f\n', max(abs(sidelobes)));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.4 Barker | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、粗同步检测 ==================== %%
fprintf('\n--- 2. 粗同步检测 ---\n\n');

%% 2.1 无噪声LFM同步
try
    fs = 48000;
    [preamble, ~] = gen_lfm(fs, 0.01, 8000, 16000);
    offset = 500;
    received = [zeros(1, offset), preamble, randn(1, 1000)*0.01];

    [pos, peak, ~] = sync_detect(received, preamble, 0.5);
    assert(abs(pos - offset - 1) <= 1, '同步位置偏差过大');
    assert(peak > 0.9, '无噪声峰值应接近1');

    fprintf('[通过] 2.1 LFM无噪声同步 | 偏移=%d, 检测=%d, 峰值=%.3f\n', offset, pos, peak);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 LFM同步 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.2 有噪声ZC同步
try
    rng(10);
    [preamble, ~] = gen_zc_seq(255, 7);
    offset = 300;
    noise = 0.5 * (randn(1, 1500) + 1j*randn(1, 1500));
    received = noise;
    received(offset+1 : offset+255) = received(offset+1 : offset+255) + preamble;

    [pos, peak, ~] = sync_detect(received, preamble, 0.3);
    assert(abs(pos - offset - 1) <= 2, '噪声下同步偏差过大');

    fprintf('[通过] 2.2 ZC有噪声同步 | SNR≈6dB, 偏移=%d, 检测=%d, 峰值=%.3f\n', ...
            offset, pos, peak);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.2 ZC有噪声 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、CFO估计 ==================== %%
fprintf('\n--- 3. CFO粗估计 ---\n\n');

%% 3.1 互相关法CFO估计
try
    rng(20);
    fs = 48000;
    [preamble, ~] = gen_zc_seq(256, 1);
    true_cfo = 50;                     % 50Hz频偏
    t = (0:255) / fs;
    rx = preamble .* exp(1j*2*pi*true_cfo*t);

    [cfo_est, ~] = cfo_estimate(rx, preamble, fs, 'correlate');
    cfo_err = abs(cfo_est - true_cfo);

    assert(cfo_err < 20, 'CFO估计误差过大');

    fprintf('[通过] 3.1 互相关CFO | 真实=%.1fHz, 估计=%.1fHz, 误差=%.1fHz\n', ...
            true_cfo, cfo_est, cfo_err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 互相关CFO | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 Schmidl-Cox法CFO估计
try
    fs = 48000;
    [half_seq, ~] = gen_zc_seq(128, 1);
    preamble_sc = [half_seq, half_seq]; % 双重复结构
    true_cfo = 30;
    t = (0:255) / fs;
    rx = preamble_sc .* exp(1j*2*pi*true_cfo*t);

    [cfo_est, ~] = cfo_estimate(rx, preamble_sc, fs, 'schmidl');
    cfo_err = abs(cfo_est - true_cfo);

    assert(cfo_err < 20, 'Schmidl CFO估计误差过大');

    fprintf('[通过] 3.2 Schmidl-Cox CFO | 真实=%.1fHz, 估计=%.1fHz, 误差=%.1fHz\n', ...
            true_cfo, cfo_est, cfo_err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 Schmidl CFO | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、细定时同步 ==================== %%
fprintf('\n--- 4. 细定时同步 ---\n\n');

%% 4.1 Gardner TED
try
    proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
    addpath(fullfile(proj_root, '04_Modulation', 'src', 'Matlab'));

    rng(30);
    sps = 8;
    symbols = 2*randi([0 1],1,100)-1;
    [shaped, ~, ~] = pulse_shape(symbols, sps, 'rrc', 0.35, 6);
    [filtered, ~] = match_filter(shaped, sps, 'rrc', 0.35, 6);

    [timing_off, ted_out] = timing_fine(filtered, sps, 'gardner');
    assert(~isempty(ted_out), 'Gardner TED输出不应为空');

    fprintf('[通过] 4.1 Gardner TED | 定时偏移=%.2f样本, TED均值=%.4f\n', ...
            timing_off, mean(ted_out));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 Gardner TED | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.2 三种TED方法均可运行
try
    methods = {'gardner', 'mm', 'earlylate'};
    all_ok = true;
    for k = 1:3
        [~, ted] = timing_fine(filtered, sps, methods{k});
        if isempty(ted), all_ok = false; end
    end
    assert(all_ok, '某些TED方法输出为空');

    fprintf('[通过] 4.2 三种TED | gardner/mm/earlylate 均正常\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 三种TED | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、帧组装/解析回环 ==================== %%
fprintf('\n--- 5. 帧组装/解析回环 ---\n\n');

%% 5.1 SC-TDE帧回环
try
    rng(40);
    data = randn(1, 200) + 1j*randn(1, 200);
    params = struct('preamble_type','lfm','fs',48000,'fc',12000,'bw',8000);

    [frame, info] = frame_assemble_sctde(data, params);
    [data_rx, train_rx, sync_info] = frame_parse_sctde(frame, info);

    assert(sync_info.sync_pos > 0, '同步失败');
    assert(length(data_rx) == length(data), '数据长度不一致');
    err = max(abs(data_rx - data));
    assert(err < 1e-10, '数据不一致');

    fprintf('[通过] 5.1 SC-TDE帧回环 | 同步pos=%d, 数据误差=%.2e\n', ...
            sync_info.sync_pos, err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 SC-TDE帧 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.2 SC-FDE帧回环
try
    rng(41);
    data = randn(1, 300) + 1j*randn(1, 300);
    params = struct('preamble_type','lfm','fs',48000,'fc',12000,'bw',8000);

    [frame, info] = frame_assemble_scfde(data, params);
    [data_rx, sync_info] = frame_parse_scfde(frame, info);

    assert(sync_info.sync_pos > 0, '同步失败');
    assert(length(data_rx) == length(data), '数据长度不一致');

    fprintf('[通过] 5.2 SC-FDE帧回环 | 含前后导码, 数据长度=%d\n', length(data_rx));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.2 SC-FDE帧 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.3 OFDM帧回环（含CFO估计）
try
    rng(42);
    data = randn(1, 512) + 1j*randn(1, 512);
    params = struct('preamble_type','zc','fs',48000);

    [frame, info] = frame_assemble_ofdm(data, params);
    [data_rx, sync_info] = frame_parse_ofdm(frame, info);

    assert(sync_info.sync_pos > 0, '同步失败');
    assert(length(data_rx) == length(data), '数据长度不一致');
    assert(isfield(sync_info, 'cfo_hz'), '应包含CFO估计');

    fprintf('[通过] 5.3 OFDM帧回环 | ZC前导, CFO估计=%.2fHz\n', sync_info.cfo_hz);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.3 OFDM帧 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.4 OTFS帧回环
try
    rng(43);
    data = randn(1, 400) + 1j*randn(1, 400);
    params = struct('preamble_type','hfm','fs',48000,'fc',12000,'bw',8000);

    [frame, info] = frame_assemble_otfs(data, params);
    [data_rx, sync_info] = frame_parse_otfs(frame, info);

    assert(sync_info.sync_pos > 0, '同步失败');
    assert(length(data_rx) == length(data), '数据长度不一致');

    fprintf('[通过] 5.4 OTFS帧回环 | HFM前导(Doppler不变)\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.4 OTFS帧 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 六、异常输入 ==================== %%
fprintf('\n--- 6. 异常输入测试 ---\n\n');

try
    caught = 0;
    try sync_detect([], [1 -1]); catch; caught=caught+1; end
    try cfo_estimate([], [1], 48000); catch; caught=caught+1; end
    try timing_fine([], 8); catch; caught=caught+1; end
    try gen_barker(6); catch; caught=caught+1; end           % 非法Barker长度
    try gen_zc_seq(0); catch; caught=caught+1; end           % N<1

    assert(caught == 5, '部分函数未对异常输入报错');

    fprintf('[通过] 6.1 异常输入拒绝 | 5项均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 6.1 异常输入 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 测试汇总 ==================== %%
fprintf('\n========================================\n');
fprintf('  测试完成：%d 通过, %d 失败, 共 %d 项\n', ...
        pass_count, fail_count, pass_count + fail_count);
fprintf('========================================\n');

if fail_count == 0
    fprintf('  全部通过！\n');
else
    fprintf('  存在失败项，请检查！\n');
end
