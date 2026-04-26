%% test_build_bem_obs_scfde.m
%% Phase 3b.1 / Phase 4 单元测试：build_bem_observations_scfde
%%
%% V2.0 (2026-04-26 Phase 4) 接口验证：
%%   Case 1 - 单训练块（K=N-1，向后兼容 V1.0 行为）
%%   Case 2 - 多训练块（K=4, N=16，Phase 4 方案 A）
%%
%% 参考：
%%   modules/13_SourceCode/src/Matlab/tests/bench_common/build_bem_observations_scfde.m
%%   modules/14_Streaming/src/Matlab/rx/modem_decode_scfde.m::build_bem_observations
%% 版本：V2.0.0 (2026-04-26)

clear functions; clear; close all; clc;

addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'bench_common'));

fprintf('========================================\n');
fprintf('  test_build_bem_obs_scfde V2.0 单元测试\n');
fprintf('========================================\n');

%% 共用参数
blk_cp        = 64;
blk_fft       = 256;
sym_per_block = blk_cp + blk_fft;     % 320
sym_delays    = [0, 5, 10, 20, 30, 40];
K_sparse      = length(sym_delays);
max_tau       = max(sym_delays);

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);

%% ============================================================
%% Case 1：单训练块（K=N-1，向后兼容 V1.0 行为）
%% ============================================================
fprintf('\n--- Case 1: 单训练块 N=4, train_indices=[1] ---\n');
N_blocks_1   = 4;
N_total_sym_1 = N_blocks_1 * sym_per_block;
train_block_indices_1 = 1;
data_block_indices_1  = 2:N_blocks_1;
N_data_1 = length(data_block_indices_1);

rng(42);
train_sym = constellation(randi(4, 1, blk_fft));
train_cp  = [train_sym(end-blk_cp+1:end), train_sym];

x_bar_blks_data_1 = cell(1, N_data_1);
for di = 1:N_data_1
    x_bar_blks_data_1{di} = constellation(randi(4, 1, blk_fft));
end

rx_sym_1 = randn(1, N_total_sym_1) + 1j*randn(1, N_total_sym_1);

[obs_y_1, obs_x_1, obs_n_1] = build_bem_observations_scfde( ...
    rx_sym_1, train_cp, x_bar_blks_data_1, blk_cp, blk_fft, sym_per_block, ...
    N_total_sym_1, sym_delays, K_sparse, ...
    train_block_indices_1, data_block_indices_1);

n_obs_1 = length(obs_y_1);
fprintf('  obs_y 长度 %d, obs_x %dx%d, obs_n %d\n', ...
        n_obs_1, size(obs_x_1,1), size(obs_x_1,2), length(obs_n_1));

% 验证：维度对齐
assert(size(obs_x_1,1) == n_obs_1, 'C1 obs_x 行数不对');
assert(size(obs_x_1,2) == K_sparse, 'C1 obs_x 列数不对');
% 验证：观测数上限 = N_blocks × (blk_cp - max_tau)
expected_max_1 = N_blocks_1 * (blk_cp - max_tau);
assert(n_obs_1 <= expected_max_1, 'C1 obs 数超上限');
assert(n_obs_1 > 0, 'C1 obs 为空');
% 验证：obs_n 范围
assert(all(obs_n_1 >= 1) && all(obs_n_1 <= N_total_sym_1), 'C1 obs_n 越界');
% 验证：obs_x 无全 0 行
assert(all(any(obs_x_1 ~= 0, 2)), 'C1 存在全 0 行');
% 验证：QPSK 幅度
mag1 = abs(obs_x_1(1, find(obs_x_1(1,:) ~= 0, 1)));
assert(abs(mag1 - 1) < 1e-9, sprintf('C1 QPSK 幅度 %.6f', mag1));
fprintf('  ✓ Case 1 单训练块 PASS（n_obs=%d / max %d）\n', n_obs_1, expected_max_1);

%% ============================================================
%% Case 2：多训练块（K=4, N=16，Phase 4 方案 A）
%% ============================================================
fprintf('\n--- Case 2: 多训练块 N=16, K=4 ---\n');
N_blocks_2   = 16;
K_train_2    = 4;
N_total_sym_2 = N_blocks_2 * sym_per_block;
% 计算 train_indices（与 modem_encode_scfde V3.0 + test_scfde_timevarying 一致）
N_train_blocks_2 = floor(N_blocks_2 / (K_train_2 + 1)) + 1;
train_block_indices_2 = round(linspace(1, N_blocks_2, N_train_blocks_2));
train_block_indices_2 = unique(train_block_indices_2);
N_train_blocks_2 = length(train_block_indices_2);
data_block_indices_2  = setdiff(1:N_blocks_2, train_block_indices_2);
N_data_2 = length(data_block_indices_2);

