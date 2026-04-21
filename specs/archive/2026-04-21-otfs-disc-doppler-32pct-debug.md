---
project: uwacomm
type: task
status: completed
created: 2026-04-21
updated: 2026-04-21
tags: [OTFS, 调试, 离散Doppler, 13_SourceCode, 07_ChannelEstEq, pilot_mode]
branch: feat/otfs-disc-doppler-debug
---

# OTFS 32% BER 专项 debug（原命名：OTFS × 离散 Doppler）

## 背景

E2E 时变信道 688 点基线（`wiki/comparisons/e2e-timevarying-baseline.md`，2026-04-19）B 阶段发现：

> OTFS 在离散 Doppler / Rician 混合 4 类信道下 **独自卡 ~32% BER**（disc-5Hz: 32.0%, hyb-K20: 31.9%, hyb-K10: 31.8%, hyb-K5: 32.1%），而其他 5 体制（SC-FDE/OFDM/SC-TDE/DSSS/FH-MFSK）全部 <1% BER @ snr=10dB。

初始假设方向（参考 [[yang-2026-uwa-otfs-nonuniform-doppler]]）：**非均匀 Doppler + on-grid 估计假设失败**。

## 复盘：进 debug 前的 CSV 深挖（2026-04-21）

进 debug 前先挖 `e2e_baseline_A3.csv` 原始数据，发现**两条惊人事实**：

### 事实 1：harness 忽略 α

`A3 OTFS` 共 48 行，按 (fd, α) 分组后，**同一 fd 下 α=0/5e-4/1e-3/2e-3 的 BER 完全相同**：

| fd | α=0 @ snr=10 | α=5e-4 @ snr=10 | α=1e-3 @ snr=10 | α=2e-3 @ snr=10 |
|----|---:|---:|---:|---:|
| 0 (static) | 33.01% | 33.01% | 33.01% | 33.01% |
| 1 | 33.66% | 33.66% | 33.66% | 33.66% |
| 5 | 49.27% | 49.27% | 49.27% | 49.27% |
| 10 | 48.95% | 48.95% | 48.95% | 48.95% |

→ `test_otfs_timevarying.m` 的 `apply_channel` 调用**不支持 `doppler_rate`**（'static/discrete/hybrid' 三个分支都没做时间伸缩）。
本次 debug **不关心 α**（harness 本身 bug，独立修）。

### 事实 2：static 就已经 33% BER @ snr=10

**关键观察**：

| SNR | fd=0 (static) BER | fd=1 (Jakes) | fd=5 | fd=10 |
|-----|---:|---:|---:|---:|
| 5 | 43.9% | 46.5% | 47.2% | 50.4% |
| 10 | **33.0%** | 33.7% | 49.3% | 49.0% |
| 15 | 2.7% | 14.2% | 44.7% | 50.1% |

- static 信道（完全无 Doppler）下 snr=10 BER=33% **与 B 阶段离散信道的 32% 数值上几乎相同**
- disc/hybrid 的 32% 很可能**不是** Doppler 问题，**根源在 static 就已经存在的某个配置 regression**

对比 2026-04-11 `wiki/comparisons/e2e-test-matrix.md` 原始 OTFS V2.0 数据：
- static: **0% @ 5dB+**（与现在 static 33% @ 10dB 严重矛盾）

→ 2026-04-11 到 2026-04-21 之间 OTFS 发生 regression。

## 嫌疑定位

读 `test_otfs_timevarying.m:20`：

```matlab
pilot_mode = 'sequence';  % 'impulse'=A冲激, 'sequence'=B ZC, 'superimposed'=C叠加
```

对照 `wiki/conclusions.md` #37（2026-04-19）：

> OTFS pilot_mode 分派 + 默认 sequence: 默认改为 **sequence (ZC)** 降 PAPR ~9dB，解决 UI 时域波形多脉冲问题。trade-off：**5dB BER 从 0% → 7.59%**（低 SNR 略差），**15dB 仍 0%**。

- 文档记载的 trade-off 只到 5dB / 15dB 两端
- **10dB 没测**，而正是当前基线显示 33% 的点
- A3 CSV 显示 sequence 在 static 信道下 BER 单调下降但 10-15dB 区间拐点陡：snr=5→44%，snr=10→33%，snr=15→2.7%——5-10dB 的 BER 平台 30-44% 说明 ZC pilot 在 moderate SNR 整体失效，要到 15dB 才恢复
- 注：conclusion #37 记载的 "5dB 7.59%" 是 2026-04-19 当时 pilot_mode 切换时**独立 test_otfs_timevarying.m 的测量**，不走 benchmark harness，与 A3 CSV 的 44% **不直接可比**

