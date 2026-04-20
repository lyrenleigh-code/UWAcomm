---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-20-alpha-estimator-dual-chirp-refinement.md
created: 2026-04-20
updated: 2026-04-20
tags: [多普勒, α估计, 双LFM, 10_DopplerProc, 13_SourceCode]
---

# α 估计器改造：双 LFM 时延差法 — 实施计划

## 架构位置

```
modules/10_DopplerProc/src/Matlab/
├── est_alpha_dual_chirp.m       # 新：核心 estimator
└── test_est_alpha_dual_chirp.m  # 新：单元测试

modules/13_SourceCode/src/Matlab/tests/SC-FDE/
├── test_scfde_timevarying.m       # 改：帧+estimator 切换
└── test_scfde_discrete_doppler.m  # 改：同步

modules/13_SourceCode/src/Matlab/tests/bench_results/
└── e2e_baseline_D_before.csv   # 已有（本次诊断）
└── e2e_baseline_D_after.csv    # 新：改造后回归数据

wiki/modules/10_DopplerProc/
└── 双LFM-α估计器.md              # 新：算法文档
```

## 步骤

### Step 1：`est_alpha_dual_chirp.m`（2h）

**代码骨架**：

```matlab
function [alpha, diag] = est_alpha_dual_chirp(bb_raw, LFM_up, LFM_dn, fs, fc, k, search_cfg)
% 功能：双 LFM（up+down chirp）时延差法估 α
% 版本：V1.0.0（2026-04-20）

%% 1. 入参校验
assert(isvector(bb_raw), 'bb_raw 必须是向量');
assert(k > 0, 'k 必须正值（up-chirp 斜率）');
assert(isfield(search_cfg, 'up_start') && isfield(search_cfg, 'dn_start'), ...
    'search_cfg 必须含 up_start/up_end/dn_start/dn_end/nominal_delta_samples');

%% 2. 匹配滤波模板（conj+fliplr）
mf_up = conj(fliplr(LFM_up));
mf_dn = conj(fliplr(LFM_dn));

%% 3. 双 chirp 匹配滤波
corr_up = filter(mf_up, 1, bb_raw);
corr_dn = filter(mf_dn, 1, bb_raw);

%% 4. 各自搜索窗内找 peak
up_win = search_cfg.up_start:min(search_cfg.up_end, length(corr_up));
dn_win = search_cfg.dn_start:min(search_cfg.dn_end, length(corr_dn));
[peak_up, up_rel] = max(abs(corr_up(up_win)));
[peak_dn, dn_rel] = max(abs(corr_dn(dn_win)));
tau_up = search_cfg.up_start + up_rel - 1;
tau_dn = search_cfg.dn_start + dn_rel - 1;

%% 5. α 估计（核心公式）
%   α = k·(Δτ_obs - Δτ_nom) / (f_lo + f_hi)
%   其中 f_lo + f_hi ≈ 2·fc（窄带近似）
dtau_samples_obs = tau_dn - tau_up;
dtau_samples_nom = search_cfg.nominal_delta_samples;
dtau_residual = (dtau_samples_obs - dtau_samples_nom) / fs;  % 秒
alpha = k * dtau_residual / (2 * fc);

%% 6. 子样本精度（可选）：峰值 parabolic 插值
if nargout > 1 || isfield(search_cfg, 'use_subsample') && search_cfg.use_subsample
    % 抛物线插值（峰两侧各取一点）
    alpha = alpha + k * (parabolic_offset(corr_up, tau_up) - ...
                          parabolic_offset(corr_dn, tau_dn)) / (2*fc*fs);
end

%% 7. 诊断输出
diag.tau_up = tau_up;
diag.tau_dn = tau_dn;
diag.peak_up = peak_up;
diag.peak_dn = peak_dn;
diag.dtau_samples = dtau_samples_obs;
diag.dtau_residual = dtau_residual;

end

function off = parabolic_offset(corr, peak_idx)
% 抛物线峰值插值，返回子样本偏移
if peak_idx <= 1 || peak_idx >= length(corr)
    off = 0; return;
end
y0 = abs(corr(peak_idx-1));
y1 = abs(corr(peak_idx));
y2 = abs(corr(peak_idx+1));
denom = 2*(y0 - 2*y1 + y2);
if abs(denom) < eps, off = 0;
else, off = (y0 - y2) / denom;
end
end
```

