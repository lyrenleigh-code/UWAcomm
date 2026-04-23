---
project: uwacomm
type: task
status: active
created: 2026-04-23
updated: 2026-04-23
related:
  - specs/archive/2026-04-22-scfde-cascade-resample-oom-fix.md
  - specs/active/2026-04-16-deoracle-rx-parameters.md
tags: [信道估计, OMP, GAMP, oracle清理, SC-FDE, 13_SourceCode, 07_ChannelEstEq]
---

# SC-FDE static 路径换 OMP 替代 GAMP + sps 相位选择去 oracle

## 背景

L5/L6 修复链（commit `b1f29ba`）通过 `ch_est_gamp` V1.4 偏 LS 兜底将 SC-FDE
在 SNR=10 dB 灾难率从 10% 降到 0%/6.7%。残余 6.7% 已确认是 SNR 受限边界。

但根本问题没解决：`ch_est_gamp` BG 稀疏先验对 custom6 6 径全活跃信道 misspec，
GAMP 频繁需要走 LS 兜底，**架构上不合理**。

同时 §7 Oracle 排查（CLAUDE.md）发现 `test_scfde_timevarying.m` 还有 3 处
`all_cp_data(1:10)` oracle 泄漏（L486 / L593 / L621），与本次清理同文件，连带做。

## 目标

1. **A. static 路径估计器替换**：`ch_est_gamp` → `ch_est_omp(K=K_sparse=6)`
   - 利用项目已计算的 `K_sparse=length(sym_delays)`（接收端协议可知）
   - 利用 `nv_eq` 自适应停止
   - 预期：彻底消除 6.7% 灾难残余 + 速度更快
2. **B. sps 相位选择去 oracle**：L486 / L593 改用功率最大化（无需 TX 数据）
   - RRC 脉冲在最佳采样相位有最大平均功率（最大眼图开度）
   - 是教科书 symbol timing recovery 标准做法

## 非目标

- **L621 GAMP 训练矩阵用 TX 数据问题** — 这涉及帧协议改动（要新增显式
  pilot 块），单独 spec 处理，本次 park
- 不改 GAMP 函数本身（V1.4 修复保留作 fallback / DSSS 等真稀疏场景）
- 不改时变（fading_type≠'static'）路径的 BEM/MMSE 估计
- 不改其他 5 体制（OFDM/SC-TDE/DSSS/FH-MFSK 仍维持各自实现）
- 不改帧结构 / α 估计 / 同步

## 设计

### Patch A：static 路径换 OMP

#### A-1. 修改 `test_scfde_timevarying.m:626`

```matlab
% BEFORE (L626)
[h_gamp_vec, ~] = ch_est_gamp(y_train, T_mat, L_h, 50, nv_eq);

% AFTER
[h_gamp_vec, ~, ~] = ch_est_omp(y_train, T_mat, L_h, K_sparse, nv_eq);
```

**API 兼容**：`ch_est_omp(y, Phi, N, K_sparse, noise_var)` 签名已存在
（`modules/07_ChannelEstEq/src/Matlab/ch_est_omp.m:1`），返回 `[h_est, H_est, support]`。

**调用参数已就绪**：
- `K_sparse` = `length(sym_delays)` = 6（在 test L247 已计算）
- `nv_eq` = `max(noise_var, 1e-10)`（test L614 已设）
- `T_mat`, `y_train`, `L_h` 不变

**变量命名**：保留 `h_gamp_vec` 旧名（下游 L628-632 引用），不改架构。

#### A-2. 加 toggle 开关（可选回退 GAMP）

```matlab
% L617 静态路径开头
use_omp_static = true;   % 默认启用 OMP
if isfield(tog, 'use_gamp_static') && tog.use_gamp_static
    use_omp_static = false;   % 显式回退 GAMP
end

if use_omp_static
    [h_gamp_vec, ~, ~] = ch_est_omp(y_train, T_mat, L_h, K_sparse, nv_eq);
else
    [h_gamp_vec, ~] = ch_est_gamp(y_train, T_mat, L_h, 50, nv_eq);
end
```

**理由**：万一 OMP 在某些场景反而更糟，留 toggle 调试。

### Patch B：sps 相位选择去 oracle

#### B-1. L486（CP 精估路径）

