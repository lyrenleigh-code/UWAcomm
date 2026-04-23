---
tags: [结论, 技术决策]
updated: 2026-04-23
---

# 关键技术结论

累积记录项目中得出的技术结论，作为后续决策依据。

## SC-FDE 接收链路 ~10% deterministic 灾难触发（2026-04-23，详见 [[specs/archive/2026-04-22-scfde-cascade-resample-oom-fix]]）

> [!warning] 重大修订
> 之前 Phase G 单 seed 跑出"α=-1e-2 SNR=10 13.14% 是 SNR 受限单点"的结论 **被 Phase J Monte Carlo 证伪**：实际是 SC-FDE **接收链路 ~10% deterministic 灾难触发率**，与 cascade 估值无关。

### Phase G 单 seed 全场景（保留为参考，需以 Phase J 重新解读）

`diag_alpha_sweep_full.m`（10 α × 3 SNR × seed=42）：SNR=10 9/10、SNR≥15 10/10。
**但这个 9/10 是 seed=42 单样本结果，不是真实工作率**。

### Phase I 关键证据（diag_seed1024_oracle_isolation.m）

cascade 完全无辜：

| α | SNR | cascade BER | oracle α BER | Δ |
|---|---|:---:|:---:|:---:|
| -1e-2 | 10 | 50.66% | 49.78% | +0.88 |
| +1e-2 | 10 | 51.42% | 50.76% | +0.66 |
| -1e-2 | 15 | 50.46% | 50.90% | -0.44 |

cascade α 估值误差仅 **1e-6 量级**（比 baseline 13% 那次还准），但 BER ~50% — 估值正确无救。

### Phase I 高 SNR 扫描（非单调 BER 反常）

`diag_seed1024_high_snr.m`（seed=1024 + α=+1e-2）：

| SNR | 10 | 15 | 20 | **25** | 30 | 40 |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| BER | 51.42% | 0% | 0% | **49.58%** | 49.71% | 50.61% |

SNR=15/20 救活、**SNR=25 又崩** → **违反 BER vs SNR 单调律** → deterministic 灾难，非 SNR 噪底。

### Phase J Monte Carlo 真实灾难率（diag_seed_monte_carlo.m，30 seed × 2 α × SNR=10）

| α | mean | **median** | 灾难率 (>30%) | 中间 (5-30%) | 健康 (<5%) |
|:---:|:---:|:---:|:---:|:---:|:---:|
| -1e-2 | 5.43% | **0%** | **3/30 (10%)** | 1 | 26 |
| +1e-2 | 5.86% | **0%** | **3/30 (10%)** | 4 | 23 |

- **双峰分布确认**（多数完美 + 少数全错），mean ≠ median
- **±α 灾难率几乎相同**（3/3）→ 不是 ±α 不对称
- **真实灾难率 ~10%**（不是 SNR 受限单点）

### 真根因（L2' Step 1 锁定，2026-04-23）：BEM 信道估计 **ill-conditioned 数值发散**

**证据**（`diag_disaster_layer_isolation.m` 4 trial Oracle H_est 表）：

| Trial | α | seed | BER | path1 |gain| | path6 |gain| | 状态 |
|---|---|:-:|:-:|---|---|---|
| 1 | -1e-2 | 1 | 0% | 1.006 | 0.150 | 健康（与静态参考 0.765/0.092 同档）|
| 2 | -1e-2 | 15 | 47.5% | **13.7** | **74.4** | 幅度爆 18-808× |
| 3 | +1e-2 | 1 | 0% | 1.009 | 0.131 | 健康 |
| 4 | +1e-2 | 23 | 49.2% | **7.9×10²⁵** | **3.1×10²⁶** | 数值溢出（接近 NaN）|

**机制**：BEM (Basis Expansion Model) 求解 `inv(H'H) · H'y` 在某些 (TX bits, RX noise)
组合下观测矩阵 H 接近奇异 → 求逆放大噪声 → h_est 幅度发散 → MMSE 均衡用错信道 → 解码全错。

经典 ill-conditioned LS 问题，BEM 估计器算法弱点。

### 5 候选层最终判定

