---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
created: 2026-04-23
updated: 2026-04-23
tags: [诊断, SC-TDE, alpha补偿, GAMP, Turbo均衡, 13_SourceCode, 12_IterativeProc, 07_ChannelEstEq]
---

# SC-TDE α=+1e-2 灾难 RCA — 实施计划

## 架构定位

**就地 diag toggle**（对齐 SC-FDE `alpha-compensation-pipeline-debug` 的前例）：

- 不抽取新函数，在 `test_sctde_timevarying.m` 中加 4 个 diag toggle（都 default=false，不影响默认路径）
- 每步一个独立 MATLAB 主脚本（`diag_D1_*.m` ~ `diag_D4_*.m`），位于 `modules/13_SourceCode/src/Matlab/tests/SC-TDE/`
- 每个 diag 脚本配置 toggle + 循环 runner，收集 BER，写 CSV + 打印判据表

**runner 修改幅度**：仅 **4 处插桩**（各约 5 行），不破坏默认行为。

## 文件清单

### 新建（4 + 1 文件）
- `modules/13_SourceCode/src/Matlab/tests/SC-TDE/diag_D1_oracle_alpha.m`
- `modules/13_SourceCode/src/Matlab/tests/SC-TDE/diag_D2_oracle_h.m`
- `modules/13_SourceCode/src/Matlab/tests/SC-TDE/diag_D3_turbo_iter_sweep.m`
- `modules/13_SourceCode/src/Matlab/tests/SC-TDE/diag_D4_gamp_vs_ls.m`
- `modules/13_SourceCode/src/Matlab/tests/SC-TDE/diag_common.m`（辅助：BER 收集 + 表格打印）

### 修改（1 文件）
- `modules/13_SourceCode/src/Matlab/tests/SC-TDE/test_sctde_timevarying.m`
  - 插桩 1：α 估计后、粗补偿前 → 读 `diag_oracle_alpha` toggle（runner line ~322）
  - 插桩 2：GAMP 估计前后 → 读 `diag_oracle_h` + `diag_use_ls` toggle（runner line ~443）
  - 插桩 3：Turbo 调用 → 读 `diag_turbo_iter` toggle（runner line ~445）
  - 插桩 4：训练精估 → 读 `diag_oracle_alpha` 时跳过（避免 oracle 路径下训练精估干扰）

### 新建 wiki（诊断完成后）
- `wiki/modules/13_SourceCode/SC-TDE调试日志.md` 追加 "V5.3 α=+1e-2 100% 灾难 RCA" 章节

## Step 1 — runner 插桩（~45 min）

### 插桩 1：Oracle α（line ~322，紧跟 P8 大 α 精扫块之后）

```matlab
% === diag D1: Oracle α（2026-04-23） === %
if exist('diag_oracle_alpha','var') && diag_oracle_alpha
    alpha_lfm = dop_rate;   % 真值来自当前 fading_cfgs 行
    if si == 1
        fprintf('  [DIAG-D1] oracle alpha=%+.2e injected\n', alpha_lfm);
    end
end
```

插入位置：`alpha_lfm = best_a;` 之后（P8 块尾）。

### 插桩 2：静态路径 GAMP/LS/Oracle h（替换 line 443-444）