```matlab
% BEFORE (L484-487)
b1=0; bp1=0;
for off=0:sps-1
    st=rf1(off+1:sps:end);
    if length(st)>=10, c=abs(sum(st(1:10).*conj(all_cp_data(1:10))));
        if c>bp1, bp1=c; b1=off; end, end, end

% AFTER
b1=0; bp1=0;
for off=0:sps-1
    st=rf1(off+1:sps:end);
    if length(st)>=10
        pwr = sum(abs(st(1:min(end,N_total_sym))).^2);   % 全段平均功率
        if pwr > bp1, bp1=pwr; b1=off; end
    end
end
```

**理由**：RRC 脉冲在最佳 sps 相位采样时，眼图全开 → 平均功率最大；偏离最佳
相位 → 部分采样在零交叉附近 → 功率下降。无需 TX 数据。

#### B-2. L593（主数据路径）— 同样的修改

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
best_off=0; best_pwr=0;
for off=0:sps-1
    st=rx_filt(off+1:sps:end);
    if length(st)>=10
        pwr = sum(abs(st(1:min(end,N_total_sym))).^2);
        if pwr > best_pwr, best_pwr=pwr; best_off=off; end
    end
end
```

## 验证矩阵

### A-only（patch A 应用，B 未改）

跑 Phase J Monte Carlo（30 seed × 2 α × SNR=10）：
- **预期**：α=+1e-2 灾难率 6.7% → **0%**（OMP 直接给稀疏 6 径解，不会过拟合）
- BER mean 进一步下降

### A+B（两个 patch 都应用）

- **回归检查**：Phase J 维持 0% 灾难（B 不应破坏 A）
- **L6 SNR 受限验证**：α=+1e-2 s17/s26 在 SNR=15/20 仍 0%
- **diag_cascade_quick**：5 baseline α 点 BER 与 commit `b1f29ba` 一致

### 性能对比

```matlab
% 跑 timeit 对比 GAMP V1.4 vs OMP
% GAMP V1.4: GAMP iter + LS 双跑 + 比较
% OMP K=6: 6 次正交投影
% 预期 OMP 快 5-10×
```

## 实施阶段

| Phase | 内容 | 工时 | 用户 checkpoint |
|-------|------|:---:|:---:|
| **A** | OMP 替换 + toggle | 30 min | 跑 Monte Carlo 验证消灾 |
| **B** | sps 功率最大化（2 处） | 20 min | 跑 baseline 验证 BER 不退 |
| **结尾** | 归档 conclusions/log/todo + commit | 10 min | - |

每 phase 独立 commit。

## 风险与回退

### Patch A 风险

- **R1**：`K_sparse=6` 是 hardcoded 信道径数。若实际信道径数 ≠6，OMP 残差大
  - 缓解：`ch_est_omp` 自适应停止已实现（`noise_var` 给出残差阈值），K_sparse 是上限
- **R2**：OMP 对 noise_var 敏感（残差阈值放过紧 → 早停 / 放过松 → 过拟合噪声）
  - 缓解：现有 ridge 阈值 `1.2*noise_var` 经验值，已经 validated；可调
- **R3**：Toeplitz 矩阵 T_mat 列相关性高（连续 TX 数据） → OMP 正交投影病态
  - 缓解：实际跑 Monte Carlo 验证

**回退**：toggle `use_gamp_static=true` 一行即可回滚

### Patch B 风险

- **R4**：功率最大化在低 SNR 下可能选错相位（噪声功率均匀）
  - 缓解：测 SNR=10 baseline 验证；若退化加 LFM 模板相关辅助
  - 实际 RRC 信号 SNR>0 时眼图开度 dominant，理论稳

**回退**：保留旧代码注释，Edit 还原即可

## 关键文件

- `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m` — 3 处改动
- `modules/07_ChannelEstEq/src/Matlab/ch_est_omp.m` — 只读，确认签名

## 备注

- L621 把 `all_cp_data(1:sym_per_block)` 当 GAMP/OMP 训练矩阵的问题（**架构层
  oracle**：用 TX 数据当训练）属独立 spec，需新增显式 pilot 块到帧结构
- 不影响 OFDM/DSSS/FH-MFSK runner（在各自 test_*_timevarying.m）
- 严格遵循"写完停下等用户跑"规则，每 phase 单独 commit
