---
project: uwacomm
type: plan
status: active
created: 2026-04-26
parent_spec: specs/active/2026-04-26-scfde-time-varying-pilot-arch.md
---

# Phase 4 实施计划：SC-FDE 多训练块协议（方案 A）

## Frame layout 设计

给定 `N_blocks` 和 `cfg.train_period_K`：
- `N_train = floor(N_blocks / (K+1)) + 1`
- `train_indices = round(linspace(1, N_blocks, N_train))`（均匀分布，含两端）
- `data_indices = setdiff(1:N_blocks, train_indices)`

举例：
- N=16, K=4 → N_train = floor(16/5) + 1 = 4，train_indices=[1,6,11,16]，data×12（13/14/15/16 对应 12 data 槽）
- N=16, K=8 → N_train = floor(16/9) + 1 = 2，train_indices=[1,16]，data×14
- N=16, K=N-1=15 (向后兼容单训练块) → N_train = floor(16/16) + 1 = 2，train_indices=[1,16]
  - **注意**：向后兼容应该 N_train=1，train_indices=[1]
  - 修正：当 K ≥ N_blocks-1 时，强制 N_train=1, train_indices=[1]（向后兼容）

修正后逻辑：
```matlab
if cfg.train_period_K >= N_blocks - 1
    N_train = 1;
    train_indices = 1;
else
    N_train = floor(N_blocks / (cfg.train_period_K + 1)) + 1;
    train_indices = round(linspace(1, N_blocks, N_train));
    train_indices = unique(train_indices);  % 防 round 重复
    N_train = length(train_indices);
end
data_indices = setdiff(1:N_blocks, train_indices);
N_data_blocks = length(data_indices);
```

## meta 字段扩展

新增字段（向后兼容老 decoder 通过缺失检查）：
- `meta.train_block_indices` — 1×N_train 全局 block index
- `meta.data_block_indices` — 1×N_data 全局 block index
- `meta.N_train_blocks` — N_train

向后兼容：老 decoder 不读这两字段，只看 `N_data_blocks = N_blocks - 1` —— **不兼容**！需统一升级 RX。

策略：
- TX：默认 `cfg.train_period_K = N_blocks - 1`（自动 N_train=1，老协议）
- RX：必须读 `meta.train_block_indices`（老 meta 缺失时 fallback 到 `[1]`）

## Phase 4a 步骤

### TX (14_Streaming/tx/modem_encode_scfde.m)

1. 加 `cfg.train_period_K`（默认 N_blocks-1）
2. 计算 `train_indices` / `data_indices` / `N_train_blocks` / `N_data_blocks`
3. 生成 `N_train` 个**相同的** train_sym（seed=77）—— 还是每个 train 用不同 seed？
   - **决定**：统一同一 train_sym（seed=77，与 RX 重建一致），简化 BEM 观测构造
4. 帧装填：data_indices 位置放数据块，train_indices 位置放 train_cp
5. meta 字段加 train_block_indices / data_block_indices / N_train_blocks
6. 保留旧字段 N_data_blocks（已是 length(data_indices)）

### RX (14_Streaming/rx/modem_decode_scfde.m)

1. 从 meta 读 train_block_indices / data_block_indices
2. **训练块本地重建**：seed=77 → train_sym（与 TX 同），所有 train_indices 位置都用同一 train_cp
3. 信道估计 (§5)：用 train_block_indices[1] 做 GAMP（沿用现逻辑）
4. 数据块去 CP + FFT (§6)：循环 data_indices 而非 `bi+1`
5. Turbo BEM (§7)：build_bem_observations 改为多训练块版本
6. info 比特截取 (§8)：基于 N_data_blocks（已自动正确）

### 13_SourceCode/tests/SC-FDE/test_scfde_timevarying.m

- 加 `cfg.train_period_K` 默认 N_blocks-1（向后兼容）
- TX 装填循环跟 14 同步
- RX 路径调相同的 build_bem_observations_scfde + ch_est_bem
- bench_init_row 加列：`train_period_K`, `N_train_blocks`

## Phase 4b 步骤

### build_bem_observations 多训练块版本

`modules/13_SourceCode/src/Matlab/tests/bench_common/build_bem_observations_scfde.m` 改造：

```matlab
function [obs_y, obs_x, obs_n] = build_bem_observations_scfde(...
    rx_sym_all, train_cp, x_bar_blks, blk_cp, blk_fft, sym_per_block, ...
    N_data_blocks, N_total_sym, sym_delays, K_sparse, ...
    train_block_indices, data_block_indices)  % 新增 2 入参
```

逻辑：
1. 训练块（train_block_indices 全部）：CP 段观测，全用 train_cp
2. 数据块（data_block_indices）：CP 段观测用 x_bar_blks（Turbo 软符号）

### 14_Streaming 局部 build_bem_observations 同步

`modules/14_Streaming/src/Matlab/rx/modem_decode_scfde.m` L296+ 局部函数改造，签名同上。

### 单元测试

`test_build_bem_obs_scfde.m`（已存在）扩展 case：
- N_train=4, K=4, N_blocks=16
- 期望 n_obs ≈ N_train × (blk_cp - max_tau)

## Phase 4c 验证

V4a static SNR={5,10,15,20} × K={4,8,16} × seed=3
- 期望：不退化（K 不影响 static）

V4b fd=1Hz K={4,8,16} × SNR={5,10,15,20} × seed=3
- **关键**：K=4 BER < 5%（恢复 Phase 1 水平）

