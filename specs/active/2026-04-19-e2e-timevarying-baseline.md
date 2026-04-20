---
project: uwacomm
type: task
status: active
created: 2026-04-19
updated: 2026-04-19
parent: 2026-04-15-streaming-framework-master.md
phase: E2E-benchmark
tags: [端到端, 基线, 时变信道, BER矩阵, 性能对比, 13_SourceCode, 14_Streaming]
---

# E2E 时变信道性能基线 benchmark

## 背景

现有 `wiki/comparisons/e2e-test-matrix.md` 的基线数据稀疏且不统一：

- SNR 仅 5 个点（0/5/10/15/20 dB），步长粗
- 时变扫描仅 `fd=1Hz` / `fd=5Hz` 两点，无法刻画性能曲线
- `doppler_rate`（CFO）在大多数测试中设为 0，未覆盖真实水声"Jakes 衰落 + 收发运动"叠加场景
- 指标仅 coded BER，**缺失**：NMSE（信道估计精度）、同步可靠性（帧检测率/定时误差）、turbo 迭代收敛曲线
- 6 体制测试 harness 各自独立，seed/数据/帧长不一致，**无法公平横向对比**
- Jakes 连续谱下 SC-FDE/OFDM/SC-TDE/OTFS 全部 ~50% BER，**根因未隔离**（是信道估计失败？BEM 阶数？均衡器 ICI？同步偏移？）

Level 2（BEM 骨架对齐）已完成（2026-04-19 归档 spec），但时变条件下端到端是否真的收敛、在哪个 fd 断崖、与各算法改进是否正相关，**目前没有可引用的基线**。

## 目标

建立一套**可重复、可公平对比、可扩展**的端到端时变信道基线，覆盖 6 体制在多维度参数网格下的性能，产出：

1. 标准化 BER/NMSE/sync 指标矩阵（CSV + Markdown）
2. 可视化（heatmap、BER-SNR 曲线、fd 扫描曲线）
3. 问题诊断起点（定位各体制在时变下的性能墙根因）
4. 未来算法改动的回归基线（后续 Level 3 α 盲估计/UI Jakes 升级均可回归到此基线）

## 范围（L1+L2 合并执行，决策锁定于 2026-04-19）

### 多普勒通道隔离表

`gen_uwa_channel` 有两个独立多普勒机制，本 spec 分阶段隔离：

| 参数 | 物理含义 | 覆盖阶段 |
|------|---------|---------|
| `fading_type='slow'` + `fading_fd_hz` | Jakes 衰落（抽头时变） | **A1** |
| `doppler_rate` (α) | 固定多普勒（收发匀速运动，整帧 CFO+宽带伸缩） | **A2** |
| 离散 Doppler / Rician 混合 | 各路径分立 Doppler 频移 | **B** |
| Jakes × 固定多普勒叠加 | 现实水声信道 | **A3** |

### 阶段 A1：Jakes-only 连续谱扫描

| 轴 | 取值 | 点数 |
|----|------|------|
| SNR | 0 / 5 / 10 / 15 / 20 dB | 5 |
| fd_hz | 0 / 0.5 / 1 / 2 / 5 / 10 Hz（`fading_type='static'` when fd=0, else `'slow'`） | 6 |
| doppler_rate | 0（锁定） | 1 |
| 信道 profile | custom-6 径 + `exponential` | 2 |
| seed | 42 | 1 |
| 体制 | 6 | 6 |

**规模**：6 × 5 × 6 × 2 = **360 点**

### 阶段 A2：固定多普勒（α）扫描

| 轴 | 取值 | 点数 |
|----|------|------|
| SNR | 0 / 5 / 10 / 15 / 20 dB | 5 |
| doppler_rate | 0 / 5e-4 / 1e-3 / 2e-3（对应相对速度 ~0/0.75/1.5/3 m/s @ 1500m/s 声速） | 4 |
| fd_hz | 0（`fading_type='static'`，锁定） | 1 |
| 信道 profile | custom-6 径 + `exponential` | 2 |
| seed | 42 | 1 |
| 体制 | 6 | 6 |

**规模**：6 × 5 × 4 × 2 = **240 点**

**每点指标（L1+L2 一次跑完）**：

