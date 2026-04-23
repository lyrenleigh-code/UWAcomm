---
project: uwacomm
type: plan
status: done
spec: specs/archive/2026-04-23-scfde-omp-replace-gamp-and-oracle-clean.md
created: 2026-04-23
updated: 2026-04-23
tags: [信道估计, OMP, GAMP, oracle清理, SC-FDE]
---

# SC-FDE OMP 替换 GAMP + sps oracle 清理 — 实施计划

## 实施结果（2026-04-23 收尾）

**双失败**：

| Phase | 改动 | 实测 | 决策 |
|---|---|---|---|
| **A** OMP 替换 GAMP | 默认走 OMP K=6 | +1e-2 灾难率 6.7% → **10%** ↗ | 默认回 GAMP V1.4，OMP 保留作 `tog.use_omp_static` toggle |
| **B** sps 功率最大化 | L484/L590 改 `sum(\|st\|²)` | -1e-2 BER 13% → **48%** ❌ | 撤回，注释保留教训 |

**Phase 0 假设被证伪**：
- "OMP K=6 给稀疏 6 径解，不会过拟合" ❌（残差驱动选错 support 同样错估）
- "RRC 在最佳相位采样总功率最大" ❌（custom6 6 径 ISI 让错误相位捕获更多能量泄漏）

**教训**：教科书做法在色散信道有反例，需用真实 BER 验证。

**真去 oracle 另起 spec**：用 LFM 模板尾部 / training preamble 相关 / Gardner TED 量化。

---

## 原始计划（保留为历史参考）

## Phase 0 产出（证据驱动，3 子代理报告综合）

### 允许 APIs 清单

| API | 文件:行 | 签名（verbatim）| 关键约束 |
|-----|--------|----------------|---------|
| `ch_est_omp` | `modules/07_ChannelEstEq/src/Matlab/ch_est_omp.m:1` | `[h_est, H_est, support] = ch_est_omp(y, Phi, N, K_sparse, noise_var)` | `K_sparse=0/[]` 启动自适应停止；`noise_var=[]` 走固定 K 次迭代；输出 `h_est` Nx1，`H_est` 1xN，`support` 1xK。**MATLAB `~` 占位接收第 3 输出安全**（语言规范）。|
| `ch_est_gamp` V1.4 | `modules/07_ChannelEstEq/src/Matlab/ch_est_gamp.m:1` | `[h_est, H_est] = ch_est_gamp(y, Phi, N, max_iter, noise_var)` | 内部含 LS Tikhonov 兜底；保留作 toggle 回退选项 |
| `match_filter` | `modules/13_SourceCode/.../tests/SC-FDE/test_scfde_timevarying.m:482, 589` | `[y_filt, ~] = match_filter(x, sps, 'rrc', rolloff, span)` | 已有调用，不改 |

### 关键变量证据（subagent #2）

| 变量 | 定义位置 | 类型/形状 | 注 |
|------|---------|----------|---|
| `y_train` | `test_scfde_timevarying.m:625` (`rx_sym_all(1:usable).'`) | **128×1 complex**（= blk_cp） | 与 spec 中"52680×91"不符，spec 写错 |
| `T_mat` | L620-624 | **128×91 lower-triangular Toeplitz** | 用 `all_cp_data` 作训练矩阵（独立 spec park）|
| `L_h` | L249（`max(sym_delays)+1`） | **91** for custom6 | 不变 |
| `K_sparse` | L250（`length(sym_delays)`） | **6** for custom6 | OMP 用 |
| `nv_eq` | L614（`max(noise_var, 1e-10)`） | scalar | OMP 用 |
| `tog` 模板 | L137-146 | struct + `bench_toggles` 注入 loop | 现有 8 toggle，新增按相同 pattern |

### sps 上下文（subagent #3）

| 行 | 路径 | 用途 | 修复后影响 |
|---|------|------|-----------|
| **L486** | `bb_comp1` (CP 精估) | 算 `alpha_cp` 输入 | 影响 alpha_cp 精度，但 L502-503 已有 gate |
| **L593** | `bb_comp` (主数据) | `rx_sym_all` 最终符号流 → 信道估计 + 解码 | **直接影响 BER** |

