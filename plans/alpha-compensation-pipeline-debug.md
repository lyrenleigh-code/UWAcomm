---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-20-alpha-compensation-pipeline-debug.md
created: 2026-04-20
updated: 2026-04-20
tags: [诊断, α补偿, pipeline, SC-FDE]
---

# α 补偿 Pipeline 深度诊断 — 实施计划

## 架构定位

**就地 diag**（用户决策）：不抽取 `run_scfde_pipeline_with_diag` 函数，直接在
`test_scfde_timevarying.m` 中以 **toggle struct `bench_diag`** 驱动插入 `save/diary`，
改动最小，runner 保持可用。

**单诊断脚本**：`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline.m`
作为主入口，它：
1. 设置 `bench_oracle_alpha=true` / `bench_diag=...` / `bench_single_path` 等开关
2. `run('test_scfde_timevarying.m')` 两次（α=0, α=2e-3）
3. 读 runner 保存的 `diag_α*.mat` 做 RMS 对比
4. 跑 H1-H8 toggle 分别测 BER

## 工作文件清单

**新建（2 文件）**：
- `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline.m`（主诊断脚本）
- `modules/13_SourceCode/src/Matlab/tests/SC-FDE/plot_alpha_pipeline_diag.m`（可视化）

**修改（1 文件）**：
- `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m`
  插入 `bench_diag` 读取 + 9 个节点 diag 保存 + 8 个 toggle 检查 + 逐块 BER

**新建 wiki**：
- `wiki/modules/10_DopplerProc/α补偿pipeline诊断.md`（报告）

## Step 1：runner 插桩（1.5h）

### 1.1 节点 diag 保存（N0-N8）

在 `test_scfde_timevarying.m` 关键位置插入条件 save：

```matlab
% 帧头 init 处加：
if exist('bench_diag','var') && isfield(bench_diag, 'enable') && bench_diag.enable
    diag = struct();
    diag.alpha_true = dop_rate;
    diag.snr_db = snr_db;
end

% N0 TX 基带（line ~163 frame_bb 后）
if exist('bench_diag','var') && bench_diag.enable
    diag.frame_bb = frame_bb(1:min(end, 10000));  % 截 10k 样本避免 MAT 过大
end

% N1 rx_pb_clean（line ~175）
if exist('bench_diag','var') && bench_diag.enable
    diag.rx_pb_clean = rx_pb_clean(1:min(end, 10000));
end

% N2 bb_raw（line ~192）
if exist('bench_diag','var') && bench_diag.enable
    diag.bb_raw = bb_raw(1:min(end, 10000));
end

% N3 bb_comp（line ~280 after resample）
if exist('bench_diag','var') && bench_diag.enable
    diag.bb_comp = bb_comp(1:min(end, 10000));
end

% N4 rc（symbol rate）
% N5 rc_blk (per block)
% N6 h_est (per block) — 需从 eq_bem_turbo_fde 内部读，加诊断返回字段
% N7 y_eq (LMMSE out)
% N8 llr / hard_decision — 同上

% 末尾 save
if exist('bench_diag','var') && bench_diag.enable
    diag.ber_per_block = ber_per_block;   % 见 1.2
    save(bench_diag.out_path, 'diag');
end
```

### 1.2 逐块 BER 统计（H6 关键）

data 段分 N_blocks 块，每块 blk_fft 符号。在 hard_decision 计算后：

```matlab
% hard_dec: hard decision symbols (1 × M_total), same shape as sym_all
ber_per_block = zeros(1, N_blocks);
for bi = 1:N_blocks
    idx = (bi-1)*blk_fft + (1:blk_fft);
    ber_per_block(bi) = sum(hard_dec(idx) ~= sym_all(idx)) / blk_fft;
end
diag.ber_per_block = ber_per_block;

% 帧头前 N=50 符号解码准确率
N_head = 50;
diag.ber_head = sum(hard_dec(1:N_head) ~= sym_all(1:N_head)) / N_head;
diag.ber_tail = sum(hard_dec(end-N_head+1:end) ~= sym_all(end-N_head+1:end)) / N_head;
```

### 1.3 8 toggle 支持

扩展 runner 开头的开关读取：

```matlab
% 默认 toggle（全部 off）
toggles = struct('skip_resample', false, 'skip_downconvert_lpf', false, ...
                 'force_best_off', false, 'oracle_h', false, ...
                 'force_lfm_pos', false, 'pad_tx_tail', false, ...
                 'skip_alpha_cp', false, 'force_bem_q', []);
if exist('bench_toggles','var') && isstruct(bench_toggles)
    fields = fieldnames(bench_toggles);
    for k = 1:numel(fields)
        toggles.(fields{k}) = bench_toggles.(fields{k});
    end
end
```