| 指标 | 定义 | 来源 |
|------|------|------|
| coded BER | 译码后最终 BER | runner 现有输出 |
| uncoded BER | 硬判决 BER（仅 SC 类） | runner 新增输出 |
| NMSE_ch | `10*log10(norm(h_est-h_true)^2/norm(h_true)^2)` | benchmark harness 旁路读 `ch_info.h_time`（**只在 runner 统计，不回灌 decoder**） |
| turbo iter BER | iter=1..N 每轮 BER | decode 函数新增 `dbg.ber_per_iter` 调试返回（`benchmark_mode=true` 时启用） |
| sync_tau_err | `abs(tau_est - tau_true)` 采样点 | runner 比对 |
| frame_detected | bool | runner 捕获 decode 异常或空输出 |

### 阶段 A3：Jakes × 固定多普勒二维叠加

| 轴 | 取值 | 点数 |
|----|------|------|
| fd_hz | 0 / 1 / 5 / 10 Hz | 4 |
| doppler_rate | 0 / 5e-4 / 1e-3 / 2e-3 | 4 |
| SNR | 5 / 10 / 15 dB（三档代表） | 3 |
| 信道 profile | custom-6 径（固定，不扫 exponential） | 1 |
| seed | 42 | 1 |
| 体制 | 6 | 6 |

**规模**：6 × 4 × 4 × 3 = **288 点**

**产出**：每体制一张 4×4 heatmap（每档 SNR 一张 → 3 × 6 = 18 张），定位"CFO+Jakes 叠加性能断崖"。

### 阶段 B：离散 Doppler / Rician 混合对照

**扫描轴**：

| 轴 | 取值 | 点数 |
|----|------|------|
| SNR | 0 / 5 / 10 / 15 / 20 dB | 5 |
| 信道 | `disc-5Hz` / `hyb-K20` / `hyb-K10` / `hyb-K5` | 4 |
| 体制 | 6 | 6 |

**规模**：6 × 5 × 4 = **120 点**

**目的**：验证"Jakes 连续谱 vs 离散/Rician 混合"对各体制的差异（尤其 OTFS），沿用现有 `test_*_discrete_doppler.m` 产出的模型参数。

### 阶段 C：帧检测率（多 seed）

**从阶段 A 主网格挑代表点**：

| 条件 | 取值 | 点数 |
|------|------|------|
| fd_hz | 0 / 1 / 5 | 3 |
| SNR | 0 / 5 / 10 dB | 3 |
| 体制 | 6 | 6 |
| seed | 42 / 43 / 44 / 45 / 46 | 5 |

**规模**：6 × 3 × 3 × 5 = **270 次运行**，每次只记 `frame_detected` → **54 点聚合**（detection_rate = 成功次数 / 5）

### 总规模与耗时估算

| 阶段 | 点数 | 每点耗时 | 子总 |
|------|------|---------|------|
| A1 Jakes-only | 360 | ~10 s | ~60 min |
| A2 固定多普勒 | 240 | ~10 s | ~40 min |
| A3 二维叠加 | 288 | ~10 s | ~50 min |
| B 离散对照 | 120 | ~10 s | ~20 min |
| C 检测率 | 270 | ~5 s | ~25 min |
| **合计** | **1278 次运行** | - | **~3.25 h** |

**执行策略**：每个阶段独立 MATLAB session（`clear functions; clear all` 重启），A1/A2/A3 可连跑也可拆次。若某阶段超时（> 90 min），允许中断并把已写入 CSV 的行作为部分结果。

## 输出位置

```
wiki/comparisons/
├── e2e-test-matrix.md                          # 现有矩阵（完成后引用新基线）
├── e2e-timevarying-baseline.md                 # 新增（主报告）
├── figures/
│   ├── bench_A1_ber_heatmap_<scheme>.png       # Jakes-only 6 体制 fd×SNR
│   ├── bench_A1_nmse_snr.png
│   ├── bench_A1_turbo_iter_<scheme>.png
│   ├── bench_A2_ber_alpha_snr_<scheme>.png     # 固定多普勒 α×SNR
│   ├── bench_A2_nmse_alpha.png
│   ├── bench_A3_heatmap_<scheme>_snr<X>.png    # 二维叠加 4×4 heatmap ×18
│   ├── bench_B_discrete_vs_jakes.png
│   └── bench_C_detection_rate.png
└── raw-data/
    ├── e2e_baseline_A1_jakes.csv               # 360 行
    ├── e2e_baseline_A2_alpha.csv               # 240 行
    ├── e2e_baseline_A3_2d.csv                  # 288 行
    ├── e2e_baseline_A_turbo_iter.csv           # A1+A2 turbo 每轮（长表）
    ├── e2e_baseline_B_discrete.csv             # 120 行
    └── e2e_baseline_C_detection.csv            # 270 行（聚合前）
```