## 假设（重排优先级）

| # | 假设 | 验证方法 | 代价 |
|---|-----|---------|------|
| **H1** ★ | **pilot_mode='sequence' 在 SNR=10dB 附近有 regression**（ZC 估计器 `ch_est_otfs_zc` 的 partial correlation sidelobe 在 moderate SNR 下主导） | 切 `pilot_mode='impulse'` 重跑 static @ snr=10dB。若 BER < 5% → H1 成立 | 0.5h |
| H2 | `apply_channel` + OTFS runner 的 SNR 参考面错位（noise_var 计算在通带 vs 基带不一致） | 对比 `noise_var = mean(abs(rx_clean).^2) * 10^(-snr_db/10)` 在 impulse / sequence 下的实际 SNR | 1h |
| H3 | 两级同步 `frame_parse_otfs` 引入系统定时偏移，OTFS demod 前的 `rx_noisy` 与参考相位不对齐 | Oracle 模式（`use_oracle=true`）+ impulse 重跑；若仍 33% → H3 | 0.5h |
| **H4** | （Yang 2026 理论）即使 H1 成立，disc-5Hz / hyb-K* 仍存在 **非均匀 Doppler on-grid 估计假设失败** | H1 确认后，impulse × 离散信道扫 | 1h |
| H5 | OTFS 帧结构设计缺陷（Jakes fd≥5Hz 下 BCCB 假设瓦解） | H4 之后的遗留问题 | 另起 spec |

**优先级**：H1 先打靶——成本最低，最可能是根因。

## 目标

1. **首要**：确定 OTFS 32% BER 的根因层次：pilot_mode regression（H1）/ SNR 参考（H2）/ 定时（H3）/ 真·非均匀 Doppler（H4）
2. **次要**：给出最小干预修复方案（若 H1 则回滚 default）
3. **第三**：回答"Yang 2026 的 off-grid block-sparse 估计"是否真的需要被引入（H4 确认才需要）

## 测试配置

### 诊断矩阵（3 × 3 × 3 = 27 runs，~5 min）

```
pilot_mode ∈ {impulse, sequence, superimposed}
channel    ∈ {static, disc-5Hz, hyb-K20}
trials     = 3（seed = 100, 200, 300）
SNR        = 10 dB（固定，只诊断"10dB 异常"）
```

### 评价指标

| 指标 | 计算 | 阈值 |
|------|------|------|
| BER_coded | 标准 | ≤ 5% = PASS |
| NMSE_h | `norm(h_est - h_true)² / norm(h_true)²` | ≤ -10 dB |
| path_detection_rate | path_info.num_paths / true_paths | ≥ 80% |
| frame_detected | sync ok | 100% |

### 信道

沿用 `test_otfs_timevarying.m` 第 105-115 行定义：5 径 `[0,1,3,5,8] chip`，3 种 Doppler 模式。

## 假设检验预期（决策树）

```
H1 先打靶
├── static + impulse × 3 trials BER ≤ 5%
│   └── H1 成立 → 扩展验证 B 信道
│       ├── disc-5Hz + impulse × 3 BER ≤ 5%
│       │   └── H4 否定：根因完全是 pilot_mode regression
│       │       → Step 4a 修复：default 回滚 impulse
│       │       → 本 spec 结束
│       └── disc-5Hz + impulse × 3 BER ~ 32%
│           └── H4 成立：存在真正的非均匀 Doppler 问题
│               → 升级衍生 spec 2026-04-22-otfs-nonuniform-doppler-ce.md
│               → 引入 Yang 2026 block-sparse OMP
└── static + impulse × 3 BER > 20%
    └── H1 否定 → 切换到 H2/H3
        ├── oracle + impulse → 0%：估计器问题，但不是 pilot_mode
        └── oracle + impulse → 33%：均衡/译码问题（深度 debug）
```

## 范围

### 做什么

1. 新建 `modules/13_SourceCode/src/Matlab/tests/OTFS/diag_otfs_32pct.m`（单点诊断）
2. 跑 27 run 诊断矩阵，输出 `diag_results/` 下 BER/NMSE 表
3. 按决策树定位根因
4. 根据根因类型决定修复与后续
5. 更新 `wiki/modules/13_SourceCode/OTFS调试日志.md`（新建）+ conclusions

### 不做什么

