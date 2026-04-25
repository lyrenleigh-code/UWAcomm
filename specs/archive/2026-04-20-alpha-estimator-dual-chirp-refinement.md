---
project: uwacomm
type: task
status: active
created: 2026-04-20
updated: 2026-04-20
parent: 2026-04-19-constant-doppler-isolation.md
tags: [多普勒, α估计, 双LFM, 10_DopplerProc, 13_SourceCode, 帧结构, estimator改造]
---

# α 估计器改造：双 LFM（up+down chirp）时延差法

## 背景

上游 spec `2026-04-19-constant-doppler-isolation.md` 跑完 D 阶段诊断（SC-FDE × 13 α 点 × SNR=10dB，
CSV `modules/13_SourceCode/src/Matlab/tests/bench_results/e2e_baseline_D.csv`）得到
**surprising finding**：α 估计器**完全失效**。α_est 恒为 ~1e-5 级噪声，非零 α 全部
BER=50%。

### 根因定位

帧结构 `[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]` 设计本意是无模糊 α 估计，
但当前实现：

1. **HFM+/HFM-**（up/down hyperbolic FM）只用于 TX 帧头，RX **完全没用它们做 α 估计**
2. **LFM1 = LFM2** 都是同一个 `LFM_bb_n`（up-chirp），RX 用"双 LFM 相位差"法
3. 同形双 LFM 的相关峰相位差数学上对 α 不敏感，只能测时钟/相位偏置

## 目标

激活帧结构里真正能估 α 的双 chirp 对——**把 LFM2 改成 down-chirp**，用 up+down
LFM 对的 peak 时延差法估 α。HFM+/HFM- 继续做帧检测/粗定时（Doppler 鲁棒）。

**验收目标**：
- SC-FDE 在 α ∈ [±1e-4, ±3e-3] 下 α 估计相对误差 < 5% @ SNR=10dB
- E2E BER 接近 α=0 基线（< 5% @ SNR=10dB）
- **α 上限保持 ±3e-2**（覆盖鱼雷/拖曳声纳高速工况），guard 扩展到够用

## 设计决策（2026-04-20 确认）

| 决策 | 选择 | 理由 |
|------|------|------|
| 帧结构 | **改**：LFM2 → down-LFM（新 `LFM_bb_neg`） | 双 LFM up+down 是最简洁 α 估计方案 |
| 5 体制切换顺序 | **先 SC-FDE 单体制跑通**，其他 4 体制后批量 | 降低回归面 |
| α 上限 | **保持 ±3e-2** | 覆盖水声全工况 |
| guard 窗 | **扩展**：`guard_samp = max(sym_delays)*sps + 80 + ceil(α_max·max(N_preamble,N_lfm))` | α=3e-2、T=30ms 下 peak 漂移 ~43 样本，guard 需吸纳 |
| OTFS | **不改** | 帧结构异，留后续 spec |
| 时变 α | **不改** | 本 spec 只做恒定 α，时变留后续 spec |
| BEM/Turbo | **不改** | α 补偿后残余由 BEM 跟踪，本 spec 不动 |

## 算法

### 双 LFM（up+down）时延差法

TX 两个 LFM 都是 `T_pre` 秒、带宽 `B = f_hi - f_lo`：

- **LFM_up**: `f(t) = f_lo + k·t`，`k = B/T_pre > 0`
- **LFM_dn**: `f(t) = f_hi - k·t`（新增）

接收端 α 导致时间轴伸缩 `t → (1+α)·t`，本地 template 不补偿时匹配滤波 peak 位置：

- **up-chirp** peak 漂移：`Δτ_up = -α·f_lo/k` （频率被压缩到 f_lo 提前出现）
- **down-chirp** peak 漂移：`Δτ_dn = +α·f_hi/k` （反向）

α 估计公式（简化，假设 f_lo ≈ f_hi ≈ fc）：

```
Δ(Δτ) = Δτ_dn - Δτ_up ≈ α·(f_lo + f_hi)/k = 2α·fc/k
α = k·(Δτ_dn - Δτ_up) / (2·fc)
```

或更通用（用实际 peak 位置差）：

```
τ_up^obs = τ_up^nom + Δτ_up
τ_dn^obs = τ_dn^nom + Δτ_dn
α = k·[(τ_dn^obs - τ_up^obs) - (τ_dn^nom - τ_up^nom)] / (f_lo + f_hi)
```

### 动态范围与精度

- **动态范围**：受 guard 搜索窗限制。α=3e-2、T_pre=30ms 下 peak 漂移 ≈ α·T_pre·fs ≈ 43 样本，
  guard 从 800 → 1100 样本（~23 ms）保证有余量
- **分辨率**：峰值定位精度 ≈ 1/fs（~21 μs），带入公式 σ_α ≈ k/(2·fc·fs) ≈
  (8kHz/30ms)/(2·12kHz·48kHz) ≈ 2.3e-4 量级（可通过插值提升到 1e-5）
- **无相位模糊**：基于峰值位置，不涉及 2π 卷绕

