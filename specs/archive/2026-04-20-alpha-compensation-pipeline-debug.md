---
project: uwacomm
type: task
status: active
created: 2026-04-20
updated: 2026-04-20
parent: 2026-04-20-alpha-estimator-dual-chirp-refinement.md
tags: [诊断, α补偿, pipeline, resample, 13_SourceCode, SC-FDE]
---

# α 补偿 Pipeline 深度诊断（α>1e-3 断崖定位）

## 背景

上游 spec `2026-04-20-alpha-estimator-dual-chirp-refinement.md` 激活双 LFM α estimator 后，
**α ≤ 1e-3 工作完美**（BER 0-2% @ SNR=10dB）。但 α ≥ 2e-3 呈断崖式 50% BER，
**四重诊断**已排除 estimator/resample/多径/CP 精修：

| 场景 | α=5e-4 | α=1e-3 | α=2e-3 |
|------|:------:|:------:|:------:|
| Estimator + spline resample | 0% | 2% | **47%** |
| Oracle α + spline resample | 0% | 0.1% | **47%** |
| Oracle α + MATLAB 多相 resample | 0% | 0.1% | **47%** |
| Oracle α + 单径 `gains=[1]` + CP 精修 | 0% | 0.1% | **47%** |

**所有诊断都指向 α=2e-3 崩溃与 estimator/resample/多径无关**——问题在 pipeline 其他环节。
本 spec 目的是**逐级定位**：在 TX→Channel→RX 链路上找出 "α=2e-3 下 oracle 补偿后"
RMS 开始发散的那个节点。

## 诊断假设（待验证/排除）

| 编号 | 假设 | 验证方法 |
|------|------|---------|
| **H1** | `comp_resample_spline` 在长信号累积相位误差，导致 bb_comp 与期望 TX 失配 | 对比 resample 后 bb_comp 与 α=0 基线 bb_raw 的 RMS per sample；画 RMS(n) vs n 看累积 |
| **H2** | `downconvert` LPF 对 fc·α ≈ 24Hz 频偏下的 data 边缘（bw_lfm/2 附近）衰减非线性 | 跳过 LPF 或扩大 cutoff；或比较 bb_raw 频谱在 α=0 vs α=2e-3 的差异 |
| **H3** | `match_filter` RRC 在 resample 后的 sps 采样相位选择被破坏（`for off=0:sps-1` 搜索最大值不再对齐） | 固定 best_off=0 或用 α=0 的 best_off 做 oracle 选择，比较 BER |
| **H4** | 信道估计 BEM 训练在 resample 后的残余 α（ppm 级）下 h_est 发散，LMMSE 失效 | 注入 oracle h_time (从 ch_info) 替换 h_est，比较 BER |
| **H5** | LFM2 peak 在 resample 后漂移，lfm_pos 偏移 1-N 样本，导致 data 段错位 | 打印 lfm_pos 在 α=0, 1e-3, 2e-3 下的值差异；或用 nominal lfm_pos 强制 |
| **H6** | Frame 尾部 data 超出 rx_pb 长度被截断（α=2e-3·N_frame ≈ 74 samples 漂移） | **(a)** 逐块 BER 统计（N_blocks=4），若 ber_blk1 ≪ ber_blk4 即验证累积漂移；**(b)** 帧头前 N 符号解码准确率（若帧头 ~100% 对而帧尾错，进一步确认对称诊断）；**(c)** TX 尾部加 zero-pad tail，若 BER 改善则确认是截断 |
| **H7** | `alpha_cp` 计算在 resample 后 bb_comp 的 CP 上输出错方向的修正（破坏已补偿 α） | 关掉 alpha_cp（强制 alpha_est=alpha_lfm），单独看 BER |
| **H8** | BEM 基函数数量/阶数对 α=2e-3 下的残余相位不足（BIC 选阶失败） | 强制 BEM Q=0（静态信道模型）或 Q=4（超保守）对比 BER |

## 目标

**首要**：识别 H1-H8 中**至少一条**能解释 α=2e-3 崩溃的假设。每条假设给出"若隔离该因素则 BER 改善 X%"的定量结果。

**次要**：产出一张 pipeline RMS 传播图，在 TX→downconvert→resample→match_filter→equalizer
→decode 各节点记录 "α=2e-3 vs α=0" 的相对 RMS，直接看到哪一级 RMS 爆炸。