8 toggle 插入点：

| Toggle | 插入位置 | 实现 |
|--------|---------|------|
| skip_resample | line ~280 | `if toggles.skip_resample, bb_comp = bb_raw; end` |
| skip_downconvert_lpf | line ~192 | 用 no-LPF downconvert 或 LPF cutoff ×2 |
| force_best_off | line ~302 for off loop | `if toggles.force_best_off, best_off = 0; end`（skip search） |
| oracle_h | BEM 调用处 | 替换 `h_est = ch_info.h_time` |
| force_lfm_pos | line ~283 | `lfm_pos = nominal_lfm_pos`（α=0 基线值） |
| pad_tx_tail | line ~163 frame_bb 后 | `frame_bb = [frame_bb, zeros(1, 1000)]` |
| skip_alpha_cp | line ~270 | `alpha_est = alpha_lfm`（忽略 alpha_cp） |
| force_bem_q | BEM 调用处 | 传 `params.Q = toggles.force_bem_q` |

## Step 2：主诊断脚本 diag_alpha_pipeline.m（1h）

```matlab
%% diag_alpha_pipeline.m
% 对应 spec: 2026-04-20-alpha-compensation-pipeline-debug.md

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(this_dir, '..', 'bench_common'));
out_dir = fullfile(this_dir, 'diag_results');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

%% 1. 基线 RMS 对比（α=0 vs α=2e-3，都用 oracle α）
for ai = [0, 2e-3]
    tag = sprintf('a%.0e', ai);
    benchmark_mode = true;
    bench_oracle_alpha = true;
    bench_snr_list = [10];
    bench_fading_cfgs = {sprintf('α=%g',ai), 'static', 0, ai, 1024, 128, 4};
    bench_channel_profile = 'custom6';
    bench_seed = 42;
    bench_stage = 'diag';
    bench_scheme_name = 'SC-FDE';
    bench_csv_path = fullfile(out_dir, sprintf('diag_%s.csv', tag));
    bench_diag = struct('enable', true, 'out_path', fullfile(out_dir, sprintf('diag_%s.mat', tag)));
    bench_toggles = struct();  % 全部 off

    run(fullfile(this_dir, 'test_scfde_timevarying.m'));
    clearvars -except ai this_dir out_dir
end

%% 2. 读 MAT 做 RMS 对比
d0 = load(fullfile(out_dir, 'diag_a0.mat'));   d0 = d0.diag;
d2 = load(fullfile(out_dir, 'diag_a2e-03.mat')); d2 = d2.diag;

nodes = {'frame_bb','rx_pb_clean','bb_raw','bb_comp','rc','rc_blk','h_est','y_eq','llr'};
fprintf('\n=== Pipeline RMS ratio (α=2e-3 vs α=0) ===\n');
rms_ratios = zeros(1, numel(nodes));
for ni = 1:numel(nodes)
    n = nodes{ni};
    if ~isfield(d0, n) || ~isfield(d2, n), continue; end
    a = d0.(n); b = d2.(n);
    rms_ratios(ni) = norm(b(:) - a(:)) / max(norm(a(:)), eps);
    fprintf('  [%-12s] ratio = %.4e\n', n, rms_ratios(ni));
end

fprintf('\n=== 逐块 BER (α=2e-3) ===\n');
fprintf('  ber_head = %.4f\n', d2.ber_head);
fprintf('  ber_per_block = [%s]\n', sprintf('%.3f ', d2.ber_per_block));
fprintf('  ber_tail = %.4f\n', d2.ber_tail);

save(fullfile(out_dir, 'pipeline_rms.mat'), 'rms_ratios', 'nodes', 'd0', 'd2');

%% 3. H1-H8 toggle 测试
toggle_list = {
    'baseline',      struct();
    'h1_skip_resample', struct('skip_resample', true);
    'h2_skip_lpf',   struct('skip_downconvert_lpf', true);
    'h3_best_off0',  struct('force_best_off', true);
    'h4_oracle_h',   struct('oracle_h', true);
    'h5_force_lfm',  struct('force_lfm_pos', true);
    'h6_pad_tail',   struct('pad_tx_tail', true);
    'h7_skip_cp',    struct('skip_alpha_cp', true);
    'h8_bem_q0',     struct('force_bem_q', 0);
    'h8_bem_q4',     struct('force_bem_q', 4);
};

ber_by_toggle = zeros(1, size(toggle_list,1));
for ti = 1:size(toggle_list,1)
    tname = toggle_list{ti,1};
    tcfg  = toggle_list{ti,2};
    fprintf('\n--- Toggle %s ---\n', tname);

    benchmark_mode = true;
    bench_oracle_alpha = true;
    bench_snr_list = [10];
    bench_fading_cfgs = {sprintf('α=%g',2e-3), 'static', 0, 2e-3, 1024, 128, 4};
    bench_channel_profile = 'custom6';
    bench_seed = 42;
    bench_stage = 'diag';
    bench_scheme_name = 'SC-FDE';
    bench_csv_path = fullfile(out_dir, sprintf('diag_toggle_%s.csv', tname));
    bench_diag = struct('enable', false);   % 不保存 MAT，只看 CSV
    bench_toggles = tcfg;

    run(fullfile(this_dir, 'test_scfde_timevarying.m'));
    % 读 CSV 取 BER
    T = readtable(bench_csv_path);
    ber_by_toggle(ti) = T.ber_coded(1);
    fprintf('  %s BER = %.4f\n', tname, ber_by_toggle(ti));
    clearvars -except out_dir toggle_list ber_by_toggle ti this_dir
end

%% 4. 保存 toggle 结果
save(fullfile(out_dir, 'toggle_results.mat'), 'toggle_list', 'ber_by_toggle');

fprintf('\n============================================\n');
fprintf('  Toggle BER ranking (α=2e-3 oracle @ SNR=10)\n');
fprintf('============================================\n');
for ti = 1:size(toggle_list,1)
    fprintf('  %-20s BER = %.4f (Δ = %+.4f)\n', toggle_list{ti,1}, ...
            ber_by_toggle(ti), ber_by_toggle(ti) - ber_by_toggle(1));
end
```

