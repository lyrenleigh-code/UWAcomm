---
project: uwacomm
type: task
status: active
created: 2026-04-24
updated: 2026-04-25
tags: [SC-FDE, BEM, oracle 清理, 判决反馈, 架构改动, 13_SourceCode, 14_Streaming, limitation]
branch: arch/scfde-bem-decision-feedback
parent_spec: specs/archive/2026-04-24-scfde-sps-deoracle-arch.md
---

# SC-FDE BEM 观测矩阵判决反馈去 oracle（Phase 3b）

## 背景

Phase 3 单 block 观测方案（spec `archive/2026-04-24-scfde-sps-deoracle-arch.md` 在本次归档中）证伪：
- 只用训练块 CP 段观测（fd=1Hz 37 个点）→ BEM DCT basis 无法拟合 Jakes 时变
- 实测：fd=1Hz 5dB 0%→49.64%，10dB 0%→49.84%，15dB 0%→47.32%，20dB 0%→49.17%
- 回滚后 BER 恢复 Phase 1 水平（0.16/0/0/0%）

根因：BEM 时变估计需要**跨块时间分散观测**采样 Jakes 变化率，单 block 观测只看到帧初始
快照，返回退化为恒定 h。

## 目标

移植 14_Streaming `modem_decode_scfde.m::build_bem_observations` 两阶段方案到
`test_scfde_timevarying.m`（+ 后续 `test_scfde_discrete_doppler.m`）：
- **Stage 1（training block）**：训练块 CP 段 + train_cp 观测（合法，已在 Phase 1
  架构里）
- **Stage 2（Turbo iter≥2）**：数据块 CP/data 段 + Turbo 判决软符号 `x_bar_blks` 观测
- BEM 从"initial 估计"变为"mid-Turbo 估计"，在 iter=1 跑完后重估一次

## 设计参考

`modules/14_Streaming/src/Matlab/rx/modem_decode_scfde.m::build_bem_observations`（L294-362）:
- 训练块 CP: `x_vec(pp) = train_cp(idx)` for `n = max_tau+1..blk_cp`
- 数据块 CP: `x_vec(pp) = xb(blk_fft - blk_cp + local_n)` （data block 尾部 blk_cp 符号 = CP）
- 数据块 data 段: `x_vec(pp) = xb(local_n - blk_cp)`
- xb = x_bar_blks{bi_idx}（Turbo 上一轮软符号）

## 关键架构改动

### D1：BEM 从 pre-Turbo 移到 Turbo iter=2

当前 `test_scfde_timevarying.m` L678-700 的 BEM 是 **iter=0 前做一次**（用 oracle
observation）作为 H_est_blocks 初值。改为：
- iter=0..1：只用 GAMP 静态信道估计（static 路径）或 per-block per-CP 近似估计
  （时变路径 fallback）
- iter=2：x_bar_blks 已有 Turbo 第一轮软符号，调 `build_bem_observations(...)` 跨块
  构造观测 → `ch_est_bem` → `h_tv_bem` 填充 H_cur_blocks
- iter=3..N：沿用新 H_cur_blocks（或继续按 DD 重估迭代）

### D2：Iter 0-1 信道估计 fallback

方案 A（推荐）：per-block DD 估计（不依赖跨块观测）
- 对每个 block bi：`H_dd = Y_freq_blocks{bi} ./ (X_init)`，X_init=1（白谱初值）
- 低精度但至少不发散

方案 B：跟 14_Streaming 一致用 per-block 判决辅助（iter=1 跑完后 fallback）

### D3：数据块观测的 idx 映射

14_Streaming 的 build_bem_observations 逻辑 L320-350：
```matlab
for bi = 1:N_data_blocks
    blk_idx = bi + 1;                       % 全局 block
    blk_start = (blk_idx - 1) * sym_per_block;
    x_bar_this = x_bar_blks{bi};            % 14_Streaming 里 x_bar_blks{1..N_data_blocks}
    ...
    blk_of_idx = floor((idx - 1) / sym_per_block);
    if blk_of_idx == 0, use train_cp;
    else bi_idx = blk_of_idx; use x_bar_blks{bi_idx};
```

注意 14_Streaming 的 `x_bar_blks` 索引从 1 开始（data block only），而 13_SourceCode
test_scfde_timevarying.m Phase 1 版本是 `x_bar_blks{1..N_blocks}` 全局 index
（x_bar_blks{1}=train_sym）。

**需对齐一种索引方案**。推荐沿用 13 版本（全局 index，x_bar_blks{1}=train_sym，
x_bar_blks{2..N}=data 软符号）。

## Phase 分解

### Phase 3b.1 — 移植 build_bem_observations

- 在 `test_scfde_timevarying.m` 内定义局部函数 `build_bem_observations_scfde(...)`
- 逻辑复制 14_Streaming（L294-362），索引按 13 全局版本
- 单元测试：调用 build_bem 返回 obs_y/obs_x/obs_n，长度 ≈ N_blocks × (blk_cp - max_delay)

### Phase 3b.2 — BEM iter 结构重组

