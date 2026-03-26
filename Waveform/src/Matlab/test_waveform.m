%% test_waveform.m
% 功能：脉冲成形/上下变频模块单元测试
% 版本：V1.0.0
% 运行方式：>> run('test_waveform.m')

clc; close all;
fprintf('========================================\n');
fprintf('  脉冲成形/上下变频模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

%% ==================== 一、脉冲成形 ==================== %%
fprintf('--- 1. 脉冲成形 ---\n\n');

%% 1.1 四种滤波器生成
try
    types = {'rc','rrc','rect','gauss'};
    sps = 8; span = 6;
    all_ok = true;
    for k = 1:4
        [~, h, t] = pulse_shape(1, sps, types{k}, 0.35, span);
        if length(h) ~= span*sps+1
            all_ok = false;
        end
    end
    assert(all_ok, '滤波器长度不正确');

    fprintf('[通过] 1.1 四种滤波器生成 | rc/rrc/rect/gauss, 长度=%d\n', span*sps+1);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 滤波器生成 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.2 RRC发+RRC收=RC（零ISI验证）
try
    sps = 8; rolloff = 0.25; span = 8;
    % 发送脉冲序列（中间放单个1，前后足够多零）
    impulse = [zeros(1,10), 1, zeros(1,10)];
    [shaped, ~, ~] = pulse_shape(impulse, sps, 'rrc', rolloff, span);
    % 收端匹配滤波
    [filtered, ~] = match_filter(shaped, sps, 'rrc', rolloff, span);

    % 找到峰值位置，检查前后sps整数倍处的ISI
    [peak_val, peak_pos] = max(abs(filtered));
    isi_positions = peak_pos + (-5:5)*sps;
    isi_positions = isi_positions(isi_positions > 0 & isi_positions <= length(filtered));
    isi_positions(isi_positions == peak_pos) = [];

    isi_values = abs(filtered(isi_positions));
    max_isi = max(isi_values) / peak_val;

    assert(isscalar(max_isi) && max_isi < 0.05, 'ISI过大');

    fprintf('[通过] 1.2 RRC+RRC=RC零ISI | 最大ISI/峰值=%.4f\n', max_isi);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 RRC零ISI | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.3 脉冲成形+匹配滤波回环
try
    rng(10);
    sps = 4; rolloff = 0.35; span = 6;
    symbols_in = 2*randi([0 1],1,100)-1;  % BPSK ±1

    [shaped, ~, ~] = pulse_shape(symbols_in, sps, 'rrc', rolloff, span);
    [filtered, ~] = match_filter(shaped, sps, 'rrc', rolloff, span);

    % 自动搜索最优采样偏移（两次'same'卷积的延迟不固定）
    best_ber = 1; best_d = 0;
    for d = 0:sps-1
        idx = d+1 : sps : length(filtered);
        n = min(length(idx), 100);
        dec = sign(real(filtered(idx(1:n))));
        b = sum(dec ~= symbols_in(1:n)) / n;
        if b < best_ber, best_ber = b; best_d = d; end
    end
    assert(best_ber == 0, '无噪声回环BER应为0');

    fprintf('[通过] 1.3 成形+匹配滤波回环 | 100符号, 最优偏移=%d, BER=0\n', best_d);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.3 成形+匹配回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、上下变频 ==================== %%
fprintf('\n--- 2. 上下变频 ---\n\n');

%% 2.1 上变频+下变频回环
try
    fs = 48000; fc = 12000;
    rng(20);
    % 生成带限基带信号（带宽 < LPF截止频率）
    sps_test = 8;
    sym = randn(1,250) + 1j*randn(1,250);
    [baseband_in, ~, ~] = pulse_shape(sym, sps_test, 'rrc', 0.35, 6);

    [passband, ~] = upconvert(baseband_in, fs, fc);
    [baseband_out, ~] = downconvert(passband, fs, fc, fs/sps_test);

    % 归一化后比较相关性
    corr_coeff = abs(sum(baseband_out .* conj(baseband_in))) / ...
                 (sqrt(sum(abs(baseband_out).^2)) * sqrt(sum(abs(baseband_in).^2)));

    assert(corr_coeff > 0.95, '上下变频回环相关性不足');

    fprintf('[通过] 2.1 上下变频回环 | fs=%dHz, fc=%dHz, 相关系数=%.4f\n', fs, fc, corr_coeff);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 上下变频回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.2 通带信号为实数
try
    fs = 48000; fc = 10000;
    baseband = (1+1j) * ones(1, 100);
    [passband, ~] = upconvert(baseband, fs, fc);

    assert(isreal(passband), '通带信号应为实数');

    fprintf('[通过] 2.2 通带信号为实数验证\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.2 通带实数 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.3 BPSK端到端（成形+上变频+下变频+匹配+判决）
try
    rng(30);
    fs = 48000; fc = 12000;
    sps = 8; rolloff = 0.35; span = 6;
    symbols_in = 2*randi([0 1],1,50)-1;

    % TX: 成形 → 上变频
    [shaped, ~, ~] = pulse_shape(symbols_in, sps, 'rrc', rolloff, span);
    [passband, ~] = upconvert(shaped, fs, fc);

    % RX: 下变频 → 匹配滤波 → 下采样 → 判决
    bw = fs / sps;                     % 基带信号带宽
    [baseband, ~] = downconvert(passband, fs, fc, bw);
    [filtered, ~] = match_filter(baseband, sps, 'rrc', rolloff, span);

    % 自动搜索最优采样偏移
    best_ber = 1; best_d = 0;
    for d = 0:sps-1
        idx = d+1 : sps : length(filtered);
        n = min(length(idx), 50);
        dec = sign(real(filtered(idx(1:n))));
        b = sum(dec ~= symbols_in(1:n)) / n;
        if b < best_ber, best_ber = b; best_d = d; end
    end
    assert(best_ber < 0.1, 'BPSK端到端BER过高');

    fprintf('[通过] 2.3 BPSK端到端 | 50符号, 偏移=%d, BER=%.1f%%\n', best_d, best_ber*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.3 BPSK端到端 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、FSK波形 ==================== %%
fprintf('\n--- 3. FSK波形生成 ---\n\n');

%% 3.1 基本波形生成
try
    freq_idx = [0 1 2 3];
    M = 4; f0 = 1000; spacing = 200; fs = 8000; dur = 0.01;
    [waveform, t, freqs] = gen_fsk_waveform(freq_idx, M, f0, spacing, fs, dur);

    samples_per_sym = round(dur * fs);
    assert(length(waveform) == 4 * samples_per_sym, '波形长度不正确');
    assert(length(freqs) == M, '频率表长度应为M');
    assert(freqs(1) == f0, '最低频率应为f0');
    assert(freqs(end) == f0 + (M-1)*spacing, '最高频率不正确');

    fprintf('[通过] 3.1 4-FSK波形 | 频率=[%s] Hz, 采样=%d/符号\n', ...
            num2str(freqs), samples_per_sym);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 FSK波形 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 FSK频率检测验证
try
    rng(40);
    M = 4; f0 = 1000; spacing = 200; fs = 8000; dur = 0.02;
    freq_idx = randi([0 M-1], 1, 20);
    [waveform, t, freqs] = gen_fsk_waveform(freq_idx, M, f0, spacing, fs, dur);

    % 通过FFT验证每段波形的主频率
    samples_per_sym = round(dur * fs);
    detected = zeros(1, 20);
    for s = 1:20
        seg = waveform((s-1)*samples_per_sym+1 : s*samples_per_sym);
        [psd, f_axis] = periodogram(seg, [], [], fs);
        [~, pk] = max(psd);
        detected_freq = f_axis(pk);
        [~, detected(s)] = min(abs(freqs - detected_freq));
        detected(s) = detected(s) - 1;  % 0-based
    end

    ber = sum(detected ~= freq_idx) / 20;
    assert(ber == 0, 'FFT频率检测错误');

    fprintf('[通过] 3.2 FSK频率检测 | 20符号FFT验证, 全部正确\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 FSK频率检测 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、DA/AD转换 ==================== %%
fprintf('\n--- 4. DA/AD转换 ---\n\n');

%% 4.1 理想模式直通
try
    signal = randn(1, 100);
    [da_out, ~] = da_convert(signal, 16, 'ideal');
    [ad_out, ~] = ad_convert(signal, 16, 'ideal');

    assert(isequal(da_out, signal), 'DA理想模式应直通');
    assert(isequal(ad_out, signal), 'AD理想模式应直通');

    fprintf('[通过] 4.1 理想DA/AD直通\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 理想DA/AD | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.2 量化SQNR验证
try
    rng(50);
    signal = sin(2*pi*50*(0:9999)/10000);  % 满量程正弦

    sqnr_list = zeros(1, 4);
    bits_list = [8, 12, 14, 16];
    for k = 1:4
        [quantized, ~] = da_convert(signal, bits_list(k), 'quantize');
        noise_power = mean((quantized - signal).^2);
        sig_power = mean(signal.^2);
        sqnr_list(k) = 10*log10(sig_power / noise_power);
    end

    % SQNR应随比特数增加（每增加1bit约6dB）
    assert(all(diff(sqnr_list) > 0), 'SQNR应随比特数递增');

    fprintf('[通过] 4.2 DA量化SQNR | ');
    for k = 1:4, fprintf('%dbit=%.1fdB ', bits_list(k), sqnr_list(k)); end
    fprintf('\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 DA量化SQNR | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.3 AD截断警告
try
    signal = [-2, -1, 0, 1, 2];
    w = warning('off', 'all');
    [ad_out, ~] = ad_convert(signal, 8, 'quantize', 1.0);  % 满量程±1
    warning(w);

    assert(all(abs(ad_out) <= 1.0), 'AD截断后不应超出满量程');

    fprintf('[通过] 4.3 AD截断 | 超量程采样正确截断\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.3 AD截断 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.4 DA+AD回环误差
try
    rng(60);
    signal = 0.8*randn(1, 1000);
    bits = 16;

    [da_out, sf] = da_convert(signal, bits, 'quantize');
    [ad_out, ~] = ad_convert(da_out, bits, 'quantize', sf*1.1);

    rel_err = max(abs(ad_out - da_out)) / max(abs(da_out));
    assert(rel_err < 0.01, 'DA→AD回环误差过大');

    fprintf('[通过] 4.4 DA→AD回环 | 16bit, 最大相对误差=%.4f\n', rel_err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.4 DA→AD回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、符号映射联合测试 ==================== %%
fprintf('\n--- 5. 与Modulation模块联合测试 ---\n\n');

% 添加调制模块路径
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, 'Modulation', 'src', 'Matlab'));

%% 5.1 QPSK全链路（映射→成形→上变频→下变频→匹配→软判决）
try
    rng(70);
    fs = 48000; fc = 12000; sps = 8; rolloff = 0.35; span = 6;
    bits_in = randi([0 1], 1, 400);    % 200个QPSK符号

    % TX: 符号映射 → 成形 → DA → 上变频
    [symbols, ~, ~] = qam_modulate(bits_in, 4, 'gray');
    [shaped, ~, ~] = pulse_shape(symbols, sps, 'rrc', rolloff, span);
    [da_out, ~] = da_convert(real(shaped), 14, 'quantize');
    da_out_q = da_convert(imag(shaped), 14, 'quantize');
    shaped_da = da_out + 1j * da_out_q;
    [passband, ~] = upconvert(shaped_da, fs, fc);

    % RX: AD → 下变频 → 匹配 → 判决
    [ad_out, ~] = ad_convert(passband, 14, 'quantize');
    bw = fs / sps;
    [baseband, ~] = downconvert(ad_out, fs, fc, bw);
    [filtered, ~] = match_filter(baseband, sps, 'rrc', rolloff, span);

    % 搜索最优偏移 + 硬判决
    best_ber = 1;
    for d = 0:sps-1
        idx = d+1 : sps : length(filtered);
        n = min(length(idx), 200);
        rx_sym = filtered(idx(1:n));
        [bits_hard, ~] = qam_demodulate(rx_sym, 4, 'gray');
        b = sum(bits_hard ~= bits_in(1:length(bits_hard))) / length(bits_hard);
        if b < best_ber, best_ber = b; end
    end
    assert(best_ber < 0.15, 'QPSK全链路BER过高');

    fprintf('[通过] 5.1 QPSK全链路 | 200符号, 14bit DA/AD, BER=%.1f%%\n', best_ber*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 QPSK全链路 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.2 16QAM成形+匹配（无变频，纯基带，跳过边缘）
try
    rng(71);
    sps = 8; rolloff = 0.25; span = 6;
    bps = 4;                           % 16QAM = 4 bit/符号
    num_sym = 300;                     % 多生成一些，只检验中间段
    margin = span + 2;                 % 跳过首尾边缘符号数
    bits_in = randi([0 1], 1, num_sym * bps);

    % TX: 映射 → 成形
    [symbols, ~, ~] = qam_modulate(bits_in, 16, 'gray');
    [shaped, ~, ~] = pulse_shape(symbols, sps, 'rrc', rolloff, span);

    % RX: 匹配 → 取中间段 → AGC → 判决
    [filtered, ~] = match_filter(shaped, sps, 'rrc', rolloff, span);

    best_ber = 1;
    for d = 0:sps-1
        idx = d+1 : sps : length(filtered);
        n = min(length(idx), num_sym);
        if n <= 2*margin, continue; end

        % 取中间段，跳过边缘
        rx_sym = filtered(idx(margin+1 : n-margin));
        rx_sym = rx_sym / sqrt(mean(abs(rx_sym).^2));

        valid_bits_start = margin * bps + 1;
        valid_bits_end = (n - margin) * bps;
        bits_valid = bits_in(valid_bits_start : valid_bits_end);

        [bits_hard, ~] = qam_demodulate(rx_sym, 16, 'gray');
        b = sum(bits_hard ~= bits_valid) / length(bits_valid);
        if b < best_ber, best_ber = b; end
    end
    assert(best_ber == 0, '基带16QAM中间段BER应为0');

    fprintf('[通过] 5.2 16QAM基带回环 | 中间%d符号, BER=0\n', num_sym - 2*margin);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.2 16QAM基带回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.3 MFSK+FSK波形生成+频率检测回环
try
    rng(72);
    addpath(fullfile(proj_root, 'SpreadSpectrum', 'src', 'Matlab'));

    M = 4; f0 = 2000; spacing = 200; fs = 16000; dur = 0.02;
    bits_in = randi([0 1], 1, 40);     % 20个4-FSK符号

    % TX: MFSK映射 → FSK波形
    [freq_idx, ~, ~] = mfsk_modulate(bits_in, M, 'gray');
    [waveform, ~, freqs] = gen_fsk_waveform(freq_idx, M, f0, spacing, fs, dur);

    % RX: 逐符号FFT频率检测 → MFSK解映射
    samples_per_sym = round(dur * fs);
    detected_idx = zeros(1, 20);
    for s = 1:20
        seg = waveform((s-1)*samples_per_sym+1 : s*samples_per_sym);
        % 各频率的能量
        energies = zeros(1, M);
        for k = 1:M
            ref = cos(2*pi*freqs(k)*(0:samples_per_sym-1)/fs);
            energies(k) = abs(sum(seg .* ref))^2;
        end
        [~, best_k] = max(energies);
        detected_idx(s) = best_k - 1;
    end
    bits_out = mfsk_demodulate(detected_idx, M, 'gray');
    ber = sum(bits_out ~= bits_in) / length(bits_in);

    assert(ber == 0, 'MFSK+FSK波形回环解码错误');

    fprintf('[通过] 5.3 MFSK+FSK波形回环 | 4-FSK, 20符号, BER=0\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.3 MFSK+FSK波形回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.4 64QAM基带回环（高阶调制验证）
try
    rng(73);
    sps = 8; rolloff = 0.25; span = 6;
    bps = 6;                           % 64QAM = 6 bit/符号
    num_sym = 400;
    margin = span + 2;
    bits_in = randi([0 1], 1, num_sym * bps);

    % TX: 映射 → 成形
    [symbols, ~, ~] = qam_modulate(bits_in, 64, 'gray');
    [shaped, ~, ~] = pulse_shape(symbols, sps, 'rrc', rolloff, span);

    % RX: 匹配 → 取中间段 → AGC → 判决
    [filtered, ~] = match_filter(shaped, sps, 'rrc', rolloff, span);

    best_ber = 1;
    for d = 0:sps-1
        idx = d+1 : sps : length(filtered);
        n = min(length(idx), num_sym);
        if n <= 2*margin, continue; end

        rx_sym = filtered(idx(margin+1 : n-margin));
        rx_sym = rx_sym / sqrt(mean(abs(rx_sym).^2));

        valid_bits_start = margin * bps + 1;
        valid_bits_end = (n - margin) * bps;
        bits_valid = bits_in(valid_bits_start : valid_bits_end);

        [bits_hard, ~] = qam_demodulate(rx_sym, 64, 'gray');
        b = sum(bits_hard ~= bits_valid) / length(bits_valid);
        if b < best_ber, best_ber = b; end
    end
    assert(best_ber == 0, '基带64QAM中间段BER应为0');

    fprintf('[通过] 5.4 64QAM基带回环 | 中间%d符号, BER=0\n', num_sym - 2*margin);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.4 64QAM基带回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 六、异常输入 ==================== %%
fprintf('\n--- 6. 异常输入测试 ---\n\n');

try
    caught = 0;
    try pulse_shape([], 8); catch; caught=caught+1; end
    try match_filter([], 8); catch; caught=caught+1; end
    try upconvert([], 48000, 12000); catch; caught=caught+1; end
    try downconvert([], 48000, 12000); catch; caught=caught+1; end
    try gen_fsk_waveform([], 4); catch; caught=caught+1; end
    try da_convert([], 16); catch; caught=caught+1; end
    try ad_convert([], 16); catch; caught=caught+1; end

    assert(caught == 7, '部分函数未对空输入报错');

    fprintf('[通过] 6.1 空输入拒绝 | 7个函数均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 6.1 空输入 | %s\n', e.message);
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