**兜底**：即使所有 H1-H8 都单独不能解释，至少定位**多因素组合**（e.g., H3+H5）并提出
后续改造方向（不在本 spec 实施）。

## 范围

### 做什么

1. **新建诊断脚本**：`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline.m`
   - 基于 test_scfde_timevarying.m clone，精简到单帧单 α 单 SNR 跑
   - 在关键节点插入 `diag.xxx = ...` 保存变量到 MAT
   - 节点清单（按 pipeline 顺序）：
     ```
     [N0]  frame_bb               (TX 基带，reference ground truth)
     [N1]  rx_pb_clean            (通过信道，无噪声)
     [N2]  bb_raw                 (下变频，含 α 效应)
     [N3]  bb_comp                (resample 后)
     [N4]  rc (symbol rate)       (match_filter + best_off 抽取)
     [N5]  rc_blk (per block)     (分块去 CP)
     [N6]  h_est (per block)      (BEM 信道估计)
     [N7]  y_eq (LMMSE out)       (均衡器输出)
     [N8]  llr / hard_decision    (译码前)
     ```
   - **逐块 BER 统计**（关键诊断，对应 H6）：
     ```
     ber_per_block = zeros(1, N_blocks);   % 4 块各自的 hard decision BER
     for bi = 1:N_blocks
         idx = (bi-1)*blk_fft + (1:blk_fft);
         ber_per_block(bi) = sum(hard_dec(idx) ~= sym_all(idx)) / blk_fft;
     end
     ```
     若 `ber_blk1 < 10%` 而 `ber_blk4 ≈ 50%`，强烈指向累积漂移/帧尾污染
2. **基线对比**：每个节点跑 α=0 和 α=2e-3 两次，保存到同一 MAT
   - 诊断指标：`rms_ratio(n) = norm(signal_α2e3[n] - signal_α0[n]) / norm(signal_α0[n])`
   - α=0 作为"完美基线"，α=2e-3 oracle 下理论应接近 α=0
3. **逐假设隔离测试**：按 H1-H8 分别注入修改，跑 α=2e-3 oracle 单点，记 BER 改善量
   - 每个假设改动必须是**可隔离** 的（toggle on/off），不相互耦合
4. **可视化**：新脚本 `modules/13_SourceCode/src/Matlab/tests/SC-FDE/plot_alpha_pipeline_diag.m`
   - Fig 1: 各节点 RMS ratio 柱状图（x=节点，y=α=2e-3 vs α=0 RMS 比值）
   - Fig 2: bb_comp 与 α=0 基线的 sample-by-sample 差异（看是否累积）
   - Fig 3: h_est 在 α=0 vs α=2e-3 下的 tap magnitude 对比
   - Fig 4: H1-H8 的 BER 改善柱状图（ranking）

### 不做

- **不改 estimator**：estimator 本身（`est_alpha_dual_chirp`）已验证正确，不是瓶颈
- **不改 resample**：两种 resample 方法一致，排除
- **不改帧结构**：本 spec 只诊断不改帧
- **不动 14_Streaming**
- **不做其他 5 体制**：SC-FDE 诊断完再推广
- **不做算法改造**：本 spec 输出"根因定位 + 后续方向"，实施留下一 spec

## 诊断详细实施

### Step 1：搭诊断脚手架（1h）

`diag_alpha_pipeline.m` 骨架：

```matlab
%% diag_alpha_pipeline.m — α 补偿 pipeline 逐级 RMS 诊断
% 对应 spec: 2026-04-20-alpha-compensation-pipeline-debug.md

clear; clc; close all;
addpath_all();  % 加各模块路径

alpha_list = [0, 2e-3];   % 基线 + 崩溃点
snr_db = 10;
seed = 42;

diag_all = struct();

for ai = 1:numel(alpha_list)
    alpha = alpha_list(ai);
    tag = sprintf('α%.0e', alpha);
    fprintf('=== 诊断 %s ===\n', tag);

    % 复用 test_scfde_timevarying 的 TX 路径（内联或函数化）
    % 注意：整个 pipeline 必须跑 oracle α（alpha_est = alpha_true）
    % 在关键节点插入 diag 记录

    diag_run = run_scfde_pipeline_with_diag(alpha, snr_db, seed);
    diag_all.(sprintf('alpha_%d', ai)) = diag_run;
end

save('diag_alpha_pipeline.mat', 'diag_all', 'alpha_list', 'snr_db', 'seed');

% 逐节点 RMS 对比
fprintf('\n=== Pipeline RMS Ratio (α=2e-3 / α=0) ===\n');
nodes = {'frame_bb','rx_pb_clean','bb_raw','bb_comp','rc','rc_blk','h_est','y_eq','llr'};
for ni = 1:numel(nodes)
    n = nodes{ni};
    a = diag_all.alpha_1.(n);
    b = diag_all.alpha_2.(n);
    rms_ratio = norm(b(:) - a(:)) / norm(a(:));
    fprintf('  [%s] RMS ratio = %.4e\n', n, rms_ratio);
end
```