## Step 3：plot_alpha_pipeline_diag.m（0.5h）

4 张图：

1. **节点 RMS ratio 柱状图**（N0-N8，log 纵轴）
2. **bb_comp 样本偏差 vs n**（看累积曲线）
3. **逐块 BER 柱状图**（block 1-4 + head + tail）
4. **Toggle BER ranking 柱状图**（降序，高亮 Δ<-0.1 的）

## Step 4：wiki 报告（0.5h）

`wiki/modules/10_DopplerProc/α补偿pipeline诊断.md`：

```markdown
# α=2e-3 崩溃 Pipeline 诊断（SC-FDE, 2026-04-20）

## 诊断矩阵

| 节点 | RMS ratio | 爆炸？ |
|------|-----------|-------|
| ... | ... | ... |

## 逐块 BER
[柱状图 + 数字]

## Toggle 排名
| 假设 | BER | Δ | 验证结果 |
|------|-----|---|---------|

## 根因结论
[一句话：如 "H6 帧尾截断 + H4 BEM 失效，两者协同"]

## 后续改造方向
1. [具体 spec 主题]
2. ...
```

## Step 5：spec 归档 + commit（0.5h）

- 本 debug spec 完成后 → `specs/archive/`
- 生成后续改造 spec 主题清单（不自己写 spec，留给用户决策）
- commit：`diag(10_DopplerProc): α 补偿 pipeline 诊断 + 根因定位`

## 时间合计

| Step | 工时 |
|------|------|
| 1 runner 插桩 | 1.5h |
| 2 主诊断脚本 | 1h |
| 3 可视化 | 0.5h |
| 4 wiki 报告 | 0.5h |
| 5 归档 commit | 0.5h |
| 缓冲 | 1.5h |
| **合计** | **~5.5h** |

## 开放问题

1. **h_est 内部访问**：`eq_bem_turbo_fde` 不返回 h_est；可能需要扩接口或用 evalin 抓，待实施决议
2. **rc_blk 节点**：每块的 symbol 序列是中间变量，保存前 N_blocks 块（典型 4）
3. **rx_pb_clean 长度**：含 preamble 可能长 10k+，截前 10k 用于 RMS 诊断

## 回滚策略

若插桩破坏 runner（α=0 正常路径 BER 退化）：
1. 把 `bench_diag.enable` 默认 false 确保关闭时 runner 行为不变
2. `save` 语句用 try/catch 包裹防止失败中断
3. 极端情况：所有 diag 改到独立文件复制一份 test_scfde_timevarying_diag.m，不动原 runner