| 候选 | 状态 | 说明 |
|---|---|---|
| **A. Channel est 极性翻转** | 🟡 部分（不是相位翻是**幅度爆**）| 真根因，但具体形式不是相位翻转 |
| B. BCJR 错误固定点 | ❌ 派生症状 | BCJR 收到错信道 → 必然反向 |
| C. Frame timing 偏移 | ❌ 排除 | lfm_pos=9817 健康/灾难 case 全相同 |
| D. CFO 边界翻转 | ❌ 排除 | cascade α err 1e-6（α 估对了）|
| E. Soft demap LLR 反号 | ❌ 派生症状 | demap 收到错信号 → 必然反向 |

**实际只有一个根因：BEM 估计 ill-conditioned**。其他都是它的下游表现。

### 修复方向（待 L5 实施）

| # | 方法 | 风险 |
|---|------|------|
| 1 | **Tikhonov 正则化** `inv(H'H + λI) H'y`，λ=噪声方差或经验值 | 低（标准做法）|
| 2 | **SVD 截断** 去掉小奇异值（条件数大于阈值）| 中（多了截断阈值参数）|
| 3 | **运行时检测 + fallback** 监测 `\|h_est\| > 阈值` 回退到上一 block | 低（不改算法）|

**建议 1（Tikhonov）** — 最低风险、最常用、不改架构。

### 工程影响

- **低 SNR + α=±1e-2 下 ~10% 帧丢失率** — 在生产 SC-FDE 系统中是高的
- **ARQ 重传同 noise pattern 救不了** — 需要 random interleaver / frame hopping 或修根因
- 不是 SNR 受限（SNR=40 dB 灾难仍 ~50%）

### bench_seed 修复（Phase H, commit `4e6e263 + d9f9e09`）

- `test_scfde_timevarying.m` L163 + L257 加 `(bench_seed-42)*100000` 偏移 + uint32 mod wrap
- 修复前 5 seed BER std=0（rng 仅基于 fi/si）→ **完全掩盖**这个 10% 灾难触发率
- backwards-compat：seed=42 与 baseline bit-exact 一致

### 之前所有 cascade 工作（Patch D+E）独立有效

- cascade 三处 `rat()` 容差 `1e-7/1e-6 → 1e-5` 解决了 OOM（从 97% → <30%）
- 5 个 baseline α 点 BER 与 commit 2947777 完全一致
- 这部分修复**与本节 deterministic 灾难根因独立**，不需要回退

## gen_doppler_channel 仿真-补偿架构修复（2026-04-22，V1.5，详见 [[specs/archive/2026-04-22-matching-pair-doppler-v1_5]]）

- **根因**：V1.1–V1.4 顺序为"Doppler 先、多径后"（Option 2），让多径延迟作用在
  已 Doppler 的信号上，接收端通带 resample 补偿后延迟被缩放为 (1+α)·τ_p，BEM
  用 nominal `sym_delays` 位置失配 → 非单调 BER 跳变（+1.5e-2=10%，+1.7e-2=0%，+2e-2=20%）
- **物理直觉**：每径共享 α 时，Doppler 应该等价于"对整个多径信号统一压缩/扩展"。
  Option 1 顺序（多径先、Doppler 后）才匹配这个物理模型，也匹配 `gen_uwa_channel`
  老仿真的 Option 1 约定（接收端 pipeline 就是按 Option 1 设计的）
- **新工具 `poly_resample.m`**：60 行 Kaiser 加窗 sinc polyphase FIR，与 MATLAB
  `resample` 数值等价（NMSE -302 dB 机器精度），通带仿真 + 接收端形成严格自逆匹配对
- **结果**：oracle_passband 全 α 点（±5e-4 到 ±3e-2，覆盖 50 节）**BER = 0**，
  无需 force_zero band-aid，pipeline 自然运行
- **两种顺序的物理场景**：Option 1 = RX 向 TX 移动 + 多径散射体静态（常见水声工况）；
  Option 2 = TX 向 RX 移动 + 散射体静态（不物理常见）

## `comp_resample_spline` α<0 本征不对称修复（2026-04-22，V7.1，详见 [[modules/10_DopplerProc/resample-negative-alpha-fix]]）

- **根因**：V7.0 当 α<0 时 `pos = (1:N)/(1-|α|) > N`，`pos_clamped = min(pos, N)` 导致
  尾部 |α|·N 样本全被 clamp 到 y(N) 单一值 → 尾部灾难性破坏
- **诊断**：首次跳出 pipeline 做纯函数单元测试（`test_resample_doppler_error.m`），
  QPSK-RRC oracle α 下 NMSE +α vs -α 差异 **75-83 dB**（|α|≥1e-2），tail_RMS 暴涨 4 个数量级