## 实施清单

### S1：benchmark 基础设施

在 `modules/13_SourceCode/src/Matlab/tests/` 下新建：

```
benchmark_e2e_baseline.m         # 主入口（分阶段 A/B/C）
bench_common/
  ├── bench_channel_profiles.m   # 统一返回 custom-6径 + exponential + 离散 + Rician
  ├── bench_append_csv.m         # CSV 追加写入
  ├── bench_grid_a.m             # 阶段 A 网格
  ├── bench_grid_b.m             # 阶段 B 网格
  ├── bench_grid_c.m             # 阶段 C 网格
  └── bench_nmse_tool.m          # oracle h_true vs h_est NMSE 计算
```

**原则**：

- **禁止**在 benchmark 里重写各体制 TX/RX — 通过 `benchmark_mode` 开关把现有 `test_*_timevarying.m` / `test_*_discrete_doppler.m` 改造为参数可注入的 runner
- 每个现有 runner 顶部加：
  ```matlab
  if ~exist('benchmark_mode','var'), benchmark_mode = false; end
  if benchmark_mode
      snr_list = bench_snr;   % 外部注入
      fading_cfgs = bench_fading_cfgs;
      channel_profile = bench_channel_profile;
      rng_seed = bench_seed;
  end
  ```
- **Oracle 旁路合规**：NMSE 计算 `ch_info.h_time` 只由 benchmark harness 读取，`modem_decode_*` 的 meta 字段保持白名单（CLAUDE.md §7）
- `modem_decode_*` 增加 `dbg.ber_per_iter` 返回（仅 `benchmark_mode=true` 时填充），不改变正常 API

### S2：执行

分五次 MATLAB session（每阶段独立重启避免缓存污染）：

```matlab
% 统一前置
clear functions; clear all;
cd('D:\Claude\TechReq\UWAcomm\modules\13_SourceCode\src\Matlab\tests');

% Session 1 — A1 Jakes-only (~60 min)
diary('bench_A1_results.txt');
benchmark_e2e_baseline('A1');
diary off;

% Session 2 — A2 固定多普勒 (~40 min)
% ... clear + diary + benchmark_e2e_baseline('A2')

% Session 3 — A3 二维叠加 (~50 min)
% ... benchmark_e2e_baseline('A3')

% Session 4 — B 离散对照 (~20 min)
% ... benchmark_e2e_baseline('B')

% Session 5 — C 检测率 (~25 min)
% ... benchmark_e2e_baseline('C')
```

若 A1 超时严重（>90 min），允许 A2/A3 延后到后续 session。

### S3：可视化与报告

- 独立 MATLAB 脚本 `bench_plot_all.m`：读 CSV → 生成所有 PNG → 保存到 `wiki/comparisons/figures/`
- 写 `wiki/comparisons/e2e-timevarying-baseline.md`：
  - frontmatter 完整（type / created / updated / tags / `[[wikilink]]` 回链）
  - 三阶段结果分节
  - 核心发现小结（性能墙 / 断崖 / Jakes vs 离散差异）
  - 图片嵌入
- 更新 `wiki/comparisons/e2e-test-matrix.md` 顶部加引用
- 更新 `wiki/index.md` + `wiki/log.md`（Stop hook 检查）

### S4：结论沉淀与归档

- 新发现结论 → `wiki/conclusions.md` 追加条目
- 跨项目价值（如 BEM 性能墙边界）→ `/promote` 回流 Hub
- spec 保持 active → 归档触发条件：三阶段完成 + 报告合入 + git commit
- 不阻塞后续 Level 3 α 盲估计 / UI Jakes 升级 spec

### S5（本 spec 覆盖完成后的扩展建议）

完成 A1/A2/A3/B/C 五阶段后，若仍有未解问题（例如 SC-TDE 在 α=2e-3 + fd=5Hz 断崖根因），再另立 spec 展开：

- 更密的 α 网格（1e-4 / 2e-4 / ... 10e-4）
- 与 `fading_type='fast'` 对照
- 不同 `max_delay_ms` / `num_paths` 的 CIR 尺度
- 14_Streaming decoder 基线（用户已决策延后）

## 约束与风险

**风险**：

