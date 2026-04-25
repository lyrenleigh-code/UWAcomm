---
project: uwacomm
type: investigation-plan
status: active
created: 2026-04-24
parent_spec: specs/active/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md
tags: [SC-TDE, fd=1Hz, 非单调, Monte Carlo, 13_SourceCode]
---

# SC-TDE fd=1Hz 非单调 BER vs SNR 调研 — 实施计划

## 阶段 1：多 seed Monte Carlo 基线（本次交付）

### 目标

通过 SC-TDE timevarying runner 多 seed 重跑 fd=1Hz Jakes，在 SNR={10,15,20} 三点上收集 BER 分布，判定 spec H1（Turbo+BEM 稀有触发 vs 普遍崩坏）。

### 配置矩阵

| 维度 | 值 | 说明 |
|------|---|------|
| scheme | SC-TDE 单体制 | runner = `tests/SC-TDE/test_sctde_timevarying.m` V5.4 |
| fading | `{'fd=1Hz','slow',1,1/12000}` | fc=12000 → dop_rate=8.33e-5（spec line 60 一致）|
| SNR | {10, 15, 20} dB | 与 spec parent fix 验证表对照 |
| seed | 1..15 | spec line 58 |
| 总 trial | 45 | 单 trial ≈ 1 min，预计 30-45 min 总时 |
| α 估计 | runner 默认（est_alpha_dual_chirp, V5.4 流程，无 post-CFO 伪补偿）| H4 排除留阶段 2 |
| oracle | 关 | 阶段 1 仅基线 |

### 注入参数（脚本→runner）

```matlab
benchmark_mode                 = true;
bench_snr_list                 = h_snr;          % 标量
bench_fading_cfgs              = h_fading_row;   % 1×4 cell
bench_channel_profile          = 'custom6';
bench_seed                     = h_seed;
bench_stage                    = 'fd1hz-nonmono-MC';
bench_scheme_name              = 'SC-TDE';
bench_csv_path                 = h_csv;
bench_diag                     = struct('enable', false);
bench_toggles                  = struct();
bench_oracle_alpha             = false;
bench_oracle_passband_resample = false;
bench_use_real_doppler         = true;
```

每 trial 一份 CSV，由 `bench_append_csv` 落盘。

### 输出

- `tests/bench_common/diag_sctde_fd1hz_out/SCTDE_seed{N}_snr{X}.csv`（45 份）
- 控制台：每 SNR 行 `mean / median / std / min / max / 灾难率`
- 灾难案例 seed 列表（按 SNR 分）
- 时间戳总用时

### 灾难阈值

`>5%` per spec line 60（保守，放大 SNR=15 的稀有触发可见度；与 diag_5scheme 的 30% 不同 — 那个针对 α=+1e-2 100% 灾难校准的）。

### 判定路径

| 阶段 1 结果 | 推论 | 下一步 |
|-------------|------|--------|
| 灾难率 < 15% 且 mean BER 单调降 | H1 confirmed: 稀有触发 | 标 known limitation，记 conclusions.md，spec 阶段 2/3 不做，归档 |
| 每 SNR 都有 ≥ 30% trial 灾难 | H1 falsified: 系统脆弱 | 进入 spec 阶段 2（H2/H3/H4 隔离） |
| 中间区（15~30%）| 部分稀有 | 阶段 2 选择性做（先 H4 oracle α 排除 estimator 偏差） |

### 模板基础

`bench_common/diag_5scheme_monte_carlo.m`（5 scheme × 15 seed × α=+1e-2 × SNR=10）的结构改写：单 scheme + 3 SNR 维。

### 不做（划界）

- 阶段 2/3 待阶段 1 结果定，不在本 plan 内
- 不修改 runner（V5.4 本体 + bench_seed 注入已就位）
- 不做可视化 figure（先看数字，必要时补 boxplot 一张）
- 不跑 fd=5Hz 或 static 对照（spec 非目标）

## 用户责任

- 我写脚本 + 此 plan
- **用户跑** `diag_sctde_fd1hz_monte_carlo.m`（30-45 min）
- 跑完贴 console 输出 + CSV 目录给我
- 我据数据填 spec 阶段 1 表格 + 判定 H1
