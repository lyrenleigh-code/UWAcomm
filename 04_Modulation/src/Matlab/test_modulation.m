%% test_modulation.m
% 功能：符号映射/判决模块单元测试
% 版本：V1.0.0
% 测试对象：
%   qam_modulate/demodulate, mfsk_modulate/demodulate, plot_constellation
%
% 运行方式：
%   在MATLAB命令行执行 >> run('test_modulation.m')

clc; close all;
fprintf('========================================\n');
fprintf('  符号映射/判决模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

%% ==================== 一、QAM无噪声回环 ==================== %%
fprintf('--- 1. QAM/PSK 无噪声回环 ---\n\n');

M_list = [2, 4, 8, 16, 64];
M_names = {'BPSK', 'QPSK', '8QAM', '16QAM', '64QAM'};

for idx = 1:length(M_list)
    M = M_list(idx);
    bps = log2(M);
    test_id = sprintf('1.%d', idx);

    try
        rng(idx);
        bits_in = randi([0 1], 1, bps * 200);
        [symbols, constellation, bit_map] = qam_modulate(bits_in, M, 'gray');
        [bits_out, ~] = qam_demodulate(symbols, M, 'gray');

        assert(isequal(bits_out, bits_in), '硬判决解调不一致');
        assert(length(symbols) == 200, '符号数应为200');
        assert(length(constellation) == M, '星座点数应为M');
        assert(abs(mean(abs(constellation).^2) - 1) < 1e-10, '平均功率应归一化为1');

        fprintf('[通过] %s %s Gray回环 | %d符号, 功率=%.4f\n', ...
                test_id, M_names{idx}, length(symbols), mean(abs(constellation).^2));
        pass_count = pass_count + 1;
    catch e
        fprintf('[失败] %s %s Gray回环 | %s\n', test_id, M_names{idx}, e.message);
        fail_count = fail_count + 1;
    end
end

%% ==================== 二、自然映射回环 ==================== %%
fprintf('\n--- 2. 自然映射回环 ---\n\n');

for idx = 1:length(M_list)
    M = M_list(idx);
    bps = log2(M);
    test_id = sprintf('2.%d', idx);

    try
        rng(idx + 10);
        bits_in = randi([0 1], 1, bps * 100);
        [symbols, ~, ~] = qam_modulate(bits_in, M, 'natural');
        [bits_out, ~] = qam_demodulate(symbols, M, 'natural');

        assert(isequal(bits_out, bits_in), 'natural映射解调不一致');

        fprintf('[通过] %s %s natural回环\n', test_id, M_names{idx});
        pass_count = pass_count + 1;
    catch e
        fprintf('[失败] %s %s natural回环 | %s\n', test_id, M_names{idx}, e.message);
        fail_count = fail_count + 1;
    end
end

%% ==================== 三、Gray映射特性 ==================== %%
fprintf('\n--- 3. Gray映射特性 ---\n\n');

%% 测试3.1：相邻星座点比特距离
try
    all_ok = true;
    for M = [4, 16, 64]
        [~, constellation, bit_map] = qam_modulate(zeros(1, log2(M)), M, 'gray');

        % 对每个星座点，找最近邻，检查汉明距离
        for k = 1:M
            dists = abs(constellation(k) - constellation).^2;
            dists(k) = inf;
            [~, nearest] = min(dists);
            hamming_dist = sum(bit_map(k,:) ~= bit_map(nearest,:));

            if hamming_dist ~= 1
                all_ok = false;
            end
        end
    end
    assert(all_ok, '存在最近邻汉明距离不为1的星座点');

    fprintf('[通过] 3.1 Gray最近邻汉明距离 | QPSK/16QAM/64QAM均为1\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 Gray最近邻汉明距离 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试3.2：比特映射唯一性
try
    all_ok = true;
    for M = [2, 4, 8, 16, 64]
        [~, ~, bit_map] = qam_modulate(zeros(1, log2(M)), M, 'gray');
        % 每行转为十进制，检查无重复
        vals = bi2de(bit_map, 'left-msb');
        if length(unique(vals)) ~= M
            all_ok = false;
        end
    end
    assert(all_ok, '存在重复的比特映射');

    fprintf('[通过] 3.2 比特映射唯一性 | 5种阶数全部无重复\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 比特映射唯一性 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、软判决LLR测试 ==================== %%
fprintf('\n--- 4. 软判决LLR ---\n\n');

%% 测试4.1：无噪声LLR符号正确
try
    rng(30);
    bits_in = randi([0 1], 1, 120);
    M = 16;
    [symbols, ~, ~] = qam_modulate(bits_in, M, 'gray');

    % 无噪声，极小方差
    [~, LLR] = qam_demodulate(symbols, M, 'gray', 1e-6);

    % LLR符号应与比特一致：bit=1→LLR>0, bit=0→LLR<0
    llr_sign = double(LLR > 0);
    assert(isequal(llr_sign, bits_in), 'LLR符号与原始比特不一致');

    fprintf('[通过] 4.1 无噪声LLR符号 | 16QAM, LLR符号完全匹配\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 无噪声LLR符号 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试4.2：AWGN下LLR硬判决与直接硬判决一致
try
    rng(40);
    M = 16;
    bits_in = randi([0 1], 1, 400);
    [symbols, ~, ~] = qam_modulate(bits_in, M, 'gray');

    noise_var = 0.1;
    noise = sqrt(noise_var/2) * (randn(size(symbols)) + 1j*randn(size(symbols)));
    rx = symbols + noise;

    [bits_hard, LLR] = qam_demodulate(rx, M, 'gray', noise_var);
    bits_soft = double(LLR > 0);

    assert(isequal(bits_hard, bits_soft), 'LLR硬判决应与最近邻硬判决一致');

    fprintf('[通过] 4.2 LLR硬判决一致性 | 16QAM, AWGN σ²=%.1f\n', noise_var);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 LLR硬判决一致性 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试4.3：不同SNR下LLR幅度趋势
try
    rng(50);
    M = 4;
    bits_in = randi([0 1], 1, 2000);
    [symbols, ~, ~] = qam_modulate(bits_in, M, 'gray');

    avg_llr = zeros(1, 3);
    snr_list = [0, 10, 20];
    for k = 1:3
        nv = 1 / (10^(snr_list(k)/10));
        noise = sqrt(nv/2) * (randn(size(symbols)) + 1j*randn(size(symbols)));
        [~, LLR] = qam_demodulate(symbols + noise, M, 'gray', nv);
        avg_llr(k) = mean(abs(LLR));
    end

    % SNR越高，LLR幅度越大（信心越高）
    assert(avg_llr(1) < avg_llr(2) && avg_llr(2) < avg_llr(3), ...
           'LLR幅度应随SNR增大');

    fprintf('[通过] 4.3 LLR幅度趋势 | SNR=%s dB → 平均|LLR|=%.1f/%.1f/%.1f\n', ...
            num2str(snr_list), avg_llr(1), avg_llr(2), avg_llr(3));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.3 LLR幅度趋势 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、MFSK测试 ==================== %%
fprintf('\n--- 5. MFSK ---\n\n');

%% 测试5.1：各阶数回环
M_fsk_list = [2, 4, 8, 16];
for idx = 1:length(M_fsk_list)
    M = M_fsk_list(idx);
    bps = log2(M);
    test_id = sprintf('5.%d', idx);

    try
        rng(idx + 20);
        bits_in = randi([0 1], 1, bps * 100);
        [freq_idx, ~, ~] = mfsk_modulate(bits_in, M, 'gray');
        bits_out = mfsk_demodulate(freq_idx, M, 'gray');

        assert(isequal(bits_out, bits_in), '解调不一致');
        assert(all(freq_idx >= 0) && all(freq_idx < M), '索引越界');

        fprintf('[通过] %s %d-FSK Gray回环 | %d符号, 索引范围[%d,%d]\n', ...
                test_id, M, length(freq_idx), min(freq_idx), max(freq_idx));
        pass_count = pass_count + 1;
    catch e
        fprintf('[失败] %s %d-FSK Gray回环 | %s\n', test_id, M, e.message);
        fail_count = fail_count + 1;
    end
end

%% 测试5.5：MFSK natural映射回环
try
    bits_in = randi([0 1], 1, 24);
    [freq_idx, ~, ~] = mfsk_modulate(bits_in, 8, 'natural');
    bits_out = mfsk_demodulate(freq_idx, 8, 'natural');

    assert(isequal(bits_out, bits_in), 'natural映射回环不一致');

    fprintf('[通过] 5.5 8-FSK natural回环\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.5 8-FSK natural回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 六、星座图绘制 ==================== %%
fprintf('\n--- 6. 星座图绘制 ---\n\n');

try
    rng(60);
    bits_test = randi([0 1], 1, 400);
    [sym_test, ~, ~] = qam_modulate(bits_test, 16, 'gray');
    noise = 0.15 * (randn(size(sym_test)) + 1j*randn(size(sym_test)));
    rx_test = sym_test + noise;

    plot_constellation(16, 'gray', rx_test);

    fprintf('[通过] 6.1 16QAM星座图绘制 | 含接收散点\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 6.1 星座图绘制 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 七、异常输入测试 ==================== %%
fprintf('\n--- 7. 异常输入测试 ---\n\n');

%% 测试7.1：空输入
try
    caught = 0;
    try qam_modulate([], 4); catch; caught = caught+1; end
    try qam_demodulate([], 4); catch; caught = caught+1; end
    try mfsk_modulate([], 4); catch; caught = caught+1; end
    try mfsk_demodulate([], 4); catch; caught = caught+1; end

    assert(caught == 4, '部分函数未对空输入报错');

    fprintf('[通过] 7.1 空输入拒绝 | 4个函数均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 7.1 空输入拒绝 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试7.2：非法M值
try
    caught = 0;
    try qam_modulate([0 1], 3); catch; caught = caught+1; end
    try qam_modulate([0 1], 32); catch; caught = caught+1; end

    assert(caught == 2, '非法M值应报错');

    fprintf('[通过] 7.2 非法M值拒绝 | M=3和M=32均被拒绝\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 7.2 非法M值 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试7.3：比特长度不匹配
try
    caught = false;
    try qam_modulate([0 1 0], 4); catch; caught = true; end

    assert(caught, '3bit不是log2(4)=2的整数倍，应报错');

    fprintf('[通过] 7.3 比特长度校验 | 3bit输入到QPSK被正确拒绝\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 7.3 比特长度校验 | %s\n', e.message);
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
