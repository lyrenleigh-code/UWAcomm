---
project: uwacomm
type: task
status: active
created: 2026-04-22
updated: 2026-04-22
parent: 2026-04-21-alpha-pipeline-large-alpha-debug.md
tags: [多普勒, resample, α补偿, 对称性, 10_DopplerProc, pipeline]
---

# comp_resample_spline α<0 方向不对称修复

## 背景

2026-04-22 的单元测试 `test_resample_doppler_error.m` 首次量化 `comp_resample_spline`
在 oracle α 下的纯数值误差，发现：

| \|α\| | NMSE(+α) | NMSE(-α) | 差异 |
|-------|:--------:|:--------:|:----:|
| 3e-3  | -93.23 dB | -93.31 dB | 对称 ✓ |
| **1e-2** | **-93.03** | **-18.06** | **-75 dB** ✗ |
| **3e-2** | **-92.64** | **-15.34** | **-77 dB** ✗ |
| 5e-2  | -92.24 | -8.98 | -83 ✗ |

**断点**：|α| ≥ 1e-2 时 -α 方向精度断崖，**尾部 RMS 暴涨 4 个数量级**（2e-5 → 0.54）。

## 根因

`comp_resample_spline.m` 当前实现：

```matlab
pos = (1:N) / (1 + alpha_est);
% accurate 模式
pos_clamped = max(1, min(pos, N));    % ← 此处 clamp
```

- α > 0（压缩）：pos_max = N/(1+α) < N → 无 clamp ✓
- α < 0（扩展）：pos_max = N/(1-|α|) > N → **尾部 |α|·N 样本全被 clamp 到最后一个值** ✗

α=-3e-2, N=48000 时，末端 1440 样本被破坏。

fast 模式行为相同（Catmull-Rom 4 点插值边界也会退化）。

## 已观察的下游影响

1. **解释了 `conclusions.md` 中"α<0 非对称"跨体制 common 根因**——不是 estimator、不是
   pipeline 其他环节，而是 `comp_resample_spline` 边界处理本征特性

2. **SC-FDE runner 的 `tail_pad` patch（2026-04-21 大 α 3-patch 第 1 条）其实就是在规避
   这个 bug**，但被当作 TX 层面的问题处理，未推广到其他体制

3. **潜在隐性影响**：OFDM/DSSS/FH-MFSK runner 若未做 tail_pad，则 α<0 路径可能都有
   未被发现的精度损失

## 目标

**主要**：`comp_resample_spline` 在 oracle α<0 下 NMSE 对称性差异 < 3 dB
（当前 75-83 dB 差异）

**次要**：
- 对所有调用方透明（不改接口，不改输出语义）
- 保持 α ≥ 0 路径的性能和精度完全不变
- fast 模式和 accurate 模式一致处理

**兜底**：
- 跨 5 体制回归（SC-FDE/OFDM/SC-TDE/DSSS/FH-MFSK）α=0 / α=+3e-2 的 BER 不退化
- 新单元测试（`test_resample_doppler_error.m`）|α|≤3e-2 对称性差异 < 5 dB

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 修复位置 | `comp_resample_spline.m` 内部 auto-pad | 对调用方透明，避免所有 runner 逐个打补丁 |
| pad 策略 | 尾部 zeros | 物理上 frame 外就是静默/噪声，zero 匹配 |
| pad 长度 | `ceil(max(pos) - N) + 4` | max 精确覆盖，+4 给 Catmull-Rom/spline 边界插值留余量 |
| 警告 | silent | 调用方不关心实现细节；若需要 diagnostic，后续加 return diag struct |
| 版本号 | V7.0.0 → **V7.1.0** | minor bump（向后兼容） |
| fast 模式 | 复用同一 pad（Catmull-Rom 自带 2 端 pad，再叠加 zeros 无副作用） | 一致性 |

## 范围

### 做什么

1. **修改 `comp_resample_spline.m`**：
   - 在 `pos` 计算后检测 `max(pos) > N`
   - 若超界，`y = [y, zeros(1, pad_right)]`，更新 N
   - fast/accurate 模式都受益
   - 更新头注释（V7.1.0 + α<0 auto-pad 说明）

