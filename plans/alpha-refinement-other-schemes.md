---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-21-alpha-refinement-other-schemes.md
created: 2026-04-21
updated: 2026-04-21
tags: [α推广, 4体制, 13_SourceCode]
---

# α 迭代 refinement 推广 4 体制 — 实施计划

## 策略

**按体制串行**（而非按 patch 并行），每体制改完立即 A2 单点回归，确认工作再继续下一体制。降低多体制同时出错的 debug 面。

**顺序**：OFDM → SC-TDE → DSSS → FH-MFSK（从最像 SC-FDE 到最异）

## Step 1: OFDM（1h）

### 改动点（timevarying + discrete_doppler 对称改）

| Patch | 位置（timevarying 行号） | 改动 |
|-------|------------------------|------|
| P1 LFM- 生成 | ~line 76 (LFM_bb 后) | 加 phase_lfm_neg / LFM_bb_neg |
| P2 guard 扩展 | ~line 78 | + ceil(α_max · max(N_pre, N_lfm)) |
| P3 帧组装 | ~line 182 | LFM2 改 LFM_bb_neg_n |
| P4 α 估计 | ~line 240-260（现有 angle(R2·conj(R1))） | 换 est_alpha_dual_chirp + 迭代 |
| P5 LFM2 精定时 | ~line 280（corr_lfm_comp） | mf_lfm → mf_lfm_neg |

OFDM 保留 alpha_cp 精修（OFDM 有空子载波 CFO 精估）。

### 验证

```matlab
% OFDM A2 单点快速回归
benchmark_e2e_baseline('A2', 'schemes', {'OFDM'}, 'snr_list', [10]);
% 检查 α=[5e-4, 1e-3, 2e-3] BER <5%
```

若 OK → 进 Step 2；若失败 → 回退 patch，debug。

## Step 2: SC-TDE（1h）

SC-TDE **时变分支 alpha_est = alpha_lfm**（跳过训练精估），无 CP 精修。

| Patch | 说明 |
|-------|------|
| P1-P3 | 同 OFDM |
| P4 α 估计 | 同 OFDM 但去掉 `+ alpha_cp`（SC-TDE 时变分支本来就不加） |
| P5 LFM2 精定时 | 同 OFDM |

注意 SC-TDE line 310 处有 `alpha_est = alpha_lfm + alpha_train`（static 分支）和 `alpha_est = alpha_lfm`（slow 分支）。改动时保持 branch 逻辑。

### 验证

```matlab
benchmark_e2e_baseline('A2', 'schemes', {'SC-TDE'}, 'snr_list', [10]);
```

## Step 3: DSSS（1h）

DSSS 本来 **alpha_est = angle(R2*conj(R1)) / (2π·fc·T_v_lfm)**，无 alpha_cp。

### 改动

- P1-P3 同 OFDM
- P4：替换 `alpha_est = angle(...)` 为 est_alpha_dual_chirp + 迭代，最终 `alpha_est = alpha_lfm`
- P5：同 OFDM

### 验证

```matlab
benchmark_e2e_baseline('A2', 'schemes', {'DSSS'}, 'snr_list', [10]);
```

**特殊关注**：DSSS 扩频码相关后，Rake 合并对残余 α 敏感度。若 α=2e-3 BER 仍 >10%，留 spec 遗留项。

## Step 4: FH-MFSK（1h）

FH-MFSK 能量检测（跳频），α 补偿在 RX 跳频时间对齐层。

### 改动

- P1-P3 同 OFDM
- P4 同 DSSS（无 alpha_cp）
- P5 同 OFDM

**FH-MFSK 默认 A1 全 fd 都工作**（benchmark 显示），A2 才崩（固定 α 破坏跳频时间基准）。改造目标：A2 α=1e-3 BER<5%。

### 验证

```matlab
benchmark_e2e_baseline('A2', 'schemes', {'FH-MFSK'}, 'snr_list', [10]);
```

## Step 5: 全体制综合回归 + wiki + commit（1h）

### 回归 D + A1 + B

```matlab
% 4 体制 × D/A1/B 全阶段
benchmark_e2e_baseline('D', 'schemes', {'OFDM','SC-TDE','DSSS','FH-MFSK'});
benchmark_e2e_baseline('A1', 'schemes', {'OFDM','SC-TDE','DSSS','FH-MFSK'});
benchmark_e2e_baseline('B', 'schemes', {'OFDM','SC-TDE','DSSS','FH-MFSK'});
```

### wiki 报告

**更新**：
- `wiki/comparisons/e2e-timevarying-baseline.md` 加 "4 体制 α 推广 after" 章节
- `wiki/modules/10_DopplerProc/双LFM-α估计器.md` 推广状态表
- `wiki/conclusions.md` 追加"4 体制 α 覆盖 1e-2"
- `wiki/log.md` 2026-04-21 条目
- `wiki/index.md`（无新页面，不必更新）

### todo.md

**移动**：`🔴 α 补偿推广到其他 4 体制` → `✅ 近期里程碑`

### Commit 顺序

1. `feat(13_SourceCode): α 迭代 refinement 推广 OFDM/SC-TDE/DSSS/FH-MFSK`
   - 8 runner 文件（4 体制 × 2 runner）
2. `docs(wiki+todo): α 推广 4 体制基线更新`
   - wiki/comparisons/ + wiki/modules/10_DopplerProc/ + conclusions + log + todo

## 开放问题（实施中决议）

1. **SC-TDE static 分支 alpha_train**：
   - Static 分支里 `alpha_train` 怎么改？
   - 决议：不动 `alpha_train`（训练精估用于非时变场景），只改 `alpha_lfm` 输入
2. **DSSS/FH-MFSK α=2e-3 是否能到 BER<5%**：
   - 若不行，验收门槛放宽到 <10%（作为扩频/跳频固有退化）
   - 记入 spec Log 遗留
3. **B 阶段回归 OTFS 独自 32%**：
   - OTFS 不在本 spec 改造范围；用户并行做 OTFS debug spec
   - 本 spec 回归只看其他 4 体制 B 阶段零退化即可

## 回滚策略

若某体制改造后 A1 α=0 路径退化（BER 从 0% 上升）：

1. 先回退 P5（LFM2 精定时）—— 若定时破坏，回 mf_lfm
2. 再回退 P4（estimator 切换）—— 若 estimator 有问题，用旧 alpha_lfm
3. 最后回退 P1-P3（帧改动）—— 极端情况

保留 SC-FDE 改造作为回滚参考模板（已 commit）。
