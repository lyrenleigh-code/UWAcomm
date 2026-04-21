---
project: uwacomm
type: task
status: active
created: 2026-04-21
updated: 2026-04-21
parent: 2026-04-20-alpha-estimator-dual-chirp-refinement.md
tags: [多普勒, α估计, HFM, 速度谱, 迭代refinement, 10_DopplerProc, 物理极限]
---

# HFM 速度谱扫描突破 α=3e-2 物理极限

## 背景

parent spec（双 LFM + 迭代 refinement）已让 SC-FDE 在 **|α|≤1e-2（15 m/s）全 BER=0%**。剩余瓶颈：

| α | BER | 问题 |
|---|:---:|:-----|
| +3e-2 (45 m/s 鱼雷) | **50%** | resample 物理极限 + LFM peak 畸变 |
| -3e-2 | 3% | α<0 不对称（rx 尾部 spline 截断） |

已定位根因在 **L1 estimator 精度 + L2 resample 累积 + L3 LFM 大 α 畸变** 交互放大，属 parent spec 的"resample 物理极限"遗留项。

## 理论基础：wei-2020 速度谱扫描

参考：[[source-summaries/wei-2020-dual-hfm-speed-spectrum]]（IEEE SPL 2020，哈工程 Wei et al.）

### HFM Doppler 不变性

HFM 信号 s_HFM(t) 在压缩因子 k=c/(c+v) 下：

```
s_HFM(k·t) ≈ s_HFM(t - ε(k)) · exp(j·ϑ(k))
             ^^^^^^^^^^^^^^         ^^^^^^^^^
             时间伸缩近似为             + 相位旋转
             时间平移
```

其中 ε(k) = (f_0/M)(1/k - 1)，ϑ(k) = -2π·f_0²/M·ln(k)，M = (f_1-f_0)·T/(f_1·f_0)。

**关键含义**：HFM peak 在 Doppler 下**位置几乎不变**（只是相位旋转），与 LFM 形成对比（LFM 的 chirp rate 被 α 扭曲，peak 畸变）。

### 速度谱函数

wei-2020 通过 Parseval 定理 + 频谱关系 $S(T,f) \propto \frac{1}{f}\exp(...)$ 推导出：

```
F(v) = 某种基于 up-HFM + down-HFM 接收信号的复数函数
       在 v = v_true 处呈尖锐峰值
```

具体 F(v) 公式待从 PDF 原文（`raw/papers/Doppler_Estimation_Based_on_Dual-HFM_Signal_and_Speed_Spectrum_Scanning.pdf`）确认（实施阶段查）。

### 速度谱扫描精度

wei-2020 核心结论：
- 传统时延差法精度 $\sigma_\alpha \propto 1/f_s$（硬件限制）
- 速度谱 1D 扫描精度**不受 fs 限制**，精度提升 ~10×
- 海试验证过

## 目标

**主要**：SC-FDE α = ±3e-2 BER < 10% @ SNR=10dB（从当前 +50% / -3%）
**次要**：α = ±5e-2 (~75 m/s 超高速) 可达 BER < 20%
**兜底**：|α| ≤ 1e-2 BER 不退化（维持 parent spec 的 0%）
**改善**：α<0 对称性（绝对值相同但 sign 不同，BER 差 < 5%）

## 设计决策（实施前确认）

| 决策 | 选择 | 理由 |
|------|------|------|
| 集成方式 | **独立模块** `est_alpha_dual_hfm_vss.m` + runner 精估后端 | 不污染 `est_alpha_dual_chirp`，清晰分层 |
| 前后级关系 | LFM 粗估（当前）→ 速度谱精估（新） | 双级分离：LFM 快速收敛到 ±1e-2，VSS 突破极限 |
| 触发条件 | \|α_lfm\| > 1e-2 时启用 | 小 α 维持当前完美，大 α 进入 VSS refinement |
| 扫描粒度 | 2D 自适应：coarse (Δv=0.5 m/s) + fine (Δv=0.02 m/s) | 对 ±75 m/s 范围 coarse 301 点 + fine 51 点 = 352 次 |
| α 搜索范围 | [-7.5e-2, +7.5e-2] | 覆盖 ±112 m/s（超实用工况） |
| 帧结构 | **不改帧** | 仍用 parent spec 的 HFM+/HFM- + LFM_up/LFM_dn，VSS 使用现有 HFM 对 |

## 范围

### 做什么

1. **新 estimator 模块**：
   - `modules/10_DopplerProc/src/Matlab/est_alpha_dual_hfm_vss.m`
   - 实现 wei-2020 速度谱函数 F(v) + 1D/2D 扫描
   - 输入：bb_raw, HFM_up, HFM_dn, fs, fc, search_cfg (v_range, Δv_coarse, Δv_fine)
   - 输出：α (scalar), diag (含 F(v) 曲线 + peak info)

