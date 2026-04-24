---
project: uwacomm
type: task
status: active
created: 2026-04-24
updated: 2026-04-24
tags: [sps timing, oracle 清理, SC-FDE, 架构改动, 13_SourceCode]
branch: arch/scfde-sps-deoracle
related:
  - specs/archive/2026-04-23-scfde-omp-replace-gamp-and-oracle-clean.md
  - specs/archive/2026-04-23-scfde-sps-deoracle-fourth-power.md
  - specs/active/2026-04-16-deoracle-rx-parameters.md
---

# SC-FDE sps 相位选择真去 oracle（第 4 次尝试 — 架构方向决策）

## 背景

### 问题位置

`test_scfde_timevarying.m:488-498` 和 L602-608 用 TX 数据 `all_cp_data(1:10)` 做 sps 相位选择参考 — 违反 CLAUDE.md §7 排查清单第 8 条（"测试 harness 允许传递协议参数，禁止传递 TX 数据"）。

```matlab
c = abs(sum(st(1:10) .* conj(all_cp_data(1:10))));  % ← RX 拿不到 all_cp_data
```

### 3 次试错总结

| # | 方向 | 结果 | 根因 |
|---|------|------|------|
| 1 | `sum(|st|²)` 功率最大化 | α=-1e-2 13%→48% 灾难 | 6 径 ISI 让错相位捕获更多能量泄漏 |
| 2 | `abs(sum(st^4))` QPSK 4 次方 NDA | Monte Carlo -1e-2 灾难率 10%、+1e-2 20%，max BER 50.6% | SNR=10 噪声 4 次放大 + ISI phasor 分散 |
| 3 | （archive/scfde-omp-... Phase B 同 #1）| — | — |

**统一教训（从 archive spec）**：
> 所有纯 NDA blind timing（功率最大化 + 4 次方）在 6 径 ISI + SNR=10 都失效。Oracle 之所以工作是因为有 ground truth；去 oracle 必须给 RX **等价 ground truth**。

### 探索性新发现（2026-04-24）

**14_Streaming `modem_decode_scfde.m` 已经架构性去 oracle**：
- `meta.train_seed=77` + RX 端 `rng(train_seed); train_sym=...` 独立重建
- 用 `train_cp(1:10)` 做 sps 相位参考（本地重建 ≠ oracle）
- 第 0 个 block 作为 training block，后续 N-1 个作为 data block

**13_SourceCode test_scfde_timevarying.m 仍是旧架构**（整帧全 data block + oracle 参考）。

## 4 候选方向评估

| 方向 | 描述 | 改动大小 | 技术风险 | 稳健性 |
|------|------|---------|---------|--------|
| **A** | **13 SC-FDE runner 迁移到 14_Streaming 架构**（第 0 block = training，RX seed=77 重建）| 大（改 TX/RX/decoder 调用 + info_bits 口径）| 中（需全 BER 回归对比）| 高（DA timing + 14 已验证）|
| **B** | **LFM 尾部推导 sps 相位**（从 LFM2 匹配滤波分数峰 + `lfm_data_offset` 推 data 起始）| 中（20-50 行 + 新函数）| 高（LFM MF 分数精度是否足够 ±1 sample）| 未知（需实测）|
| **C** | **Gardner TED**（调 `08_Sync/timing_fine.m`）| 小（<10 行）| **高**（纯 NDA，与失败方向同族）| 低（教训已说明纯 NDA 在 6 径 ISI + SNR=10 失效）|
| **D** | **标注 known-limitation，接受 offline benchmark oracle** | 0（仅注释 + README）| 0 | N/A（不清理，显式声明）|

### 方向 A 细节

TX 改动（L172-184）：
```matlab
% 第 0 block: training（seed=77 固定，RX 可重建）
rng(77);
train_sym = constellation(randi(4, 1, blk_fft));
train_cp = [train_sym(end-blk_cp+1:end), train_sym];
% 其余 N-1 block: data（bench_seed 注入）
rng(uint32(mod(100 + fi + (bench_seed-42)*100000, 4294967296)));
info_bits = randi([0 1], 1, N_info_data);
% coded/interleave/qpsk 生成 data_sym (blk_fft × (N-1) symbols)
...
all_cp_data = [train_cp, data_cp_concat];  % 第 0 block = training
```

RX 改动（L488-498, L602-608）：
```matlab
% 本地重建 train_sym
rng(77); train_sym_rx = constellation(randi(4, 1, blk_fft));
train_cp_rx = [train_sym_rx(end-blk_cp+1:end), train_sym_rx];
% sps 对齐
c = abs(sum(st(1:10) .* conj(train_cp_rx(1:10))));  % ← RX 独立重建，非 oracle
```

Decoder 改动：
- 整帧 Turbo 保留，但 BER 统计只取 data block 部分
- `N_info` 计算口径改为 `M_per_blk*(N_blocks-1)/n_code - mem`
- 影响 `bench_append_csv` 的 `ber_coded` 参考基准

### 方向 B 细节