- **修复**：V7.1 单处 5 行 patch，检测 `pos_max > N` 时内部 zero-pad y 尾部，对调用方透明
- **结果**：单元层面 NMSE 对称性差异 **75-83 → <3 dB**；SC-FDE α=-3e-2 BER **2.66% → 0%**
- **历史地位**：闭合 2026-04-20~21 多次 "α<0 非对称 疑似 spline/尾部" 诊断循环的真根因
- **教训**：Oracle pipeline 诊断"某层没问题"的前提是输入符合该层隐含假设（silent failure 陷阱）

## DSSS 符号级 Doppler 跟踪（2026-04-22，Sun-2020 JCIN 2020）

- **DSSS block 估计（整帧单 α）在大 α 下失败**：α=1e-2 帧尾 chip 漂移 ~370 samples，Rake 对齐崩
- **Sun-2020 符号级跟踪**：相邻 Gold31 peak 时差 → 瞬时 α；三点余弦内插 sub-sample 精度
- **Sequential tracking 关键**：`tau_expected(k) = tau_peaks(k-1) + T_sym/(1+α)` 动态，突破搜索窗累积偏移
- **结果**：D α=+3e-2 BER **51% → 2.2%**（25× 改善）；A2/D |α|≤3e-3 全 0% 维持
- **Symbol mean > Symbol per-sym**（静态 α 下，逐符号 resample 的 symbol-boundary 不连续反而害）
- 遗留：α=±1e-2 改善小（需 adaptive Gold31 bank）；α<0 不对称（common root cause）

## α 推广 4 体制（2026-04-21，spec `2026-04-21-alpha-refinement-other-schemes.md`）

3/4 体制推广成功（SC-FDE 模板复用），SC-TDE 下游 α 敏感失败：

| 体制 | A2 全范围 | D \|α\|≤1e-2 | α=+3e-2 | 备注 |
|------|-----------|-------------|---------|------|
| **SC-FDE** | 0% | 0% | 5.4% | 参考 |
| **OFDM** | 0% | 0% | 11.4% | CP 精修有偏差 → 禁用（用空子载波 CFO 替代） |
| **DSSS** | 0% | \|α\|≤3e-3 全 0% | 崩 | 扩频 chip-timing 固有限制 α≥1e-2 |
| **FH-MFSK** | 0% | **全 0%** | 21% | 新增 α 补偿（原无），跨 fd 全通 |
| **SC-TDE** | α=0 SNR≥15 OK | α≠0 崩 50% | - | 下游对残余 α 敏感，独立 spec 处理 |

## α=3e-2 突破（2026-04-21，详见 [[modules/10_DopplerProc/大α-pipeline-不对称诊断]]）

- **α=+3e-2 BER 50% vs α=-3e-2 3% 不对称根因**：estimator 对 +α 方向系统偏差 2%（残余 7e-4），残余超 CP 精修阈值 2.4e-4 → CP wrap 错方向
- **Oracle 诊断证明 pipeline 无不对称**（α=±3e-2 Oracle BER 全 0%），不是 pipeline 物理极限
- **Estimator 迭代 2/5/10/20 次结果恒定**（2% 系统偏差，非收敛速度问题）
- **Pragmatic 修复 3 处**（不改架构）：
  1. TX 帧默认 tail padding（防 α 压缩截断）
  2. CP 精修阈值门禁（|α_lfm|>1.5e-2 或 |α_cp|>0.7×CP_thres 时跳过 CP 精修）
  3. 正向大 α 精扫（α_lfm>1.5e-2 时 ±2e-3 范围选 LFM peak sum 最大的 α）
- **结果**：α=+3e-2 BER **50% → 5.4%**，工作范围 1e-2 → **3e-2**（45 m/s 鱼雷/高速 AUV）

## 迭代 α refinement（2026-04-20，详见 [[modules/10_DopplerProc/α补偿pipeline诊断]]）

- **α=2e-3 断崖 50% BER 根因**：CP 精修 `angle(R_cp)/(2π·fc·T_block)` 有 **±2.4e-4 无模糊阈值**
  - 对 blk_fft=1024, fc=12kHz: |α_残余| < 1/(2·fc·T_block) = 2.44e-4
  - Estimator alpha_lfm 在 6 径下有系统 14% 低估 → α≥2e-3 下残余超阈值 CP wrap
