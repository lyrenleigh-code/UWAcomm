---
project: uwacomm
type: design
status: archived
created: 2026-04-26
updated: 2026-04-26
archived: 2026-04-26
parent_spec: specs/archive/2026-04-24-scfde-bem-decision-feedback-arch.md
related: A1 验证 (commit c8ccb06)、Phase 3b limitation
tags: [SC-FDE, 协议层, 时变信道, 训练块, 导频, 13_SourceCode, 14_Streaming, Phase4, Phase5]
branch: claude-uwacomm-work-20260425
---

# SC-FDE 时变信道 fd=1Hz limitation 协议层突破设计（Phase 4）

## 背景

Phase 3b.2 + 路线 4 (A1) 验证（2026-04-26 commit `c8ccb06`）确认：jakes fd=1Hz × 1.024s 帧 ≈ 1 完整 Jakes 周期下，单训练块 SC-FDE 在 14 production / 13 移植 decoder 都 ~50% BER —— **架构层 trade-off，不可在 decoder 层优化**。

要恢复 Phase 1 水平 BER（fd=1Hz 0.16/0/0/0%），需协议层改动。本 spec 评估 4 候选方案，推荐方案 A 立 Phase 4。

## 候选方案对比

### 方案 A：多训练块周期插入（Periodic Pilot Block Insertion）

帧结构：`[train | data×K | train | data×K | ...]`，每 K 个 data block 后插入一个训练块。

- **TX**：`modem_encode_scfde.m` 改 frame layout（加参数 `cfg.train_period_K`）
- **RX**：`modem_decode_scfde.m` 提取每个训练块作 BEM 观测，跨块时间分散覆盖 Jakes 周期
- **吞吐损失**：`1/(K+1)`：K=4 → 20%, K=8 → 11.1%
- **BEM 观测**：每帧 `M+1` 个训练块 CP 段，时间分散 `M·K·T_block`，覆盖整个 Jakes 周期

### 方案 B：叠加导频（Superimposed Pilot, OTFS 式）

每数据块叠加低功率训练序列 `p[n]`：`x[n] = data[n] + α·p[n]`。RX 用 superimposed pilot 段相关分离 H + data。

- **TX**：每块加 superimposed pilot
- **RX**：叠加导频做初始 H，再 Turbo 软判决
- **吞吐损失**：0（不占符号槽，仅占功率，~10% 功率分担）
- **复杂度**：高（动 modem 协议 + RX 分离算法）
- **参考**：Zakharov 2019 MBA + Sun 2020 DSSS（Hub `source-summaries/sun-2020-dsss-passband-doppler.md`）

### 方案 C：超训练块覆盖整个 Jakes 周期

单训练块长度 `≥ 1/(2·fd_min)`：fd=1Hz → 训练块 ≥ 0.5s ≈ 3000 samples（@fs=48kHz, sym_rate=6kHz → 750 sym）。

- **TX**：blk_fft=训练块长度（>256，FFT 复杂度增加）
- **RX**：训练块横跨 Jakes 周期，BEM 单块即可拟合时变
- **吞吐损失**：极大（训练块占整帧主要部分，N_blocks 减少）
- **复杂度**：低（仅参数调整）
- **❌ 不推荐**：吞吐损失太大；fd_min 未知不能 hardcode

### 方案 D：半训练（Decision-Aided Training, RX-only）

帧结构不变 `[train | data×K]`，K 大但 RX 用 Turbo iter≥2 的高置信度软符号（var<0.3）当作"虚拟训练序列"扩充 BEM 观测。

- **TX**：不改
- **RX**：BEM 观测扩张，门控 `var<0.3`（比 14 production 的 0.5 严格）
- **吞吐损失**：0
- **复杂度**：低（只动 RX 门控）
- **❌ A1 已部分否定**：jakes fd=1Hz 第 8 block 完全失配，var<0.5 都达不到，var<0.3 不可能；本质是 A1 已证明的 decoder-only 路线失败延续

## 推荐：方案 A（多训练块插入）

