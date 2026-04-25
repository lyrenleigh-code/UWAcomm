---
project: uwacomm
spec: specs/active/2026-04-24-scfde-bem-decision-feedback-arch.md
status: draft
created: 2026-04-25
---

# Plan：SC-FDE BEM 判决反馈去 oracle 架构改造

## Phase 切分

按 spec Phase 分解，工程上拆为 3 个独立 commit：

### Commit 1（Phase 3b.1）— 移植 build_bem_observations_scfde 局部函数

- 在 `test_scfde_timevarying.m` 末尾（fprintf/fclose 之后）加 local function:
  ```matlab
  function [obs_y, obs_x, obs_n] = build_bem_observations_scfde( ...
      rx_sym_all, train_cp, x_bar_blks, blk_cp, blk_fft, sym_per_block, ...
      N_data_blocks, N_total_sym, sym_delays, K_sparse)
  ```
- 索引对齐 13 全局版本（x_bar_blks{1}=train_sym, x_bar_blks{2..N}=data 软符号）
- 单元测试：脚本 `tests/SC-FDE/test_build_bem_obs_scfde.m`
  - 1 trial × default fading × SNR=15
  - 调 build_bem_observations_scfde + ch_est_bem
  - 检查 obs_y/obs_x 维度 & 无 NaN/Inf
- Commit message: `arch(scfde): build_bem_observations_scfde 局部函数移植 (Phase 3b.1)`

### Commit 2（Phase 3b.2）— BEM iter 结构重组

- Pre-Turbo BEM block (L678-719) 改为 fallback：
  - 时变路径：`H_cur_blocks{bi} = fft(h_static)` 用 GAMP/LS 静态估计（per-block 一致）
  - 标记为 iter 0-1 临时初值
- Turbo loop 内（titer==2 之后、iter=3 反馈之前）插入 BEM 重估 block：
  ```matlab
  if titer == 2
      [obs_y, obs_x, obs_n] = build_bem_observations_scfde(...);
      [h_tv_bem, ~, ~] = ch_est_bem(obs_y, obs_x, obs_n, N_total_sym, ...);
      for bi = 1:N_blocks
          blk_mid = (bi-1)*sym_per_block + round(sym_per_block/2);
          h_td_est = zeros(1, blk_fft);
          for p = 1:K_sparse
              h_td_est(eff_delays(p)+1) = h_tv_bem(p, blk_mid);
          end
          H_cur_blocks{bi} = fft(h_td_est) .* phase_ramp_frac;
      end
  end
  ```
- 后续 iter 沿用 H_cur_blocks（DD 重估保留）
- Commit message: `arch(scfde): BEM 移到 iter=2 用 Turbo 软符号重估 (Phase 3b.2)`

### Commit 3（Phase 3b.3+3b.4）— 验证 + discrete_doppler 推广

- V3a α=0 static SNR={10,15,20} × 5 seed: 不退化
- V3b fd=1Hz SNR={5,10,15,20}: 回归 Phase 1 水平（0.16/0/0/0%）
- V3c fd=5Hz: 持平物理极限 ~50%
- V3d α=±1e-2 不退化
- `test_scfde_discrete_doppler.m` 同模板迁移
- 文档：调试日志 V2.3 章节、conclusions、log/index 同步、TODO
- spec archive
- Commit message: `arch(scfde): BEM 判决反馈 verify + discrete_doppler 推广 (Phase 3b.3+4)`

## 风险

- **R1**：iter=0..1 fallback 估计若不准 → Turbo 发散 → x_bar_blks 不可信 → iter=2 BEM 也不准
  - 缓解：先用 GAMP 静态估计作 fallback（等同当前 static 路径）；实测观察
- **R2**：Phase 3 单 block 观测证伪经验：BEM 需跨块时间分散观测拟合 Jakes 时变
  - 本 plan iter=2 时 x_bar_blks 已有 2..N data 块软符号，跨块观测充分
- **R3**：fd=5Hz 物理极限下软符号全错，BEM 估计为 garbage
  - ~50% 场景本来就是灾难，不影响其他场景结论

## 工时

- Commit 1：~30 min（含 unit test）
- Commit 2：~45-60 min（架构重组，需调试 iter 间状态传递）
- Commit 3：~60-90 min（4 verify 矩阵 + discrete_doppler 推广 + 文档）
- 总：~2.5-3h

## 当前进度

- Commit 1（Phase 3b.1）: 进行中