- **修复**：迭代 α refinement（默认 2 次），对 resample 后信号再估残余（est_alpha_dual_chirp 无相位模糊），快速收敛
- **结果**：SC-FDE α 工作范围从 1e-3 → **1e-2**（10× 扩展），覆盖 15 m/s 快艇/AUV
- **Pipeline 无其他瓶颈**（8 toggle 诊断证明）；α=3e-2 是 resample 物理极限（另 spec 处理）

## 双 LFM α 估计器（2026-04-20，详见 [[modules/10_DopplerProc/双LFM-α估计器]]）

- **帧里 4 同步头**（HFM+/HFM-/LFM1/LFM2）历来设计本意是无模糊 α 估计，但旧 RX 代码里 LFM1=LFM2=同一 up-chirp，"双 LFM 相位差"法对 α 数学上不敏感（只能测时钟偏置）
- **把 LFM2 换 down-chirp + est_alpha_dual_chirp**（up/down peak 时延差法）激活后：
  - A2 α=5e-4 BER 48.7% → **0%** @ SNR=10
  - A2 α=1e-3 BER 49% → **2%** @ SNR=10
  - D 阶段核心 α ∈ [±1e-4, +1e-3] 全通
- **α>1e-3 BEM 外推不动**（estimator 输出正确但残余 α 让 BEM 失效）
- **α<0 非对称**（疑似 spline/尾部截断）—— 留后续

## E2E 时变基线（2026-04-19，详见 [[comparisons/e2e-timevarying-baseline]]）

- **Jakes 连续谱 + fd≥1Hz 是当前接收机通用杀手**：SC-FDE/OFDM/SC-TDE/OTFS 全部崩 ~50%；离散 Doppler 反而友好（这 4 体制在 B 阶段都 <1%），说明根因是"BEM/LMMSE 对连续谱建模不足"而非多径本身
- **固定 α≥5e-4 即崩**（fc=12kHz 对应 fd≈6Hz CFO）：SC-FDE/OFDM/SC-TDE 全部 ~50%，暴露接收端缺少 α 盲估计/补偿，与 `specs/active/2026-04-16-deoracle-rx-parameters.md` 方向一致
- **DSSS 对 α 线性退化**（非断崖），扩频增益吸收部分 CFO
- **FH-MFSK 是抗时变基准线**（fd=10Hz/α=5e-4 仍 <1% BER）
- **OTFS 在离散 Doppler 下独自卡 32% BER**（surprising finding），需专项 debug；其他 5 体制在 B 阶段均 <1%

## 信道估计

1. **散布导频是精度决定性因素**：比算法选择影响大10-20dB
2. **BEM(DCT)+散布导频最优**：高fd下全面优于CE-BEM和DD-BEM
3. **接收端禁用发射端参数**：Oracle只作性能对比基准
4. **模块07 doppler_rate 修正后基线 (2026-04-12)**：fd≤5Hz 下 oracle α 补偿后 5dB+ 基本不变；fd=10Hz 是系统 ICI 极限（oracle 在高 SNR 非单调反弹 0.73%→3.65%，非算法问题）；DD-BEM 在 fd=5Hz@20dB 有 0.26% 判决误差传播地板

## 均衡

5. **FDE在长时延信道下全面优于TDE**：有5dB编码增益优势
6. **两级分离架构有效**：多普勒估计与精确定时解耦
7. **UAMP对BCCB无优势**：LMMSE per-frequency权重已最优，UAMP Turbo不稳定
8. **时变信道需 nv_post 实测噪声兜底 nv_eq (2026-04-14)**：BEM+散布导频有残余模型误差，高 SNR 时名义噪声远小于实际残差；MMSE 公式 (|h0|² + nv_eq) 过度去噪 → LLR 过度自信 → BER 在高 SNR 反弹。对策：从训练段用 h_tv 重构 y_pred，`nv_eq = max(nv_eq, nv_post_meas)`，该策略已在 OFDM V4.3 / SC-TDE V5.2 落地
9. **时变信道应跳过训练/CP 精估 (2026-04-14)**：训练段相位差 R_t1/R_t2 在 Jakes 多普勒扩散下被污染，训练精估 α 误差可达 88%；时变只用 LFM 相位粗估 + BEM 跟踪残余即可

## 信道模型