V4c fd=5Hz K={4,8} × SNR={5,10,15,20} × seed=3
- 期望：BER < 10%（fd=5Hz 物理极限相对宽松）

V4d K vs BER 曲线（fd=1Hz SNR=10dB）
- K = {1, 2, 4, 8, 12, 15(单训练块)}
- 趋势期望：K↑ → BER↑（吞吐 vs 性能 trade-off）

V4e 13/14 双侧
- 13 test_scfde_timevarying.m K=4 vs 14_Streaming production K=4
- 期望：BER 差 < 1 pp（实现一致）

## 验证脚本

`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_a2_phase4_periodic_pilot.m`：
- 仿 A1 脚本结构
- 加 K 参数循环
- 输出 V4a/b/c/d/e 表格

## 风险预案

- R1：N_blocks=16, K=4 → N_train=4 → BEM 观测 n_obs ≈ 4×(128-90) = 152，足够拟合 6 径 × DCT 阶 (BIC 自适应) - 应该 OK
- R2：14_Streaming P1-P4 测试默认 K=N_blocks-1 自动单训练块 - 不破坏
- R3：jakes 自相关零点位置随机 → 4 个均匀分布 train block 大概率有 2-3 个落在非零自相关区域 - 应该 OK

## 实施顺序（committable 单元）

1. **Commit 1 (Phase 4a)**：TX/RX/13 test 同步加 train_period_K（默认向后兼容）+ build_bem_observations 接口扩展（但内部仍按单训练块走）
2. **Commit 2 (Phase 4b)**：build_bem_observations 多训练块逻辑实施 + 单测
3. **Commit 3 (Phase 4c V4a)**：static V4a sanity check
4. **Commit 4 (Phase 4c V4b)**：fd=1Hz K=4 关键验证
5. **Commit 5 (Phase 4c V4c+V4d)**：fd=5Hz + K vs BER 曲线
6. **Commit 6 (归档)**：spec → archive + log/conclusions/调试日志同步

## 工时

- Plan: 0.5h（本文档）✅
- 4a TX+RX+13 test: 2h
- 4b BEM 改造 + 单测: 1h
- 4c 验证: 2-3h
- 文档/归档: 0.5h
- 总计：~6h（与 spec 估计一致）

---

## Phase 5 实施计划（方案 E：block-pilot 末尾插入）

V4 方案 A 失败（V4b/V4c FAIL）后追加。

### 5a TX：modem_encode_scfde V4.0

新增字段 `cfg.pilot_per_blk`（默认 0 = 禁用）：
- `N_data_per_blk = blk_fft - pilot_per_blk`
- `M_per_blk = 2 * N_data_per_blk`（QPSK，data 槽位减少）
- `M_total = M_per_blk * N_data_blocks`
- pilot 序列 seed=99（QPSK from constellation, length=pilot_per_blk）

帧装填（每 data block）：
```matlab
data_sym = sym_all((di-1)*N_data_per_blk+1 : di*N_data_per_blk);   % blk_fft - 32 长度
block_full = [data_sym, pilot_seq];                                  % blk_fft 长度
x_cp = [block_full(end-blk_cp+1:end), block_full];                   % sym_per_block
```

meta 字段：`pilot_per_blk`, `pilot_seed`, `N_data_per_blk`

### 5b RX：build_bem_obs_pretturbo_scfde + modem_decode_scfde V4.1

新建函数 `build_bem_obs_pretturbo_scfde.m`：
- 输入：rx_sym_all + train_cp + pilot_seq + train/data indices + pilot_per_blk
- 观测构造：
  - 训练块 CP 段（max_tau+1..blk_cp）— 全 train_cp 已知 → 干净 obs
  - 每 data block 末 pilot 段（local index `blk_cp+N_data_per_blk+1..sym_per_block`）— pilot_seq 已知 → 干净 obs
  - 跨 idx 跳转时只在 idx 落入 train_cp 或 pilot 段时构造 obs（其他 data 段未知，跳过）
- 输出：obs_y / obs_x / obs_n（全干净）

modem_decode_scfde V4.1 改动（§5 GAMP 之后 §6 之前）：
```matlab
if N_pilot_per_blk > 0
    [obs_y_pre, obs_x_pre, obs_n_pre] = build_bem_obs_pretturbo_scfde(...);
    [h_tv_init, ~, ~] = ch_est_bem(obs_y_pre, obs_x_pre, obs_n_pre, ...);
    % 替换 H_est_blocks 为时变 H_tv
    for bi = 1:N_data_blocks
        blk_idx = data_block_indices(bi);
        blk_mid = (blk_idx-1)*sym_per_block + round(sym_per_block/2);
        h_td_blk = zeros(1, blk_fft);
        for p = 1:K_sparse
            h_td_blk(eff_delays(p)+1) = h_tv_init(p, blk_mid);
        end
        H_est_blocks{bi} = fft(h_td_blk);
    end
end
```

### 5c 验证

V5a：static × pilot_per_blk={0,32} 不退化 sanity
V5b：fd=1Hz × pilot_per_blk={32, 64} × SNR×4 × seed×3 — **关键，期望 BER < 5%**
V5c：fd=5Hz × pilot_per_blk=32 × SNR×4 — BER < 10%

验证脚本：`diag_a3_phase5_block_pilot.m`（A2 基础上加 pilot_per_blk 循环）

### 工时

- 5a TX 改造：30 min
- 5b RX + build_bem_obs_pretturbo + 单元测试：2h
- 13 test 同步：30 min（仅在 cfg 加 pilot_per_blk + 装填同步）
- 5c 验证：1h
- 总计：~4h