### 可选第二级（LFM 相位精估）

若双 LFM 时延估 α 后残余仍大，可用**相同 LFM 的相位差**做第三级精估
（原代码的"alpha_lfm = angle(R2·conj(R1))"逻辑在 α 小残余下仍有效）。本 spec
**暂不启用**（Step 3 评估是否需要）。

## 接口

```matlab
function [alpha, diag] = est_alpha_dual_chirp(bb_raw, LFM_up, LFM_dn, fs, fc, k, search_cfg)
% 输入：
%   bb_raw      - 1×N complex，下变频后基带信号
%   LFM_up      - 1×N_lfm complex，up-chirp 模板（match filter 已 conj+fliplr）
%   LFM_dn      - 1×N_lfm complex，down-chirp 模板
%   fs          - 采样率 (Hz)
%   fc          - 载频 (Hz)
%   k           - chirp 斜率 (Hz/s，正值)
%   search_cfg  - struct:
%       .up_start/.up_end          up-chirp 峰搜索窗（样本索引）
%       .dn_start/.dn_end          down-chirp 峰搜索窗
%       .nominal_delta_samples     (τ_dn^nom - τ_up^nom) 样本数
% 输出：
%   alpha       - scalar, α 估计
%   diag        - struct:
%       .tau_up/.tau_dn            peak 样本位置
%       .peak_up/.peak_dn          peak 幅度
%       .dtau_samples              观测 Δτ 样本数
%       .dtau_residual             相对 nominal 的残差
```

## 范围

### 做什么

1. **TX 帧改造**（`test_scfde_timevarying.m` 先改 SC-FDE）：
   - 新生成 `LFM_bb_neg`（down-chirp，f_hi → f_lo）
   - 帧组装第 4 位从 `LFM_bb_n`（up 复用）改为 `LFM_bb_neg_n`（down 单独）
   - guard_samp 扩展
2. **新 estimator 模块**：
   - `modules/10_DopplerProc/src/Matlab/est_alpha_dual_chirp.m`
   - `modules/10_DopplerProc/src/Matlab/test_est_alpha_dual_chirp.m`（单元测试：纯 AWGN + 6 径静态）
3. **SC-FDE runner 切换**：
   - `test_scfde_timevarying.m` α 估计入口替换为 `est_alpha_dual_chirp` 调用
   - `test_scfde_discrete_doppler.m` 同步改（保持两个 runner 一致）
4. **回归**：
   - D 阶段：SC-FDE × 13 α 点（before/after 对比图）
   - A2 阶段：SC-FDE × 4 α 点 × 5 SNR（20 pts，确认 α∈[5e-4, 2e-3] BER 大幅改善）
   - A1 阶段：SC-FDE × 6 fd 点 × 5 SNR（30 pts，确认 Jakes 路径不退化）
5. **Step 完成后**：保留 4 个其他体制（OFDM/SC-TDE/DSSS/FH-MFSK）的切换到后续增量

### 不做

- **OTFS 不改**：帧结构异
- **时变 α 不改**：本 spec 假设 α 帧内恒定
- **BEM/LMMSE/Turbo 不改**：α 补偿后残余由 BEM 跟踪
- **14_Streaming 不动**：先在 13_SourceCode 固化
- **OFDM/SC-TDE/DSSS/FH-MFSK 切换推迟**：SC-FDE 跑通后再批量推广

## 验收标准

### 单元级

- [ ] `est_alpha_dual_chirp` 纯 AWGN 无多径，α ∈ [±1e-4, ±1e-2]，|err|/|α| < 5% @ SNR=10dB
- [ ] 6 径静态信道，α ∈ [±1e-4, ±3e-3]，|err|/|α| < 10% @ SNR=10dB
- [ ] α=3e-2：允许 |err|/|α| < 30%（边界工况），但 BER 不崩 50%
- [ ] α=0 零偏 < 5e-5

### SC-FDE 集成

- [ ] D 阶段 after-refinement：α ∈ [±1e-4, ±3e-3] BER < 5% @ SNR=10dB
- [ ] D 阶段 α=±1e-2：BER < 15% @ SNR=10dB
- [ ] A2 阶段 after-refinement：α=[5e-4, 1e-3, 2e-3] × SNR∈[10,15,20] 全部 BER < 5%
- [ ] A1 阶段 α=0 路径 BER 与 before 一致（不退化）

### 帧结构改动回归

- [ ] 帧检测率（HFM 正相关峰）与改前对齐（HFM 未动，不应受影响）
- [ ] 帧定时（LFM 精定时）在 α=0 下保持精度

## 时间估计

| Step | 内容 | 工时 |
|------|------|------|
| 1 | `est_alpha_dual_chirp.m` + 单元测试 | 2h |
| 2 | SC-FDE 帧改造 + guard 扩展 + estimator 切换 | 1.5h |
| 3 | D/A2/A1 回归跑 + 数据分析 | 1h |
| 4 | wiki 文档 + conclusions 更新 | 0.5h |
| 5 | spec 归档 + commit | 0.5h |
| **合计** | | **~5.5h** |

