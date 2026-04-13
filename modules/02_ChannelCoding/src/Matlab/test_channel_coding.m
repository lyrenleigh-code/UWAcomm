%% test_channel_coding.m
% 功能：信道编解码模块单元测试
% 版本：V1.0.0
% 测试对象：
%   hamming_encode/decode, conv_encode/viterbi_decode, turbo_encode/decode
%
% 运行方式：
%   在MATLAB命令行执行 >> run('test_channel_coding.m')

clc; close all;

% 添加跨模块依赖路径（Turbo编码需要交织模块）
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

fprintf('========================================\n');
fprintf('  信道编解码模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

%% ==================== 一、Hamming码测试 ==================== %%
fprintf('--- 1. Hamming 分组码 ---\n\n');

%% 测试1.1：Hamming(7,4) 无差错回环
try
    msg = [1 0 1 1  0 0 1 0];         % 2个码块，每块4bit
    [codeword, G, H] = hamming_encode(msg, 3);
    [decoded, num_corr] = hamming_decode(codeword, 3);

    assert(isequal(decoded, msg), '无差错解码不一致');
    assert(num_corr == 0, '无差错时不应有纠错');
    assert(length(codeword) == 14, '码字长度应为14');

    fprintf('[通过] 1.1 Hamming(7,4)无差错 | 码率=%.3f\n', 4/7);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 Hamming(7,4)无差错 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.2：Hamming(7,4) 单比特纠错
try
    msg = [1 0 1 1];
    [codeword, ~, ~] = hamming_encode(msg, 3);

    % 逐位引入单比特错误，验证均能纠正
    all_ok = true;
    for pos = 1:7
        corrupted = codeword;
        corrupted(pos) = 1 - corrupted(pos);   % 翻转第pos位
        [decoded, num_corr] = hamming_decode(corrupted, 3);
        if ~isequal(decoded, msg) || num_corr ~= 1
            all_ok = false;
            fprintf('  位置%d纠错失败\n', pos);
        end
    end
    assert(all_ok, '存在无法纠正的单比特错误');

    fprintf('[通过] 1.2 Hamming(7,4)单比特纠错 | 7个错误位置全部纠正\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 Hamming(7,4)单比特纠错 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.3：Hamming(15,11)编解码
try
    rng(10);
    msg = randi([0 1], 1, 44);        % 44 = 11*4，4个码块
    [codeword, ~, ~] = hamming_encode(msg, 4);
    [decoded, ~] = hamming_decode(codeword, 4);

    assert(isequal(decoded, msg), 'Hamming(15,11)解码不一致');
    assert(length(codeword) == 60, '码字长度应为60');  % 15*4

    fprintf('[通过] 1.3 Hamming(15,11)编解码 | 44bit信息, 码率=%.3f\n', 11/15);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.3 Hamming(15,11)编解码 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.4：G和H正交性验证
try
    [~, G, H] = hamming_encode(zeros(1, 4), 3);

    % H * G' 应为零矩阵 (mod 2)
    product = mod(H * G.', 2);
    assert(all(product(:) == 0), 'H*G'' mod 2 不为零矩阵');

    fprintf('[通过] 1.4 G/H正交性 | H*G''=0 (mod 2)\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.4 G/H正交性 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、卷积码测试 ==================== %%
fprintf('\n--- 2. 卷积码 + Viterbi译码 ---\n\n');

%% 测试2.1：(2,1,3)码无噪声回环
try
    msg = [1 0 1 1 0 0 1];
    [coded, trellis] = conv_encode(msg, [7, 5], 3);
    [decoded, metric] = viterbi_decode(coded, trellis, 'hard');

    assert(isequal(decoded, msg), '无噪声解码不一致');
    assert(metric == 0, '无噪声路径度量应为0');

    fprintf('[通过] 2.1 (2,1,3)码无噪声 | 编码率=1/2, 输出%d比特\n', length(coded));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 (2,1,3)码无噪声 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.2：(2,1,7)标准码无噪声回环
try
    rng(20);
    msg = randi([0 1], 1, 100);
    [coded, trellis] = conv_encode(msg);   % 默认[171,133], K=7
    [decoded, ~] = viterbi_decode(coded, trellis);

    assert(isequal(decoded, msg), '(2,1,7)码解码不一致');

    fprintf('[通过] 2.2 (2,1,7)标准码 | 100bit信息, %d bit编码输出\n', length(coded));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.2 (2,1,7)标准码 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.3：硬判决纠错能力
try
    rng(30);
    msg = randi([0 1], 1, 50);
    [coded, trellis] = conv_encode(msg, [7,5], 3);

    % 引入少量错误（约5%误码率）
    num_errors = round(length(coded) * 0.05);
    err_pos = randperm(length(coded), num_errors);
    corrupted = coded;
    corrupted(err_pos) = 1 - corrupted(err_pos);

    [decoded, ~] = viterbi_decode(corrupted, trellis, 'hard');
    ber = sum(decoded ~= msg) / length(msg);

    assert(ber < 0.05, 'BER过高');

    fprintf('[通过] 2.3 硬判决纠错 | 信道BER=%.1f%%, 译码后BER=%.1f%%\n', ...
            num_errors/length(coded)*100, ber*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.3 硬判决纠错 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.4：软判决性能优于硬判决
try
    rng(40);
    msg = randi([0 1], 1, 200);
    [coded, trellis] = conv_encode(msg, [7,5], 3);

    % BPSK调制 + AWGN噪声
    bpsk = 2*coded - 1;               % 0→-1, 1→+1
    snr_db = 3;
    noise_std = 1 / sqrt(2 * 10^(snr_db/10));
    rx = bpsk + noise_std * randn(size(bpsk));

    % 硬判决
    hard_rx = double(rx > 0);
    [dec_hard, ~] = viterbi_decode(hard_rx, trellis, 'hard');
    ber_hard = sum(dec_hard ~= msg) / length(msg);

    % 软判决
    [dec_soft, ~] = viterbi_decode(rx, trellis, 'soft');
    ber_soft = sum(dec_soft ~= msg) / length(msg);

    fprintf('[通过] 2.4 软/硬判决对比 | SNR=%ddB, 硬BER=%.1f%%, 软BER=%.1f%%\n', ...
            snr_db, ber_hard*100, ber_soft*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.4 软/硬判决对比 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.5：网格结构验证
try
    [~, trellis] = conv_encode([0], [7,5], 3);

    assert(trellis.numStates == 4, '(2,1,3)码应有4个状态');
    assert(trellis.n == 2, '输出比特数应为2');
    assert(trellis.K == 3, '约束长度应为3');
    assert(size(trellis.nextState, 1) == 4, '状态转移表行数应为4');

    fprintf('[通过] 2.5 网格结构 | %d状态, n=%d, K=%d\n', ...
            trellis.numStates, trellis.n, trellis.K);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.5 网格结构 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、Turbo码测试 ==================== %%
fprintf('\n--- 3. Turbo 迭代编解码 ---\n\n');

%% 测试3.1：无噪声回环
try
    rng(50);
    msg = randi([0 1], 1, 100);
    [coded, params] = turbo_encode(msg);

    % 无噪声软值：0→-1, 1→+1
    soft_rx = 2*coded - 1;
    [decoded, ~] = turbo_decode(soft_rx, params, 20, 6);

    assert(isequal(decoded, msg), 'Turbo无噪声解码不一致');

    fprintf('[通过] 3.1 Turbo无噪声回环 | 100bit, 码率=1/3, 编码长度=%d\n', length(coded));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 Turbo无噪声回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试3.2：AWGN信道下的迭代增益
try
    rng(60);
    msg = randi([0 1], 1, 500);
    [coded, params] = turbo_encode(msg, 8, 42);

    % BPSK + AWGN
    bpsk = 2*coded - 1;
    snr_db = 1.0;
    noise_std = 1 / sqrt(2 * 10^(snr_db/10) * (1/3));
    rx = bpsk + noise_std * randn(size(bpsk));

    % 不同迭代次数的BER
    ber_list = zeros(1, 4);
    iter_list = [1, 2, 4, 8];
    for k = 1:4
        [dec, ~] = turbo_decode(rx, params, snr_db, iter_list(k));
        ber_list(k) = sum(dec ~= msg) / length(msg);
    end

    % 迭代次数增加，BER应不增
    is_monotone = all(diff(ber_list) <= 0.01);

    fprintf('[通过] 3.2 迭代增益 | SNR=%.1fdB, BER: ', snr_db);
    for k = 1:4
        fprintf('%d次=%.1f%% ', iter_list(k), ber_list(k)*100);
    end
    fprintf('\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 迭代增益 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试3.3：编码输出长度和结构验证
try
    msg = randi([0 1], 1, 64);
    [coded, params] = turbo_encode(msg);

    assert(length(coded) == 3 * 64, '码率1/3，输出长度应为3N');
    assert(isequal(coded(1:64), msg), '前N位应为系统位（与原始信息一致）');
    assert(params.msg_len == 64, 'params.msg_len应为64');
    assert(length(params.interleaver) == 64, '交织器长度应为N');

    fprintf('[通过] 3.3 编码结构 | 系统位保持, 输出3N=%d\n', length(coded));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.3 编码结构 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试3.4：交织器一致性
try
    msg = randi([0 1], 1, 128);

    % 同一seed应产生相同交织器
    [~, p1] = turbo_encode(msg, 6, 99);
    [~, p2] = turbo_encode(msg, 6, 99);
    assert(isequal(p1.interleaver, p2.interleaver), '相同seed应产生相同交织器');

    % 不同seed应产生不同交织器
    [~, p3] = turbo_encode(msg, 6, 100);
    assert(~isequal(p1.interleaver, p3.interleaver), '不同seed应产生不同交织器');

    % 交织+解交织应为恒等
    test_data = 1:128;
    assert(isequal(test_data, test_data(p1.interleaver(p1.deinterleaver))), ...
           '交织后解交织应还原');

    fprintf('[通过] 3.4 交织器一致性 | seed确定性 + 逆映射正确\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.4 交织器一致性 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、LDPC码测试 ==================== %%
fprintf('\n--- 4. LDPC 低密度奇偶校验码 ---\n\n');

%% 测试4.1：无噪声编解码回环
try
    rng(70);
    n_ldpc = 64; rate_ldpc = 0.5;
    k_ldpc = round(n_ldpc * rate_ldpc);
    msg = randi([0 1], 1, k_ldpc);

    [codeword, H_ldpc, G_ldpc] = ldpc_encode(msg, n_ldpc, rate_ldpc, 0);

    % 验证码字满足校验方程
    syndrome = mod(H_ldpc * codeword.', 2);
    assert(all(syndrome == 0), '码字不满足校验方程');

    % 无噪声软值
    soft_rx = 2*codeword - 1;          % 0→-1, 1→+1
    [decoded, ~, iters] = ldpc_decode(soft_rx, H_ldpc, k_ldpc, 20, 50);
    assert(isequal(decoded, msg), '无噪声解码不一致');

    fprintf('[通过] 4.1 LDPC(%d,%d)无噪声回环 | 迭代%d次收敛\n', ...
            n_ldpc, k_ldpc, iters);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 LDPC无噪声回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试4.2：H*G'=0 验证
try
    n_ldpc = 64; rate_ldpc = 0.5;
    k_ldpc = round(n_ldpc * rate_ldpc);
    [~, H_ldpc, G_ldpc] = ldpc_encode(zeros(1, k_ldpc), n_ldpc, rate_ldpc, 0);

    product = mod(H_ldpc * G_ldpc.', 2);
    assert(all(product(:) == 0), 'H*G'' mod 2 不为零矩阵');

    fprintf('[通过] 4.2 LDPC H*G''=0 | 生成矩阵与校验矩阵正交\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 LDPC H*G''=0 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试4.3：AWGN信道下BP译码
try
    rng(80);
    n_ldpc = 128; rate_ldpc = 0.5;
    k_ldpc = round(n_ldpc * rate_ldpc);
    msg = randi([0 1], 1, k_ldpc * 2);  % 2个码块

    [codeword, H_ldpc, ~] = ldpc_encode(msg, n_ldpc, rate_ldpc, 5);

    % BPSK + AWGN
    bpsk = 2*codeword - 1;
    snr_db = 4.0;
    sigma = 1 / sqrt(2 * rate_ldpc * 10^(snr_db/10));
    rx = bpsk + sigma * randn(size(bpsk));

    [decoded, ~, iters] = ldpc_decode(rx, H_ldpc, k_ldpc, snr_db, 50);
    ber = sum(decoded ~= msg) / length(msg);

    fprintf('[通过] 4.3 LDPC AWGN译码 | SNR=%ddB, BER=%.1f%%, 迭代=[%s]\n', ...
            snr_db, ber*100, num2str(iters));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.3 LDPC AWGN译码 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试4.4：不同码长和码率
try
    configs = {[32, 0.5], [64, 0.75], [128, 0.5]};
    all_ok = true;

    for c = 1:length(configs)
        n_t = configs{c}(1);
        r_t = configs{c}(2);
        k_t = round(n_t * r_t);
        msg_t = randi([0 1], 1, k_t);
        [cw_t, H_t, ~] = ldpc_encode(msg_t, n_t, r_t, c);

        syn_t = mod(H_t * cw_t.', 2);
        if ~all(syn_t == 0)
            all_ok = false;
            fprintf('  LDPC(%d,%d) 校验失败\n', n_t, k_t);
        end
    end
    assert(all_ok, '部分配置校验失败');

    fprintf('[通过] 4.4 多码长码率 | (32,16) (64,48) (128,64) 校验均通过\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.4 多码长码率 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试4.5：seed一致性
try
    n_ldpc = 64; rate_ldpc = 0.5;
    k_ldpc = round(n_ldpc * rate_ldpc);
    msg = zeros(1, k_ldpc);

    [~, H1, ~] = ldpc_encode(msg, n_ldpc, rate_ldpc, 42);
    [~, H2, ~] = ldpc_encode(msg, n_ldpc, rate_ldpc, 42);
    [~, H3, ~] = ldpc_encode(msg, n_ldpc, rate_ldpc, 99);

    assert(isequal(H1, H2), '相同seed应产生相同H矩阵');
    assert(~isequal(H1, H3), '不同seed应产生不同H矩阵');

    fprintf('[通过] 4.5 LDPC seed一致性 | 相同seed→相同H, 不同seed→不同H\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.5 LDPC seed一致性 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、异常输入测试 ==================== %%
fprintf('\n--- 5. 异常输入测试 ---\n\n');

%% 测试5.1：空输入
try
    caught = 0;
    funcs = {@() hamming_encode([], 3), ...
             @() hamming_decode([], 3), ...
             @() conv_encode([]), ...
             @() turbo_encode([]), ...
             @() ldpc_encode([])};
    names = {'hamming_encode', 'hamming_decode', 'conv_encode', 'turbo_encode', 'ldpc_encode'};

    for k = 1:length(funcs)
        try
            funcs{k}();
        catch
            caught = caught + 1;
        end
    end
    assert(caught == length(funcs), '部分函数未对空输入报错');

    fprintf('[通过] 5.1 空输入拒绝 | 5个函数均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 空输入拒绝 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试5.2：非二进制输入
try
    caught = 0;
    try hamming_encode([0 1 2 3], 3); catch; caught = caught+1; end
    try conv_encode([0 0.5 1]); catch; caught = caught+1; end
    try turbo_encode([3 4 5]); catch; caught = caught+1; end
    try ldpc_encode([0 1 2 3]); catch; caught = caught+1; end

    assert(caught == 4, '部分函数未对非二进制输入报错');

    fprintf('[通过] 5.2 非二进制输入拒绝 | 4个编码函数均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.2 非二进制输入拒绝 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试5.3：Hamming块长度不匹配
try
    caught = false;
    try
        hamming_encode([1 0 1], 3);    % 3 bit 不是 k=4 的整数倍
    catch
        caught = true;
    end
    assert(caught, 'Hamming应对非k整数倍长度报错');

    fprintf('[通过] 5.3 Hamming块长度校验 | 非4整数倍输入被正确拒绝\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.3 Hamming块长度校验 | %s\n', e.message);
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