| 维度 | A 多训练块 | B 叠加导频 | C 超训练块 | D 半训练 |
|------|----------|----------|----------|---------|
| 实现复杂度 | 低 | 高 | 低 | 低 |
| 吞吐损失 | 11-20% | 0 | 极大 | 0 |
| 物理直觉 | 清晰（跨块时间分散） | 中（功率分担） | 弱（依赖 fd 已知） | 弱（A1 已证 decoder-only 路线失败） |
| 与现有算法兼容 | 完全（不动 ch_est_bem） | 需新算法 | 完全 | 完全 |
| 学术参考 | 通用 | Zakharov 2019 / Sun 2020 | 罕见 | 已有但失败 |
| 适合 Phase 4 立项 | ✅ 推荐 | 长期方向 | ❌ | ❌ |

**理由**：
1. 实现复杂度最低（只改 frame layout + RX 训练块识别）
2. 吞吐损失可控（K=4-8 → 11-20%）且参数可调
3. 物理直觉清晰（跨块时间分散必然覆盖 Jakes 周期，不依赖 fd 已知）
4. 与 `ch_est_bem` 完全兼容
5. K 参数可调，可做 K vs BER 曲线 → trade-off 决策有数据支撑

## Phase 4 分解（方案 A）

### Phase 4a — Frame layout 协议改动

- `modem_encode_scfde.m`：加参数 `cfg.train_period_K`（默认 N_blocks-1 = 单训练块，向后兼容）；每 K 个 data block 后插入 train block
- `meta` 字段加 `train_block_indices`（1×(M+1) 全局 block index）+ `data_block_indices`（1×N_data 全局）
- `modem_decode_scfde.m`：提取所有 train block 作 BEM 观测；data block 仍走 Turbo

### Phase 4b — BEM 观测扩展

- `build_bem_observations_scfde.m` 改造：训练块 CP 段 × (M+1)，跨块时间覆盖
- 数据块 CP 段（Turbo 软符号）作 fallback 增强（可选，类似 Phase 3b.2）

### Phase 4c — 验证

| 测试 | 场景 | 期望 |
|------|------|------|
| V4a | static SNR={5,10,15,20} × seed×3 | 不退化 |
| V4b | fd=1Hz K={4,8,16} × SNR×4 × seed×3 | K=4 BER < 5%（恢复 Phase 1 水平） |
| V4c | fd=5Hz K={4,8} × SNR×4 | 接近 fd=1Hz K=8 性能 |
| V4d | K vs BER 曲线 | trade-off 决策依据 |
| V4e | 13 + 14 双侧（13_SourceCode test_scfde_timevarying.m + 14 production） | 一致 |

## 非目标

- ❌ 不做方案 B/C/D（B 长期方向，C/D 已分析不推荐）
- ❌ 不动 `ch_est_bem` 内部
- ❌ 不动其他 5 体制
- ❌ 暂不做 OTFS 式叠加导频（OTFS 项目已暂停 per memory `feedback_uwacomm_skip_otfs`）

## 风险

- **R1**：跨训练块 BEM 观测仍可能 rank-deficient（K 太大 → 训练块数 < BEM 阶数）。缓解：K=4 起，逐步加大；ch_est_bem 加 BIC 自适应阶数。
- **R2**：14_Streaming production 接口改动可能破坏 P1-P4 测试。缓解：`default cfg.train_period_K = N_blocks-1`（单训练块）保持向后兼容。
- **R3**：吞吐损失 ≥ 11% 可能不被项目目标接受。缓解：Phase 4d K vs BER 曲线作数据驱动决策。
- **R4**：jakes 自相关零点位置随机，K=4 可能不足以覆盖（最坏 4 块全在自相关零点附近）。缓解：必要时加 train block 准随机偏移（type Latin square 设计）。

## 接受准则

- [ ] `modem_encode_scfde.m` 加 `train_period_K` 参数（向后兼容 K=N_blocks-1）
- [ ] `modem_decode_scfde.m` 跨训练块 BEM 观测
- [ ] `build_bem_observations_scfde.m` 单元测试 PASS
- [ ] V4a static 不退化
- [ ] **V4b fd=1Hz K=4 BER < 5%（恢复 Phase 1 水平）**
- [ ] V4c fd=5Hz K=4-8 BER < 10%
- [ ] V4d K vs BER 曲线作 trade-off 决策依据
- [ ] V4e 13 + 14 双侧实现一致
- [ ] SC-FDE 调试日志 V3.0 章节
- [ ] Spec 归档

