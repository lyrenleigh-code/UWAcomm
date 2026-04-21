---
project: uwacomm
type: task
status: active
created: 2026-04-22
updated: 2026-04-22
parent: 2026-04-21-alpha-refinement-other-schemes.md
related:
  - 2026-04-20-alpha-estimator-dual-chirp-refinement.md
  - 2026-04-21-alpha-pipeline-large-alpha-debug.md
references:
  - wiki/source-summaries/sun-2020-dsss-passband-doppler-tracking.md
tags: [DSSS, Doppler跟踪, 符号级, Sun2020, 10_DopplerProc, 13_SourceCode]
---

# DSSS 符号级 Doppler 跟踪（Sun-2020）突破 α=1e-2

## 背景

parent spec 2026-04-21-alpha-refinement-other-schemes 推广 α 补偿到 4 体制后，DSSS 结果：

| α | BER | 评价 |
|---|:---:|:----:|
| 0 ~ 3e-3 | 0% | ✓ 块估计 + Rake 足够 |
| **1e-2（15 m/s）** | **42-46%** | ✗ 扩频 chip-timing 漂移，Rake 对齐失败 |
| 3e-2 | 50% | ✗ |

**根因**：DSSS 块估计（整帧单 α + 一次 resample）假设 α 常值。大 α 下：
- α·N_total ≈ 10⁻² × 36864 ≈ **369 样本时钟漂移**
- 每 chip 序列（Gold31 长 31 chip × sps 8 = 248 样本/symbol）的 peak 位置随帧位置漂移数样本
- Rake 合并依赖精确 chip 对齐，漂移导致 fingers 失配

## 参考方法：Sun-2020 符号级 Doppler 跟踪

[[source-summaries/sun-2020-dsss-passband-doppler-tracking|Sun et al. JCIN 2020]]（哈工程）方案：

### 核心公式

相邻 DSSS 符号的 Gold31 相关峰时差：
```
Δτ = τ_{k+1} - τ_k = α · T_sym
```
每符号得一个**瞬时 α 估计**，形成 α(k) 序列。

### 关键改进

1. **通带操作**（非基带）：时延精度 ∝ fc，passband 更准
2. **三点余弦内插**：`R(τ) ≈ A·cos(ω(τ - τ_0))` 拟合 peak ±1 样本 → sub-sample 精度
3. **自适应本地参考**：用滤波后 α(k) 选 dopplerized Gold31 参考（补偿相关幅度畸变）
4. **先验 Doppler 限制**：AUV 最大速度 → 搜索窗口限制，抗噪声

### 论文验证

- 跟踪 ppm 级动态 α（优于 DFE+PLL + Sharif 闭锁环）
- 可 FPGA 实现

## 目标

**主要**：
- D |α|≤1e-2（15 m/s）BER < 5%（从 42-46%）
- D |α|=3e-2 BER < 20%（从 50%）
- A2 全范围维持 BER=0%（不退化）

**次要**：
- 块估计回退路径（保持向后兼容）
- 符号级 α 输出序列（为未来 Kalman/PLL 平滑准备）

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 实施位置 | 新 estimator `est_alpha_dsss_symbol.m` 在 10_DopplerProc | 职责单一，未来可复用 |
| 运行层级 | Baseband 优先（passband 可选） | baseband 代码已成熟；passband 留 Phase 2 扩展 |
| 前置粗估 | 复用双 LFM est_alpha_dual_chirp（α_block） | 块估计给 symbol tracking 初值（先验限制搜索） |
| 插值方法 | 三点余弦内插（Sun-2020） | 对 Gold31 相关 main peak 是 cosine 形状，匹配度高 |
| 滤波器 | 一阶 IIR 低通（α = β·α_prev + (1-β)·α_new, β=0.7） | 去除符号级估计噪声，保留动态 |
| **Resample 策略** | **均值 + 逐符号都实现，对比** | 用户决策：验证逐符号 resample 是否真的更准（预期复杂度换精度） |
| **IIR 初值** | **前 5 个符号累加（不开滤波），第 6 符号起启用 IIR** | 用户决策：避免 alpha_block 先验被初期噪声污染 |
| **低 SNR 处理** | **不 fallback**（DSSS 工作在低 SNR 是常态） | 用户决策：依赖 α_block 先验 + IIR 去噪，不因 peak_snr 低而跳 estimator |
| 参考 bank | 延后（Phase 2）| 先验证符号级跟踪效果，再做 bank |
| α 上限 | 3e-2（与 SC-FDE 一致） | 实用水声工况覆盖 |