2. **单元测试**：
   - `modules/10_DopplerProc/src/Matlab/test_est_alpha_dual_hfm_vss.m`
   - AWGN + 6 径静态，α ∈ [±1e-3, ±1e-2, ±3e-2, ±5e-2, ±7e-2]
   - @ SNR=10dB 验收：\|α\|≤5e-2 相对误差 < 5%；\|α\|=7e-2 记录不 assert

3. **SC-FDE runner 集成**：
   - `tests/SC-FDE/test_scfde_timevarying.m` 和 `test_scfde_discrete_doppler.m`
   - 在 parent spec 的迭代 refinement 后追加：
     ```matlab
     if abs(alpha_lfm) > 1e-2 && exist('bench_enable_vss','var') && bench_enable_vss
         [alpha_vss, vss_diag] = est_alpha_dual_hfm_vss(bb_raw, HFM_bb_n, HFM_bb_neg_n, ...);
         alpha_lfm = alpha_vss;
     end
     ```
   - 默认 `bench_enable_vss=true`（新默认启用）
   - 可 toggle 关闭对比

4. **回归**：
   - D stage 全 13 α 点（含 ±3e-2）
   - 新增测试点 α = ±5e-2、±7e-2（需扩展 bench_grids.D）
   - A2 / A1 不退化验证

### 不做

- ❌ 不改 LFM estimator（`est_alpha_dual_chirp` 保持）
- ❌ 不改帧结构（HFM+/HFM- 已存在，直接用）
- ❌ 不改 BEM/Turbo/均衡
- ❌ 不推广到其他 4 体制（独立 spec，在 α 推广 4 体制里）
- ❌ 不实施 lalevee-2025 的 FPGA 二分搜索（留后续工程实现）

## 接口

```matlab
function [alpha, diag] = est_alpha_dual_hfm_vss(bb_raw, HFM_up, HFM_dn, fs, fc, k_hfm, search_cfg)
% 功能：HFM 双信号速度谱扫描法估 α（wei-2020 IEEE SPL）
% 输入：
%   bb_raw    - 1×N complex，下变频基带信号
%   HFM_up    - 1×N_hfm complex，up-HFM 模板（f_0 → f_1）
%   HFM_dn    - 1×N_hfm complex，down-HFM 模板（f_1 → f_0）
%   fs, fc    - 采样率 / 载频 (Hz)
%   k_hfm     - HFM 参数（f_0, f_1, T 按 wei-2020 定义，struct 形式）
%   search_cfg- struct:
%       .v_range        [v_min, v_max] (m/s)，默认 ±c·7.5e-2 ≈ ±112
%       .dv_coarse      粗扫步长 (m/s)
%       .dv_fine        精扫步长 (m/s)
%       .c_sound        声速，默认 1500 m/s
%       .hfm_up_search  up-HFM peak 搜索窗
%       .hfm_dn_search  down-HFM peak 搜索窗
% 输出：
%   alpha - v/c，符号约定与 gen_uwa_channel.doppler_rate 对齐
%   diag  - struct:
%       .v_est              估计速度 (m/s)
%       .F_coarse           粗扫速度谱曲线
%       .F_fine             精扫速度谱曲线
%       .peak_psr           peak-to-sidelobe ratio
%       .scan_time_s        扫描耗时
```

## 实施 Step（参考 plan）

1. **PDF 理论摘录**（0.5h）：从 wei-2020 原文摘出 F(v) 具体公式，补进 wiki source-summary
2. **estimator 实现**（2h）：`est_alpha_dual_hfm_vss.m` + 内部辅助函数
3. **单元测试**（1h）：AWGN α 扫描 → 验证 \|α\|≤5e-2 < 5% rel_err
4. **SC-FDE runner 集成**（1h）：加 vss 分支 + toggle + diag
5. **回归**（1h）：D 阶段 13 α + 新增 ±5e-2、±7e-2 点
6. **wiki + todo + commit**（0.5h）

## 验收标准

### 单元级

- [ ] AWGN 纯噪声下 α ∈ [±1e-3, ±1e-2, ±3e-2] 相对误差 < 3% @ SNR=10dB
- [ ] α = ±5e-2 相对误差 < 5%
- [ ] α = ±7e-2 相对误差 < 15%（边界工况）
- [ ] α = 0 绝对误差 < 5e-5
- [ ] 对称性：\|α_est(+v) + α_est(-v)\| < 10% |v|（验证 α<0 方向无偏差）

### SC-FDE 集成

