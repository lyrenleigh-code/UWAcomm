%% test_multicarrier.m
% 功能：多载波/多域变换模块单元测试
% 版本：V1.0.0
% 运行方式：>> run('test_multicarrier.m')

clc; close all;
fprintf('========================================\n');
fprintf('  多载波/多域变换模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

%% ==================== 一、OFDM ==================== %%
fprintf('--- 1. OFDM调制/解调 ---\n\n');

%% 1.1 CP-OFDM无噪声回环
try
    rng(10);
    N = 64; cp_len = 16;
    data = randn(1, N*10) + 1j*randn(1, N*10);  % 10个OFDM符号

    [signal, params] = ofdm_modulate(data, N, cp_len, 'cp');
    recovered = ofdm_demodulate(signal, N, cp_len, 'cp');

    err = max(abs(recovered - data));
    assert(err < 1e-10, 'CP-OFDM回环误差过大');
    assert(params.num_symbols == 10, '符号数应为10');

    fprintf('[通过] 1.1 CP-OFDM回环 | 10符号, N=%d, CP=%d, 误差=%.2e\n', N, cp_len, err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 CP-OFDM | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.2 ZP-OFDM无噪声回环
try
    rng(11);
    N = 64; cp_len = 16;
    data = randn(1, N*5) + 1j*randn(1, N*5);

    [signal, ~] = ofdm_modulate(data, N, cp_len, 'zp');
    recovered = ofdm_demodulate(signal, N, cp_len, 'zp');

    err = max(abs(recovered - data));
    assert(err < 1e-10, 'ZP-OFDM回环误差过大');

    fprintf('[通过] 1.2 ZP-OFDM回环 | 5符号, 误差=%.2e\n', err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 ZP-OFDM | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.3 导频插入/提取回环
try
    rng(12);
    N = 64;
    data = randn(1, 200) + 1j*randn(1, 200);

    [with_pilot, p_idx, d_idx] = ofdm_pilot_insert(data, N, 'comb_4', 1+1j);
    [data_rx, pilot_rx, ~, ~] = ofdm_pilot_extract(with_pilot, N, 'comb_4');

    % 导频值应为插入的值
    assert(all(abs(pilot_rx(:) - (1+1j)) < 1e-10), '导频值不一致');
    % 数据回环
    min_len = min(length(data_rx), length(data));
    assert(max(abs(data_rx(1:min_len) - data(1:min_len))) < 1e-10, '导频模式下数据不一致');

    fprintf('[通过] 1.3 导频插入/提取 | comb_4, %d导频/符号, %d数据/符号\n', ...
            length(p_idx), length(d_idx));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.3 导频 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.4 离散导频(scattered)插入/提取回环
try
    rng(13);
    N = 64;
    data = randn(1, 200) + 1j*randn(1, 200);

    [with_pilot, p_idx, d_idx] = ofdm_pilot_insert(data, N, 'scattered_4', 1);
    [data_rx, pilot_rx, ~, ~] = ofdm_pilot_extract(with_pilot, N, 'scattered_4');

    % 导频值均为1
    assert(all(abs(pilot_rx(:) - 1) < 1e-10), '离散导频值不一致');
    % 数据回环
    min_len = min(length(data_rx), length(data));
    assert(max(abs(data_rx(1:min_len) - data(1:min_len))) < 1e-10, '离散导频数据不一致');

    % 验证不同符号导频位置不同
    sym1_pilots = find(abs(with_pilot(1:N) - 1) < 1e-10);
    sym2_pilots = find(abs(with_pilot(N+1:2*N) - 1) < 1e-10);
    assert(~isequal(sym1_pilots, sym2_pilots), '离散导频各符号位置应不同');

    fprintf('[通过] 1.4 离散导频回环 | scattered_4, 各符号导频位置交错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.4 离散导频 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、SC-FDE ==================== %%
fprintf('\n--- 2. SC-FDE分块CP ---\n\n');

%% 2.1 SC-FDE加CP/去CP回环
try
    rng(20);
    block_size = 128; cp_len = 32;
    data = randn(1, 500) + 1j*randn(1, 500);

    [signal, params] = scfde_add_cp(data, block_size, cp_len);
    [freq_blocks, time_blocks] = scfde_remove_cp(signal, block_size, cp_len);

    % 时域块还原（含补零）
    data_padded = [data, zeros(1, params.pad_len)];
    for b = 1:params.num_blocks
        orig_block = data_padded((b-1)*block_size+1 : b*block_size);
        err = max(abs(time_blocks(b,:) - orig_block));
        assert(err < 1e-10, sprintf('第%d块时域不一致', b));
    end

    % 频域块验证：FFT(时域块) == freq_blocks
    for b = 1:params.num_blocks
        fft_check = fft(time_blocks(b,:), block_size);
        assert(max(abs(freq_blocks(b,:) - fft_check)) < 1e-10, 'FFT不一致');
    end

    fprintf('[通过] 2.1 SC-FDE CP回环 | %d块, 块大小=%d, CP=%d\n', ...
            params.num_blocks, block_size, cp_len);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 SC-FDE CP | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、OTFS ==================== %%
fprintf('\n--- 3. OTFS调制/解调 ---\n\n');

%% 3.1 DFT方法回环
try
    rng(30);
    N = 8; M = 32;
    dd_data = randn(N, M) + 1j*randn(N, M);

    [signal, params] = otfs_modulate(dd_data, N, M, M/4, 'dft');
    [dd_rx, ~] = otfs_demodulate(signal, N, M, M/4, 'dft');

    err = max(abs(dd_rx(:) - dd_data(:)));
    assert(err < 1e-8, 'OTFS DFT方法回环误差过大');

    fprintf('[通过] 3.1 OTFS DFT回环 | N=%d, M=%d, 误差=%.2e\n', N, M, err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 OTFS DFT | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 Zak方法回环
try
    rng(31);
    N = 8; M = 32;
    dd_data = randn(N, M) + 1j*randn(N, M);

    [signal, ~] = otfs_modulate(dd_data, N, M, M/4, 'zak');
    [dd_rx, ~] = otfs_demodulate(signal, N, M, M/4, 'zak');

    err = max(abs(dd_rx(:) - dd_data(:)));
    assert(err < 1e-8, 'OTFS Zak方法回环误差过大');

    fprintf('[通过] 3.2 OTFS Zak回环 | 误差=%.2e\n', err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 OTFS Zak | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.3 DFT与Zak两种方法输出一致性
try
    rng(32);
    N = 8; M = 16;
    dd_data = randn(N, M) + 1j*randn(N, M);

    [sig_dft, p_dft] = otfs_modulate(dd_data, N, M, 0, 'dft');
    [sig_zak, p_zak] = otfs_modulate(dd_data, N, M, 0, 'zak');

    err = max(abs(sig_dft - sig_zak));
    assert(err < 1e-8, 'DFT和Zak方法输出不一致');

    fprintf('[通过] 3.3 DFT/Zak一致性 | 最大差异=%.2e\n', err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.3 DFT/Zak一致性 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.4 DD域导频嵌入/提取
try
    rng(33);
    N = 8; M = 32;
    config = struct('pilot_k',4, 'pilot_l',16, 'pilot_value',sqrt(N*M), 'guard_k',2, 'guard_l',3);
    [data_idx, guard, num_data] = otfs_get_data_indices(N, M, config);

    data = randn(1, num_data) + 1j*randn(1, num_data);
    [dd_frame, pilot_pos, ~, ~] = otfs_pilot_embed(data, N, M, config);

    % 导频位置值正确
    assert(abs(dd_frame(4,16) - sqrt(N*M)) < 1e-10, '导频值不正确');
    % 数据位置值正确
    assert(max(abs(dd_frame(data_idx) - data.')) < 1e-10, '数据值不正确');
    % 保护区为零（除导频外）
    guard_no_pilot = guard; guard_no_pilot(4,16) = false;
    assert(all(abs(dd_frame(guard_no_pilot)) < 1e-10), '保护区应为零');

    fprintf('[通过] 3.4 DD域导频 | 导频@(%d,%d), 保护区(%dx%d), 数据格点=%d\n', ...
            pilot_pos(1), pilot_pos(2), 2*config.guard_k+1, 2*config.guard_l+1, num_data);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.4 DD域导频 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.5 多脉冲导频
try
    rng(34);
    N = 8; M = 32;
    positions = [2,8; 2,24; 6,8; 6,24];
    cfg = struct('mode','multi_pulse','pilot_positions',positions,'guard_k',1,'guard_l',2,'pilot_value',2);
    [didx, ~, ndata] = otfs_get_data_indices(N, M, cfg);

    data = randn(1, ndata) + 1j*randn(1, ndata);
    [dd, info, ~, ~] = otfs_pilot_embed(data, N, M, cfg);

    % 4个导频位置值正确
    for p = 1:4
        assert(abs(dd(positions(p,1), positions(p,2)) - 2) < 1e-10, '多脉冲导频值不正确');
    end
    assert(strcmp(info.mode, 'multi_pulse'), '模式应为multi_pulse');

    fprintf('[通过] 3.5 多脉冲导频 | 4个脉冲, 数据格点=%d\n', ndata);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.5 多脉冲导频 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.6 叠加导频
try
    rng(35);
    N = 8; M = 32;
    cfg = struct('mode','superimposed','pilot_power',0.2);

    data = randn(1, N*M) + 1j*randn(1, N*M);
    [dd, info, gmask, ~] = otfs_pilot_embed(data, N, M, cfg);

    % 叠加模式无保护区
    assert(~any(gmask(:)), '叠加模式不应有保护区');
    % 帧 = 数据 + 导频图案
    data_mat = reshape(data, N, M);
    pilot_recovered = dd - data_mat;
    assert(max(abs(pilot_recovered(:) - info.pilot_pattern(:))) < 1e-10, '导频图案不一致');
    assert(strcmp(info.mode, 'superimposed'), '模式应为superimposed');

    fprintf('[通过] 3.6 叠加导频 | 功率比=%.1f, 全格点利用\n', cfg.pilot_power);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.6 叠加导频 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.7 序列导频(ZC)
try
    rng(36);
    N = 8; M = 32;
    cfg = struct('mode','sequence','seq_type','zc','seq_root',1,...
                 'pilot_k',4,'pilot_l',16,'guard_k',2,'guard_l',3,'pilot_value',2);
    [didx, ~, ndata] = otfs_get_data_indices(N, M, cfg);

    data = randn(1, ndata) + 1j*randn(1, ndata);
    [dd, info, ~, ~] = otfs_pilot_embed(data, N, M, cfg);

    % 导频行有序列值（非零）
    pilot_row_vals = dd(4, info.positions(:,2));
    assert(all(abs(pilot_row_vals) > 0.1), '序列导频值不应为零');
    assert(strcmp(info.mode, 'sequence'), '模式应为sequence');
    assert(length(info.values) == size(info.positions,1), '序列长度与位置数不匹配');

    fprintf('[通过] 3.7 序列导频(ZC) | 序列长度=%d\n', length(info.values));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.7 序列导频 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.8 自适应保护区导频
try
    rng(37);
    N = 8; M = 32;
    % 小扩展信道
    cfg_small = struct('mode','adaptive','pilot_k',4,'pilot_l',16,...
                       'max_delay_spread',1,'max_doppler_spread',1,'pilot_value',3);
    [~, ~, ndata_small] = otfs_get_data_indices(N, M, cfg_small);

    % 大扩展信道
    cfg_large = struct('mode','adaptive','pilot_k',4,'pilot_l',16,...
                       'max_delay_spread',4,'max_doppler_spread',3,'pilot_value',3);
    [~, ~, ndata_large] = otfs_get_data_indices(N, M, cfg_large);

    % 大扩展信道保护区更大 → 数据格点更少
    assert(ndata_small > ndata_large, '大扩展信道数据格点应更少');

    data_s = randn(1, ndata_small) + 1j*randn(1, ndata_small);
    [dd_s, info_s, ~, ~] = otfs_pilot_embed(data_s, N, M, cfg_small);
    assert(abs(dd_s(4,16) - 3) < 1e-10, '导频值不正确');

    fprintf('[通过] 3.8 自适应保护区 | 小扩展:%d格点, 大扩展:%d格点\n', ndata_small, ndata_large);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.8 自适应保护区 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、PAPR ==================== %%
fprintf('\n--- 4. PAPR计算与抑制 ---\n\n');

%% 4.1 PAPR计算
try
    rng(40);
    % OFDM信号PAPR通常较高
    data_ofdm = randn(1, 256) + 1j*randn(1, 256);
    [sig_ofdm, ~] = ofdm_modulate(data_ofdm, 256, 64, 'cp');
    [papr_ofdm, ~, ~] = papr_calculate(sig_ofdm);

    % 常数包络信号PAPR=0dB
    const_sig = exp(1j*2*pi*0.1*(1:1000));
    [papr_const, ~, ~] = papr_calculate(const_sig);

    assert(papr_const < 0.1, '恒模信号PAPR应接近0dB');
    assert(papr_ofdm > 3, 'OFDM PAPR应>3dB');

    fprintf('[通过] 4.1 PAPR计算 | OFDM=%.1fdB, 恒模=%.1fdB\n', papr_ofdm, papr_const);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 PAPR计算 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.2 PAPR削峰
try
    rng(41);
    data = randn(1, 512) + 1j*randn(1, 512);
    [sig, ~] = ofdm_modulate(data, 256, 64, 'cp');
    [papr_before, ~, ~] = papr_calculate(sig);

    [sig_clipped, clip_ratio] = papr_clip(sig, 6, 'clip');
    [papr_after, ~, ~] = papr_calculate(sig_clipped);

    assert(papr_after <= 6 + 0.5, '削峰后PAPR应<=目标+余量');
    assert(papr_after < papr_before, '削峰后PAPR应降低');

    fprintf('[通过] 4.2 PAPR削峰 | 前=%.1fdB, 后=%.1fdB, 目标=6dB, 削峰比=%.1f%%\n', ...
            papr_before, papr_after, clip_ratio*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 PAPR削峰 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、可视化 ==================== %%
fprintf('\n--- 5. 可视化 ---\n\n');

%% 5.1 OFDM频谱图
try
    rng(50);
    data = randn(1, 256*4) + 1j*randn(1, 256*4);
    [sig, ~] = ofdm_modulate(data, 256, 64, 'cp');
    plot_ofdm_spectrum(sig, 48000, 'OFDM 256子载波 fs=48kHz');

    fprintf('[通过] 5.1 OFDM频谱可视化\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 OFDM频谱 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.2 OTFS DD域格点图
try
    rng(51);
    N = 8; M = 32;
    config = struct('pilot_k',4, 'pilot_l',16, 'guard_k',2, 'guard_l',3);
    [data_idx, ~, num_data] = otfs_get_data_indices(N, M, config);
    data = (2*randi([0 1],1,num_data)-1) + 1j*(2*randi([0 1],1,num_data)-1); % QPSK
    [dd_frame, pp, ~, ~] = otfs_pilot_embed(data, N, M, config);
    plot_otfs_dd_grid(dd_frame, 'OTFS DD Grid (8x32)', pp);

    fprintf('[通过] 5.2 OTFS DD域格点可视化\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.2 OTFS DD域 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 六、异常输入 ==================== %%
fprintf('\n--- 6. 异常输入 ---\n\n');

try
    caught = 0;
    try ofdm_modulate([], 64); catch; caught=caught+1; end
    try ofdm_demodulate([], 64, 16); catch; caught=caught+1; end
    try ofdm_pilot_insert([], 64); catch; caught=caught+1; end
    try ofdm_pilot_extract([], 64); catch; caught=caught+1; end
    try scfde_add_cp([], 128); catch; caught=caught+1; end
    try scfde_remove_cp([], 128, 32); catch; caught=caught+1; end
    try otfs_modulate([], 8, 32); catch; caught=caught+1; end
    try papr_calculate([]); catch; caught=caught+1; end
    try papr_clip([]); catch; caught=caught+1; end

    assert(caught == 9, '部分函数未对空输入报错');

    fprintf('[通过] 6.1 空输入拒绝 | 9个函数均正确报错\n');
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
