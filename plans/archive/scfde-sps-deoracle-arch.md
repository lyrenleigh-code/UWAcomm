---
project: uwacomm
type: plan
spec: specs/active/2026-04-24-scfde-sps-deoracle-arch.md
status: active
created: 2026-04-24
updated: 2026-04-24
---

# SC-FDE 迁移 14_Streaming 架构（A 方向）执行计划

## 目标回顾

把 `test_scfde_timevarying.m` 从"全 data block + all_cp_data oracle 参考"迁移到
14_Streaming 的"block 1 = training（seed=77）+ blocks 2..N = data + RX 本地重建
train_sym" 架构。同时清理 sps / GAMP / BEM 三处 oracle。

## 架构对齐参考

Production reference: `modules/14_Streaming/src/Matlab/tx/modem_encode_scfde.m` +
`rx/modem_decode_scfde.m`。契约：
- `meta.train_seed = 77` 共享
- Block 1: `train_cp = [train_sym(end-blk_cp+1:end), train_sym]`（blk_fft symbols + CP）
- Blocks 2..N: 数据块承载 `info_bits`
- RX: `rng(77); train_sym=...; train_cp=...;` 本地重建

## 核心设计决策

### D1：选 `train_seed=77` 常量（与 14_Streaming 对齐）

不受 `bench_seed` 影响（training 内容确定性）；`bench_seed` 只影响 data block。

### D2：`N_info` 口径下调

原：`N_info = M_total/n_code - mem`，其中 `M_total = 2*blk_fft*N_blocks`
新：`N_info = M_total/n_code - mem`，其中 `M_total = 2*blk_fft*(N_blocks-1)`
- N_blocks=4 时 info bits 减少 25%
- 旧 BER 基线**不可直接对比**（info_bits 数量不同）
- bench CSV 的 `ber_coded` 统计口径相应改变

### D3：Turbo decoder 只喂 data block 符号

`rx_sym_all` 里第 0 block 是 training block 的噪声观测，不进译码。
Turbo 输入从 `rx_sym_all(1:N_total_sym)` 改为 `rx_sym_all(sym_per_block+1:end)`（后 N-1 block）。

### D4：sps 对齐用本地重建的 `train_cp(1:10)`

替换 L488/L605 的 `conj(all_cp_data(1:10))` → `conj(train_cp(1:10))`。

### D5：GAMP 训练矩阵用 `train_cp`（整块 blk_fft+blk_cp 长度，不止 CP）

14_Streaming 做法：`usable = min(blk_fft, length_rx_train_block)`，训练矩阵观测
长度为 `blk_fft`（比原来 `blk_cp` 多一个数量级，估计精度提升）。

### D6：BEM 观测矩阵分阶段

**初始 iter**：只用训练 block 的 CP 段（`max_delay+1 : blk_cp`）作为观测，
`x_vec = train_cp(idx)`。
**Turbo iter 2+**：数据 block 用判决反馈（`x_vec = decided_data_sym(idx)`）。

Phase 3 先做前半（训练块观测），后半 park（判决反馈是 modem_decode_scfde 现有实现但
非本 spec 核心）。

## Phase 分解

### Phase 1 — 最小切换（TX 训练块 + sps 去 oracle）

**目的**：开最小闭环，跑通 "训练块架构 + oracle GAMP/BEM" 组合，孤立验证训练块机制本身无 regression。

改动：
- **TX 端**（L168-188）：
  - 开头 `rng(77)` 生成 `train_sym`（blk_fft 符号）
  - `train_cp = [train_sym(end-blk_cp+1:end), train_sym]`
  - `all_cp_data(1:sym_per_block) = train_cp`
  - 切回 `rng(bench_seed 派生)`，`N_info` 按 D2 算
  - `coded/interleave/qpsk` 填 blocks 2..N
- **RX 端**（L488/L605 附近）：
  - 本地重建 `train_cp`（RX 端加 4 行）
  - sps 对齐：`conj(train_cp(1:10))` 替换 `conj(all_cp_data(1:10))`
- **GAMP/BEM 保留 oracle**（暂不改）：仍用 `all_cp_data`
- **BER 统计**：`M_total / n_code - mem` 按 D2 新口径

验证：
- V1.1 α=0 static SNR={10,15,20} × 5 seed：BER 应与旧 baseline 大致一致（不完全一致，因 info_bits 少 25%）
- V1.2 α=+1e-2 × 5 seed：BER 维持 0%（6613041 水平）
- V1.3 α=-1e-2 × 5 seed：BER 维持（历史 10% 灾难率，不增加）