10. **Jakes ≠ 实际水声信道**：Jakes连续Doppler谱过度悲观，实际水声是Rician混合(离散强径+弱散射)
11. **Jakes连续谱确认为伪瓶颈(2026-04-13)**：6体制×6信道对比，离散Doppler下全部可工作

## 体制对比（2026-04-13 离散Doppler全体制对比）

12. **离散Doppler下全部6体制可工作**：disc-5Hz/Rician混合信道，高速体制5-10dB达0%BER
13. **SC-TDE在离散Doppler下逆袭**：Jakes ~48%@全SNR → disc-5Hz **0%@5dB+**，改善最大
14. **FH-MFSK唯一全信道可工作**：Jakes也在0dB即0%，跳频分集+能量检测天然抗Doppler
15. **OTFS在离散Doppler下完美工作**：含分数频移(max 5Hz)→0% BER@10dB+，BCCB模型精确

## OTFS 专项（2026-04-13~14）

16. **OTFS PAPR无法窗化降低**：PAPR=7.1dB根因IFFT随机叠加，CP-only和数据脉冲成形均无效
17. **Hann脉冲成形降旁瓣有效**：频谱PSL降13.8dB，模糊度多普勒PSL降33dB，分辨力展宽2.3x(水声可接受)
18. **OTFS冲激pilot导致时域尖刺**：pilot_value=sqrt(N_data)能量集中单DD点，产生32×sub_block的周期性峰值，PAPR达20dB
19. **ZC序列pilot显著降PAPR**：sequence模式PAPR降9.2dB(21→12dB)，但边缘延迟阴影落入数据区造成估计偏差

## 流式仿真框架（2026-04-15 P1 + P2 完成）

20. **方案 A passband 原生信道有效**：`gen_uwa_channel_pb` 直接在 passband 做多径（real FIR + 载波相位 tap）+ Jakes 时变 + spline Doppler，避免 channel 内部 down/up convert 的概念混乱；与 baseband 等价模型数学一致
21. **Doppler 漂移随帧长线性累积**：长帧 N_body × α 样本漂移，超过半个符号即解码失败；P1 用 oracle 补偿（chinfo 读 α 反 resample），P5/P6 应改用 LFM1/LFM2 相位差盲估计
22. **MATLAB R2025b 静态分析陷阱**：`uilabel(...).Layout.Row = X` 链式赋值让 MATLAB 把函数名误判为变量，整函数所有该名调用失败；必须 `lbl = uilabel(...); lbl.Layout.Row = X`
23. **流式帧检测 hybrid 优于纯阈值**（P2）：纯阈值检测对 Jakes 衰落首帧不鲁棒（peak 远低于 peak_max 被过滤）；hybrid 模式 = 首帧在预期窗口取绝对最大锚定 + 后续帧用 frame_len 预测 ±5% 窗口取本地最大，深衰落漏检不连锁
24. **FH-MFSK 软判决 LLR 显著改善衰落鲁棒性**（P2）：硬判决 1 位错即 CRC 挂；改用每符号 8 频率能量算 per-bit LLR `(max_e_b1 - max_e_b0) / median(e)` 送 Viterbi，配合 [7,5] 卷积码 dfree=5 能纠多位错
25. **FH-MFSK 无均衡，多径展宽 > 50% 符号时长即崩**：FFT 能量检测对 ISI 无能为力；延时展宽 1.5ms vs 符号 2ms (75%) 时连软 LLR 也救不回；OFDM/SC-FDE 自带均衡器才能扛大延时展宽
26. **downconvert LPF 暖机吃首帧**：64 阶 FIR 前 ~64 样本是瞬态会损伤 frame 1 HFM；流式 RX 必须**预填零给 LPF 暖机**（rx_pb_padded = [zeros(N_warmup), rx_pb]，再 trim 输出）

## SC-FDE decode 诊断（2026-04-17）

27. **SC-FDE convergence_flag 单阈值失效 (2026-04-17)**：`modem_decode_scfde` 原 `med_llr > 5` 判据在 LLR clip ±30 下过严，BER=0 场景仍显示未收敛；改三选一（`med_llr > 5 || 硬判决稳定 || 高置信LLR>70%`）。详见 [[SC-FDE调试日志]]
28. **estimated_snr 不应减 10*log10(sps) (2026-04-17)**：`rx_filt` 未做 RRC 能量归一化，`P_sig_train / nv_eq` 本身就是符号域 SNR；旧代码额外减 sps 增益导致恒定偏低 ~10dB。去掉后 est_snr 贴近真实值 ±4dB
29. **est_ber 估计依赖 LLR 正确归一化**：`mean(0.5*exp(-|L|))` 在 LLR scale 偏小（L157 clip ±30）时虚高，不能作 BER 参考；建议用 `hard_converged_iter > 0` 直接置 0。暂留独立修复