```matlab
if strcmpi(ftype, 'static')
    rx_train = rx_sym_recv(1:train_len);
    L_h = max(sym_delays)+1;
    T_mat = zeros(train_len, L_h);
    for col = 1:L_h
        T_mat(col:train_len, col) = training(1:train_len-col+1).';
    end

    % === diag D2/D4: Oracle h / LS fallback（2026-04-23） === %
    if exist('diag_oracle_h','var') && diag_oracle_h
        h_est_gamp = zeros(1, L_h);
        for p = 1:length(sym_delays)
            h_est_gamp(sym_delays(p)+1) = gains(p);
        end
        if si == 1, fprintf('  [DIAG-D2] oracle h injected\n'); end
    elseif exist('diag_use_ls','var') && diag_use_ls
        h_ls = (T_mat' * T_mat + 1e-3*eye(L_h)) \ (T_mat' * rx_train(:));
        h_est_gamp = h_ls(:).';
        if si == 1, fprintf('  [DIAG-D4] LS (ridge=1e-3) instead of GAMP\n'); end
    else
        [h_gamp_vec, ~] = ch_est_gamp(rx_train(:), T_mat, L_h, 50, noise_var);
        h_est_gamp = h_gamp_vec(:).';
    end

    % === diag D3: Turbo iter override（2026-04-23） === %
    if exist('diag_turbo_iter','var') && ~isempty(diag_turbo_iter)
        turbo_iter_use = diag_turbo_iter;
    else
        turbo_iter_use = turbo_iter;
    end
    [bits_out,~] = turbo_equalizer_sctde(rx_sym_recv, h_est_gamp, training, ...
        turbo_iter_use, noise_var, eq_params, codec);

    % === diag：打印诊断 h 对比 === %
    if si == 1 && exist('diag_dump_h','var') && diag_dump_h
        h_true = zeros(1, L_h);
        for p = 1:length(sym_delays), h_true(sym_delays(p)+1)=gains(p); end
        fprintf('  [DIAG-H] |h_est| main=%.3f, tap2=%.3f, tap3=%.3f | |h_true| main=%.3f, tap2=%.3f, tap3=%.3f\n', ...
                abs(h_est_gamp(1)), abs(h_est_gamp(sym_delays(2)+1)), abs(h_est_gamp(sym_delays(3)+1)), ...
                abs(h_true(1)), abs(h_true(sym_delays(2)+1)), abs(h_true(sym_delays(3)+1)));
    end
else
    % 时变分支（不本 spec 范围，保留原逻辑）
    ...
end
```

### 插桩 3：训练精估跳过（line ~362，保证 oracle α 下干净）

```matlab
if strcmpi(ftype, 'static') && ~(exist('diag_oracle_alpha','var') && diag_oracle_alpha)
    % 原训练精估 α_train 逻辑...
else
    alpha_train = 0;
    alpha_est = alpha_lfm;
end
```

**验证方式**：插桩后 `bench_seed=42` 默认 diag_* 全 false 跑一次，确认 BER 与 HEAD=3dac2aa 完全一致（回归不变）。

## Step 2 — diag_common.m 辅助脚本（~15 min）

```matlab
function diag_common(diag_name, bench_fading_cfgs, toggles, snr, seeds, out_csv)
% diag_common — SC-TDE 诊断公共入口
% toggles: struct，字段如 .oracle_alpha, .oracle_h, .use_ls, .turbo_iter
...
```

核心逻辑：对每个 seed × 每个 toggle 组合跑 runner（evalc 隔离），读 BER，CSV 落盘。

## Step 3 — D1 Oracle α 脚本（~10 min）

`diag_D1_oracle_alpha.m`：
- 对比 `{oracle_alpha=false, oracle_alpha=true}` × α=+1e-2 × SNR=10 × seed 1..5
- 输出 10 行 CSV：seed / mode / alpha_est / ber_coded
- 打印两栏：基线 vs oracle，BER mean/median/std

**判据打印**：
```
[D1 判据]
  baseline  mean=XX.XX% / median=XX.XX% / std=X.XX%
  oracle_α  mean=XX.XX% / median=XX.XX% / std=X.XX%
  → 若 oracle_α mean <5% → α估计是主因（H5 confirmed），建议进 α 精度专项
  → 若 oracle_α mean >30% → α无关，进 D2
```

## Step 4 — D2 Oracle h 脚本（~10 min）

`diag_D2_oracle_h.m`：
- 4 组：`(oracle_alpha, oracle_h) ∈ {(F,F), (T,F), (F,T), (T,T)}` × 5 seed = 20 trial
- 独立于 D1 跑，重复"基线"组用于交叉验证
- 叠加 oracle 能定位是 α 还是 h 占主导

## Step 5 — D3 turbo_iter sweep（~10 min）

`diag_D3_turbo_iter_sweep.m`：
- turbo_iter ∈ {1, 2, 3, 5, 10} × 5 seed = 25 trial（所有 oracle=false）
- 期望观察 BER-vs-iter 曲线：
  - **若单调上升**（iter=1 好，iter=10 差）→ H2 "iter≥2 错误放大" 确认
  - **若单调下降**（iter=10 最好）→ Turbo 本身正常，问题在上游
  - **若全 50%** → DFE iter=1 就失败，进 D4

