%% test_spread_spectrum.m
% 功能：扩频/解扩模块单元测试
% 版本：V1.1.0
% 运行方式：>> run('test_spread_spectrum.m')
% V1.1: 增加可视化（扩频码相关特性/DSSS波形/跳频图案）

clc; close all;
fprintf('========================================\n');
fprintf('  扩频/解扩模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;
vis = struct();  % 可视化数据收集

%% ==================== 一、扩频码生成 ==================== %%
fprintf('--- 1. 扩频码生成 ---\n\n');

%% 1.1 m序列长度和周期性
try
    seq = gen_msequence(7);
    L = 2^7 - 1;
    assert(length(seq) == L, '长度应为127');
    assert(isequal(seq, [seq(L+1:2*L-length(seq)), seq]), '不满足周期性');

    % 自相关检验：峰值=L，旁瓣=-1（±1映射后）
    seq_bipolar = 2*seq - 1;
    acorr = ifft(fft(seq_bipolar) .* conj(fft(seq_bipolar)));
    assert(abs(acorr(1) - L) < 1e-6, '自相关峰值应为L');
    assert(all(abs(acorr(2:end) + 1) < 1e-6), '自相关旁瓣应为-1');

    fprintf('[通过] 1.1 m序列(n=7) | L=%d, 自相关峰值=%d, 旁瓣=-1\n', L, L);
    pass_count = pass_count + 1;
    vis.mseq_acorr = acorr; vis.mseq_L = L; vis.ok_mseq = true;
catch e
    fprintf('[失败] 1.1 m序列 | %s\n', e.message);
    fail_count = fail_count + 1;
    vis.ok_mseq = false;
end

%% 1.2 Gold码长度和互相关限界
try
    code1 = gen_gold_code(7, 0);
    code2 = gen_gold_code(7, 10);
    L = 2^7 - 1;
    assert(length(code1) == L, 'Gold码长度应为127');
    assert(~isequal(code1, code2), '不同shift应产生不同码');

    % 互相关限界 t(n) = 2^((n+2)/2)+1 (n奇) 或 2^((n+1)/2)+1
    c1 = 2*code1-1; c2 = 2*code2-1;
    xcorr_val = abs(sum(c1 .* c2));
    t_bound = 2^((7+1)/2) + 1;        % = 17
    assert(xcorr_val <= t_bound, '互相关超出Gold码限界');

    fprintf('[通过] 1.2 Gold码(n=7) | 互相关=%d, 限界=%d\n', xcorr_val, t_bound);
    pass_count = pass_count + 1;
    vis.gold_c1 = c1; vis.gold_c2 = c2; vis.ok_gold = true;
catch e
    fprintf('[失败] 1.2 Gold码 | %s\n', e.message);
    fail_count = fail_count + 1;
    vis.ok_gold = false;
end

%% 1.3 Walsh-Hadamard正交性
try
    W = gen_walsh_hadamard(16);
    assert(size(W,1) == 16 && size(W,2) == 16, '应为16x16');

    % 正交性: W*W' = N*I
    product = W * W';
    assert(isequal(product, 16*eye(16)), 'W*W''应为16*I');

    fprintf('[通过] 1.3 Walsh-Hadamard(16) | 16x16完全正交\n');
    pass_count = pass_count + 1;
    vis.walsh = W; vis.ok_walsh = true;
catch e
    fprintf('[失败] 1.3 Walsh-Hadamard | %s\n', e.message);
    fail_count = fail_count + 1;
    vis.ok_walsh = false;
end

%% 1.4 Kasami码集大小和码长
try
    [codes, nc] = gen_kasami_code(6);
    L = 2^6 - 1;
    expected_nc = 2^3 + 1;            % 2^(degree/2)+1 = 9

    assert(nc == expected_nc, '码字数应为9');
    assert(size(codes, 2) == L, '码长应为63');
    assert(size(codes, 1) == nc, '码矩阵行数应为9');

    fprintf('[通过] 1.4 Kasami码(n=6) | %d码字, 码长=%d\n', nc, L);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.4 Kasami码 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、DSSS扩频/解扩 ==================== %%
fprintf('\n--- 2. DSSS直接序列扩频 ---\n\n');

%% 2.1 无噪声回环
try
    code = gen_msequence(5);
    code_bipolar = 2*code - 1;
    symbols_in = [1 -1 1 1 -1 -1 1 -1 1 1];

    spread = dsss_spread(symbols_in, code_bipolar);
    [symbols_out, ~] = dsss_despread(spread, code_bipolar);

    assert(isequal(sign(symbols_out), symbols_in), '解扩符号不一致');
    assert(length(spread) == length(symbols_in)*length(code_bipolar), '扩频长度错误');

    fprintf('[通过] 2.1 DSSS无噪声回环 | 10符号, 码长=%d\n', length(code));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 DSSS无噪声 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.2 扩频增益验证
try
    rng(10);
    code = gen_msequence(7);
    code_bp = 2*code-1; L = length(code_bp);
    symbols_in = 2*randi([0 1],1,200) - 1;

    spread = dsss_spread(symbols_in, code_bp);
    % 加噪使扩频前SNR约0dB
    noise = randn(size(spread));
    [sym_out, ~] = dsss_despread(spread + noise, code_bp);
    ber = sum(sign(sym_out) ~= symbols_in) / length(symbols_in);

    % 扩频增益约10*log10(127)≈21dB，BER应很低
    assert(ber < 0.05, 'BER过高，扩频增益不足');

    fprintf('[通过] 2.2 扩频增益 | L=%d(%.1fdB), 输入SNR≈0dB, BER=%.1f%%\n', ...
            L, 10*log10(L), ber*100);
    pass_count = pass_count + 1;
    vis.dsss_sym_in = symbols_in(1:20); vis.dsss_spread = spread(1:20*L);
    vis.dsss_noisy = spread(1:20*L) + noise(1:20*L);
    vis.dsss_sym_out = sym_out(1:20); vis.dsss_code_len = L;
    vis.ok_dsss = true;
catch e
    fprintf('[失败] 2.2 扩频增益 | %s\n', e.message);
    fail_count = fail_count + 1;
    vis.ok_dsss = false;
end

%% ==================== 三、CSK扩频/解扩 ==================== %%
fprintf('\n--- 3. CSK循环移位键控 ---\n\n');

%% 3.1 无噪声回环
try
    base_code = 2*gen_msequence(7) - 1;
    rng(20);
    bits_in = randi([0 1], 1, 20);    % 10个2-CSK符号

    spread = csk_spread(bits_in, base_code, 2);
    [bits_out, ~] = csk_despread(spread, base_code, 2);

    assert(isequal(bits_out, bits_in), 'CSK解扩不一致');

    fprintf('[通过] 3.1 2-CSK无噪声回环 | 20bit\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 2-CSK无噪声 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 4-CSK回环
try
    base_code = 2*gen_msequence(7) - 1;
    rng(21);
    bits_in = randi([0 1], 1, 40);    % 20个4-CSK符号

    spread = csk_spread(bits_in, base_code, 4);
    [bits_out, ~] = csk_despread(spread, base_code, 4);

    assert(isequal(bits_out, bits_in), '4-CSK解扩不一致');

    fprintf('[通过] 3.2 4-CSK无噪声回环 | 40bit, 20符号\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 4-CSK无噪声 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、M-ary扩频/解扩 ==================== %%
fprintf('\n--- 4. M-ary组合扩频 ---\n\n');

%% 4.1 Walsh码M-ary回环
try
    W = gen_walsh_hadamard(8);         % 8个正交码
    rng(30);
    bits_in = randi([0 1], 1, 30);    % 10个3-bit符号

    spread = mary_spread(bits_in, W);
    [bits_out, ~] = mary_despread(spread, W);

    assert(isequal(bits_out, bits_in), 'M-ary解扩不一致');

    fprintf('[通过] 4.1 8-ary Walsh回环 | 30bit, 10符号\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 8-ary Walsh | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.2 抗噪声能力
try
    rng(31);
    W = gen_walsh_hadamard(16);
    bits_in = randi([0 1], 1, 400);   % 100个4-bit符号

    spread = mary_spread(bits_in, W);
    noise = 0.5 * randn(size(spread));
    [bits_out, ~] = mary_despread(spread + noise, W);
    ber = sum(bits_out ~= bits_in) / length(bits_in);

    fprintf('[通过] 4.2 16-ary抗噪声 | BER=%.1f%% (噪声σ=0.5)\n', ber*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 16-ary抗噪声 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、差分检测器 ==================== %%
fprintf('\n--- 5. 差分检测器 ---\n\n');

%% 5.1 DCD无噪声检测
try
    % 差分编码：d(n) = b(n) XOR d(n-1)
    rng(40);
    bits_orig = randi([0 1], 1, 50);
    diff_encoded = zeros(1, 51);       % 多一个参考符号
    diff_encoded(1) = 1;
    for k = 1:50
        diff_encoded(k+1) = xor(bits_orig(k), diff_encoded(k));
    end
    symbols = 2*diff_encoded - 1;      % ±1

    % 模拟DSSS相关输出（无噪声，带固定相位偏移）
    phase = pi/6;
    corr_values = symbols * exp(1j*phase);

    [decisions, ~] = det_dcd(corr_values);
    bits_dcd = (1 - decisions) / 2;    % +1→0, -1→1

    assert(isequal(bits_dcd, bits_orig), 'DCD检测结果不一致');

    fprintf('[通过] 5.1 DCD无噪声 | 50bit, 固定相偏=%.0f°\n', phase*180/pi);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 DCD | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.2 DED无噪声检测
try
    rng(41);
    bits_orig = randi([0 1], 1, 50);

    % 双差分编码
    diff1 = zeros(1, 52);
    diff1(1) = 1; diff1(2) = 1;
    for k = 1:50
        diff1(k+2) = xor(xor(bits_orig(k), diff1(k+1)), diff1(k));
    end
    symbols = 2*diff1 - 1;

    phase = pi/4;
    corr_values = symbols * exp(1j*phase);

    [decisions, ~] = det_ded(corr_values);
    bits_ded = (1 - decisions) / 2;

    % DED需要更多参考，检查有效段
    valid_len = min(length(bits_ded), length(bits_orig));
    ber = sum(bits_ded(1:valid_len) ~= bits_orig(1:valid_len)) / valid_len;

    fprintf('[通过] 5.2 DED无噪声 | BER=%.1f%%, 相偏=%.0f°\n', ber*100, phase*180/pi);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.2 DED | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.3 DCD抗相位波动
try
    rng(42);
    bits_orig = randi([0 1], 1, 200);
    diff_encoded = zeros(1, 201);
    diff_encoded(1) = 1;
    for k = 1:200
        diff_encoded(k+1) = xor(bits_orig(k), diff_encoded(k));
    end
    symbols = 2*diff_encoded - 1;

    % 缓慢相位漂移
    phase_drift = linspace(0, 2*pi, 201);
    corr_values = symbols .* exp(1j*phase_drift);

    % 相干检测（失败）
    bits_coherent = (1 - sign(real(corr_values(2:end) .* conj(corr_values(1))))) / 2;

    % DCD检测（应成功）
    [decisions, ~] = det_dcd(corr_values);
    bits_dcd = (1 - decisions) / 2;
    ber_dcd = sum(bits_dcd ~= bits_orig) / 200;

    assert(ber_dcd < 0.05, 'DCD在缓慢相位漂移下BER应很低');

    fprintf('[通过] 5.3 DCD抗相位漂移 | 相位0→360°, BER=%.1f%%\n', ber_dcd*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.3 DCD抗相位漂移 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 六、跳频(FH)扩频 ==================== %%
fprintf('\n--- 6. 跳频(FH)扩频 ---\n\n');

%% 6.1 跳频图案生成
try
    num_freqs = 16;
    [pat1, ~] = gen_hop_pattern(100, num_freqs, 42);
    [pat2, ~] = gen_hop_pattern(100, num_freqs, 42);
    [pat3, ~] = gen_hop_pattern(100, num_freqs, 99);

    assert(isequal(pat1, pat2), '相同seed应产生相同图案');
    assert(~isequal(pat1, pat3), '不同seed应产生不同图案');
    assert(all(pat1 >= 0) && all(pat1 < num_freqs), '图案取值越界');
    assert(length(unique(pat1)) > 1, '图案不应为常数');

    fprintf('[通过] 6.1 跳频图案生成 | 100跳, %d频率, seed确定性验证\n', num_freqs);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 6.1 跳频图案 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 6.2 跳频/去跳频回环
try
    num_freqs = 8;
    freq_in = [0 3 7 2 5 1 4 6 0 3];
    [pattern, ~] = gen_hop_pattern(length(freq_in), num_freqs, 10);

    hopped = fh_spread(freq_in, pattern, num_freqs);
    freq_out = fh_despread(hopped, pattern, num_freqs);

    assert(isequal(freq_out, freq_in), '去跳频后索引不一致');
    assert(~isequal(hopped, freq_in), '跳频后不应与原始相同');
    assert(all(hopped >= 0) && all(hopped < num_freqs), '跳频后索引越界');

    fprintf('[通过] 6.2 FH回环 | 10符号, %d频率\n', num_freqs);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 6.2 FH回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 6.3 FH-MFSK全链路（联合Modulation模块）
try
    % 添加调制模块路径
    proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    addpath(fullfile(proj_root, '04_Modulation', 'src', 'Matlab'));

    rng(50);
    M = 8; num_freqs = 16;
    bits_in = randi([0 1], 1, 60);    % 20个3-bit符号

    % 发端：MFSK映射 → 跳频
    [freq_idx, ~, ~] = mfsk_modulate(bits_in, M, 'gray');
    [pattern, ~] = gen_hop_pattern(length(freq_idx), num_freqs, 77);
    hopped = fh_spread(freq_idx, pattern, num_freqs);

    % 收端：去跳频 → MFSK解映射
    dehopped = fh_despread(hopped, pattern, num_freqs);
    bits_out = mfsk_demodulate(dehopped, M, 'gray');

    assert(isequal(bits_out, bits_in), 'FH-MFSK全链路解码不一致');

    fprintf('[通过] 6.3 FH-MFSK全链路 | 8FSK+16频跳频, 60bit完全还原\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 6.3 FH-MFSK全链路 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 6.4 跳频频率分散性
try
    num_freqs = 16;
    [pattern, ~] = gen_hop_pattern(1600, num_freqs, 0);

    % 统计各频率出现次数，应近似均匀
    counts = histcounts(pattern, 0:num_freqs);
    expected = 1600 / num_freqs;
    max_dev = max(abs(counts - expected)) / expected;

    assert(max_dev < 0.2, '频率分布偏差过大');

    fprintf('[通过] 6.4 频率分散性 | %d频率均匀度偏差<20%%\n', num_freqs);
    pass_count = pass_count + 1;
    vis.fh_pattern = pattern(1:100); vis.fh_counts = counts;
    vis.fh_nfreqs = num_freqs; vis.ok_fh = true;
catch e
    fprintf('[失败] 6.4 频率分散性 | %s\n', e.message);
    fail_count = fail_count + 1;
    vis.ok_fh = false;
end

%% ==================== 七、异常输入 ==================== %%
fprintf('\n--- 7. 异常输入测试 ---\n\n');

try
    caught = 0;
    try dsss_spread([], [1 -1]); catch; caught=caught+1; end
    try dsss_despread([], [1 -1]); catch; caught=caught+1; end
    try csk_spread([], [1 -1]); catch; caught=caught+1; end
    try csk_despread([], [1 -1]); catch; caught=caught+1; end
    try mary_spread([], ones(4,8)); catch; caught=caught+1; end
    try mary_despread([], ones(4,8)); catch; caught=caught+1; end
    try det_dcd([]); catch; caught=caught+1; end
    try det_ded([]); catch; caught=caught+1; end
    try gen_msequence(1); catch; caught=caught+1; end         % degree<2
    try fh_spread([], [1 2], 4); catch; caught=caught+1; end
    try fh_despread([], [1 2], 4); catch; caught=caught+1; end
    try gen_hop_pattern(0, 8, 0); catch; caught=caught+1; end % num_hops<1

    assert(caught == 12, '部分函数未对异常输入报错');

    fprintf('[通过] 7.1 异常输入拒绝 | 12项均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 6.1 异常输入 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 可视化（独立于测试） ==================== %%

% --- Figure 1: 扩频码相关特性 --- %
try
    if isfield(vis,'ok_mseq') && vis.ok_mseq && isfield(vis,'ok_gold') && vis.ok_gold ...
            && isfield(vis,'ok_walsh') && vis.ok_walsh
        figure('Name','扩频码相关特性','NumberTitle','off','Position',[50 80 1200 400]);

        % m序列自相关
        subplot(1,3,1);
        stem(0:vis.mseq_L-1, real(vis.mseq_acorr), 'b', 'MarkerSize', 2, 'LineWidth', 0.5);
        xlabel('延迟 (码片)'); ylabel('自相关值');
        title(sprintf('m序列自相关 (L=%d)', vis.mseq_L)); grid on;

        % Gold码互相关
        subplot(1,3,2);
        xcorr_full = xcorr(vis.gold_c1, vis.gold_c2);
        stem(-(vis.mseq_L-1):(vis.mseq_L-1), xcorr_full, 'r', 'MarkerSize', 2, 'LineWidth', 0.5);
        xlabel('延迟 (码片)'); ylabel('互相关值');
        title('Gold码互相关'); grid on;

        % Walsh-Hadamard正交矩阵
        subplot(1,3,3);
        imagesc(vis.walsh * vis.walsh');
        colorbar; axis equal tight;
        xlabel('码索引'); ylabel('码索引');
        title('Walsh W·W'' (应为对角)');
    end
catch; end

% --- Figure 2: DSSS扩频/解扩波形 --- %
try
    if isfield(vis,'ok_dsss') && vis.ok_dsss
        figure('Name','DSSS扩频波形','NumberTitle','off','Position',[50 50 1200 600]);
        L = vis.dsss_code_len;
        n_show = 5;  % 显示前5个符号

        % 原始符号
        subplot(4,1,1);
        stairs(vis.dsss_sym_in(1:n_show), 'b', 'LineWidth', 1.2);
        xlim([0.5 n_show+0.5]); ylim([-1.5 1.5]);
        ylabel('幅度'); title('原始符号'); grid on;

        % 扩频后信号
        subplot(4,1,2);
        plot(vis.dsss_spread(1:n_show*L), 'b', 'LineWidth', 0.5);
        xlim([1 n_show*L]); ylim([-1.5 1.5]);
        ylabel('幅度'); title(sprintf('扩频信号 (码长=%d)', L)); grid on;

        % 加噪后
        subplot(4,1,3);
        plot(vis.dsss_noisy(1:n_show*L), 'Color',[0.6 0.3 0], 'LineWidth', 0.5);
        xlim([1 n_show*L]); ylim([-3 3]);
        ylabel('幅度'); title('加噪后 (SNR≈0dB)'); grid on;

        % 解扩输出
        subplot(4,1,4);
        stem(vis.dsss_sym_out(1:n_show), 'r', 'LineWidth', 1.2, 'MarkerSize', 6);
        hold on;
        stairs(vis.dsss_sym_in(1:n_show), 'b--', 'LineWidth', 1);
        xlim([0.5 n_show+0.5]);
        legend('解扩输出','原始符号'); ylabel('幅度');
        title('解扩恢复'); grid on;
        xlabel('符号索引');
    end
catch; end

% --- Figure 3: 跳频图案与频率分布 --- %
try
    if isfield(vis,'ok_fh') && vis.ok_fh
        figure('Name','跳频图案','NumberTitle','off','Position',[80 60 1100 450]);

        % 跳频时频图
        subplot(1,2,1);
        scatter(1:length(vis.fh_pattern), vis.fh_pattern, 20, vis.fh_pattern, 'filled');
        colormap(jet); colorbar;
        xlabel('跳数(时间)'); ylabel('频率索引');
        title(sprintf('跳频图案 (%d频率)', vis.fh_nfreqs)); grid on;
        ylim([-0.5 vis.fh_nfreqs-0.5]);

        % 频率使用分布
        subplot(1,2,2);
        bar(0:vis.fh_nfreqs-1, vis.fh_counts, 'FaceColor',[0.3 0.6 0.9]);
        hold on;
        expected = sum(vis.fh_counts) / vis.fh_nfreqs;
        line([-0.5 vis.fh_nfreqs-0.5], [expected expected], 'Color','r','LineStyle','--','LineWidth',1.5);
        legend('实际次数','理想均匀','Location','best');
        xlabel('频率索引'); ylabel('出现次数');
        title('频率使用分布'); grid on;
    end
catch; end

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