**关键事实**：
- `all_cp_data` = 随机 TX 数据（`info_bits→coded→QPSK`，**非可重生训练序列**）→ 真 oracle 泄漏
- SC-FDE 帧**无 training 前导**（subagent 已 grep 确认无 `training =` 赋值）
- SC-TDE/DSSS 用 `training`（rng seeded，可重生）作清洁 pattern；但**SC-FDE 改帧结构超本期范围**
- `modules/08_Sync/timing_fine.m` 有 Gardner TED 但输出连续 offset，不直接给整数相位

**结论**：本期采用**功率最大化** `sum(|st|^2)`（教科书 RRC timing recovery，无需 TX 数据，无需新模块）。

### 反模式清单

| ❌ | 说明 |
|---|------|
| `ch_est_omp(y, Phi, N, 50, nv_eq)` | `50` 在 OMP 是 `K_sparse`，远超信道径数 6，会过迭代。**必须用 `K_sparse=6`**（已有变量）|
| `ch_est_omp(y, Phi, N, [], nv_eq)` | 触发 `ceil(L_h/10)=10` 默认 K — 仍 > 6，**不优**；显式传 6 更稳 |
| 用 SC-TDE 的 `training` pattern 替代 sps 相位 | SC-FDE 帧无 training preamble，需改帧结构 → **超本期范围** |
| 把 sps 相位改成 Gardner TED | 输出连续 offset 不直接对接 `0..sps-1` 整数；引入新模块依赖 |
| spec 中 path `13_SourceCode/tests/...` | 实际是 `13_SourceCode/src/Matlab/tests/...`（subagent 已纠正）|

## 影响的文件

| 文件 | 改动 | Phase |
|------|------|------|
| `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m` | L137 toggle 加默认值 + L617-636 OMP 分支 | A |
| 同上 | L484-487 + L590-596 sps 功率最大化 | B |
| `modules/07_ChannelEstEq/src/Matlab/ch_est_omp.m` | **只读，不改** | - |

---

## Phase A：static 路径换 OMP（30 min）

### What to implement

**Copy** `tog` 现有 toggle pattern（L137-146）添加 `use_gamp_static`，**Copy** OMP 调用签名（`ch_est_omp.m:1`）替换 L626 GAMP 调用。

### Allowed APIs（来自 Phase 0）

- `ch_est_omp(y, Phi, N, K_sparse, noise_var)` — 三输出，`~` 占位安全
- 现有 `tog.<field>` + `bench_toggles` 注入 pattern（test L137-146）

### Anti-patterns to avoid

- ❌ 用 `K_sparse=50`（旧 GAMP `max_iter` 值）
- ❌ 用 `K_sparse=[]`（默认 `ceil(91/10)=10` > 真实 6）
- ❌ 改 `h_gamp_vec` 变量名（下游 L628-635 引用）

### A-1. 加 toggle 默认值

**位置**：`test_scfde_timevarying.m:137-140`

```matlab
% BEFORE
tog = struct('skip_resample', false, 'skip_downconvert_lpf', false, ...
             'force_best_off', false, 'oracle_h', false, ...
             'force_lfm_pos', false, 'pad_tx_tail', false, ...
             'skip_alpha_cp', false, 'force_bem_q', []);

% AFTER (新增 use_gamp_static, 默认 false → 走新 OMP 分支)
tog = struct('skip_resample', false, 'skip_downconvert_lpf', false, ...
             'force_best_off', false, 'oracle_h', false, ...
             'force_lfm_pos', false, 'pad_tx_tail', false, ...
             'skip_alpha_cp', false, 'force_bem_q', [], ...
             'use_gamp_static', false);
```

L141-146 的 `bench_toggles` 注入 loop 会自动处理新字段。

### A-2. L626 GAMP → OMP（带 toggle 回退）

**位置**：`test_scfde_timevarying.m:617-636`

