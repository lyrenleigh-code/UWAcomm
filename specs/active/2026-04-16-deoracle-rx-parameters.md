---
project: uwacomm
type: task
status: completed
created: 2026-04-16
updated: 2026-04-16
parent: 2026-04-15-streaming-framework-master.md
phase: P3-fix
depends_on: [P3.3]
tags: [去oracle, 接收端, 14_Streaming, 13_SourceCode, 信道估计, 噪声估计]
---

# 去 Oracle — 接收端盲估计改造

## 背景

P3.1~P3.3 从 13_SourceCode 端到端测试中抽取 6 体制 modem decode，但抽取过程中
将测试 harness 的 oracle 模式（已知信道/已知SNR/已知时延位置）一并带入了流式架构。
经排查，**13_SourceCode E2E 测试本身就存在同类 oracle 依赖**，P3 只是忠实搬运。

本 spec 旨在系统性消除接收端对发射端参数的非法依赖，使 14_Streaming（及回溯
13_SourceCode）的 RX 链路可独立运行，不依赖 TX meta 中的数据符号、精确噪声方差、
信道结构先验。

## 排查结论（2026-04-16 审计）

### 已完成去 oracle（3 项，无需修改）

| 项目 | 体制 | 实现方式 |
|------|------|----------|
| LFM/HFM 粗同步 + Doppler 估计 | 全部 | 匹配滤波+双LFM相位差 |
| OFDM 空子载波 CFO 估计 | OFDM | null subcarrier能量最小化 |
| OTFS DD域信道估计 | OTFS | 导频脉冲/ZC/叠加，delay/doppler由估计器输出 |

### 待修复 oracle（6 类）

| 编号 | 问题 | 涉及体制 | 严重度 | 修复难度 |
|------|------|----------|--------|----------|
| **O1** | 信道估计用 TX 数据符号而非训练/导频 | SC-FDE, OFDM | CRITICAL | 大 |
| **O2** | 噪声方差由 harness 直传 | SC-FDE, OFDM, SC-TDE, DSSS, OTFS | HIGH | 小 |
| **O3** | 信道时延位置 `sym_delays` 已知 | SC-FDE, OFDM, SC-TDE, DSSS | HIGH | 中 |
| **O4** | 多普勒扩展 `fd_hz` 已知 | SC-FDE, OFDM, SC-TDE | MEDIUM | 小 |
| **O5** | 衰落类型 `fading_type` 分支已知 | SC-FDE, OFDM, SC-TDE | MEDIUM | 小 |
| **O6** | 符号定时用 TX 数据做参考 | SC-FDE, OFDM | LOW-MEDIUM | 小 |

### 违规代码定位

#### O1：信道估计用 TX 数据

- `rx/modem_decode_scfde.m`
  - L85: `tx_blk1 = meta.all_cp_data(1:sym_per_block)` → GAMP 训练矩阵
  - L114: `x_vec(pp) = meta.all_cp_data(idx)` → BEM 观测矩阵
- `rx/modem_decode_ofdm.m`
  - L137: `tx_blk1 = meta.all_cp_data(1:sym_per_block)` → OMP 训练矩阵
  - L165: `x_vec(pp) = meta.all_cp_data(idx)` → BEM 观测矩阵
  - L203: `meta.all_cp_data(idx)` → nv_post 残差计算
  - L319: `x_vec(pp) = meta.all_cp_data(idx)` → DD-BEM 初始段仍用 TX 数据
- `rx/modem_decode_sctde.m`
  - L109: `tx_sym = meta.all_sym` → 加载整个 TX 符号序列
  - L141/L192/L222: 在 `known_map` 位置使用（架构可接受但实现不安全）

#### O2：噪声方差直传

- `modem_decode_scfde.m:70`, `modem_decode_ofdm.m:122`,
  `modem_decode_sctde.m:77`, `modem_decode_dsss.m:71`,
  `modem_decode_otfs.m:46`
- 三个测试文件: `meta_rx = meta_tx; meta_rx.noise_var = noise_var;`

#### O3：信道时延已知

- `sys_params_default.m:49,67,81,96,112` — 各体制 `sym_delays`/`chip_delays` hardcode
- 所有 decode 函数通过 `cfg.sym_delays` 直接使用

#### O4：多普勒扩展已知

- `modem_decode_scfde.m:126`, `modem_decode_ofdm.m:177`,
  `modem_decode_sctde.m:155` — `ch_est_bem(..., cfg.fd_hz, ...)`

#### O5：衰落类型已知

- `modem_decode_scfde.m:81`, `modem_decode_ofdm.m:76,132`,
  `modem_decode_sctde.m:42`

#### O6：符号定时参考

- `modem_encode_scfde.m:88`: `meta.pilot_sym = all_cp_data(1:10)` — CP数据，非训练
- `modem_encode_ofdm.m:101`: 同上

## Spec

### 修复方案

#### Phase A: 快速修复（O2, O4, O5, O6）— 估计 1 天

**O2 噪声方差盲估计**:
- 删除 `meta.noise_var` 字段传递
- SC-FDE/OFDM: 用训练段（修 O1 后）残差估计 `nv = mean(|y - Hx_train|^2)`
- SC-TDE: 已有 nv_post 逻辑，改为主路径（非 fallback）
- DSSS: 用训练码片相关残差
- OTFS: 已有 guard 区域估计，改为默认

**O4 多普勒扩展自适应**:
- BEM 的 `fd_hz` 参数改为 `fd_hz_max`（保守上界，如 10Hz）
- 启用 `ch_est_bem` 已有的 BIC 自动选阶功能（`Q_mode='auto'`，已实现）
- 或直接用 LFM 阶段估计的 Doppler scale 反推 fd

