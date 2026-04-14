---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-12-sctde-tv-doppler-optimize.md
created: 2026-04-14
tags: [SC-TDE, 多普勒, Turbo, BEM]
---

# SC-TDE V5.2 时变多普勒优化 — 实现计划

## 问题诊断

V5.1 基线：

| 场景 | 5dB | 10dB | 15dB | 20dB |
|------|-----|------|------|------|
| static | 1.95% | 0.55% | 0.10% | 0.00% |
| fd=1Hz | 46.80% | 13.91% | 0.76% | **1.60%** |
| fd=5Hz | 45.34% | 46.24% | 46.38% | 44.71% |

- fd=1Hz@5dB 46.80% → 多普勒估计误差 88%（`alpha_est=9.65e-6` vs `alpha_true=8.33e-5`）
- fd=1Hz@20dB 反弹 0.76% → 1.60% → MMSE 公式噪声项过小，LLR 过度自信
- fd=5Hz 物理极限（alpha*fc 在 Jakes 频谱内），非目标

## 根因定位

对比 OFDM V4.3（fd=1Hz 已解）与 SC-TDE V5.1：

**差距 1：时变仍在训练精估**
- `test_sctde_timevarying.m:269-274` 无条件做 `alpha_train = angle(R_t2·conj(R_t1))`
- Jakes 下训练前半/后半段相位差被多普勒扩散污染 → alpha_train 引入错误
- OFDM V4.3 的对策：`if static: alpha_est = alpha_lfm + alpha_cp; else: alpha_est = alpha_lfm`

**差距 2：无 nv_post 实测噪声兜底**
- BEM(DCT) + 散布导频在有限快照下有残余模型误差
- 高 SNR 时名义 `nv_eq = 10^(-SNR/10) * sig_pwr` 远小于实际残差噪声
- MMSE `conj(h0) * rx_ic / (|h0|² + nv_total)` 用过小 nv_total → 等效噪声被低估
- LLR 通过 `-2√2·real/nv_post` 被过度放大 → BCJR 过度自信 → 误判不可恢复
- OFDM V4.3 对策：从 CP 段实测噪声，`nv_eq = max(nv_eq, nv_post)`

## 修改方案

### 修改 1：时变跳过训练精估

**文件**：`modules/13_SourceCode/src/Matlab/tests/SC-TDE/test_sctde_timevarying.m:269-274`

```matlab
% 原代码（无条件训练精估）
T_half = floor(train_len / 2);
R_t1 = sum(rc(1:T_half) .* conj(training(1:T_half)));
R_t2 = sum(rc(T_half+1:2*T_half) .* conj(training(T_half+1:2*T_half)));
alpha_train = angle(R_t2 * conj(R_t1)) / (2*pi*fc*T_half/sym_rate);
alpha_est = alpha_lfm + alpha_train;

% 改为（仅静态信道精估）
if strcmpi(ftype, 'static')
    T_half = floor(train_len / 2);
    R_t1 = sum(rc(1:T_half) .* conj(training(1:T_half)));
    R_t2 = sum(rc(T_half+1:2*T_half) .* conj(training(T_half+1:2*T_half)));
    alpha_train = angle(R_t2 * conj(R_t1)) / (2*pi*fc*T_half/sym_rate);
    alpha_est = alpha_lfm + alpha_train;
else
    alpha_est = alpha_lfm;  % 时变：仅用LFM粗估，残余由BEM跟踪
end
```

### 修改 2：BEM 估计后实测 nv_post 兜底 nv_eq

**文件**：`test_sctde_timevarying.m`，在 BEM 估计（line ~388）后、Turbo 循环（line ~397）前插入。

```matlab
% --- 从训练段实测 nv_post（防高SNR时LLR过度自信）---
nv_post_sum = 0; nv_post_cnt = 0;
for n = max(sym_delays)+1 : train_len
    y_pred = 0;
    for pp = 1:P_paths
        idx = n - sym_delays(pp);
        if idx >= 1
            y_pred = y_pred + h_tv(pp, n) * training(idx);
        end
    end
    nv_post_sum = nv_post_sum + abs(rx_sym_recv(n) - y_pred)^2;
    nv_post_cnt = nv_post_cnt + 1;
end
nv_post_meas = nv_post_sum / max(nv_post_cnt, 1);
nv_eq = max(nv_eq, nv_post_meas);  % 时变兜底
```

后续 iter1/iter2+ 的 MMSE 分母 `nv_total = nv_eq + isi_unknown_pwr` 和 `nv_eq / max(1-var_x_avg, 0.01)` 自动用兜底后的 nv_eq。

### 修改 3：诊断输出

在 BEM 诊断行（line ~392）补充 nv_post 诊断：

```matlab
fprintf('\n  [对齐] corr=%.3f, off=%d | [BEM] Q=%d, obs=%d, cond=%.0f | nv_post=%.2e (nv_eq_orig=%.2e)\n', ...
    align_corr, best_off, bem_info.Q, length(obs_y), bem_info.cond_num, nv_post_meas, noise_var);
```

## 影响范围

| 文件 | 变更 | 行数 |
|------|------|------|
| `test_sctde_timevarying.m` | 时变跳过训练精估 + nv_post 兜底 | +15~20 行 |
| `turbo_equalizer_sctde.m` | **不改**（仅 static 分支使用）| - |
| 其他模块 | **不改** | - |

## 验证

1. 运行 `test_sctde_timevarying.m`，保存 `test_sctde_timevarying_results.txt`
2. 对比验收标准：
   - [ ] fd=1Hz@15dB BER < 0.5%（基线 0.76%）
   - [ ] fd=1Hz@20dB BER < fd=1Hz@15dB（基线反弹）
   - [ ] static 全 SNR 不退化（0%@10dB+）
   - [ ] fd=5Hz 可保持（已知 Jakes 极限，不要求改善）
3. 诊断日志含 `nv_post_meas` / `nv_eq_orig` / 多普勒估计误差

## 风险

| 风险 | 概率 | 应对 |
|------|------|------|
| 低 SNR（0~5dB）nv_post 过大反导致过度保守 | 中 | 限 nv_post 上限，如 `min(nv_post_meas, 10*nv_eq)` |
| 时变跳过训练精估使低 SNR 同步退化 | 低 | LFM 已有充足精度（相位法），训练精估主要用于消除残余 |
| static 分支受影响 | 无 | if 分支隔离，不共用 |

## 步骤

1. ✅ 分析差距（完成）
2. 修改 test_sctde_timevarying.m（2 处）
3. 运行测试 + 核对验收
4. 若未达标→诊断 nv_post / alpha_est / 逐迭代 BER，迭代
5. 更新 wiki debug log + todo + 归档 spec