```matlab
% BEFORE (L626)
[h_gamp_vec, ~] = ch_est_gamp(y_train, T_mat, L_h, 50, nv_eq);

% AFTER
if tog.use_gamp_static
    [h_gamp_vec, ~] = ch_est_gamp(y_train, T_mat, L_h, 50, nv_eq);
else
    % OMP（默认）：K_sparse=6（custom6 真实径数），nv_eq 启动残差自适应停止
    [h_gamp_vec, ~, ~] = ch_est_omp(y_train, T_mat, L_h, K_sparse, nv_eq);
end
```

变量 `h_gamp_vec` 名保留（下游 L628-635 引用）。

### Phase A 验证清单（用户跑）

```matlab
clear functions; clear all;
cd('D:\Claude\TechReq\UWAcomm\modules\13_SourceCode\src\Matlab\tests\SC-FDE');

% 1) Backwards-compat：toggle 回退 GAMP 应与 commit b1f29ba bit-exact
% 暂时 toggle bench_toggles.use_gamp_static = true，跑 cascade_quick
% （脚本里默认 false，我们要 true 验证回退路径）
% → 测试看 5 点 BER 与 b1f29ba baseline 一致

% 2) OMP 默认路径：跑 Monte Carlo
diary('diag_monte_carlo_phase_A.txt');
run('diag_seed_monte_carlo.m');
diary off;
```

**验收**：
- 灾难率 (BER>30%): -1e-2 0/30, **+1e-2 6.7% → 0/30**
- max BER < 5%
- mean BER 进一步下降
- 速度 OMP 应快于 GAMP（K=6 vs GAMP iter 100）

**Phase A commit**：`feat(SC-FDE): static 路径换 OMP 替代 GAMP（消 6.7% 灾难残余）`

---

## Phase B：sps 相位选择去 oracle（20 min）

### What to implement

**Copy** 教科书 RRC symbol timing recovery 模式：在 `0..sps-1` 整数偏移中选**符号流总功率最大**的相位（无需 TX 数据）。

### Allowed APIs

- 纯 base MATLAB（`abs`, `sum`），无新依赖

### Anti-patterns to avoid

- ❌ 改 `bp1`/`b1`/`best_off`/`best_pwr` 变量名（保 backwards-compat）
- ❌ 用 `length(st)` 而非 `min(end, N_total_sym)` 上界 — 取不全长度可能未对齐 TX 帧

### B-1. L484-487（CP 精估路径）

**位置**：`test_scfde_timevarying.m:483-487`

```matlab
% BEFORE
b1=0; bp1=0;
for off=0:sps-1
    st=rf1(off+1:sps:end);
    if length(st)>=10, c=abs(sum(st(1:10).*conj(all_cp_data(1:10))));
        if c>bp1, bp1=c; b1=off; end, end, end

% AFTER
% Phase B: sps 相位用功率最大化（无 oracle）；RRC 在最佳相位采样时眼图全开 → 总功率最大
b1=0; bp1=0;
for off=0:sps-1
    st=rf1(off+1:sps:end);
    if length(st)>=10
        n_take = min(length(st), N_total_sym);
        pwr = sum(abs(st(1:n_take)).^2);
        if pwr > bp1, bp1=pwr; b1=off; end
    end
end
```

### B-2. L590-596（主数据路径）

**位置**：`test_scfde_timevarying.m:590-596`

```matlab
% BEFORE
best_off=0; best_pwr=0;
for off=0:sps-1
    st=rx_filt(off+1:sps:end);
    if length(st)>=10, c=abs(sum(st(1:10).*conj(all_cp_data(1:10))));
        if c>best_pwr, best_pwr=c; best_off=off; end
    end
end

% AFTER
% Phase B: sps 相位用功率最大化（无 oracle）；同 L484-487
best_off=0; best_pwr=0;
for off=0:sps-1
    st=rx_filt(off+1:sps:end);
    if length(st)>=10
        n_take = min(length(st), N_total_sym);
        pwr = sum(abs(st(1:n_take)).^2);
        if pwr > best_pwr, best_pwr=pwr; best_off=off; end
    end
end
```

### Phase B 验证清单（用户跑）