- [ ] D stage α = +3e-2 BER < 10% @ SNR=10dB（从 50%）
- [ ] D stage α = -3e-2 BER < 5% @ SNR=10dB（从 3%，优化）
- [ ] D stage α = ±5e-2 BER < 20%
- [ ] 【兜底】|α| ≤ 1e-2 BER 维持 0%（不退化）
- [ ] A2 / A1 α=0 路径 BER 完全不变

### 性能

- [ ] 单次 VSS 扫描耗时 < 0.5s（对比 `est_alpha_dual_chirp` 约 0.01s，可接受）
- [ ] 2 级级联总耗时 < 1s/帧

## 时间估计

| Step | 内容 | 工时 |
|------|------|------|
| 1 | PDF 理论摘录 + F(v) 公式确认 | 0.5h |
| 2 | estimator 实现 | 2h |
| 3 | 单元测试 | 1h |
| 4 | SC-FDE runner 集成 | 1h |
| 5 | 回归 + 对称性验证 | 1h |
| 6 | wiki + todo + commit | 0.5h |
| **合计** | | **~6h** |

## 风险

| 风险 | 缓解 |
|------|------|
| F(v) 公式 PDF 细节差异（wiki summary 高层描述） | Step 1 精读 PDF 关键公式；若公式复杂，实施阶段可先用"2D 扫描 α + HFM 相关 PSR 最大" 简化版 |
| 速度谱扫描计算量大 | 粗-细分级扫描 + 1D 一次扫描（而非 2D）；单帧 < 0.5s 可接受 |
| α=+3e-2 / α=-3e-2 仍有残余不对称 | VSS 是对称运算（F(v) 对 v 符号无偏），若 resample 层仍不对称则留 remaining |
| resample 物理极限本身（α>1e-2 spline 累积误差） | VSS 精确后 resample 用精确 α，累积误差应小；若仍崩，说明 spline 本身需要换高阶 FIR 或其他方法 |
| 帧长不够 VSS 扫描 | HFM 持续 30 ms，足够 wei-2020 §III-D 的最优参数 |

## 非目标（显式排除）

- ❌ 不替换 `est_alpha_dual_chirp`（继续作为 \|α\|≤1e-2 主力）
- ❌ 不改帧结构
- ❌ 不做其他 4 体制 VSS（留后续，或作 α 推广 4 体制独立 subtask）
- ❌ 不做时变 α 跟踪
- ❌ 不做 lalevee-2025 FPGA 二分搜索

## 交付物

1. `modules/10_DopplerProc/src/Matlab/est_alpha_dual_hfm_vss.m`
2. `modules/10_DopplerProc/src/Matlab/test_est_alpha_dual_hfm_vss.m`
3. SC-FDE runner 2 文件（timevarying + discrete_doppler）集成
4. `bench_grids.m` D 阶段追加 ±5e-2 / ±7e-2 测试点
5. D stage 扩展 CSV + PNG（before/after + 对称性图）
6. `wiki/modules/10_DopplerProc/HFM速度谱α估计器.md`
7. `wiki/conclusions.md` +1 条
8. `todo.md` 把 "α=3e-2 物理极限突破" 移到完成

## Log

- 2026-04-21 创建 spec（基于 parent spec 遗留项 + wei-2020 论文摘要）
- 2026-04-21 **实施中断（探索未完）**：
  - Step 1 完成：PDF 公式摘录（`raw/papers/Doppler...pdf` §II-III）
  - Step 2 完成：`est_alpha_dual_hfm_vss.m` + 单元测试框架
  - Step 3 遇到两个问题：
    1. **paper 严格 Eq.14（U(f)=f⁴·|X(f)|²/(S(f))²）在基带实现 PSR≈1**（Y(v) 平坦）
       - 可能通带/基带频率映射 subtle error
       - `(S(f))²` 复分母相位抵消
       - 需要更深入 debug 2h+
    2. **简化版 F(v)=peak_up × peak_dn 工作但精度 7-19%**（α=±3e-2）
       - 和当前 est_alpha_dual_chirp 迭代（~2% 精度）相近，无显著优势
  - **关键发现（方向转向）**：回顾 D 阶段数据
    - α=+3e-2 BER=50%（est 2% 精度）
    - α=-3e-2 BER=3% （est 0.4% 精度）
    - **α 估计精度相近，但 BER 差异 17×**
    - 说明 α=3e-2 崩溃根因在 **pipeline 其他环节**（resample/BEM/downconvert），
      **不是 estimator 精度问题**
  - **决策**：暂停 VSS 集成，保留 `est_alpha_dual_hfm_vss.m` + test 作未来入口
    （若需要突破 estimator 精度再回来继续）
  - **开新 spec**：`2026-04-21-alpha-pipeline-large-alpha-debug.md`
    用 diag_alpha_pipeline 工具诊断 α=±3e-2 pipeline 节点 RMS 不对称根因