- 移除 pre-Turbo 的 BEM 调用（L678-700 时变分支）
- 时变分支 iter=0..1 改用 per-block DD estimate 作 H_cur_blocks 初值
- iter=2 调 build_bem_observations 重估 h_tv → 覆盖 H_cur_blocks
- iter=3..N 沿用 / 继续 DD 重估

### Phase 3b.3 — 回归验证

- V3a α=0 static SNR={10,15,20} × 5 seed: 不退化
- V3b fd=1Hz SNR={5,10,15,20}: **回归 Phase 1 水平**（0.16/0/0/0%）
- V3c fd=5Hz: 持平物理极限 ~50%
- V3d α=+1e-2/-1e-2 × 5 seed: 不退化（Phase 1 水平）

### Phase 3b.4 — 推广

- `test_scfde_discrete_doppler.m` 同模板迁移（带离散 Doppler 场景验证）

## 非目标

- ❌ 不改 14_Streaming（production 已完成）
- ❌ 不改 `ch_est_bem` 内部（观测接口不变）
- ❌ 不动其他 5 体制
- ❌ 不做 `test_scfde_static.m`（oracle baseline 已声明）

## 风险

- **R1**：iter=0..1 fallback 估计若不准 → Turbo 发散 → x_bar_blks 不可信 → iter=2 BEM
  也不准。缓解：实测观察，必要时用 per-block GAMP 初值（但 GAMP 假设稀疏静态，时变下
  可能不适合）
- **R2**：Turbo mid-iter 改信道架构可能与 E2E benchmark C 阶段 CSV 字段（turbo_final_iter）
  冲突。缓解：保持 turbo_iter=6 不变，只是内部 BEM 重估位置变
- **R3**：fd=5Hz 物理极限下软符号全错，x_bar_blks 观测为随机噪声 → BEM 估计为
  garbage。缓解：~50% 场景本来就是灾难，不影响结论

## 工时估算

- Phase 3b.1：移植 build_bem_observations（30 min）
- Phase 3b.2：BEM 结构重组（45 min）
- Phase 3b.3：验证 + 迭代（30-60 min）
- Phase 3b.4：discrete_doppler 迁移（30 min）
- 总计：~2-3h 单次工作

## 接受准则

- [ ] Phase 3b.1 build_bem_observations_scfde 单元测试通过
- [ ] Phase 3b.2 iter=2 BEM 调用成功，无矩阵 rank 错误
- [ ] V3b fd=1Hz 5dB 0.16% / 10-20dB 0%（回归 Phase 1 水平）
- [ ] V3a static 不退化
- [ ] discrete_doppler runner 同模板迁移
- [ ] `wiki/modules/13_SourceCode/SC-FDE调试日志.md` 追加 V2.3 章节
- [ ] 本 spec + 原 sps-deoracle-arch spec 归档
- [ ] `all_cp_data` 在 RX 链路完全消除（包括 nv_post 估计段 L413 的残留）

## 关键文件

- ✏️ `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m`（主）
- ✏️ `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_discrete_doppler.m`（Phase 3b.4）
- 📖 `modules/14_Streaming/src/Matlab/rx/modem_decode_scfde.m::build_bem_observations`
- 📖 Parent spec: `specs/archive/2026-04-24-scfde-sps-deoracle-arch.md`

## 优先级

🟡 中优先。Phase 1+2 已去 2/3 oracle（sps + GAMP）static 路径干净；BEM 剩余 oracle
属时变路径，benchmark baseline 场景可接受（CLAUDE.md §2 白名单）。触发 Phase 3b 的条件：
- E2E benchmark 要跑 production-grade 时变信道对比
- 学术论文需要证明完全去 oracle 的 SC-FDE 时变 BER
- 若均无，低优先保持当前状态

## 进度（2026-04-25 归档）

### Phase 3b.1 ✅ commit `55e3cd5`
- `build_bem_observations_scfde.m` 移植到 `tests/bench_common/`（13 全局 index 版本）
- 单元测试 `test_build_bem_obs_scfde.m` 6/6 PASS（n_obs=96，h_tv 6×1280，ch_est_bem 兼容）

### Phase 3b.2 🟡 实施完成（未 commit），实测显示 fd 时变路径灾难
**`test_scfde_timevarying.m` 三处 edit**：
1. addpath `bench_common`
2. L648-720 重构：删除 oracle BEM 分支，统一 GAMP 静态估计作 iter=0..1 fallback
3. Turbo loop titer=2 入口插入 `build_bem_observations_scfde + ch_est_bem` 重估

**默认运行 BER（4 SNR × 3 fading × 1 seed）**：

| 场景 | 5dB | 10dB | 15dB | 20dB | 接受准则 | 状态 |
|------|-----|------|------|------|----------|------|
| static | 0.00% | 0.00% | 0.00% | 0.00% | 不退化 | ✅ V3a PASS |
| fd=1Hz | 50.23% | 50.13% | 50.03% | 50.31% | 0.16/0/0/0% | ❌ V3b 灾难 |
| fd=5Hz | 50.73% | 49.90% | 49.22% | 51.31% | ~50% 物理极限 | ✅ V3c PASS |