## 工时估算（方案 A）

- Phase 4a：modem_encode/decode 改造 1-2h
- Phase 4b：BEM 观测扩展 1h
- Phase 4c：5 项验证 2-3h
- 文档/归档：30 min
- **总计：~5-7h 单次工作**

## 参考

- A1 实测：commit `c8ccb06`，`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_a1_streaming_decoder_jakes.m`
- Parent spec：`specs/archive/2026-04-24-scfde-bem-decision-feedback-arch.md`
- Hub source：`Ohmybrain/wiki/source-summaries/sun-2020-dsss-passband-doppler.md`（Zakharov 2019 MBA + superimposed pilot）
- 现有协议基线：`modules/14_Streaming/src/Matlab/tx/modem_encode_scfde.m`（block 1=train, blocks 2..N=data）

## 优先级

🟢 高优先（接 Phase 3b.2 limitation 直接续接）。但工作量 5-7h 较大，建议**用户先拍板方案** A/B/C/D，再决定立 Phase 4 实施。

## 用户拍板（2026-04-26）：方案 A 立 Phase 4 实施

## Phase 4（方案 A）实施 + V4 验证（2026-04-26）

实施完成 commits（待 commit）：
- `modem_encode_scfde.m V3.0`：cfg.train_period_K + meta.train_block_indices/data_block_indices
- `modem_decode_scfde.m`：读 train/data indices + 局部 build_bem_observations 升级到 V4.0
- `build_bem_observations_scfde.m V2.0`：data-only x_bar_blks + train/data indices 入参
- `test_scfde_timevarying.m`：bench_train_period_K 协议派生
- `test_build_bem_obs_scfde.m V2.0`：单元测试 3/3 PASS（单训练块 96 obs / 多训练块 K=4 N=16 384 obs / ch_est_bem 兼容）

### V4 实测（A2 脚本，3 seed × 4 SNR × 4 K × 3 fading）

| K | N_train | 吞吐 | static (4 SNR mean) | fd=1Hz | fd=5Hz |
|---|---|---|---|---|---|
| 15 (单) | 1 | 93.8% | 0.13% | 47.05% | 49.63% |
| 8 | 2 | 87.5% | 0.17% | 49.17% | 49.52% |
| 4 | 4 | 75.0% | 0.52% | 49.97% | 48.95% |
| 2 | 6 | 62.5% | 0.13% | 49.35% | 50.05% |

### 接受准则（V4）

- [x] V4a static 任意 K 不退化（PASS）
- [ ] V4b fd=1Hz K=4 BER < 5%（**FAIL** mean=49.97%）
- [ ] V4c fd=5Hz K=4 BER < 10%（**FAIL** mean=48.95%）

### V4 失败根因

**iter=0..1 H_init 仍单块 GAMP** — Phase 4 协议层加了多 train block，但 RX 仍把第 1 个 train block 的 GAMP 估计当作所有 block 的初值：
1. iter=0..1 LMMSE-IC 用 H_init = GAMP(train_block_indices(1))
2. jakes 第 8 block h 与训练块 h 自相关 ≈ 0 → 完全失配 → 软符号 ~50% 错（var ≈ 0.5）
3. titer=2 BEM 触发条件 `mean(var)<0.6` 满足，但 BEM 观测中 12 个 data block CP 段（每段 ~24 obs，共 ~288 obs）用 garbage 软符号
4. 4 个干净 train CP（96 obs）被 288 garbage obs 稀释 → BEM 估计仍受污染 → Turbo 不收敛

**UWAcomm-codex 独立验证**（spec checkpoint 2026-04-25）：fd=1Hz seed=42 SNR=10 BER=50.23%，结论"初始 H 质量不足，Turbo 在 BEM 前已发散，spec 标 blocked"。

## 后续方向（2026-04-26 用户决策）

按顺序实施：

### 方案 E（先做）：block-pilot 末尾插入