## 理论推导

### 符号级 α 估计

DSSS 帧：`[前导 | training (N_t chips) | data (N_d chips)]`
Gold31 × sps=8 → 每 DSSS symbol 长 248 samples @ fs=48000

符号 k 的匹配滤波 peak 位置：
```
τ_k = k · T_sym_samples + τ_0 + α · k · T_sym_samples
     = (k + δ_k) · T_sym_samples + τ_0
```
其中 τ_0 = 帧起始偏移, δ_k = α·k (累积 Doppler 偏移)

相邻峰时差：
```
τ_{k+1} - τ_k = T_sym_samples · (1 + α) ≈ T_sym_samples + α·T_sym_samples
```

每对符号可得一个 α 估计：
```
α̂_k = (τ_{k+1} - τ_k - T_sym_samples) / T_sym_samples
```

### 三点余弦内插

相关 peak 邻 ±1 样本的幅度 y_{-1}, y_0, y_{+1}。余弦拟合：
```
R(τ) = A·cos(ω·(τ - τ_0))
```
解析解的 sub-sample 偏移：
```
Δτ = atan2(y_{-1} - y_{+1}, 2·y_0 - y_{-1} - y_{+1}) / ω
```
对 main-peak-lobe（ω = π/T_sym_samples）精度约 0.1 sample，对应 α 精度 ~4e-4。

## 接口

```matlab
function [alpha_track, alpha_block, diag] = est_alpha_dsss_symbol(bb_raw, ...
                                                                    gold_ref, sps, fs, fc, ...
                                                                    frame_cfg, track_cfg)
% 功能：DSSS 符号级 α 跟踪（Sun-2020）
% 版本：V1.0.0（2026-04-22）
%
% 输入：
%   bb_raw     - 1×N complex 基带信号（已 downconvert）
%   gold_ref   - Gold31 序列（31 chip 基带）
%   sps        - samples per chip
%   fs, fc     - 采样率 / 载波（Hz）
%   frame_cfg  - struct:
%       .data_start_samples  data 段起始样本
%       .n_symbols           总 symbol 数
%       .n_train             training symbol 数
%   track_cfg  - struct:
%       .alpha_block        粗估 α（双 LFM 给出，用作先验中心）
%       .alpha_max          搜索半径（abs 最大）
%       .iir_beta           一阶 IIR 滤波系数（默认 0.7）
%       .use_subsample      bool，默认 true
% 输出：
%   alpha_track - 1×n_symbols 瞬时 α 序列（逐符号）
%   alpha_block - scalar，alpha_track 平均（用于 resample）
%   diag        - 诊断字段
```

## 范围

### 做什么（Phase 1 + 基础 2）

**Phase 1（核心 symbol-level tracking）**：
1. 新模块 `modules/10_DopplerProc/src/Matlab/est_alpha_dsss_symbol.m`
2. 单元测试 `test_est_alpha_dsss_symbol.m`（AWGN × α 扫描 + 固定 α + 线性 α 漂移）
3. DSSS runner 加 `doppler_track_mode` 开关：`'block'`（默认，现有） | `'symbol'`（新）
4. A2/D 回归 + 与 block 模式对比
5. wiki + todo + commit

**Phase 2（可选扩展）**：
- 通带相关（passband operation）
- 自适应 dopplerized Gold31 bank
- 2D 联合优化（α + timing）