2. **重跑单元测试** `test_resample_doppler_error.m`：
   - 验证 |α|≤3e-2 对称性恢复（NMSE diff < 5 dB）
   - 保存 before/after 对比图

3. **跨体制 runner 审计**（Task B）：
   - grep OFDM/SC-TDE/DSSS/FH-MFSK 四个 runner 是否已有 TX tail_pad
   - 如无，说明修复 `comp_resample_spline` 本身是必要的（不是重复工作）

4. **端到端回归**（关键 smoke test）：
   - D 阶段 13 α 点 × SC-FDE/OFDM/DSSS/FH-MFSK（OTFS 跳过）
   - 对比 α<0 路径 BER 改善
   - A2 α=0 路径 BER 不退化（回归兜底）

5. **Wiki 记录**：
   - `wiki/conclusions.md` +1 条（resample α<0 根因）
   - `wiki/modules/10_DopplerProc/` 新增 `resample-negative-alpha-fix.md` 记录诊断 + 修复

### 不做

- ❌ 不改 runner 的 tail_pad 逻辑（runner 层面冗余 pad 作为"双保险"保留）
- ❌ 不改 SC-TDE（它的 α≠0 崩是下游 α 敏感问题，不由 resample 主导）
- ❌ 不改 OTFS（用户已排除）
- ❌ 不做 fast 模式独立优化（V7.1.0 只做 pad）
- ❌ 不改 `comp_resample_piecewise` / `comp_resample_matlab` / `comp_resample_farrow`
  （仅专项聚焦 spline 实现；其他 resample 方法的对称性问题独立诊断）

## 实施步骤

1. **patch `comp_resample_spline.m`**（10 min）
2. **单元测试回归**（5 min）
3. **runner 审计 + 诊断记录**（15 min）
4. **端到端 D 阶段回归**（5 体制 × 13 α ≈ 30 min）
5. **wiki 更新 + spec 归档**（15 min）
6. **commit**（5 min）

## 验收标准

### 单元级
- [ ] `test_resample_doppler_error.m`: QPSK-RRC |α|≤3e-2 NMSE 对称性差异 < 5 dB
- [ ] 单频 + LFM 同上验收
- [ ] α ≥ 0 路径 NMSE 不变（精度完全不退化）

### 集成级
- [ ] SC-FDE D 阶段 α=-3e-2 BER 不变或改善（当前 0%）
- [ ] OFDM D 阶段 α=-3e-2 BER 改善（若 runner 原无 tail_pad）
- [ ] DSSS D 阶段 α=-3e-2 BER 改善
- [ ] FH-MFSK D 阶段 α=-3e-2 BER 改善
- [ ] A2 α=0 路径 BER 完全不变（5 体制）

## 交付物

1. `modules/10_DopplerProc/src/Matlab/comp_resample_spline.m` V7.1.0
2. `modules/10_DopplerProc/src/Matlab/test_resample_doppler_error.m` before/after 截图
3. `wiki/modules/10_DopplerProc/resample-negative-alpha-fix.md`
4. `wiki/conclusions.md` 新条目
5. D 阶段 4 体制回归 CSV + 对比图
6. commit: `fix(10_DopplerProc): comp_resample_spline V7.1.0 α<0 auto-pad 消除尾部 clamp`

## 风险

| 风险 | 缓解 |
|------|------|
| zero-pad 引入 RRC 带外泄漏 | pad 只在 pos 超界时触发；上下文中 frame 外就是噪声，zero 是物理合理近似 |
| runner tail_pad 与内部 pad 冲突 | 互不影响（内部 pad 只针对 pos 超界；runner pad 在 TX 层面扩展 frame） |
| 其他 resample 方法（farrow/piecewise/matlab）未修 | 本 spec 范围仅 spline；其他方法独立诊断（若 runner 未调用则无影响） |
| 下游代码依赖 y_resampled 长度 == N | 保持不变（输出长度还是 N，只是内部 y 临时加长） |

## Log

- 2026-04-22 创建 spec（基于 `test_resample_doppler_error.m` 首次暴露的 resample 本征不对称）