**V3b fd=1Hz 灾难根因**（spec R1 兑现）：
- jakes fd=1Hz × 16 block × 256 sym/block ≈ 1.024s ≈ 一个完整 Jakes 周期
- 第 8 block 时刻 h 与训练块 h 自相关接近 0（T₀=1/(2fd)=0.5s）
- iter=0..1 用 GAMP 静态 H 在第 8 block 附近完全失配 → titer=1 软符号 ~50% 错
- titer=2 BEM 用 garbage 软符号构造观测 → BEM 估计 garbage → Turbo 不收敛
- Phase 1 oracle BEM 0.16% 是因为 oracle x_bar 直接给出正确 h，**完全跳过软符号-信道耦合**
- 软符号-BEM 鸡-蛋耦合在 jakes 时变 + 单训练块下不可解

**14_Streaming 对比调研结论**：
14_Streaming production 的 `modem_decode_scfde::build_bem_observations` **没有 jakes fd=1Hz 实测 BER 数据**：
- 14_Streaming 验证场景：`gen_doppler_channel + p4_channel_tap` = α 时变 + 静态多径 conv
- 13_SourceCode 验证场景：`gen_uwa_channel` = jakes Doppler spread（径增益时变）
- fd=1Hz 50% 是 jakes 时变 + 单训练块 + 判决反馈架构 trade-off 的**首次实测发现**，无 production 对比标杆

### Phase 3b.3/3b.4 ⏸ 未启动（pending）

### 接受准则达成度

- [x] Phase 3b.1 build_bem_observations_scfde 单元测试通过
- [x] Phase 3b.2 iter=2 BEM 调用成功，无矩阵 rank 错误
- [ ] V3b fd=1Hz 5dB 0.16% / 10-20dB 0% — **不可达成**（架构 trade-off）
- [x] V3a static 不退化
- [ ] discrete_doppler runner 同模板迁移（Phase 3b.4 未启动）
- [x] `wiki/modules/13_SourceCode/SC-FDE调试日志.md` 追加 V2.3 章节
- [ ] 本 spec + 原 sps-deoracle-arch spec 归档（待用户决策）
- [x] `all_cp_data` 在 RX 链路完全消除（spec 接受准则核心目标达成）

### 用户决策（2026-04-26）：先跑路线 4 (A1) → 据结果走路线 1

## A1 验证 + 路线 1 落地（2026-04-26）

### A1 实测

**Plan**: `plans/a1-streaming-decoder-jakes-validation.md`
**脚本**: `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_a1_streaming_decoder_jakes.m`

TX 14_Streaming `modem_encode_scfde` + Channel `gen_uwa_channel` jakes fd=1Hz + RX 14_Streaming production `modem_decode_scfde`（含 `mean(var)<0.6` BEM 门控 + `var<0.5` DD fallback），3 seed × 4 SNR × 3 fading，36 次运行无 crash。

| 场景 | A1 (14 production) mean | V3 (13 移植 1 seed) | 差异 |
|------|--------------------------|---------------------|------|
| static (健全) | 0.41% (5dB 1.60% / 其余 ~0) | 0/0/0/0% | < 2 pp |
| **fd=1Hz** | **50.02%** | **50.18%** | **< 0.2 pp** |
| fd=5Hz | 49.86% | 50.29% | < 0.5 pp |

### 决策：架构 trade-off 确认

14_Streaming production 与 13 移植在 jakes fd=1Hz 下 BER 几乎相同（差 < 0.2 pp）→ **不是 13 移植 bug，是架构层 trade-off**。`mean(var)<0.6` BEM 门控 + `var<0.5` DD fallback 都被 jakes 第 8 block 失配触发的 ~50% 软符号错误关闭 → H 永不更新 → BER ~50%。

**协议层根因**：单训练块 + jakes fd=1Hz × 1.024s 帧周期 ≈ 1 完整 Jakes 周期 → 不可在 decoder 层优化。

### 接受准则（重写后）

- [x] Phase 3b.1 build_bem_observations_scfde 单元测试通过
- [x] Phase 3b.2 iter=2 BEM 调用成功，无矩阵 rank 错误
- [x] V3a static 不退化
- [x] **V3b fd=1Hz limitation 已知**（架构 trade-off，14 production 也 ~50%；要回 Phase 1 水平需协议层改动）
- [x] V3c fd=5Hz ~50% 物理极限
- [x] discrete_doppler runner 同模板迁移（Phase 3b.4）
- [x] `wiki/modules/13_SourceCode/SC-FDE调试日志.md` 追加 V2.3 + V2.4 章节
- [x] 本 spec + 原 sps-deoracle-arch spec 归档
- [x] `all_cp_data` 在 RX 链路完全消除（spec 接受准则核心目标达成）

### 后续协议层方向（不在 Phase 3b 范围）

要恢复 Phase 1 水平 BER，需开新 spec：
- 多训练块插入（每 4-8 block）
- 导频 superimposed（OTFS 式）
- 超训练块覆盖 Jakes 周期