本 spec 默认只做 Phase 1 + 基础验收。Phase 2 效果待 Phase 1 数据决定是否必需。

### 不做

- ❌ 不改 14_Streaming（DSSS 流式 P3.3 已有 Rake+DCD，后续 spec 再推广）
- ❌ 不改其他体制（FH-MFSK/SC-TDE 各有自己的 α 处理）
- ❌ 不做 Kalman/PLL 跟踪（本 spec 用一阶 IIR，足够）
- ❌ 不改 Gold31 序列本身
- ❌ 不做 adaptive bank（Phase 2）
- ❌ 不做时变信道（本 spec 假设 fading_type='static'，α 恒定）

## 验收标准

### 单元测试

- [ ] AWGN 纯噪声 α=1e-3, 3e-3, 1e-2 @ SNR=10dB：α 估计相对误差 < 1%
- [ ] 线性漂移 α(t) = α_0 + β·t（β=1e-4/sym）：跟踪 RMSE < 5e-4
- [ ] α=3e-2（边界）：rel_err < 5%，单独记录

### DSSS runner 集成

- [ ] **A2 全范围不退化**：α ∈ [0, 5e-4, 1e-3, 2e-3] × SNR∈[5,10,15,20] BER < 1%（from 现有 0%）
- [ ] **D |α|≤3e-3 不退化**：BER 维持 0%
- [ ] **D |α|=1e-2**：BER < 5%（从 42-46%）
- [ ] **D |α|=3e-2**：BER < 20%（从 50%）
- [ ] B 阶段（离散 Doppler）不退化（block 回退兼容）

### 代码质量

- [ ] block/symbol 模式都可 runtime 切换，无编译开关
- [ ] symbol 模式失败（peak 找不到）自动回退到 block 模式
- [ ] 单元测试 ≥ 80% 覆盖

## 时间估计

| Step | 内容 | 工时 |
|------|------|------|
| S1 | 读 Sun-2020 PDF 确认公式 + 设计 frame_cfg | 0.5h |
| S2 | 实现 `est_alpha_dsss_symbol.m` + 余弦内插 + IIR 平滑 | 2h |
| S3 | 单元测试 `test_est_alpha_dsss_symbol.m`（AWGN + 固定/线性漂移） | 1h |
| S4 | DSSS runner 集成 + mode 切换 + A2/D 回归 | 1.5h |
| S5 | block vs symbol 对比分析 + 优化参数 | 0.5h |
| S6 | wiki 报告 + todo + commit | 0.5h |
| **合计** | | **~6h** |

## 风险

| 风险 | 缓解 |
|------|------|
| 符号级 peak 搜索受噪声影响严重（低 SNR 漏峰） | 用块估计 α_block 给的先验缩小搜索窗；低 SNR 自动回退 block |
| 大 α 下符号内 chip 也漂移（不仅符号间） | 每 N 符号（N=4~8）重新校准一次 α，而非每符号累加 |
| 余弦内插对 Gold31 multi-lobe 不精确 | Phase 2 改 parabolic 或直接 chirp rate fit |
| α=3e-2 下 α·T_sym ≈ 7 samples/sym 漂移超 Gold31 分辨力 | 边界记录；若本 spec 不达目标，Phase 2 上 adaptive bank |
| 切模式时 rc 提取边界处理 | 保持和 block 模式同款 `lfm_pos + lfm_data_offset` 计算 |

## 非目标

- ❌ 不动 P1-P8 patches（继续用 SC-FDE 模板）
- ❌ 不改 Rake+DCD 核心算法
- ❌ 不做 passband 相关（Phase 2）
- ❌ 不做 adaptive Gold31 bank（Phase 2）
- ❌ 不改 gen_uwa_channel

## 交付物