核心 helper `run_scfde_pipeline_with_diag(alpha, snr_db, seed)` 从
`test_scfde_timevarying.m` 抽取 TX+RX 链路，接受 oracle α，在 N0-N8 各节点
保存 `diag.<name>` 字段。

### Step 2：逐假设隔离（3h）

为每条 H1-H8 定义一个 toggle：

```matlab
% Cfg struct 驱动：cfg.h1_skip_resample = true/false
cfg = default_cfg();       % 所有 toggle 默认 false
cfg.h1_skip_resample = true;
[ber_h1, diag_h1] = run_scfde_pipeline_with_diag(2e-3, 10, 42, cfg);
```

| H | Toggle | 实现 |
|---|--------|------|
| H1 | `skip_resample` | `bb_comp = bb_raw`（不 resample）；α=0 下应 OK，α=2e-3 下 BER 应高于 baseline |
| H2 | `skip_downconvert_lpf` | downconvert 后不过 LPF，或 LPF cutoff ×2 |
| H3 | `force_best_off` | best_off = 0（固定 sps 相位）或 = α=0 下的 best_off |
| H4 | `oracle_h` | h_est 用 `ch_info.h_time` 替换 BEM 输出 |
| H5 | `force_lfm_pos` | lfm_pos 用 α=0 下的 nominal 值（不基于 LFM2 peak） |
| H6 | `pad_tx_tail` | TX 尾部加 1000 样本 zero-pad，防 α 压缩后 data 截断 |
| H7 | `skip_alpha_cp` | alpha_est = alpha_lfm（不加 alpha_cp） |
| H8 | `force_bem_q` | BEM 阶数 Q=0 或 Q=4 |

每个 toggle 跑 α=2e-3 oracle，记 BER。对比基线（47%）的改善。

### Step 3：可视化与分析（1h）

`plot_alpha_pipeline_diag.m` 读 `diag_alpha_pipeline.mat` 画图。

分析要点：
- 哪个节点 RMS ratio 第一次超过 1%（SNR=10dB 下噪声 RMS 约 10%）
- 哪个 toggle 让 BER 从 47% 显著降低（>10% 改善）
- 多因素组合：如 H4 + H5 是否协同

### Step 4：报告与后续 spec（0.5h）

**输出**：`wiki/modules/10_DopplerProc/α补偿pipeline诊断.md`

包含：
1. 8 假设 each 的 BER 改善表
2. Pipeline RMS 传播图
3. 根因结论（一句话）
4. 推荐改造方向（列出后续 spec 主题）

## 验收标准

- [ ] `diag_alpha_pipeline.m` 能跑通并输出 diag MAT（α=0, α=2e-3 各一次）
- [ ] N0-N8 RMS ratio 表格生成，能看到哪级爆炸
- [ ] H1-H8 每条独立 toggle 测试完成（8 次 BER 跑）
- [ ] 结论写入 wiki，至少 1 条假设**明确验证**或**明确排除**
- [ ] 输出后续改造 spec 主题清单（≥ 1 条）

## 非目标

- ❌ 实际修复 α=2e-3 崩溃（本 spec 只诊断）
- ❌ 其他 5 体制（等 SC-FDE 根因找到再推广）
- ❌ 时变 α 下的诊断（本 spec 只做固定 α=2e-3）
- ❌ 改动 estimator 或 resample

## 时间估计

| Step | 内容 | 工时 |
|------|------|------|
| 1 | diag 脚手架（run_scfde_pipeline_with_diag 抽取） | 1h |
| 2 | H1-H8 toggle 测试 | 3h |
| 3 | 可视化脚本 + 分析 | 1h |
| 4 | wiki 报告 + 后续 spec 主题草案 | 0.5h |
| **合计** | | **~5.5h** |

