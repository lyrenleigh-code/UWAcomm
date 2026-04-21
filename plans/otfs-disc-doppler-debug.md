---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-21-otfs-disc-doppler-32pct-debug.md
created: 2026-04-21
updated: 2026-04-21
tags: [OTFS, 调试, pilot_mode, 13_SourceCode]
---

# OTFS 32% BER 专项 debug — 实现计划

## 挂靠位置

**诊断脚本**：`modules/13_SourceCode/src/Matlab/tests/OTFS/diag_otfs_32pct.m`
**结果 MAT**：`modules/13_SourceCode/src/Matlab/tests/OTFS/diag_results/`
**wiki 报告**：`wiki/modules/13_SourceCode/OTFS调试日志.md`（新建）

选 13_SourceCode 下 OTFS test 目录而非独立模块，因为涉及完整 E2E（不是多普勒单模块问题）。

## Step 1: 诊断脚本骨架（30 min）

### 复用策略

`test_otfs_timevarying.m` 已 900+ 行，不抽取——直接复制核心帧生成段 + 单点循环，裁剪为精简诊断脚本。

### 脚本结构

```matlab
% diag_otfs_32pct.m
% OTFS 32% BER 根因诊断
% 对应 spec: specs/active/2026-04-21-otfs-disc-doppler-32pct-debug.md

clear functions; clear all; close all;
diary('diag_results/otfs_32pct_diag_log.txt');

%% === 配置 === %%
SNR_DB   = 10;
N_TRIALS = 3;  % 每 pilot_mode 跑 3 次
PILOT_MODES = {'impulse', 'sequence', 'superimposed'};

% 信道配置（static 6 径 = 诊断基线）
CHANNELS = {
    'static',     'static',   zeros(1,5);
    'disc-5Hz',   'discrete', [0, 3, -4, 5, -2];
    'hyb-K20',    'hybrid',   struct('doppler_hz',[0,3,-4,5,-2], 'fd_scatter',0.5, 'K_rice',20);
};

%% === 复用路径 === %%
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

%% === 循环 === %%
results = struct();
for ch_i = 1:size(CHANNELS, 1)
    for pm_i = 1:numel(PILOT_MODES)
        for tr_i = 1:N_TRIALS
            % 复用 test_otfs_timevarying.m 的参数段 + 单 SNR 单信道单 trial 跑
            % 收集：ber_coded / h_est NMSE / pilot energy / frame_detected
            [ber, nmse, frame_ok] = run_otfs_once( ...
                CHANNELS{ch_i,1}, CHANNELS{ch_i,2}, CHANNELS{ch_i,3}, ...
                PILOT_MODES{pm_i}, SNR_DB, 100*tr_i);
            results.(sanitize(CHANNELS{ch_i,1})).(PILOT_MODES{pm_i}).ber(tr_i) = ber;
            results.(sanitize(CHANNELS{ch_i,1})).(PILOT_MODES{pm_i}).nmse(tr_i) = nmse;
            results.(sanitize(CHANNELS{ch_i,1})).(PILOT_MODES{pm_i}).frame_ok(tr_i) = frame_ok;
        end
    end
end

save('diag_results/otfs_32pct_diag.mat', 'results', 'SNR_DB', 'N_TRIALS');
print_summary(results);
diary off;
```

### run_otfs_once 签名

```matlab
function [ber, nmse, frame_ok] = run_otfs_once(fname, ftype, fparams, pilot_mode, snr_db, seed)
% 内联 test_otfs_timevarying.m 核心段：
%   1. 设置参数（sym_rate/fc/N/M/cp_len 等）
%   2. 按 pilot_mode 生成 pilot_config（从 test_otfs_timevarying:64-81 复制）
%   3. 生成一帧 TX (随机 bits → encode → interleave → QPSK → OTFS)
%   4. 过 apply_channel
%   5. frame_assemble/parse_otfs (passband=true)
%   6. 加噪声 + OTFS demod
%   7. 按 pilot_mode 分派到 ch_est_otfs_{dd/zc/superimposed}
%   8. LMMSE + Turbo
%   9. 算 BER
%   10. 算 h_est NMSE vs h_true（从 clean pilot-only 回推）
end
```

**关键**：不用 benchmark_mode，直接 function call。

## Step 2: 主假设验证分支（0.5-1.5h）

### 决策树

```
跑完 Step 1 → 看 results.static.impulse.ber 均值
  ├── 均值 ≤ 5%  →  H1 成立 ✅
  │                   跑 Step 2a: 扩展到 disc-5Hz/hyb-K20 × impulse
  │                   ├── <5% → H4 否定（Yang 2026 理论不适用）→ 结论：pilot regression
  │                   └── ~32% → H4 成立 → H5 待验证 → 升级衍生 spec
  │
  └── 均值 ~ 33% → H1 否定 → 转 Step 2b
                   跑 use_oracle=true + impulse + static × 3
                   ├── BER=0% → 估计器才是问题，但不是 pilot_mode
                   └── BER ~ 33% → 瓶颈在均衡/译码（H3）→ 深度 debug 需新 spec
```

