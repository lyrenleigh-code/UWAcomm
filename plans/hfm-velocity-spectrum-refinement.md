---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-21-hfm-velocity-spectrum-refinement.md
created: 2026-04-21
updated: 2026-04-21
tags: [HFM, 速度谱, α估计, 10_DopplerProc]
---

# HFM 速度谱扫描突破 α=3e-2 — 实施计划

## Step 1: PDF 公式确认（0.5h）

读 `raw/papers/Doppler_Estimation_Based_on_Dual-HFM_Signal_and_Speed_Spectrum_Scanning.pdf` §II-III，摘录：

1. HFM Doppler 不变性 s(kt) ≈ s(t-ε(k))·exp(jϑ(k))
2. HFM 频谱近似形式 S(T,f) 的 C(T) 和 1/f 结构
3. 速度谱函数 **F(v) 的完整公式**（核心待确认）
4. up-HFM / down-HFM 双信号的组合方式（互相关 or 分别扫描 or 其他）
5. 参数选择准则（T, f_0, f_1）对 RMSE 的影响

**输出**：补进 `wiki/source-summaries/wei-2020-dual-hfm-speed-spectrum.md`（当前只高层描述），加数学附录。

**回退**：若 PDF 公式太复杂，Step 2 实施**简化版**——"在多个 α 候选上 resample + HFM 相关，取 peak 最大的 α"（本质上是 α 搜索，不如论文的 1D 速度谱巧妙但可工作）。

## Step 2: estimator 实现（2h）

### 文件：`modules/10_DopplerProc/src/Matlab/est_alpha_dual_hfm_vss.m`

### 两级扫描架构

```matlab
function [alpha, diag] = est_alpha_dual_hfm_vss(bb_raw, HFM_up, HFM_dn, fs, fc, k_hfm, search_cfg)

%% 1. 粗扫
v_coarse = search_cfg.v_range(1) : search_cfg.dv_coarse : search_cfg.v_range(2);
F_coarse = zeros(size(v_coarse));
for vi = 1:length(v_coarse)
    F_coarse(vi) = speed_spectrum_value(bb_raw, HFM_up, HFM_dn, v_coarse(vi), fs, fc, k_hfm);
end
[~, i_peak] = max(abs(F_coarse));
v_coarse_est = v_coarse(i_peak);

%% 2. 精扫（以粗估为中心 ±3·dv_coarse）
v_fine_range = v_coarse_est + (-3*search_cfg.dv_coarse : search_cfg.dv_fine : 3*search_cfg.dv_coarse);
F_fine = zeros(size(v_fine_range));
for vi = 1:length(v_fine_range)
    F_fine(vi) = speed_spectrum_value(bb_raw, HFM_up, HFM_dn, v_fine_range(vi), fs, fc, k_hfm);
end
[~, i_fine] = max(abs(F_fine));

% 抛物线三点插值
v_est = parabolic_refine(v_fine_range, abs(F_fine), i_fine);

alpha = v_est / search_cfg.c_sound;

%% 3. 诊断
diag.v_est     = v_est;
diag.F_coarse  = F_coarse;
diag.F_fine    = F_fine;
diag.v_coarse_grid = v_coarse;
diag.v_fine_grid   = v_fine_range;
diag.peak_psr      = peak_to_sidelobe(abs(F_fine), i_fine);
diag.scan_time_s   = toc;
end

function F = speed_spectrum_value(bb_raw, HFM_up, HFM_dn, v, fs, fc, k_hfm)
% 按 wei-2020 公式计算 F(v)
% 临时简化版（Step 1 若公式复杂时用）：
%   α = v/c; bb_k = resample(bb_raw, α); F = |HFM_up_corr(bb_k)| × |HFM_dn_corr(bb_k)|
c = 1500;
alpha = v / c;
bb_k = comp_resample_spline(bb_raw, alpha, fs, 'fast');
mf_up = conj(fliplr(HFM_up(:).'));
mf_dn = conj(fliplr(HFM_dn(:).'));
peak_up = max(abs(filter(mf_up, 1, bb_k)));
peak_dn = max(abs(filter(mf_dn, 1, bb_k)));
F = peak_up * peak_dn;  % 简化：两 peak 乘积，正确 v 下两者同时最大
end
```

### 关键实现点

- **速度而非 α 为扫描变量**：精度更直观（m/s），1D 扫描
- **对称设计**：`v_range` 对称，F(v) 对 ±v 处理一致，避免 α<0 不对称
- **抛物线插值**：精扫取峰后做三点拟合，子样本精度
- **PSR 诊断**：peak_to_sidelobe 作质量指标（低 → VSS 失败 → fallback）

## Step 3: 单元测试（1h）

### 文件：`modules/10_DopplerProc/src/Matlab/test_est_alpha_dual_hfm_vss.m`

仿照 `test_est_alpha_dual_chirp.m` 结构：