从已知 LFM2 模板做匹配滤波：
```matlab
% LFM2 在 bb_comp 中的精确分数位置（MF 峰值 parabolic 插值）
mf_out = filter(conj(fliplr(LFM_bb_neg_n)), 1, bb_comp);
[~, peak_int] = max(abs(mf_out));
% parabolic 插值得分数偏移
dy = (abs(mf_out(peak_int+1)) - abs(mf_out(peak_int-1))) / ...
     (2 * (2*abs(mf_out(peak_int)) - abs(mf_out(peak_int-1)) - abs(mf_out(peak_int+1))));
lfm_frac_pos = peak_int + dy;   % LFM2 结束的分数位置
% data 起始 = LFM2 结束 + guard_samp
data_start_frac = lfm_frac_pos + guard_samp;
% data_start_frac mod sps 决定 sps 相位选择
sps_phase_est = round(mod(data_start_frac, sps));
```

**关键假设**：LFM2 匹配滤波的分数峰精度在 SNR=10 + ISI 下优于 ±1 sample（~0.125 符号）。
需要实测验证。

### 方向 C 细节

```matlab
% 现有 08_Sync/timing_fine.m 接口
[timing_offset, ~] = timing_fine(rx_filt, sps, 'gardner');
% timing_offset ∈ [-sps/2, sps/2)，round 到整数 sps 相位
best_off = mod(round(-timing_offset), sps);
```

**风险**：历史教训明确说明 Gardner 等 NDA 方法在本场景失效，仅作 sanity check 不值得投入。

### 方向 D 细节

`test_scfde_timevarying.m` 属于 offline benchmark runner，不是 production path。
CLAUDE.md §2 白名单允许 "oracle baseline" 用途：
> 这些参数**只能用于性能对比基准（oracle baseline）**，不能作为最终系统输入。

14_Streaming `modem_decode_scfde.m` 是 production path，已架构性去 oracle。

**动作**：在 runner 头部和 §7 清单注释明确标注 "offline benchmark，oracle 显式保留用于算法对比"，并在 `wiki/conclusions.md` 加一条说明两套 SC-FDE 架构的分工。

## 推荐

**推荐顺序 D > B > A > C**：

1. **D**（最小成本）：加注释明确分工，0 代码改动。**符合 CLAUDE.md §2 白名单精神**。14_Streaming 已代表 production。
2. **B**（如需 "不加 training 也清理"）：LFM 尾部推导，中等复杂度但不改架构。需 1 次 ~30 min 实测验证可行性。
3. **A**（如需架构统一）：13 → 14 对齐，大改动，需全 BER 回归。**收益 = 架构一致性**，不是功能性。
4. **C**（不推荐）：纯 NDA，历史教训已排除。

## 验证矩阵（按方向分）

### D（注释）

- [ ] runner 头部加"offline benchmark，oracle 保留"注释
- [ ] CLAUDE.md §7 排查清单第 8 条补注"benchmark runner 豁免"
- [ ] `wiki/conclusions.md` 新增：两套 SC-FDE 架构分工
- [ ] 14_Streaming SC-FDE 再确认 sps 真去 oracle（grep 验证）

### B（LFM 尾部）

- [ ] 实现 `lfm_sps_phase_est(bb_comp, LFM_template, guard_samp, sps)` 辅助函数
- [ ] Patch test_scfde_timevarying.m L484-498 + L602-608，加 toggle `tog.use_lfm_sps_est`
- [ ] α 扫描 5 α × 5 seed：对比 oracle vs new，灾难率不增（baseline -1e-2 0/30、+1e-2 6.7%）
- [ ] max BER 不破 30.6%（baseline）
- [ ] 低 SNR 边界（SNR=15 仍救活）

### A（架构对齐）

- [ ] TX 改第 0 block = training（seed=77）
- [ ] RX 本地重建 train_sym
- [ ] BER 统计口径改为 data block only
- [ ] 全 α/SNR 基线回归（需更新 e2e-test-matrix.md）
- [ ] 14_Streaming 侧已有实现可参考，降低风险

## 非目标

- ❌ 修复 SNR=10 边界 ~6.7% 灾难（已知 limitation）
- ❌ 改 GAMP/OMP 估计器（V1.4 稳定）
- ❌ 改其他 5 体制的 sps 处理
- ❌ 动 14_Streaming production 代码

## 关键文件

- 📖 `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m` — L484/L602 oracle 位置
- 📖 `modules/14_Streaming/src/Matlab/rx/modem_decode_scfde.m` — 已去 oracle 的参考架构
- 📖 `modules/08_Sync/src/Matlab/timing_fine.m` — 方向 C 的模块
- 📖 `specs/archive/2026-04-23-scfde-{omp-*, sps-deoracle-fourth-power}.md` — 失败记录

## 风险

- **R1（D 方向）**：被未来 audit 视为"规避问题"。缓解：明确在 CLAUDE.md §7 加"benchmark runner 豁免"，并持续维护 14_Streaming 作为 production reference。
- **R2（B 方向）**：LFM MF 分数精度在 SNR=10 + 6 径 ISI 下不够。缓解：实验验证 phase 先；若分辨率不够自动回退 oracle。
- **R3（A 方向）**：改动面大可能引入 regression；14_Streaming 架构在 benchmark 场景可能有 decoder 适配细节。缓解：分 phase 做，每 phase 单独验证。

## Checkpoint 分布

讨论 → 用户选方向（Checkpoint 1）→ 按选定方向起 sub-plan → 实施 → 用户验证 → 归档