### Step 2a：H1 成立后的验证

加跑：
```matlab
% 在 Step 1 脚本末尾追加
if mean(results.static.impulse.ber) <= 0.05
    fprintf('>>> H1 confirmed. Running B-stage extension with impulse...\n');
    % 跑 disc-5Hz / hyb-K20 × impulse × 3 trials
end
```

### Step 2b：H1 否定后的 oracle 对照

```matlab
if mean(results.static.impulse.ber) > 0.2
    fprintf('>>> H1 rejected. Running oracle comparison...\n');
    [ber_oracle, ~, ~] = run_otfs_once('static', 'static', zeros(1,5), ...
                                       'impulse', SNR_DB, 42, 'use_oracle', true);
    fprintf('Oracle + impulse + static: BER = %.2f%%\n', 100*ber_oracle);
end
```

## Step 3: wiki 整理（30 min）

### 3.1 新建 `wiki/modules/13_SourceCode/OTFS调试日志.md`

```markdown
---
type: debug-log
created: 2026-04-21
updated: 2026-04-21
tags: [调试日志, OTFS, 13_SourceCode]
---

# OTFS 调试日志

## 2026-04-21 — 32% BER 根因定位

### 背景
[摘 spec]

### 诊断
[表：3 pilot_mode × 3 channel × 3 trial 的 BER/NMSE]

### 结论
[根据 H1-H5 结果]

### 后续工作
[升级 spec 或直接修 default pilot_mode]
```

### 3.2 更新 `wiki/conclusions.md`

追加：
- #38: OTFS pilot_mode='sequence' 在 SNR=10dB 的 regression（若 H1 成立）
- #39: （可选）disc-5Hz 下 OTFS 是否仍有独立问题（H4 结论）

### 3.3 同步 `wiki/index.md` + `wiki/log.md`

Stop hook 强校验。

## Step 4: 顺带修复（可选，独立 sub-commit）

### 4a: pilot_mode 默认值回滚

**条件**：若 H1 成立且 sequence 的 trade-off 明显不值（例如 10dB BER 33% → impulse 0%）。

改：
```matlab
% test_otfs_timevarying.m:20
pilot_mode = 'impulse';  % 回滚：SNR=10dB 下 sequence BER 33% (2026-04-21 发现)
                         % PAPR 优势留给专门的 SLM/PTS spec
```

### 4b: harness α 忽略 bug

**条件**：本 debug 完成后顺手修。

在 `test_otfs_timevarying.m:194` 的 `apply_channel` 调用前，检查 benchmark_mode 下 `doppler_rate` 是否需要作用：

```matlab
% 若 benchmark_mode 且 fading_cfgs 含 α 字段（4 列版本）
if benchmark_mode && size(fading_cfgs, 2) >= 4
    dop_rate = fading_cfgs{fi, 4};
    % 在 apply_channel 后做 resample（或者用 gen_uwa_channel 的 doppler_rate 路径）
end
```

**注意**：apply_channel 的 'static/discrete/hybrid' 分支**本身不支持 α**（见 `common/apply_channel.m`）。
需要调用 `gen_uwa_channel` + `fading_type='static'` + `doppler_rate` 路径（与 SC-FDE/OFDM runner 一致）。
此修复**独立 spec** 或归并到现有的 `specs/active/2026-04-21-alpha-refinement-other-schemes.md`。

## Step 5: Commit + PR

两个层次的 commit：

```
commit 1: feat(13_SourceCode): OTFS 32% BER 诊断脚本
  - tests/OTFS/diag_otfs_32pct.m 新建
  - 3×3×3 诊断完成，根因定位 pilot_mode='sequence' regression

commit 2: fix(13_SourceCode): OTFS pilot_mode 默认值回滚 impulse  [若 H1 成立]
  - SNR=10dB 下 sequence BER 33% vs impulse 0% (2026-04-21 诊断)
  - 保留 pilot_mode 参数化，可通过显式设置走 sequence

commit 3: docs(wiki): OTFS 32% 根因 + conclusions #38
```

PR 标题：`fix(OTFS): 32% BER 瓶颈定位 + pilot_mode 回滚`

## 风险与决策点

| 节点 | 决策 |
|------|------|
| Step 1 发现 static impulse 也 33% | 立刻扩 Step 2b，不再跑 Step 2a |
| Step 2a 发现 disc-5Hz + impulse 仍 32% | 输出 H4/H5 待验证记录，新开 spec；本 spec 结束 |
| Step 2b 发现 oracle 也 33% | 深度 debug，可能超出本 spec 工时预算，拆新 spec |

## 开放问题

1. P3 demo UI 的 OTFS scheme（`current_scheme` 后端）是否也默认 sequence？如果是，要否同步回滚？（不在本 spec scope）
2. 若 impulse 在 disc-5Hz 下**边缘可用**（比如 5-10%），算不算 H4 肯定？决策阈值建议 5%。