## 风险

| 风险 | 缓解 |
|------|------|
| 抽取 run_scfde_pipeline_with_diag 工作量被低估（runner 内嵌 900 行） | 允许"就地打 diary + save"代替函数化抽取，保留 runner 不动 |
| H1-H8 均无显著效果（不能定位） | 允许 H9/H10 扩展（帧 sync 精度、SNR 估计、LLR scaling 等） |
| RMS ratio 诊断被噪声主导 | 使用无噪声路径（`rx_pb_clean`）做主诊断，只在 llr/BER 对比时加噪声 |
| diag MAT 文件过大 | 只存各节点的前 N 个样本 + 统计量（RMS/能量/相位），不存全序列 |

## 开放问题（实施中决议）

1. **run_scfde_pipeline_with_diag 抽取方式**：就地 diag vs 函数化抽取？先就地 diag 快速迭代
2. **RMS ratio 阈值**：多大算"爆炸"？建议 >0.5（约等于信号变成噪声）
3. **多因素耦合**：如果单个 toggle 都不救，尝试两两组合（最多 8·7/2=28 次跑），时间允许才做

## 回滚策略

若诊断完全不收敛（所有假设都不对）：
1. 生成 IR（impulse response）测试：TX 只发单位冲激，α=2e-3 下 RX 是否能恢复
2. 完全跳过 runner，用纯信道 + resample 合成数据测 BER 下限
3. 若仍崩，说明 α=2e-3 在当前 fs/fc/sym_rate 组合下就是 **物理极限**，需要放大 fs 或改帧设计

## Log

- 2026-04-20 创建 spec（基于 refinement spec 的四重诊断结果排除 estimator/resample/多径）
- 2026-04-20 用户决策：(1) 就地 diag（不抽 function）；(2) 无噪声 rx_pb_clean 做 RMS 主诊断；(3) **H6 必跑逐块 BER + 帧头解码准确率**（对称诊断：帧头对则帧尾污染成立）
- 2026-04-20 **Step 1-4 完成**：
  - runner 插桩（9 节点 + 10 toggle + 逐块 BER），默认 disabled 零回归
  - diag_alpha_pipeline.m 跑完 12 次迭代（2 baseline + 10 toggle）
  - **根因定位**：CP 精修 `angle(R_cp)/(2π·fc·T_block)` 相位模糊阈值 ±2.4e-4，
    estimator 14% 系统误差让 α≥2e-3 残余超阈值 wrap
  - **意外发现**：之前 "oracle α BER=47%" 结论错了——那次强制 `alpha_cp=0` 切断 CP 精修链路；
    真正 oracle（alpha_lfm=真值 + 保留 CP 精修）baseline BER = 0%
  - H2-H8 toggle 全部 0 影响（pipeline 无其他瓶颈），只有 H1 skip_resample 崩 50%
- 2026-04-20 **修复**：在 `test_scfde_timevarying.m` 加迭代 α refinement（默认 2 次）：
  对 resample 后的 bb 重新跑 est_alpha_dual_chirp 估残余，累加到 alpha_lfm。
  Peak 位置法无相位模糊，快速收敛到 CP 阈值内
- 2026-04-20 **结果**：
  - A2 α=2e-3 BER **47% → 0%**（SNR≥10）
  - D 阶段 α ∈ [±1e-4, ±1e-2] 全 BER=0%（工作范围扩 10×）
  - α=3e-2 仍崩（resample 物理极限，留后续 spec）
- 2026-04-20 **产出**：
  - `wiki/modules/10_DopplerProc/α补偿pipeline诊断.md`
  - `figures/D_*_{before,mvp,after_iter}.png` 9 PNG 三代对比
  - `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_alpha_pipeline.m`
  - 诊断数据 `diag_results/` 12 MAT + CSV

## Result

- **完成日期**：2026-04-20
- **状态**：✅ 完成
- **关键产出**：α=2e-3 崩溃根因 = CP 精修 ±2.4e-4 相位模糊阈值；修复 = 迭代 α refinement（默认 2 次）+ CP 阈值门禁；A2 α=2e-3 BER 47%→0%，工作范围扩 10× → \|α\|≤1e-2 全 0%
- **后继 spec**：`archive/2026-04-21-alpha-pipeline-large-alpha-debug.md`（α=3e-2 物理极限突破）
- **归档**：2026-04-25 by spec 状态审计批量归档