**O5 衰落类型统一路径**:
- 删除 `if strcmpi(fading_type, 'static')` 分支
- 统一走时变路径（BEM），静态信道下 BEM 自然退化为 LS
- 若需保留静态快速路径，改为后验判断：估计 fd 后 if fd < 阈值则简化

**O6 符号定时参考修正**:
- SC-FDE/OFDM 的 `meta.pilot_sym` 改为使用 LFM 定时后的已知位置偏移
  或在帧结构中显式插入训练前缀（与 O1 联动）

#### Phase B: 训练机制设计（O1）— 估计 2~3 天

**SC-FDE 训练方案**（两选一）:
- 方案 A（最小改动）: 在每 N_blocks 的**第 1 块**改为已知训练块（seed 固定）
  - RX 用训练块做 GAMP/OMP 估计初始 CIR
  - 后续块走 DD 迭代精化（已有 Turbo DD-LS 逻辑）
  - 代价: 1/N_blocks 速率损失（~3%@32块）
- 方案 B（散布导频）: 对齐 SC-TDE 架构，在数据流中插入已知导频簇
  - 需要改 encode + decode + 帧结构
  - 更适合时变信道，但改动量大

**OFDM 训练方案**:
- 方案 A（推荐）: OFDM 第 1 块改为全导频 OFDM 符号（梳状或块状导频）
  - 子载波位置已知，RX 做 LS/OMP 初始估计
  - 后续块仍走 DD-BEM
  - 代价: 1/N_blocks 速率损失（~6%@16块）
- 方案 B: 在每块的 null_idx 附近交替插入 pilot（散布导频）
  - 需修改子载波分配

**SC-TDE 安全重构**:
- `meta.all_sym` 拆分为 `meta.training` + `meta.pilot_sym_ref` + `meta.known_map`
- decode 端本地重生成 training（seed=99）和 pilot_sym_ref
- 禁止传入 `all_sym`

#### Phase C: 信道时延估计（O3）— 估计 1~2 天

**方案**: 在信道估计前增加时延搜索前级

- 选项 1（简单）: 用 OMP 的稀疏恢复结果自动发现非零抽头位置
  - `ch_est_omp` 已支持，目前 `L_h` + `K_sparse` 是先验
  - 改为: 传入 `L_max`（最大时延扩展，协议参数）+ 稀疏度上界
  - OMP 输出非零位置 → 作为后续 BEM/GAMP 的 `sym_delays`
- 选项 2（精确）: 训练序列自相关峰搜索
  - `delays_est = find(abs(R_xy) > threshold) - 1`
  - DSSS: 训练码片相关，天然可发现 Rake finger 位置

### 验收标准

- [ ] **meta 字段审计**: decode 函数的 meta 参数不包含 `all_cp_data`, `all_sym`,
      `noise_var` 等 TX 数据/oracle 字段。允许的 meta 字段限于:
      `N_info`, `perm_all`, `blk_fft/blk_cp/N_blocks`（协议参数）,
      `pilot_config`（导频配置）, `data_indices`（帧结构）
- [ ] **噪声方差盲估计**: 删除 `meta.noise_var` 注入，5 体制的 fallback 路径全部通过测试
- [ ] **时延位置估计**: `sym_delays` 不再由 `sys_params_default` hardcode 传入 decode，
      由 OMP/相关峰搜索得到
- [ ] **BEM 自适应阶数**: `fd_hz` 不传入 decode，BEM 用 BIC 自动选阶或保守上界
- [ ] **衰落类型统一**: 删除 `fading_type` 分支，统一时变路径
- [ ] **BER 回归**: 每体制 BER 与当前基线偏差 ≤ 1%（去 oracle 可能略有损失）
- [ ] **Oracle 排查清单**: 提交前过 CLAUDE.md §7 Oracle 排查清单

### 测试策略

1. **逐项验证**: 每修复一类 oracle，立即跑对应体制测试，确认 BER 不退化
2. **全体制回归**: 全部修复后跑 `test_p3_unified_modem.m`（删除 `meta_rx = meta_tx` 行）
3. **时变信道回归**: 恢复 fd=1Hz/5Hz 场景，验证 BEM 自适应阶数+盲噪声估计有效
4. **A/B 对比**: 保留 oracle baseline 作为性能上界参考

### 风险

| 风险 | 概率 | 缓解 |
|------|------|------|
| 训练块导致 SC-FDE/OFDM 速率下降 | 确定 | 控制在 <6%，P4 header 帧头可复用训练 |
| 盲噪声估计在低 SNR 偏差大 | 中 | nv_post 残差法在 Turbo 后精度随迭代改善 |
| OMP 时延搜索漏径 | 低 | 设 L_max 为最大时延扩展的 1.5x 余量 |
| BEM BIC 选阶在极低 SNR 欠拟合 | 低 | 设 Q_min=2 下界 |

### 优先级排序

```
Phase A (O2+O4+O5+O6) → Phase B (O1) → Phase C (O3)
```

Phase A 可立即开始，不影响帧结构。Phase B 需要 encode/decode 联动修改。
Phase C 可与 Phase B 并行。

## Plan

待讨论确认后创建 `plans/deoracle-rx-parameters.md`。

## Log

### 2026-04-16 — Spec 创建

Oracle 审计完成，6 类问题定位到代码行级。确认 13_SourceCode E2E 本身就存在
同类 oracle 依赖（非 P3 引入），需系统性修复。