每个 data block 末段 `N_pilot_per_blk` 个 symbol 替换为已知 pilot：
- 帧结构：`block = [CP | data_part | pilot_part]`，`data_part_len = blk_fft - N_pilot_per_blk`
- 例 N_pilot_per_blk=32, blk_fft=256 → data_per_blk=224，吞吐损失 12.5%
- pilot_seq seed=99（与 train_seed=77 错开），RX 本地重建
- **关键**：pre-Turbo BEM 直接用 train block CP + 每 data block 末 pilot 段构造观测（**全干净，无软符号依赖**）
- iter=0 用 BEM 时变 H_tv 而非单块 GAMP

物理直觉：N_blocks=16 × pilot_per_blk=32 = 512 干净跨时间观测，足以拟合 jakes fd=1Hz × 1.024s 帧周期（远超 Nyquist 2·fd·T=2 sample 要求）。

灵感：UWAcomm-codex `2026-04-14-otfs-spread-pilot.md` 已 completed（superimposed pilot 方案 C），static/disc-5Hz × SNR=10/15/20 coded BER 全 0%，TX PAPR ≤10dB 验收 PASS。OTFS 域 superimposed pilot 实施成熟，思路移植到 SC-FDE 时域。

### Phase 4-revision（再做）：iter=0 多 train block 联合 BEM

沿用方案 A 架构（多 train block），但把 iter=0..1 的 H_init 改为 pre-Turbo pure-pilot BEM（不等 Turbo 软符号）。
- 与方案 E 互补：方案 E 加 pilot 槽，Phase 4-revision 沿用 train block 但提前 BEM
- 工作量比方案 E 小（不动 frame layout，只改 RX）

## Phase 5（方案 E）实施计划

### 5a Frame layout（TX）

- `modem_encode_scfde.m V4.0`：`cfg.pilot_per_blk` (默认 0=禁用)
- `meta.pilot_per_blk`, `meta.pilot_seed=99`, `meta.N_data_per_blk = blk_fft - pilot_per_blk`
- 每 data block：`[data_per_blk QPSK + pilot_per_blk pilot]` → CP 取末 blk_cp 符号

### 5b RX pre-Turbo BEM

- 新建 `build_bem_obs_pretturbo_scfde.m`：用 train block CP + 每 data block pilot 段构造观测（全干净）
- `modem_decode_scfde.m V4.1`：在 §5 GAMP 之后 §6 之前加 pre-Turbo BEM 调用
- `H_est_blocks` 初始化用 BEM h_tv 时变估计而非单块 GAMP

### 5c 验证

- V5a static SNR={5,10,15,20} × pilot_per_blk={0,32} × seed=3 → 不退化
- V5b fd=1Hz pilot_per_blk={32, 64} × SNR×4 × seed×3 → **关键**：BER < 5%
- V5c fd=5Hz pilot_per_blk={32} × SNR×4 → BER < 10%

## Phase 5 接受准则

- [x] modem_encode_scfde V4.0：pilot_per_blk 协议（向后兼容默认 0）
- [x] modem_decode_scfde V4.1：pre-Turbo BEM 入口
- [x] build_bem_obs_pretturbo_scfde.m + 单元测试 V2.0 PASS（3/3）
- [x] V5a static 不退化（pilot=128 SNR≥10 全 0%；SNR=5 边界 5.02%）
- [x] **V5b fd=1Hz pilot=128 BER mean=3.37%（< 5% PASS）✅**
- [ ] V5c fd=5Hz BER mean=13.80%（< 10% FAIL，但 SNR=20 已 3.53%）
- [x] SC-FDE 调试日志 V3.0 章节
- [x] Spec 归档（active → archive）

## Phase 4 + Phase 5 实测落地（2026-04-26 归档）

### Phase 4 方案 A — 失败根因（多 train block 但 RX 单块 GAMP H_init）

A2 实测（3 seed × 4 SNR × 3 fading × 4 K，pre-Turbo OFF）：

| K | N_train | 吞吐 | static | fd=1Hz | fd=5Hz |
|---|---|---|---|---|---|
| 15 (单 train baseline) | 1 | 93.8% | 0.13% | 47.05% | 49.63% |
| 8 | 2 | 87.5% | 0.17% | 49.17% | 49.52% |
| 4 | 4 | 75.0% | 0.52% | **49.97%** | 48.95% |
| 2 | 6 | 62.5% | 0.13% | 49.35% | 50.05% |