fprintf('  N_train=%d, train_indices=[%s]\n', N_train_blocks_2, ...
        strjoin(arrayfun(@(x)sprintf('%d',x), train_block_indices_2, 'UniformOutput',false), ' '));
fprintf('  N_data=%d, data_indices=[%s...]\n', N_data_2, ...
        strjoin(arrayfun(@(x)sprintf('%d',x), data_block_indices_2(1:min(8,end)), 'UniformOutput',false), ' '));

x_bar_blks_data_2 = cell(1, N_data_2);
for di = 1:N_data_2
    x_bar_blks_data_2{di} = constellation(randi(4, 1, blk_fft));
end

rx_sym_2 = randn(1, N_total_sym_2) + 1j*randn(1, N_total_sym_2);

[obs_y_2, obs_x_2, obs_n_2] = build_bem_observations_scfde( ...
    rx_sym_2, train_cp, x_bar_blks_data_2, blk_cp, blk_fft, sym_per_block, ...
    N_total_sym_2, sym_delays, K_sparse, ...
    train_block_indices_2, data_block_indices_2);

n_obs_2 = length(obs_y_2);
fprintf('  obs_y 长度 %d (train+data CP 段)\n', n_obs_2);

% 验证
assert(size(obs_x_2,1) == n_obs_2, 'C2 obs_x 行数不对');
assert(size(obs_x_2,2) == K_sparse, 'C2 obs_x 列数不对');
expected_max_2 = N_blocks_2 * (blk_cp - max_tau);
assert(n_obs_2 <= expected_max_2, 'C2 obs 数超上限');
% Case 2 应该比 Case 1 更多观测（block 数多）
assert(n_obs_2 > n_obs_1, sprintf('C2 obs 数 %d ≤ Case 1 %d，应更多', n_obs_2, n_obs_1));
assert(all(obs_n_2 >= 1) && all(obs_n_2 <= N_total_sym_2), 'C2 obs_n 越界');
assert(all(any(obs_x_2 ~= 0, 2)), 'C2 全 0 行');
% 验证：obs_n 包含多个 train block 的 CP 段
%   每个 train block CP 段贡献 ≤ blk_cp-max_tau=24 obs，N_train=4 → ≥ 4×部分有效
n_in_train = 0;
for ti = 1:N_train_blocks_2
    blk_global = train_block_indices_2(ti);
    blk_start = (blk_global - 1) * sym_per_block;
    n_in_train = n_in_train + sum(obs_n_2 > blk_start & obs_n_2 <= blk_start + blk_cp);
end
fprintf('  train block CP 段观测数 %d (期望 ≤ %d)\n', n_in_train, N_train_blocks_2 * (blk_cp - max_tau));
assert(n_in_train > 0, 'C2 train block CP 观测为 0');
fprintf('  ✓ Case 2 多训练块 PASS（n_obs=%d / N_train=%d）\n', n_obs_2, N_train_blocks_2);

%% ============================================================
%% Case 3: ch_est_bem 兼容性（Case 2 数据）
%% ============================================================
fprintf('\n--- Case 3: ch_est_bem 兼容性 (Case 2 多训练块输出) ---\n');
addpath(fullfile(fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))))), '07_ChannelEstEq', 'src', 'Matlab'));
if exist('ch_est_bem', 'file') == 2
    try
        [h_tv_test, ~, ~] = ch_est_bem(obs_y_2(:), obs_x_2, obs_n_2(:), N_total_sym_2, ...
            sym_delays, 1, 6000, 0.01, 'dct', struct('Q_mode','auto','lambda_scale',1.0));
        assert(size(h_tv_test, 1) == K_sparse, 'C3 ch_est_bem 维度错');
        assert(size(h_tv_test, 2) == N_total_sym_2, 'C3 时间维度错');
        assert(all(isfinite(h_tv_test(:))), 'C3 含 NaN/Inf');
        fprintf('  ✓ Case 3 ch_est_bem 兼容 (h_tv: %dx%d)\n', size(h_tv_test));
    catch ME
        fprintf('  ✗ Case 3 ch_est_bem FAIL: %s\n', ME.message);
    end
else
    fprintf('  ⚠ ch_est_bem 不在 path，跳过\n');
end

fprintf('\n========================================\n');
fprintf('  test_build_bem_obs_scfde V2.0 完成\n');
fprintf('========================================\n');