1. **Oracle 泄漏**：benchmark 内部 `ch_info.h_time` 只能用于 NMSE 计算，**不得**回灌到 decoder 的 `meta` 字段。按 CLAUDE.md §7 Oracle 排查清单核查。
2. **耗时**：180 点 × 平均 10s = 30 分钟；若某体制慢（如 OTFS turbo 3 轮）可能 > 1 小时。S2 先跑 static 6 点计时，再决定是否拆分。
3. **公平性**：6 体制比特率/帧长不同，不能直接比 BER 绝对值，需分层解读（高速组 SC-FDE/OFDM/SC-TDE/OTFS；低速组 DSSS/FH-MFSK）。
4. **可复现**：必须 `clear functions; clear all`（MATLAB 缓存），seed 固定，record MATLAB 版本到 CSV metadata 列。

**非目标**（本 spec 不做）：

- ❌ 改算法（均衡器/估计器都用现有版本，只跑 benchmark）
- ❌ 14_Streaming 流式基线（**用户决策**：等端到端明确后另立 spec）
- ❌ α 盲估计改造（Level 3 另立 spec）
- ❌ UI Jakes 升级（另立 spec）
- ❌ Level 3 二维扫描（S5 仅建议，不实施）

## 决策（2026-04-19 锁定）

| # | 问题 | 决策 |
|---|------|------|
| 1 | 只 L1 还是 L1+L2 | **L1+L2 合并**，一次跑完 |
| 2 | 信道 profile | **custom-6 径 + exponential 两个都跑** |
| 3 | 离散 Doppler / Rician 对照 | **纳入**（阶段 B） |
| 4 | 14_Streaming 同步跑 | **不做**，等 13_SourceCode 基线明确后再说 |

## Log

- 2026-04-19 创建 spec，提出 L1/L2/L3 分层方案
- 2026-04-19 用户决策锁定：L1+L2 合并、两 profile、加离散对照、14_Streaming 延后
- 2026-04-19 spec 调整为三阶段（A / B / C）
- 2026-04-19 用户指出 A 只覆盖 Jakes 衰落，缺固定多普勒 α 扫描。阶段 A 拆为：
  - **A1** Jakes-only（原 A）
  - **A2** 固定多普勒 α 扫描（新增，240 点）
  - **A3** α × fd 二维叠加（从可选 S5 提升为必跑，288 点）
  总规模扩至 1278 次运行，~3.25 h
- 2026-04-19 起草 `plans/e2e-timevarying-baseline.md`
- 2026-04-19 **S1.1 bench_common 工具完成**（7 文件 + 7/7 自测通过）：
  - bench_grids / bench_channel_profiles / bench_init_row / bench_format_row /
    bench_append_csv / bench_turbo_iter_log / bench_nmse_tool
  - 路径：`modules/13_SourceCode/src/Matlab/tests/bench_common/`
- 2026-04-19 **S1.2a SC-FDE 参考改造完成**（verify ber=0% @ static+10dB）
- 2026-04-19 **S1.2b 5 timevarying runner 批量改造完成**（OFDM/SC-TDE/OTFS/DSSS/FH-MFSK
  各 1 点 verify 通过）
- 2026-04-19 **S1.2c 5 discrete_doppler runner 改造完成**（OTFS 无独立 discrete 版，
  由 timevarying 复用；SC-FDE/OFDM/SC-TDE/DSSS/FH-MFSK 5/5 verify 通过）

### S1 累计产出（当前 session 结束）

- 7 个 bench_common 工具（`tests/bench_common/`）
- 11 个改造过的 runner（6 timevarying + 5 discrete_doppler）
- 3 个 verify 脚本（test_bench_common / verify_scfde_bench /
  verify_ofdm_bench / verify_timevarying_all / verify_discrete_bench）
- benchmark_mode 注入协议已定型：顶部开关块 + fading_cfgs 后覆盖块 + 主循环后
  CSV 写入 + return 跳过可视化

### 待续（下一 session）

- **S1.3 benchmark 主入口** `benchmark_e2e_baseline(stage)`
  - 分 A1/A2/A3/B/C 五阶段；每个 stage 遍历 schemes × profiles × 参数组合，
    构造体制特定 `bench_fading_cfgs` 并 run runner
  - 体制 fading_cfgs 格式差异（7/4/3 列）由 `build_fading_cfgs` 适配
  - 阶段 C 前置要求：让 `bench_seed` 驱动 runner 内 rng（当前未改；建议 C 阶段
    延后到后续 spec，本期先做 A1/A2/A3/B 四阶段）
  - A2 阶段 OTFS 跳过（物理上固定 α 不适合 OTFS DD 域框架）