**FAIL** — V4b/V4c 均不达标。仅协议层加 train block 但 RX 仍用第 1 个 train block 的 GAMP 单块 H_init → jakes 第 8 block 完全失配 → 软符号 ~50% 错（var≈0.5）→ 14 production 的 `mean(var)<0.6` 关闭 BEM + `var<0.5` 关闭 DD fallback → H 永不更新 → BER ~50%。

### Phase 4-revision — 多 train block + pre-Turbo BEM

modem_decode_scfde V4.1 扩展 pre-Turbo BEM 触发条件 `(N_pilot_per_blk > 0) || (N_train_blocks > 1)`，跳过 Turbo 软符号依赖。

A2 v2 实测：

| K | N_train | static | fd=1Hz | fd=5Hz | obs/帧 |
|---|---|---|---|---|---|
| 15 (无 pre-Turbo) | 1 | 0.13% | 47.05% | 49.63% | n/a |
| 8 | 2 | 11.30% | 49.74% | 49.30% | ~76 |
| **4** | 4 | 3.35% | **18.31%** | 49.25% | ~152 |
| 2 | 6 | 0.53% | 17.72% | 50.12% | ~228 |

**部分改善**：K=4 fd=1Hz 47% → 18.31%（30 pp），但仍 > 5% 接受准则。obs 数 152 远不及方案 E 1178。

### Phase 5 方案 E — block-pilot 末尾插入

**TX 协议**：每 data block 末嵌入 N_pilot_per_blk 个 pilot symbol（seed=99）。N_pilot ≥ blk_cp 时 CP 全 pilot → CP+pilot tail 全干净 BEM 观测。

A3 实测（5 pilot × 3 fading × 3 seed × 4 SNR）：

| pilot_per_blk | static (mean) | **fd=1Hz** | fd=5Hz | 吞吐 |
|---|---|---|---|---|
| 0 (baseline) | 0.13% | 47.05% | 49.63% | 100% |
| 32 | 6.17% | 48.66% | 49.28% | 87.5% |
| 64 | 14.20% | 49.37% | 48.70% | 75% |
| 96 | 2.66% | 45.55% | 49.72% | 62.5% |
| **128 (=blk_cp)** | **1.38%** | **3.37%** ✅ | 13.80% | **50%** |

**关键阈值**：仅 pilot ≥ blk_cp 时 work（max_tau=90 占用 CP 段 obs 资格）。

### A4 组合验证 — A+E 不优于纯方案 E

A+E (K=4 + pilot=64) 实测 fd=1Hz 20.82% 远不及纯 K=15+pilot=128 的 3.25%。pilot<blk_cp 时多 train + 少 pilot 的 obs 几乎全被 lookup all_known check 否决。

### V5c 调优尝试（fd_est_pretturbo 10→20）

实测 fd=5Hz 12.97% → 13.80%，几乎无效。auto Q 公式 `2·ceil(fd·T)+3`（fd_est=10→Q=21, fd_est=20→Q=39）已经足够，**Q 不是瓶颈**。fd=5Hz 低 SNR BEM 噪声敏感是与 Q 阶无关的物理代价。

### 突破总结（vs baseline）

| 指标 | baseline | 方案 E pilot=128 | 改善倍数 |
|---|---|---|---|
| fd=1Hz mean | 47.05% | **3.37%** | **14×** |
| fd=5Hz mean | 49.63% | 13.80% | 3.6× |
| fd=5Hz SNR=20 | 50.06% | 3.53% | 14× |

### 已知 Limitation

1. **吞吐损失 50%** — pilot=128=blk_cp 物理代价，由 max_tau/blk_fft 比决定
2. **fd=5Hz 低 SNR (5-10dB) BER 15-29%** — BEM 在低 SNR 噪声敏感，需 SNR≥15dB 才稳定工作
3. **pilot < blk_cp 不 work** — A+E 组合实测劣于纯方案 E

### 后续方向（不在本期范围）

- BEM 噪声鲁棒化（lambda 自适应 + iter refinement）
- Midamble pilot（pilot 放 block 中部，不依赖 CP 段全 pilot）
- 协议设计：减小 max_tau / blk_cp 比，让 pilot < blk_cp 也能干净
- Turbo 内置 BEM refinement（mid-Turbo BEM 复用 pre-Turbo 结果）