```matlab
clear functions; clear all;
cd('D:\Claude\TechReq\UWAcomm\modules\13_SourceCode\src\Matlab\tests\SC-FDE');

% 1) baseline cascade_quick 5 点应保持 Phase A 结果（B 不应破坏 A）
diary('diag_cascade_quick_phase_B.txt');
run('diag_cascade_quick.m');
diary off;

% 2) Monte Carlo 应保持 Phase A 灾难率 0%
diary('diag_monte_carlo_phase_B.txt');
run('diag_seed_monte_carlo.m');
diary off;
```

**验收**：
- cascade_quick 5 点 BER 与 Phase A 一致（差 <1%）
- Monte Carlo 灾难率维持 0%
- mean BER 不退化

**Phase B commit**：`fix(tests/SC-FDE): sps 相位选择改用功率最大化（去 all_cp_data oracle 泄漏 2 处）`

---

## Phase C 收尾（10 min）

- 更新 `wiki/conclusions.md`：新增 "static OMP 替代 GAMP" 条目
- 更新 `wiki/log.md` + `wiki/index.md`
- 更新 `todo.md`：标记完成 + park L621 GAMP 训练矩阵 oracle 任务（独立 spec）
- 归档 spec → `specs/archive/`
- plan 标 `done`

## 测试策略

### 回归基线

- baseline = commit `b1f29ba`（V1.4 GAMP 修复链）
- baseline 产物：`diag_seed_monte_carlo` 输出（30 seed × 2 α）
  - α=-1e-2 灾难率 0%, max 21.2%
  - α=+1e-2 灾难率 6.7%, max 30.6%

### 矩阵
| 阶段 | 验证脚本 | 期望 |
|------|---------|------|
| A | diag_cascade_quick + diag_seed_monte_carlo | 灾难 0/0; cascade_quick 5 点 0/0/0/0/0% (-1e-2 仍 13%) |
| A toggle GAMP 回退 | bench_toggles.use_gamp_static=true 跑 cascade_quick | 与 baseline `b1f29ba` bit-exact |
| B | diag_cascade_quick + diag_seed_monte_carlo | 维持 A 结果，BER 不退化 |
| 全链 | diag_residual_snr_limit | s17/s26 SNR=15/20 仍 0% |

## 风险与回退

### Phase A 风险

- **R1**：OMP 在 SNR=20 dB 高 SNR 下因 K_sparse 过严 missing 弱径 → BER 退化
  - 缓解：跑 SNR=10/15/20 验证；若发现，把 K_sparse 改成 `K_sparse + 2`（容错）
- **R2**：`ch_est_omp` 对 Toeplitz 列相关矩阵病态
  - 缓解：toggle 回退 `use_gamp_static=true`

**回退**：`bench_toggles.use_gamp_static = true` 一行 → 完全回 V1.4 GAMP

### Phase B 风险

- **R3**：低 SNR 下噪声功率干扰相位选择 → 选错 sps offset
  - 缓解：实测 SNR=10 dB diag_cascade_quick 结果验证；若退化，加 LFM 模板辅助（独立 spec）
- **R4**：信号有 DC offset 时功率最大化偏 0 相位
  - 缓解：基带信号正常无 DC（已下变频），不应触发

**回退**：Edit 还原 L484-487 + L590-596（4 行）

## 关键文件清单（确认无误）

- ✏️ `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m`
- 📖 `modules/07_ChannelEstEq/src/Matlab/ch_est_omp.m` （只读）
- 📖 `modules/07_ChannelEstEq/src/Matlab/ch_est_gamp.m` （只读，回退路径）

## 备注

- 严格遵循"写完停下等用户跑"规则，每 phase 单独 commit
- L621 `T_mat` 用 TX 数据是更深的 oracle 问题（架构层），park 为独立 spec
- nv_eq 用 oracle SNR 也是 §2 违反（独立 spec：用训练残差估 nv_post）
- subagent 报告 IDs 留作可追溯：a883b99c4832e0dfa / adaf70d56fa37c8c0 / a2f32ba6cc81da909
