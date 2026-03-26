%% test_interleaving.m
% 功能：交织/解交织模块单元测试
% 版本：V1.0.0
% 测试对象：
%   block_interleave/deinterleave, random_interleave/deinterleave,
%   conv_interleave/deinterleave
%
% 运行方式：
%   在MATLAB命令行执行 >> run('test_interleaving.m')

clc; close all;
fprintf('========================================\n');
fprintf('  交织/解交织模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

%% ==================== 一、块交织测试 ==================== %%
fprintf('--- 1. 块交织器 ---\n\n');

%% 测试1.1：指定行列数回环
try
    data = 1:12;
    [intlv, nr, nc, pl] = block_interleave(data, 3, 4);
    deintlv = block_deinterleave(intlv, nr, nc, pl);

    assert(isequal(deintlv, data), '解交织结果不一致');
    assert(pl == 0, '无需补零时pad_len应为0');

    % 验证交织效果：按行写入[1 2 3 4; 5 6 7 8; 9 10 11 12]，按列读出
    expected = [1 5 9 2 6 10 3 7 11 4 8 12];
    assert(isequal(intlv, expected), '交织顺序不正确');

    fprintf('[通过] 1.1 指定行列(3x4)回环 | 交织序列=%s\n', num2str(intlv));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 指定行列回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.2：自动计算尺寸回环
try
    rng(1);
    data = randi([0 1], 1, 100);
    [intlv, nr, nc, pl] = block_interleave(data);
    deintlv = block_deinterleave(intlv, nr, nc, pl);

    assert(isequal(deintlv, data), '自动尺寸解交织失败');
    assert(nr * nc >= 100, '矩阵尺寸不足');

    fprintf('[通过] 1.2 自动尺寸(100元素) | %dx%d矩阵, 补零%d\n', nr, nc, pl);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 自动尺寸 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.3：仅指定行数
try
    data = 1:20;
    [intlv, nr, nc, pl] = block_interleave(data, 5);
    deintlv = block_deinterleave(intlv, nr, nc, pl);

    assert(isequal(deintlv, data), '仅指定行数解交织失败');
    assert(nr == 5, '行数应为5');

    fprintf('[通过] 1.3 仅指定行数=5 | 列数自动=%d, 补零%d\n', nc, pl);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.3 仅指定行数 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.4：需要补零的情况
try
    data = 1:10;
    [intlv, nr, nc, pl] = block_interleave(data, 4, 3);
    deintlv = block_deinterleave(intlv, nr, nc, pl);

    assert(isequal(deintlv, data), '补零后解交织不一致');
    assert(pl == 2, '10元素填4x3矩阵应补2个零');

    fprintf('[通过] 1.4 补零交织 | 10→4x3, 补零=%d\n', pl);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.4 补零交织 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试1.5：突发错误打散效果
try
    data = ones(1, 24);
    data(7:12) = 0;                    % 连续6位突发错误
    [intlv, nr, nc, pl] = block_interleave(data, 6, 4);

    % 交织后连续错误应被打散
    error_pos = find(intlv == 0);
    max_consecutive = max(diff([0, find(diff(error_pos) > 1), length(error_pos)]));

    assert(max_consecutive < 6, '交织后突发错误未被充分打散');

    fprintf('[通过] 1.5 突发错误打散 | 原始连续6位→交织后最大连续%d位\n', max_consecutive);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.5 突发错误打散 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、随机交织测试 ==================== %%
fprintf('\n--- 2. 随机交织器 ---\n\n');

%% 测试2.1：基本回环
try
    rng(10);
    data = randi([0 255], 1, 100);
    [intlv, perm] = random_interleave(data, 42);
    deintlv = random_deinterleave(intlv, perm);

    assert(isequal(deintlv, data), '随机交织解交织不一致');
    assert(~isequal(intlv, data), '交织后不应与原始相同');

    fprintf('[通过] 2.1 随机交织回环 | 100元素, seed=42\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 随机交织回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.2：seed确定性
try
    data = 1:50;
    [intlv1, perm1] = random_interleave(data, 99);
    [intlv2, perm2] = random_interleave(data, 99);
    [intlv3, ~] = random_interleave(data, 100);

    assert(isequal(intlv1, intlv2), '相同seed应产生相同结果');
    assert(isequal(perm1, perm2), '相同seed应产生相同置换');
    assert(~isequal(intlv1, intlv3), '不同seed应产生不同结果');

    fprintf('[通过] 2.2 seed确定性 | 相同seed→相同, 不同seed→不同\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.2 seed确定性 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.3：不污染全局随机状态
try
    rng(123);
    before = rand(1, 5);
    rng(123);
    [~, ~] = random_interleave(1:100, 0);
    after = rand(1, 5);

    assert(isequal(before, after), '交织器改变了全局随机状态');

    fprintf('[通过] 2.3 全局rng保护 | 调用前后随机序列一致\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.3 全局rng保护 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.4：置换为有效排列
try
    data = 1:200;
    [~, perm] = random_interleave(data, 7);

    assert(length(perm) == 200, '置换长度应为200');
    assert(isequal(sort(perm), 1:200), '置换应为1:N的排列');

    fprintf('[通过] 2.4 置换有效性 | 200元素排列验证\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.4 置换有效性 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试2.5：软值（实数）交织
try
    data = randn(1, 50);
    [intlv, perm] = random_interleave(data, 5);
    deintlv = random_deinterleave(intlv, perm);

    assert(max(abs(deintlv - data)) < 1e-12, '实数交织精度丢失');

    fprintf('[通过] 2.5 软值交织 | 浮点精度保持\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.5 软值交织 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、卷积交织测试 ==================== %%
fprintf('\n--- 3. 卷积交织器 ---\n\n');

%% 测试3.1：基本回环（含延迟对齐）
try
    data = 1:120;
    B = 4; M = 5;
    total_delay = (B-1) * M;          % 固定总延迟

    [intlv, ~, ~] = conv_interleave(data, B, M);
    deintlv = conv_deinterleave(intlv, B, M);

    % 卷积交织+解交织引入固定延迟，跳过过渡段后应一致
    valid_start = total_delay + 1;
    if valid_start <= length(data)
        data_valid = data(1:end - total_delay);
        deintlv_valid = deintlv(valid_start:end);
        assert(isequal(deintlv_valid, data_valid), '有效段解交织不一致');
    end

    fprintf('[通过] 3.1 卷积交织回环 | B=%d, M=%d, 总延迟=%d\n', B, M, total_delay);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 卷积交织回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试3.2：第1支路直通
try
    data = 1:24;
    B = 3; M = 4;
    [intlv, ~, ~] = conv_interleave(data, B, M);

    % 第1支路(idx=1,4,7,10,...)应直通：intlv(1)=data(1), intlv(4)=data(4)...
    direct_positions = 1:B:length(data);
    assert(isequal(intlv(direct_positions), data(direct_positions)), ...
           '第1支路应为直通');

    fprintf('[通过] 3.2 第1支路直通 | 位置%s处值不变\n', num2str(direct_positions(1:4)));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 第1支路直通 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试3.3：大数据量回环
try
    rng(20);
    data = randi([0 1], 1, 1000);
    B = 6; M = 12;
    total_delay = (B-1) * M;

    [intlv, ~, ~] = conv_interleave(data, B, M);
    deintlv = conv_deinterleave(intlv, B, M);

    data_valid = data(1:end - total_delay);
    deintlv_valid = deintlv(total_delay+1:end);
    assert(isequal(deintlv_valid, data_valid), '大数据量解交织不一致');

    fprintf('[通过] 3.3 大数据量(1000) | B=%d, M=%d, 有效段完全一致\n', B, M);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.3 大数据量 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试3.4：数据长度保持
try
    data = 1:50;
    [intlv, ~, ~] = conv_interleave(data, 5, 3);

    assert(length(intlv) == 50, '卷积交织不应改变数据长度');

    fprintf('[通过] 3.4 数据长度保持 | 输入50, 输出%d\n', length(intlv));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.4 数据长度保持 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、异常输入测试 ==================== %%
fprintf('\n--- 4. 异常输入测试 ---\n\n');

%% 测试4.1：空输入
try
    caught = 0;
    try block_interleave([]); catch; caught = caught+1; end
    try block_deinterleave([], 2, 2); catch; caught = caught+1; end
    try random_interleave([], 0); catch; caught = caught+1; end
    try random_deinterleave([], [1]); catch; caught = caught+1; end
    try conv_interleave([]); catch; caught = caught+1; end
    try conv_deinterleave([], 3, 4); catch; caught = caught+1; end

    assert(caught == 6, '部分函数未对空输入报错');

    fprintf('[通过] 4.1 空输入拒绝 | 6个函数均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 空输入拒绝 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 测试4.2：解交织参数不匹配
try
    caught = 0;
    try block_deinterleave(1:10, 3, 4, 0); catch; caught = caught+1; end  % 10≠3*4
    try random_deinterleave(1:5, [1 2 3]); catch; caught = caught+1; end  % 长度不匹配

    assert(caught == 2, '参数不匹配应报错');

    fprintf('[通过] 4.2 参数不匹配拒绝 | 块长度错误、置换长度错误均被捕获\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 参数不匹配 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、Turbo码集成验证 ==================== %%
fprintf('\n--- 5. Turbo码集成验证 ---\n\n');

%% 测试5.1：更新后的Turbo编解码回环
try
    rng(50);
    msg = randi([0 1], 1, 100);
    [coded, params] = turbo_encode(msg);

    soft_rx = 2*coded - 1;
    [decoded, ~] = turbo_decode(soft_rx, params, 20, 6);

    assert(isequal(decoded, msg), 'Turbo码更新后无噪声解码失败');

    fprintf('[通过] 5.1 Turbo集成验证 | 更新交织模块后回环正确\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 Turbo集成验证 | %s\n', e.message);
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
