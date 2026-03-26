%% test_source_coding.m
% 功能：信源编解码模块单元测试
% 版本：V1.0.0
% 测试对象：
%   huffman_encode, huffman_decode, uniform_quantize, uniform_dequantize
%
% 运行方式：
%   在MATLAB命令行执行 >> run('test_source_coding.m')

clc; close all;
fprintf('========================================\n');
fprintf('  信源编解码模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

%% ==================== 一、Huffman编码测试 ==================== %%
fprintf('--- 1. Huffman 编码/解码 ---\n\n');

%% 测试1.1：常规多符号编解码回环
try
    symbols_in = [0 1 1 2 2 2 3 3 3 3 4 4 4 4 4];
    [bitstream, codebook, cr] = huffman_encode(symbols_in);
    symbols_out = huffman_decode(bitstream, codebook, length(symbols_in));

    assert(isequal(symbols_out, symbols_in), '解码结果与原始不一致');
    assert(cr > 0, '压缩比应为正数');

    fprintf('[通过] 1.1 常规多符号回环 | 符号数=%d, 编码比特=%d, 压缩比=%.2f\n', ...
            length(symbols_in), length(bitstream), cr);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 常规多符号回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.2：单一符号序列
try
    symbols_in = [5 5 5 5 5];
    [bitstream, codebook, ~] = huffman_encode(symbols_in);
    symbols_out = huffman_decode(bitstream, codebook, length(symbols_in));

    assert(isequal(symbols_out, symbols_in), '单一符号解码失败');
    assert(length(codebook) == 1, '单一符号码本应只有1个条目');

    fprintf('[通过] 1.2 单一符号序列 | 码字=''%s''\n', codebook(1).code);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 单一符号序列 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.3：两符号等概率
try
    symbols_in = [0 1 0 1 0 1];
    [bitstream, codebook, ~] = huffman_encode(symbols_in);
    symbols_out = huffman_decode(bitstream, codebook, length(symbols_in));

    assert(isequal(symbols_out, symbols_in), '两符号解码失败');
    assert(all(cellfun(@length, {codebook.code}) == 1), '等概率两符号码字应各为1比特');

    fprintf('[通过] 1.3 两符号等概率 | 码字: %s→''%s'', %s→''%s''\n', ...
            num2str(codebook(1).symbol), codebook(1).code, ...
            num2str(codebook(2).symbol), codebook(2).code);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.3 两符号等概率 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.4：大规模随机数据回环
try
    rng(42);
    symbols_in = randi([0, 15], 1, 10000);
    [bitstream, codebook, cr] = huffman_encode(symbols_in);
    symbols_out = huffman_decode(bitstream, codebook, length(symbols_in));

    assert(isequal(symbols_out, symbols_in), '大规模数据解码不一致');

    fprintf('[通过] 1.4 大规模随机回环 | 10000符号, 16种符号, 压缩比=%.3f\n', cr);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.4 大规模随机回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.5：非均匀分布（验证压缩效果）
try
    rng(7);
    probs = [0.5, 0.25, 0.125, 0.0625, 0.0625];
    cum_probs = cumsum(probs);
    r = rand(1, 5000);
    symbols_in = zeros(1, 5000);
    for k = 1:5000
        symbols_in(k) = find(r(k) <= cum_probs, 1) - 1;
    end

    [bitstream, codebook, cr] = huffman_encode(symbols_in);
    symbols_out = huffman_decode(bitstream, codebook, length(symbols_in));

    % 理论熵
    H = -sum(probs .* log2(probs));
    avg_len = length(bitstream) / length(symbols_in);

    assert(isequal(symbols_out, symbols_in), '非均匀分布解码不一致');
    assert(avg_len < H + 1, '平均码长应小于 H+1');

    fprintf('[通过] 1.5 非均匀分布压缩 | 理论熵=%.3f, 平均码长=%.3f\n', H, avg_len);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.5 非均匀分布压缩 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.6：前缀码验证（无二义性）
try
    symbols_in = [0 1 2 3 4 5 6 7];
    [~, codebook, ~] = huffman_encode(symbols_in);
    codes = {codebook.code};

    % 验证无码字是另一个码字的前缀
    is_prefix_free = true;
    for i = 1:length(codes)
        for j = 1:length(codes)
            if i ~= j && strncmp(codes{i}, codes{j}, length(codes{i}))
                is_prefix_free = false;
            end
        end
    end
    assert(is_prefix_free, '码字不满足前缀码条件');

    fprintf('[通过] 1.6 前缀码验证 | %d个码字均满足前缀条件\n', length(codes));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.6 前缀码验证 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、均匀量化测试 ==================== %%
fprintf('\n--- 2. 均匀量化/反量化 ---\n\n');

%% 测试2.1：基本量化反量化回环
try
    signal_in = [-0.9, -0.5, 0.0, 0.3, 0.8];
    num_bits = 8;
    val_range = [-1, 1];

    [indices, levels, qsig] = uniform_quantize(signal_in, num_bits, val_range);
    signal_out = uniform_dequantize(indices, num_bits, val_range);

    % 量化误差应不超过半个步长
    delta = (val_range(2) - val_range(1)) / 2^num_bits;
    max_err = max(abs(signal_out - signal_in));

    assert(max_err <= delta / 2 + eps, '量化误差超过半步长');
    assert(isequal(qsig, signal_out), '量化信号与反量化结果应一致');

    fprintf('[通过] 2.1 基本回环 | 8bit, 最大误差=%.6f, 步长/2=%.6f\n', max_err, delta/2);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 基本回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.2：不同量化比特数
try
    signal_in = linspace(-1, 0.99, 1000);
    val_range = [-1, 1];
    all_ok = true;

    for nbits = [1, 2, 4, 8, 12, 16]
        [indices, ~, ~] = uniform_quantize(signal_in, nbits, val_range);
        signal_out = uniform_dequantize(indices, nbits, val_range);

        delta = 2 / 2^nbits;
        max_err = max(abs(signal_out - signal_in));

        if max_err > delta / 2 + 1e-10
            all_ok = false;
            fprintf('  %d-bit量化误差过大: %.6e > %.6e\n', nbits, max_err, delta/2);
        end
    end
    assert(all_ok, '某些比特数下量化误差超限');

    fprintf('[通过] 2.2 多比特数验证 | 1/2/4/8/12/16 bit 均通过\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.2 多比特数验证 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.3：信号截断（超出量化范围）
try
    signal_in = [-2.0, -1.5, 0.0, 1.5, 2.0];
    num_bits = 8;
    val_range = [-1, 1];

    % 应产生截断warning
    w = warning('off', 'all');
    [indices, ~, qsig] = uniform_quantize(signal_in, num_bits, val_range);
    warning(w);

    % 截断后量化值应在合法范围内
    assert(all(indices >= 0) && all(indices < 2^num_bits), '截断后索引越界');
    assert(all(qsig >= val_range(1)) && all(qsig <= val_range(2)), '截断后信号越界');

    fprintf('[通过] 2.3 信号截断 | 超范围样本被正确截断到 [%.1f, %.1f]\n', ...
            val_range(1), val_range(2));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.3 信号截断 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.4：量化级数验证
try
    num_bits = 4;
    val_range = [0, 16];
    L = 2^num_bits;                     % 应有16级

    [~, levels, ~] = uniform_quantize(linspace(0, 15.9, 100), num_bits, val_range);

    assert(length(levels) == L, '量化级数不等于 2^num_bits');
    assert(abs(levels(1) - 0.5) < 1e-10, '第一级量化电平应为0.5');
    assert(abs(levels(end) - 15.5) < 1e-10, '最后一级量化电平应为15.5');

    fprintf('[通过] 2.4 量化级数 | %d-bit → %d级, 电平范围 [%.1f, %.1f]\n', ...
            num_bits, L, levels(1), levels(end));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.4 量化级数 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.5：量化噪声功率验证
try
    rng(99);
    num_bits = 8;
    val_range = [-1, 1];
    delta = 2 / 2^num_bits;

    % 均匀分布信号，量化噪声理论功率 = delta^2 / 12
    signal_in = val_range(1) + (val_range(2) - val_range(1)) * rand(1, 100000);
    [indices, ~, ~] = uniform_quantize(signal_in, num_bits, val_range);
    signal_out = uniform_dequantize(indices, num_bits, val_range);

    noise_power = mean((signal_out - signal_in).^2);
    theory_power = delta^2 / 12;
    relative_err = abs(noise_power - theory_power) / theory_power;

    assert(relative_err < 0.05, '量化噪声功率偏离理论值超过5%%');

    fprintf('[通过] 2.5 量化噪声功率 | 实测=%.4e, 理论=%.4e, 相对误差=%.2f%%\n', ...
            noise_power, theory_power, relative_err * 100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.5 量化噪声功率 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、联合测试 ==================== %%
fprintf('\n--- 3. 联合流程测试 ---\n\n');

%% 测试3.1：量化 → Huffman编码 → 解码 → 反量化 全链路
try
    rng(123);
    % 模拟一段正弦信号
    t = (0:999) / 1000;
    signal_in = 0.8 * sin(2 * pi * 5 * t);

    % 发射端：量化 + Huffman编码
    num_bits = 8;
    val_range = [-1, 1];
    [indices_tx, ~, ~] = uniform_quantize(signal_in, num_bits, val_range);
    [bitstream, codebook, cr] = huffman_encode(indices_tx);

    % 接收端：Huffman解码 + 反量化
    indices_rx = huffman_decode(bitstream, codebook, length(indices_tx));
    signal_out = uniform_dequantize(indices_rx, num_bits, val_range);

    % 验证：量化索引完全一致（无损编码不应引入额外误差）
    assert(isequal(indices_rx, indices_tx), '全链路量化索引不一致');

    % 重建信号误差
    snr_db = 10 * log10(mean(signal_in.^2) / mean((signal_out - signal_in).^2));

    fprintf('[通过] 3.1 全链路回环 | 1000样本正弦, 压缩比=%.2f, 重建SNR=%.1f dB\n', ...
            cr, snr_db);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 全链路回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、异常输入测试 ==================== %%
fprintf('\n--- 4. 异常输入测试 ---\n\n');

%% 测试4.1：空输入
try
    caught = false;
    try
        huffman_encode([]);
    catch
        caught = true;
    end
    assert(caught, 'huffman_encode 应对空输入报错');

    caught = false;
    try
        uniform_quantize([], 8, [-1,1]);
    catch
        caught = true;
    end
    assert(caught, 'uniform_quantize 应对空输入报错');

    fprintf('[通过] 4.1 空输入拒绝 | 两个函数均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 空输入拒绝 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试4.2：非法参数
try
    caught = false;
    try
        uniform_quantize([1,2,3], -1, [-1,1]);   % 负比特数
    catch
        caught = true;
    end
    assert(caught, 'uniform_quantize 应对负比特数报错');

    caught = false;
    try
        uniform_quantize([1,2,3], 8, [1, -1]);   % 范围倒置
    catch
        caught = true;
    end
    assert(caught, 'uniform_quantize 应对范围倒置报错');

    caught = false;
    try
        uniform_dequantize([0, 256], 8, [-1,1]);  % 索引越界
    catch
        caught = true;
    end
    assert(caught, 'uniform_dequantize 应对索引越界报错');

    fprintf('[通过] 4.2 非法参数拒绝 | 负比特/范围倒置/索引越界 均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 非法参数拒绝 | %s\n', e.message);
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