## Step 6 — D4 GAMP → LS 替换（~10 min）

`diag_D4_gamp_vs_ls.m`：
- 对比 `{GAMP, LS_ridge=1e-3}` × 5 seed = 10 trial
- 关键额外输出：每 seed 打印 `|h_est| vs |h_true|`（三个主要抽头）

## 产出预期与后续分支

4 步 diag 跑完共 **65 trial**，单 trial < 20 s → 总 < 25 min 跑完。

**决策树**：
```
D1 oracle_α 恢复? → YES → est_alpha_dual_chirp 偏差专项（新 spec）
                    NO  → D2
D2 oracle_h 恢复?  → YES → GAMP 发散（新 spec：SC-TDE GAMP guard 或 LS fallback）
                    NO  → D3
D3 turbo_iter=1 BER<5%? → YES → iter≥2 错误放大（新 spec：ISI 消除加 PLL / LLR clip）
                          NO  → D4
D4 LS 恢复?        → YES → 与 D2 冲突，重审；YES 且 D2 NO 则只是 GAMP 边界问题
                    NO  → 进 D5 同步/定时层（新 spec 扩展）
```

每到一步，用户跑脚本看结果，我分析 CSV，**不代下结论**。定位到根因层后，结束本 RCA spec，开 fix spec。

## 执行步骤（用户视角）

1. 我写插桩 + 5 脚本 — 停，用户看代码 ✋
2. 用户跑：
   ```
   cd modules/13_SourceCode/src/Matlab/tests/SC-TDE
   clear functions; clear all;
   diary('diag_D1_results.txt');
   run('diag_D1_oracle_alpha.m');
   diary off;
   ```
3. 用户贴 `diag_D1_results.txt` 输出给我
4. 我分析 → 建议是否进 D2（或直接跳到根因层）
5. 重复 D2/D3/D4（可能提前停止）

## 验证不破坏回归（Gate）

**不用 Phase c 灾难场景做 gate**（两边都 50% 会掩盖真正的 regression）。改用 **α=0 干净 static 基线**，已知 BER << 1%，任何插桩破坏都会被放大。

```matlab
% diag_* 全 false 跑 α=0 基线，BER 必须远低于 1%
clear functions; clear all;
diary('diag_regression_check.txt');
benchmark_mode = true;
bench_fading_cfgs = {'nominal','static',0,0};   % α=0 static
bench_snr_list = [10, 15, 20];
bench_seed = 42;
bench_channel_profile = 'custom6';
run('test_sctde_timevarying.m');
diary off;
```

**期望 BER（参考 SC-TDE V5.1 调试日志）**

| SNR | 期望 BER | 上限（gate 失败阈值） |
|-----|---------|-------------------|
| 10 dB | 0.55% | ≤ 1.0% |
| 15 dB | 0.10% | ≤ 0.5% |
| 20 dB | 0.00% | ≤ 0.1% |

任一 SNR 超上限 → 插桩破坏默认路径，**先修插桩再跑 diag**。

## 风险点

- **R1**：runner 第 443 行周边改动较多（oracle_h 分支 + LS 分支 + turbo_iter 重命名），逻辑容易 break static/时变分支。缓解：改动仅包在 `if strcmpi(ftype,'static')` 内部，时变分支完全不动。
- **R2**：`h_sym` 或 `gains`/`sym_delays` 构造的"真信道"与 GAMP 估计的坐标系可能有 scale 偏差（如 `gains_raw` 未归一化 vs `gains` 归一化）。缓解：插桩 3 的 dump 能直接看到对比。
- **R3**：evalc 隔离失败（runner 内 clear 影响），导致脚本间变量泄漏。缓解：每个 diag_* 脚本开头 `clear functions; clear;`。

## Gate（进 Step 2 前）

- [ ] 用户 review 本 plan 是否接受
- [ ] 确认插桩位置和 toggle 命名
- [ ] 确认 5 seed 样本量是否够（若不够可扩到 15）