**单元测试** `test_est_alpha_dual_chirp.m`：

```matlab
% 场景：纯 AWGN 无多径；α 扫描；assert |err|/|α|<5%
fs = 48000; fc = 12000; T_pre = 0.03; B = 8000;
t = (0:round(T_pre*fs)-1)/fs;
LFM_up = exp(1j*2*pi*(0      + 0.5*B/T_pre*t).*t);
LFM_dn = exp(1j*2*pi*((B+0)  - 0.5*B/T_pre*t).*t);  % f: B→0
k = B/T_pre;

alpha_list = [0, 1e-4, 5e-4, 1e-3, 3e-3, 1e-2];
snr_db = 10;

for ai = 1:numel(alpha_list)
    alpha_true = alpha_list(ai);
    % 生成受 α 影响的 RX 信号：时间伸缩 t→(1+α)t
    frame = [LFM_up, zeros(1,1000), LFM_dn, zeros(1,1000)];
    t_new = (0:length(frame)-1)/fs * (1+alpha_true);
    rx = interp1(0:length(frame)-1, frame, t_new*fs, 'spline', 0);
    rx_noisy = rx + sqrt(10^(-snr_db/10))*(randn(size(rx))+1j*randn(size(rx)))/sqrt(2);
    % 估计
    cfg.up_start = 1; cfg.up_end = 2000;
    cfg.dn_start = 2001; cfg.dn_end = 4000;
    cfg.nominal_delta_samples = length(LFM_up) + 1000;
    [alpha_est, diag_out] = est_alpha_dual_chirp(rx_noisy, LFM_up, LFM_dn, fs, fc, k, cfg);
    fprintf('α=%+.2e → est=%+.2e, err=%.2e\n', alpha_true, alpha_est, abs(alpha_est-alpha_true));
    if alpha_true ~= 0
        assert(abs(alpha_est-alpha_true)/abs(alpha_true) < 0.05, ...
               'α=%.2e 相对误差 > 5%%', alpha_true);
    end
end
```

### Step 2：SC-FDE 帧改造 + estimator 切换（1.5h）

**改动点清单**（`test_scfde_timevarying.m`）：

1. **行 64-71 HFM- 保留**（继续做帧检测），**行 72-76 新增 down-LFM**：
   ```matlab
   % LFM- 基带版本（down-chirp，f_hi → f_lo，α估计用）
   chirp_rate_lfm = (f_hi - f_lo) / preamble_dur;
   phase_lfm_neg = 2*pi * (f_hi * t_pre - 0.5 * chirp_rate_lfm * t_pre.^2);
   LFM_bb_neg = exp(1j*(phase_lfm_neg - 2*pi*fc*t_pre));
   ```
2. **行 77 guard_samp 扩展**：
   ```matlab
   alpha_max_design = 3e-2;
   guard_samp = max(sym_delays) * sps + 80 + ceil(alpha_max_design * max(N_preamble, N_lfm));
   ```
3. **行 157-162 功率归一化 + 帧组装**：
   ```matlab
   LFM_bb_neg_n = LFM_bb_neg * lfm_scale;
   frame_bb = [HFM_bb_n, zeros(1,guard_samp), HFM_bb_neg_n, zeros(1,guard_samp), ...
               LFM_bb_n, zeros(1,guard_samp), LFM_bb_neg_n, zeros(1,guard_samp), shaped_bb];
   ```
4. **行 195-210 RX α 估计替换**：
   ```matlab
   addpath(fullfile(proj_root, 'modules','10_DopplerProc','src','Matlab'));
   mf_lfm = conj(fliplr(LFM_bb_n));
   mf_lfm_neg = conj(fliplr(LFM_bb_neg_n));

   % 新 API
   cfg = struct();
   cfg.up_start = 2*N_preamble + 2*guard_samp + 1;
   cfg.up_end   = cfg.up_start + N_lfm + guard_samp;
   cfg.dn_start = cfg.up_end + 1;
   cfg.dn_end   = cfg.dn_start + N_lfm + guard_samp;
   cfg.nominal_delta_samples = N_lfm + guard_samp;
   k_lfm = (f_hi - f_lo) / preamble_dur;
   [alpha_lfm, alpha_diag] = est_alpha_dual_chirp(bb_raw, LFM_bb_n, LFM_bb_neg_n, ...
                                                   fs, fc, k_lfm, cfg);

   % 保留 R1 作为精定时用（只用 up-LFM 的峰位）
   R1 = alpha_diag.peak_up;
   sync_peak = abs(R1) / sum(abs(LFM_bb_n).^2);
   ```