## 全项目 Code Review 修复（2026-04-19）

30. **Turbo 均衡 La_dec_info 反馈缺失 (2026-04-19)**：模块 12 的 5 个 turbo_equalizer_*（scfde/ofdm/sctde/otfs/scfde_crossblock）原始实现 `La_dec_info = []` 后迭代内从不更新，BCJR 始终用零先验。这是 2026-04-17 记录的 SC-FDE convergence 问题的**真实根因**。修复：每轮末尾 `La_dec_info = Le_dec_info;` 反馈。影响所有 Turbo 均衡体制
31. **SC-FDE convergence 三选一判据应扩散 (2026-04-19)**：已抽出 `common/decode_convergence.m`，在 modem_decode_{ofdm,sctde,otfs}.m 同步使用；OFDM estimated_snr 同 SC-FDE V2.1.0 去 `10*log10(sps)` 减法
32. **多普勒重采样符号约定统一 (2026-04-19)**：`comp_resample_farrow` V4 的 `pos=(1:N)*(1+α)` 方向与 `comp_resample_spline` V7 的 `pos=(1:N)/(1+α)` 相反，切换 comp_method 产生二倍补偿误差。Farrow 升 V5.0.0 统一为除法方向
33. **turbo_decode Lc 缩放外提 (2026-04-19)**：`L_sys = Lc*sys` 等 4 个表达式在迭代循环内每次重算，值完全相同。外提到循环前，iter=10 时节省 ~40 次冗余计算
34. **siso_decode_conv 加 tail_mode 参数 (2026-04-19)**：V3.1.0 支持 'zero'（默认，conv_encode 配对）和 'unknown'（turbo_encode 无尾比特配对），防止未来误混用两套 BCJR 边界
35. **LDPC LLR 输出符号统一 (2026-04-19)**：`ldpc_decode` 内部 BP 用 log(P(0)/P(1))，现输出前取反对齐输入约定"正值→bit 1"
36. **Oracle 泄漏显式标注 (2026-04-19)**：`eq_bem_turbo_fde` / `rx_chain.rx_otfs` 加显眼 ORACLE 警告 + 变量重命名（h_time_block_oracle），供 baseline 对比保留但明确非真实接收链路

37. **OTFS pilot_mode 分派 + 默认 sequence (2026-04-19, 部分撤销 2026-04-21)**：`modem_decode_otfs` 
  原仅调 `ch_est_otfs_dd`（impulse 专用），导频去除已分派但信道估计未分派。
  修复：按 `cfg.pilot_mode` 分派到 `ch_est_otfs_{dd,zc,superimposed}`。默认曾改为 
  **sequence (ZC)** 降 PAPR ~9dB（20dB→12dB），解决 UI 时域波形多脉冲问题。
  trade-off：5dB BER 从 0% → 7.59%（低 SNR 略差），15dB 仍 0%。
  **2026-04-21 发现 10dB 下 sequence BER 28-32%**（#38），已回滚 default，保留参数化。

38. **OTFS pilot_mode='sequence' 在 SNR=10dB 严重 regression (2026-04-21)**：
  [[e2e-timevarying-baseline]] B 阶段 OTFS 独自 32% BER，专项诊断（27 run 矩阵）定位
  根因是 `pilot_mode='sequence'` 的 `ch_est_otfs_zc` 在 moderate SNR 漏检 40-60% 路径
  （impulse 的 3σ 阈值检测 5-7 径，sequence 的 LS+CAZAC 只 2-3 径）。
  结果（均值）：static 0.04% / 28.06%，disc-5Hz 0% / 30.41%，hyb-K20 0.02% / 32.56%。
  修复：`test_otfs_timevarying.m:20` 默认回滚 'impulse'。
  衍生：原先拟用 [[yang-2026-uwa-otfs-nonuniform-doppler]] 的非均匀 Doppler 理论被证伪
  （H4 否定），暂不引入 off-grid block-sparse OMP。详见 [[OTFS调试日志]]。