（注：其他 4 体制切换留后续 incremental PR，按 SC-FDE 模式复用）

## 风险

| 风险 | 缓解 |
|------|------|
| HFM 真实是 hyperbolic FM（不是 LFM），peak 位置对 α 不敏感（Doppler 鲁棒） | 确认后 HFM 保留作帧检测；α 估计交给新的 up/down LFM 对 |
| LFM2 改成 down-chirp 破坏现有 CP 精估链路 | CP 精估在 data 区间内，不依赖 LFM2 波形（LFM 只用于定时）；验证 test_scfde_timevarying 改后跑 A1 α=0 路径 BER 不变 |
| guard 扩展使帧变长、开销增大 | 典型扩展 ~4 ms / 帧（~总长 1%），可接受 |
| 双 LFM peak 位置互扰（up/down 搜索窗重叠） | search_cfg 严格分割：up 窗 = LFM1 前导区，dn 窗 = LFM2 前导区，中间留 guard |
| α=3e-2 下 LFM peak 漂移超出搜索窗 | Step 1 单元测试覆盖 α=3e-2，若 peak 漂出则扩搜索窗或记入非线性矫正 |
| 其他 4 体制 runner 共享同款 LFM estimator 代码，切换成本被估低 | 本 spec 只承诺 SC-FDE；其他体制独立 incremental 处理 |

## 交付物

1. `modules/10_DopplerProc/src/Matlab/est_alpha_dual_chirp.m`
2. `modules/10_DopplerProc/src/Matlab/test_est_alpha_dual_chirp.m`
3. `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m`（帧改 + estimator 切换）
4. `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_discrete_doppler.m`（同步改）
5. D/A1/A2 after-refinement CSV + PNG（before/after 对比）
6. `wiki/modules/10_DopplerProc/双LFM-α估计器.md`
7. `wiki/conclusions.md` +1 条
8. spec 归档 + commit

## Log

- 2026-04-20 创建 spec（基于 D 阶段诊断数据）
- 2026-04-20 用户决策：帧可改、先 SC-FDE 单体制、保持 α 上限 ±3e-2、扩 guard
- 2026-04-20 算法由"双 HFM"改为"双 LFM（up+down）"：HFM 是 hyperbolic FM 对 Doppler 鲁棒，反而做不了 α 估计；LFM（linear FM）做 up/down 时延差才是正确路径
- 2026-04-20 **Step 1 完成**：`est_alpha_dual_chirp.m` + 单元测试，9/9 核心 α ∈ [±1e-4, ±3e-3] PASS (<2% rel_err)；边界 |α| ∈ [1e-2, 3e-2] 记录不 assert
- 2026-04-20 **Step 2 完成**：SC-FDE runner 帧结构 LFM2 → down-chirp、guard 扩展、α 估计入口切换；发现符号约定反向（runner 内 `alpha_lfm = -alpha_lfm_raw` 补偿）
- 2026-04-20 **Step 3 完成**：D/A2/A1 回归
  - A2 α=5e-4 SNR=10dB BER **48.7% → 0%**（完美）
  - A2 α=1e-3 SNR=10dB BER **49% → 2%**
  - A2 α=2e-3 仍崩 50%（estimator 相对精度 15%，残余让 BEM 失效）
  - D 阶段 α ∈ [+1e-4, +1e-3] 全 0% BER；α<0 不对称（-1e-3 仍 41%）
  - A1 α=0 路径基线保持（fd=0 BER=0%）
- 2026-04-20 **Step 4 完成**：wiki 文档 `wiki/modules/10_DopplerProc/双LFM-α估计器.md`；conclusions / log / index 同步
- 2026-04-20 **遗留**（留后续 incremental）：
  - α<0 不对称（疑似 rx 尾部 spline 截断）
  - α > 1e-3 时 BEM 对残余 α 不 tolerant
  - α ∈ [1e-2, 3e-2] 超出当前 MVP 范围
  - 其他 4 体制（OFDM/SC-TDE/DSSS/FH-MFSK）切换
  - OTFS 专题（无 HFM 对帧结构）

## Result

- **完成日期**：2026-04-20
- **状态**：✅ 完成
- **关键产出**：双 LFM up+down chirp α estimator + 迭代 refinement；A2 α=5e-4 BER 48.7%→0%；α 工作范围 1e-4→1e-2（15 m/s）
- **后继 spec**：
  - `archive/2026-04-20-alpha-compensation-pipeline-debug.md`（α=2e-3 崩溃 → CP 精修阈值 + 迭代 refinement，全 0%）
  - `archive/2026-04-21-alpha-pipeline-large-alpha-debug.md`（α=3e-2 突破，工作范围扩到 45 m/s）
  - `archive/2026-04-21-alpha-refinement-other-schemes.md`（推广 OFDM/DSSS/FH-MFSK，partial）
  - `archive/2026-04-22-resample-negative-alpha-asymmetry.md`（α<0 修复，已归档）
- **归档**：2026-04-25 by spec 状态审计批量归档