**不测的**：大 α=3e-2 / 大 Monte Carlo / BEM fd=1Hz 退化（等 Phase 3）

### Phase 2 — GAMP 训练矩阵去 oracle

**目的**：利用训练块 blk_fft 个已知符号，替代 `all_cp_data(1:sym_per_block)`。

改动（L633 附近）：
```matlab
% before: tx_blk1 = all_cp_data(1:sym_per_block);  % ← 整帧 CP+data
% after:  tx_blk1 = train_cp;                       % ← 训练块 CP+train
% usable = min(blk_cp + blk_fft/8, sym_per_block) 按 14_Streaming 做法
```

如果按 14_Streaming 做法（`usable = blk_fft`），T_mat 变大，GAMP 更准。但要注意
training block 的 CP 是 `train_sym(end-blk_cp+1:end)`，不同于原代码的逻辑。

验证：V1 同上，BER 应不退化（理论上 GAMP 训练数据变多，估计更准）。

### Phase 3 — BEM 观测矩阵分阶段去 oracle（时变路径）

**目的**：时变信道（ftype≠static）下，BEM 不再用 TX data block 当观测。

改动（L660-677 附近）：
- **初始观测**：只在 block 1 的 CP 段（max_delay+1 : blk_cp）内取观测，`x_vec = train_cp(idx)`
- **data block 的 CP 段不当观测**（14_Streaming 不依赖，本 spec 也省略）

验证：V3.1 fd=1Hz SNR={10,15,20} × 5 seed：BER 变化量化（减少观测可能劣化，需量化影响）

**R3 风险**：只用训练块 1 个 CP 段作 BEM 观测 ≈ `blk_cp-max_delay` 个观测点（典型 30-60），
可能不够拟合 BEM basis。14_Streaming 的 modem_decode_scfde.m 里还有 Turbo iter 2+
的判决反馈，补充 data block 观测 —— 本 plan 不做判决反馈（复杂度过大），先看裸 BEM
表现。如果退化严重 → 开 Phase 3b 加判决反馈 iter。

### Phase 4 — 推广另外 2 个 SC-FDE runner

适用：`test_scfde_static.m`（无时变 BEM 路径）+ `test_scfde_discrete_doppler.m`
（同 timevarying 架构 + apply_channel 代替 gen_uwa_channel）

直接 copy 模板。

## 不改动的事项

- ❌ 14_Streaming modem_encode/decode_scfde.m
- ❌ 其他 4 体制 runner
- ❌ GAMP/BEM/Turbo 内部逻辑
- ❌ 帧结构（HFM/LFM 部分）
- ❌ `benchmark_e2e_baseline.m` CSV schema
- ❌ bench_append_csv 等公共工具

## BER 基线迁移

本 Phase 做完后，所有旧 BER 基线作废（info_bits 数量变了）。需要重新跑：
- E2E timevarying baseline（spec `2026-04-19-e2e-timevarying-baseline.md`）SC-FDE 列
- Monte Carlo α=±1e-2 灾难率（memory SC-FDE 2026-04-23 session）
- E2E C 阶段 Phase a 的 benchmark（spec `2026-04-19-constant-doppler-isolation.md`）

**提议**：先完成 Phase 1-2，再决定是否重跑这些 baseline（需用户授权 ~20 min 跑）。

## Checkpoint 分布

```
Phase 1: 代码改动 → 用户跑 V1.1-V1.3 → approve
Phase 2: 代码改动 → 用户跑 V2 → approve
Phase 3: 代码改动 → 用户跑 V3 → approve
Phase 4: 代码改动 (2 runner) → 用户 smoke → approve
结尾: commit
```

## 非平凡决策点（等用户确认）

- **Q1**：是否 Phase 1 就把 Turbo 输入改为 data block only（排除 training block）？
  - 是：符合 14_Streaming，但 decoder 调用参数变了
  - 否：先简单把 training block 的 rx_sym 也塞进 Turbo（info_bits 相应 pad）
- **Q2**：是否需要保留"旧架构 toggle"（`tog.use_legacy_no_training = true`）作回归？
  - 是：更安全，但复杂度上升
  - 否：直接切新架构，旧结果在 git history 里
- **Q3**：Phase 3 BEM 退化如果发生，接受还是做 Phase 3b 判决反馈？

待用户决定 Q1/Q2 后开始 Phase 1。