5. **行 213-242 保留 CP 精估链路不动**（`alpha_cp` 仍然有效）：
   ```matlab
   alpha_est = alpha_lfm + alpha_cp;  % 两级合成
   ```
6. **行 252-255 LFM2 定时基准**：原本 `[~, lfm2_local] = max(corr_lfm_comp)`
   现在 LFM2 是 down-chirp，改用 LFM+ peak（tau_up）作为主定时基准，
   LFM2 peak 仅作 α 估计不参与定时。

**`test_scfde_discrete_doppler.m` 同步改**：相同改动块。

### Step 3：回归（1h）

跑以下三组并对比：

```matlab
% 1. D stage α 扫描
benchmark_e2e_baseline('D', 'schemes', {'SC-FDE'});
% 对比 bench_results/e2e_baseline_D.csv before vs after

% 2. A2 stage 固定 α 扫描
benchmark_e2e_baseline('A2', 'schemes', {'SC-FDE'});
% 关注 α=[5e-4, 1e-3, 2e-3] × SNR=[10,15,20] 格点 BER

% 3. A1 stage Jakes 扫描（α=0 路径）
benchmark_e2e_baseline('A1', 'schemes', {'SC-FDE'});
% 关注 fd=0 基线未退化；fd>0 时变（独立于本 spec）

% 4. 可视化
plot_constant_doppler_sweep();   % D 图
% A1/A2 图由 bench_plot_all 生成 + 手工合并 before/after 对比
```

### Step 4：wiki 归档（0.5h）

**新文件** `wiki/modules/10_DopplerProc/双LFM-α估计器.md`：

```markdown
---
type: concept
created: 2026-04-20
updated: 2026-04-20
tags: [多普勒, α估计, 双LFM, estimator, 10_DopplerProc]
---

# 双 LFM（up+down chirp）α 估计器

> spec: [[specs/active/2026-04-20-alpha-estimator-dual-chirp-refinement]]
> 代码：`modules/10_DopplerProc/src/Matlab/est_alpha_dual_chirp.m`
> 关联：[[恒定多普勒隔离测试]]、[[conclusions#α估计]]

## 原理
[数学推导 + peak 漂移图]

## 接口
[摘 spec]

## 性能
[D/A2 before/after 对比表 + 4 图]

## 回归
[A1 fd=0 基线不退化证明]
```

**更新**：
- `wiki/index.md` +1 页面
- `wiki/log.md` +1 条
- `wiki/conclusions.md` +1 条（"双 LFM 时延差激活后 SC-FDE 在 α≤X 可工作"）
- `wiki/comparisons/e2e-timevarying-baseline.md` 相关章节补注脚

### Step 5：spec 归档 + commit

- `specs/active/2026-04-19-constant-doppler-isolation.md` → `specs/archive/`（诊断已完成）
- `specs/active/2026-04-20-alpha-estimator-dual-chirp-refinement.md` → `specs/archive/`
- commit 分三个原子提交：
  1. `feat(10_DopplerProc): est_alpha_dual_chirp 双 LFM 时延差 α 估计器`
  2. `feat(13_SourceCode/SC-FDE): 帧结构改 LFM2→down-chirp + α estimator 切换`
  3. `docs(wiki): 双 LFM α estimator + constant-doppler 诊断 + refinement 报告`

## 开放问题（实施中决议）

1. **子样本精度插值是否开启**：默认开，Step 3 回归时对比开/关差异
2. **α=3e-2 极限 peak 搜索窗**：Step 2 实测若漂出窗，扩到 2·guard_samp
3. **search_cfg nominal_delta_samples 精度**：理论值 = N_lfm+guard_samp，但考虑 HFM 帧检测误差需加余量 ±10 样本

## 回滚策略

Step 2 SC-FDE 切换后若 A1 α=0 路径 BER 退化（帧定时被破坏），回滚顺序：
1. 先回退 estimator 入口（alpha_est=0），验证帧定时本身没坏
2. 若帧定时坏 → 回退帧结构（LFM2 改回 up-chirp）
3. 若帧定时没坏但 α 估出错 → Step 1 estimator 本身有 bug，单元测试加强