- ❌ 在本 spec 内实现 Yang 2026 的 off-grid block-sparse OMP（若 H4 成立，仅输出衍生 spec 主题）
- ❌ 修复 harness α 忽略 bug（独立归到 `2026-04-21-alpha-refinement-other-schemes` 或新 spec）
- ❌ OTFS PAPR 优化（原本 pilot_mode='sequence' 的动机，留给 SLM/PTS spec）
- ❌ 碰 14_Streaming

## 交付物

1. `modules/13_SourceCode/src/Matlab/tests/OTFS/diag_otfs_32pct.m`
2. `diag_results/otfs_32pct_diag_log.txt` + `otfs_32pct_diag.mat`
3. `wiki/modules/13_SourceCode/OTFS调试日志.md`
4. （H1 成立）`test_otfs_timevarying.m:20` default 回滚 + 回归跑 static × impulse → 验证 0%
5. `conclusions.md` 追加 1-2 条
6. （H4 成立）衍生 spec 草案 `specs/active/2026-04-22-otfs-nonuniform-doppler-ce.md`

## 时间估计

| 步骤 | 工时 |
|------|------|
| 诊断脚本编写 | 0.5h |
| 诊断跑 + 分析 | 0.5h |
| 决策分支 A（H1 成立）：回滚 + 回归 | 0.5h |
| 决策分支 B（H4 成立）：衍生 spec 起草 | 0.5h |
| 决策分支 C（H1/H2/H3 均否）：深度 debug | 2h（超预算则拆 spec）|
| wiki + commit | 0.5h |
| **合计** | **~2.5-4.5h** |

## 风险

- **H1 恰好成立，B stage 离散场景 impulse 也好** → 最干净的收尾，但这意味着 Yang 2026 这次用不上，源头分析之前多做了（可接受）
- **H1 成立但 disc-5Hz + impulse 仍异常** → 最复杂，需区分 "非均匀 Doppler" vs "帧同步在 discrete Doppler 下的问题"
- **所有 H 都否** → 回到 2026-04-11 baseline 对比 git bisect，找 regression commit

## 引用

- [[yang-2026-uwa-otfs-nonuniform-doppler]]（Yang et al. 2026, IEEE JOE）—— H4 / 衍生 spec 理论支撑
- [[zheng-2025-dd-turbo-sc-uwa]]（Zheng et al. 2025）—— 若深度 debug 要换 DD-MMSE 内核，参考
- `wiki/comparisons/e2e-timevarying-baseline.md` B 阶段表
- `wiki/conclusions.md` #37（pilot_mode 切换历史）
- CSV：`modules/13_SourceCode/src/Matlab/tests/bench_results/e2e_baseline_A3.csv`（A3 OTFS 48 行）

## Log

- 2026-04-21 创建 spec；分支 `feat/otfs-disc-doppler-debug` 已拉
- 2026-04-21 **重排假设顺序**：H1 (pilot_mode regression) 升为首优，原 H0（Yang 2026 非均匀 Doppler）降为 H4；依据 A3 CSV 显示 **static 已 33% BER @ snr=10** 推翻 "32% 是 Doppler 问题"
- 2026-04-21 摄入 6 篇 Doppler 参考，其中 [[yang-2026-uwa-otfs-nonuniform-doppler]] 作为 H4 备用理论
- 2026-04-21 **诊断跑完 (27 run)**：
  - 结果 (均值 ± std, SNR=10dB, 3 trials)：
    | Channel | impulse | sequence | superimposed |
    |---|---:|---:|---:|
    | static | 0.04% ± 0.06 | **28.06% ± 2.79** | 0.00% ± 0.00 |
    | disc-5Hz | 0.00% ± 0.00 | **30.41% ± 1.40** | 0.08% ± 0.07 |
    | hyb-K20 | 0.02% ± 0.03 | **32.56% ± 1.16** | 0.37% ± 0.56 |
  - **H1 成立**，**H4 否定**（Yang 2026 不需要）
  - 辅助：NMSE impulse=-2.9dB / sequence=+3.0dB；path detection impulse 5-8 径 / sequence 2-3 径
- 2026-04-21 **修复**：
  - `test_otfs_timevarying.m:20` default `'sequence'` → `'impulse'`
  - 补 `10_DopplerProc` addpath（`comp_resample_spline` 依赖）
- 2026-04-21 **归档**：`wiki/modules/13_SourceCode/OTFS调试日志.md` 新建；conclusions.md 追加 #38，#37 补撤销说明
- 2026-04-21 spec 归档到 `specs/archive/`