- **S2 执行**：五 session（或四 session，C 跳过）跑完 CSV
- **S3 可视化 + wiki 报告**
- **S4 归档 commit**

- 2026-04-19 **S1.3 benchmark 主入口完成**（4 新文件）：
  - `tests/benchmark_e2e_baseline.m`（主 function，A1/A2/A3/B 四阶段 dispatch）
  - `tests/bench_common/bench_run_single.m`（function workspace 隔离 runner 调用）
  - `tests/bench_common/bench_build_fading_cfgs.m`（6 体制 × 4 阶段 fading_cfgs 适配器）
  - `tests/bench_common/bench_get_fft_params.m`（按 fd 分档返回 fft_size/cp/nblk）
  - Dry-run 验证：A1=36, A2=20(OTFS 已跳过), A3=96, B=24 = **176 combos**
  - Smoke test：full A1 × snr=[10]，36/36 pass，耗时 86.6s
  - BER 分布合理（fd=0 多数 =0，fd≥5Hz 高速组退化到 40~50%）
- 2026-04-19 **决策**：profiles 默认仅 `{'custom6'}`（runner 不根据 `bench_channel_profile`
  切换 ch_params，仅作 meta 标签记录）；`exponential` 扫描需 runner 内部改造，
  延后到下一 spec。规模从 1278 → **688 实际跑点**（A1=180 / A2=100 / A3=288 / B=120 / C 延后）
- 2026-04-19 **S2 启动**：A1 全量（180 点）后台执行中

## Result

**完成日期**：2026-04-19
**实施范围**：A1 / A2 / A3 / B 四阶段（C 延后）；单 profile=custom6（exponential 延后）

### 产出

- **代码**（14 文件）：
  - `modules/13_SourceCode/src/Matlab/tests/benchmark_e2e_baseline.m`（主入口）
  - `modules/13_SourceCode/src/Matlab/tests/bench_plot_all.m`（可视化）
  - `modules/13_SourceCode/src/Matlab/tests/bench_common/`（7 工具 + 3 自测 + 4 verify）
  - 11 改造 runner（6 timevarying + 5 discrete_doppler），`benchmark_mode` 注入协议
- **数据**（4 CSV，688 行）：
  - `bench_results/e2e_baseline_{A1,A2,A3,B}.csv`
- **可视化**（10 PNG，1.7 MB）：
  - `wiki/comparisons/figures/{A1,A2,A3,B,summary}_*.png`
- **报告**：`wiki/comparisons/e2e-timevarying-baseline.md`
- **Oracle 审计**：新增代码 0 泄漏（`bench_nmse_tool.m` 注释中提及 `ch_info.h_time` 为设计说明，实际该工具本期未被调用；主入口/runner 改造 0 匹配 `meta.(all_cp_data|all_sym|noise_var|pilot_sym)`）

### 关键发现

1. **Jakes 连续谱 + fd≥1Hz 通用杀手**：SC-FDE/OFDM/SC-TDE/OTFS 全 ~50% BER，离散 Doppler 反而 <1%。根因是连续谱建模不足而非多径本身
2. **固定 α≥5e-4 即崩**（SC-FDE/OFDM/SC-TDE），与 [[specs/active/2026-04-16-deoracle-rx-parameters]] 方向吻合
3. **DSSS 对 α 线性退化**（非断崖）；**FH-MFSK 是抗时变基准线**（跨 fd/α 域均 <1%）
4. **OTFS 在 B 离散信道独自卡 ~32%**（surprising finding），需专项 debug

### 延后项（下一 spec 范围）

- C 阶段多 seed 检测率（需 runner rng 驱动改造）
- `exponential` profile 扫描（需 runner 支持 `bench_channel_profile` 切换 ch_params）
- NMSE / sync_tau_err / turbo iter 长表填充
- OTFS × 离散 Doppler 专项 debug
- α 盲估计模块对接后回归此基线

### 执行统计

| Stage | combos | rows | pass | fail | runtime |
|-------|--------|------|------|------|---------|
| A1 Jakes | 36 | 180 | 36 | 0 | 4.7 min |
| A2 固定α | 20 | 100 | 20 | 0 | ~3 min |
| A3 2D    | 96 | 288 | 96 | 0 | 9.0 min |
| B 离散   | 24 | 120 | 24 | 0 | 3.1 min |
| **合计** | **176** | **688** | **176** | **0** | **~20 min** |