1. `modules/10_DopplerProc/src/Matlab/est_alpha_dsss_symbol.m` + 单元测试
2. `modules/13_SourceCode/src/Matlab/tests/DSSS/test_dsss_timevarying.m` 加 mode 开关
3. A2/D 回归 CSV + before/after PNG
4. `wiki/modules/10_DopplerProc/DSSS符号级Doppler跟踪.md`
5. `wiki/conclusions.md` + log + index + todo 同步
6. 分 3 commit：
   - `feat(10_DopplerProc): est_alpha_dsss_symbol Sun-2020 符号级跟踪`
   - `feat(13_SourceCode/DSSS): symbol mode 集成 + A2/D 回归`
   - `docs(wiki+todo): DSSS 符号级跟踪突破 α=1e-2`

## Log

- 2026-04-22 创建 spec（基于 parent 推广结果 + Sun-2020 论文）
- 2026-04-22 用户决策：(1) 均值 + 逐符号 resample 都实现做对比；(2) IIR 前 5 符号累加后启用；(3) 低 SNR 不 fallback（DSSS 本来工作在低 SNR）
- 2026-04-22 **Step 1 PDF 精读**：关键 Eq 18 (rx model), Eq 19 (local ref), Eq 20 (cross-corr), Eq 21 (三点内插)
- 2026-04-22 **Step 2 estimator 实现**（est_alpha_dsss_symbol.m）：
  - 匹配滤波 + sequential peak tracking（tau_expected(k) 基于 tau_peaks(k-1)+T_sym 动态）
  - 余弦内插 sub-sample（Sun-2020 Eq.21）
  - IIR warmup 5 符号累加 + β=0.7 平滑
- 2026-04-22 **Step 3 单元测试 5/6 PASS**：α∈[1e-4, 1e-2] 精度 <5%，α=3e-2 约 20% err（边界）
- 2026-04-22 **Step 4 DSSS runner 集成**（`doppler_track_mode` 开关 + `comp_resample_piecewise`）：
  - 符号发现 1：sequential tracking 让 α=1e-2 估计精度 0.02%（突破粗估局部最优）
  - 符号发现 2：alpha_raw 公式应为 `T_sym/Δτ - 1`（符号约定，不是 `(Δτ-T_sym)/T_sym`）
  - runner 里 `benchmark_e2e_baseline` 不传 `doppler_track_mode` → hardcoded `'symbol'` default
- 2026-04-22 **对比结果**（Block vs Symbol mean vs Symbol per-sym）：

  | α | Block | Symbol (均值) | Symbol_per_sym (逐符号) |
  |---|:-----:|:------------:|:----------------------:|
  | 0 ~ 3e-3 | 0% | 0% | 0% |
  | +1e-2 | 42.4% | 38.8% | 38.8% |
  | -1e-2 | 46.0% | 40.8% | 40.8% |
  | **+3e-2** | **51.0%** | **2.2%** ✓ | 4.2% |
  | -3e-2 | 47.4% | 35.0% | 50.4% (退化) |

  **结论**：静态 α 下 **均值 resample > 逐符号**（per-sym 的 boundary 不连续反而害）。
  A2 全范围 0% 维持。

- 2026-04-22 **验收部分达标**：
  - [x] A2 全范围 不退化 ✓
  - [x] D |α|≤3e-3 维持 0% ✓
  - [~] D |α|=1e-2 BER < 5% —— 实际 38-41%，未达标（小改善 ~5%）
  - [x] D α=+3e-2 BER < 20% —— 实际 **2.2%** ✓✓（预期外的巨大突破）
  - [~] D α=-3e-2 BER < 20% —— 实际 35%，未达标（α<0 不对称）

- 2026-04-22 **遗留（Phase 2 方向）**：
  - α=±1e-2 改善有限：需 adaptive dopplerized Gold31 bank（Sun-2020 未实现）
  - α=-3e-2 仍 35%：α<0 不对称（与 SC-FDE 同款 estimator 问题）
  - benchmark_e2e_baseline 不传 `doppler_track_mode`：需加参数透传（未来优化）
  - 时变 α（Jakes）下 symbol per-sym 应优于 mean（A1 Jakes 测试未做）