```matlab
alpha_list = [0, 1e-3, -1e-3, 1e-2, -1e-2, 3e-2, -3e-2, 5e-2, -5e-2, 7e-2, -7e-2];
snr_db = 10;

% 生成 HFM+/HFM- 帧（与 SC-FDE runner 一致的 phase_hfm / phase_hfm_neg）
% 用 interp1 + CFO 注入 物理模型 rx_bb
% 每 α 跑 VSS，记 α_est, rel_err, scan_time

% 验收：
% |α|≤3e-2  rel_err < 3%
% |α|=5e-2  rel_err < 5%
% |α|=7e-2  仅记录
% 对称：|est(+v) - (-est(-v))| / v < 10%
```

## Step 4: SC-FDE runner 集成（1h）

### `tests/SC-FDE/test_scfde_timevarying.m`

在 parent spec 的迭代 refinement 后（现 `for iter_a = 1:bench_alpha_iter ... end` 循环后）追加：

```matlab
% 【2026-04-21】HFM 速度谱精估（大 α 专用，默认启用）
if ~exist('bench_enable_vss','var') || isempty(bench_enable_vss)
    bench_enable_vss = true;
end
if bench_enable_vss && abs(alpha_lfm) > 1e-2
    cfg_vss = struct('v_range', [-112, 112], 'dv_coarse', 0.5, 'dv_fine', 0.02, ...
                     'c_sound', 1500, ...
                     'hfm_up_search', [1, 2*N_preamble], ...
                     'hfm_dn_search', [N_preamble+guard_samp+1, 3*N_preamble+guard_samp]);
    k_hfm_struct = struct('f_0', f_lo, 'f_1', f_hi, 'T', preamble_dur);
    [alpha_vss, vss_diag] = est_alpha_dual_hfm_vss(bb_raw, HFM_bb_n, HFM_bb_neg_n, ...
                                                    fs, fc, k_hfm_struct, cfg_vss);
    if vss_diag.peak_psr > 3  % 质量检查
        alpha_lfm = alpha_vss;
    end
end
```

同步改 `test_scfde_discrete_doppler.m`。

### 不改现有 LFM 迭代

保留 parent spec 的双 LFM + 迭代，VSS 只在 \|α\|>1e-2 分支接管。

## Step 5: 回归 + 扩展测试点（1h）

### 扩展 D stage

```matlab
% bench_grids.m 修改：
grids.D.doppler_rate_list = [0, 1e-4, -1e-4, 5e-4, -5e-4, 1e-3, -1e-3, ...
                              3e-3, -3e-3, 1e-2, -1e-2, 3e-2, -3e-2, ...
                              5e-2, -5e-2, 7e-2, -7e-2];  % 17 点（原 13 + 4）
```

### 跑回归

```matlab
% SC-FDE with VSS (默认启用)
benchmark_e2e_baseline('D', 'schemes', {'SC-FDE'});

% SC-FDE without VSS (对比)
bench_enable_vss = false;
benchmark_e2e_baseline('D', 'schemes', {'SC-FDE'});

% A2 / A1 回归（确保 |α|≤1e-2 不退化）
benchmark_e2e_baseline('A2', 'schemes', {'SC-FDE'});
benchmark_e2e_baseline('A1', 'schemes', {'SC-FDE'});
```

### 对称性图

新 PNG：`figures/D_alpha_symmetry_after_vss.png`
- x = |α_true|, y = |α_est(+v) + α_est(-v)| / |v|
- 理想 0（完全对称）

## Step 6: wiki + todo + commit（0.5h）

### 新 wiki

`wiki/modules/10_DopplerProc/HFM速度谱α估计器.md`：
- 原理（wei-2020 引用）
- 接口 + 实现细节
- before/after 对比数据表
- 对称性图
- 与 `双LFM-α估计器` 的分工（\|α\|≤1e-2 LFM，\|α\|>1e-2 VSS）

### 更新

- `wiki/conclusions.md` +1 条（VSS 突破 3e-2 物理极限）
- `wiki/log.md` 2026-04-21 条目
- `wiki/index.md` +1 页面
- `todo.md`：
  - `🟡 α=3e-2 物理极限突破` → 🟢 完成
  - `🟡 α<0 不对称修复` → 视 VSS 对称性结果，可能完成或重新分类

### Commit

1. `feat(10_DopplerProc): est_alpha_dual_hfm_vss 速度谱扫描 α 估计器`
2. `feat(13_SourceCode/SC-FDE): VSS 精估后端集成 (|α|>1e-2 接管)`
3. `docs(specs+plans+wiki+todo): HFM 速度谱突破 3e-2`

## 开放问题（实施中决议）

1. **F(v) 简化版若 Step 1 公式复杂**：用两个 peak 的乘积 / 和作为简化 F(v)；质量要求稍低但实现简单
2. **PSR 阈值**：多少算"VSS 失败"？初值 3.0（经验），实施中根据测试数据调
3. **扫描范围**：±112 m/s 足够？实际水声工况 ≤30 m/s，保留一倍余量就够
4. **粗扫步长 Δv**：0.5 m/s 对应 α=3.3e-4，够粗吗？太细浪费算力

## 回滚策略

若 Step 5 发现 \|α\|>1e-2 下 VSS 未提升（甚至退化）：

1. 关闭 `bench_enable_vss`（runner 层 toggle 保留）
2. 调查 F(v) 实现是否正确（对比 wei-2020 附录）
3. 调整 PSR 阈值、扫描步长
4. 极端：简化 F(v) 用"最大 HFM 相关"替代论文公式
