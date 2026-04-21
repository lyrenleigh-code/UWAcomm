---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-22-dsss-symbol-doppler-tracking.md
created: 2026-04-22
updated: 2026-04-22
tags: [DSSS, Doppler跟踪, 符号级, Sun2020]
---

# DSSS 符号级 Doppler 跟踪 — 实施计划

## Step 1: Sun-2020 PDF 细节 + 设计（0.5h）

读 `raw/papers/A_Symbol-Based_Passband_Doppler_Tracking_and_Compensation_Algorithm_for_Underwater_Acoustic_DSSS_Communications.pdf`：
1. **Eq. (k-1, k) 的精确形式** — 相邻峰时差如何推导 α
2. **余弦内插公式** — 3 点 peak 邻拟合
3. **自适应参考** — dopplerized Gold31 生成方式（Phase 2 保留）
4. **α 平滑滤波** — 参考论文的 β 值

输出：补充 wiki summary 的附录；确定 Phase 1 最终算法。

**回退**：若公式细节不清，用简化版：
- 相邻峰时差纯线性公式
- 抛物线插值替代余弦（已有 SC-FDE 模板）

## Step 2: `est_alpha_dsss_symbol.m` 实现（2h）

### 文件：`modules/10_DopplerProc/src/Matlab/est_alpha_dsss_symbol.m`

### 骨架

```matlab
function [alpha_track, alpha_block, diag] = est_alpha_dsss_symbol(bb_raw, gold_ref, sps, fs, fc, frame_cfg, track_cfg)

T_sym_samples = length(gold_ref) * sps;  % Gold31 * sps = 31*8 = 248 samples
n_sym = frame_cfg.n_symbols;
alpha_center = track_cfg.alpha_block;  % 先验中心
search_radius = ceil(track_cfg.alpha_max * T_sym_samples * 2);  % 搜索半径（样本）

%% 1. 匹配滤波（Gold31 模板）
mf_gold = conj(fliplr(gold_ref));
% upsample gold_ref 到 sample rate
mf_gold_up = zeros(1, length(gold_ref) * sps);
for k = 1:length(gold_ref), mf_gold_up((k-1)*sps+1:k*sps) = gold_ref(k); end
mf = conj(fliplr(mf_gold_up));

%% 2. 初始预期 peak 位置（假设 α_center 补偿后）
tau_expected = frame_cfg.data_start_samples + (0:n_sym-1) * T_sym_samples;

%% 3. 逐符号 peak 搜索 + 余弦内插
tau_peaks = zeros(1, n_sym);
for k = 1:n_sym
    % 搜索窗
    win_lo = max(1, round(tau_expected(k) - search_radius));
    win_hi = min(length(bb_raw), round(tau_expected(k) + search_radius));
    corr_seg = filter(mf, 1, bb_raw(win_lo:win_hi));
    [peak_val, peak_rel] = max(abs(corr_seg));
    peak_idx = win_lo + peak_rel - 1;

    % 余弦内插
    if track_cfg.use_subsample && peak_rel > 1 && peak_rel < length(corr_seg)
        y_m1 = abs(corr_seg(peak_rel - 1));
        y_0  = abs(corr_seg(peak_rel));
        y_p1 = abs(corr_seg(peak_rel + 1));
        % 余弦模型解析 sub-sample 偏移
        num = y_m1 - y_p1;
        den = 2 * (2*y_0 - y_m1 - y_p1);
        if abs(den) > eps
            delta = num / den;
            delta = max(-0.5, min(0.5, delta));
            peak_idx = peak_idx + delta;
        end
    end
    tau_peaks(k) = peak_idx;
end

%% 4. 符号间 α 估计
alpha_raw = zeros(1, n_sym - 1);
for k = 1:n_sym-1
    dtau = tau_peaks(k+1) - tau_peaks(k);  % samples
    alpha_raw(k) = (dtau - T_sym_samples) / T_sym_samples;
end

%% 5. IIR 平滑
beta = track_cfg.iir_beta;  % 默认 0.7
alpha_track = zeros(1, n_sym);
alpha_track(1) = alpha_center;  % IIR 初值
for k = 1:n_sym-1
    alpha_track(k+1) = beta * alpha_track(k) + (1-beta) * alpha_raw(k);
end

%% 6. 总 α 平均（用于 resample）
alpha_block = mean(alpha_track);

%% 7. 诊断
diag.tau_peaks = tau_peaks;
diag.alpha_raw = alpha_raw;
diag.peak_snr  = peak_val / median(abs(corr_seg));  % 最后一个作样本

end
```

### 关键实现细节

- **upsampling Gold31**：gold_ref (31 chips) 展开到 248 samples（每 chip 占 sps 样本）
- **搜索窗**：基于 α_center 预测 + 扩展半径
- **余弦内插**：论文用 `atan2(y_-1 - y_+1, 2y_0 - y_-1 - y_+1) / ω`，我简化为线性近似
- **低 SNR 回退**：若 peak_snr < 阈值（如 3），alpha_track 用 alpha_center

## Step 3: 单元测试（1h）

### 文件：`modules/10_DopplerProc/src/Matlab/test_est_alpha_dsss_symbol.m`

```matlab
% 场景 A: 固定 α (AWGN 纯噪声)
alpha_list = [0, 1e-4, 1e-3, 3e-3, 1e-2, 3e-2];
snr_db = 10;

for ai = 1:numel(alpha_list)
    alpha_true = alpha_list(ai);
    % 生成 DSSS 帧（Gold31 × 100 symbol + 训练）
    [frame, gold_ref] = make_dsss_test_frame(100, 10);  % 100 data + 10 train
    % 物理模型 α 注入
    n_orig = 0:length(frame)-1;
    frame_alpha = interp1(n_orig, frame, n_orig*(1+alpha_true), 'spline', 0);
    t_cfo = n_orig / fs;
    frame_alpha = frame_alpha .* exp(1j * 2*pi * fc * alpha_true * t_cfo);
    % AWGN
    rx = frame_alpha + noise @ 10dB;

    % 跑 estimator
    [alpha_track, alpha_block, diag] = est_alpha_dsss_symbol(rx, gold_ref, 8, fs, fc, ...
        frame_cfg, track_cfg);

    rel_err = abs(alpha_block - alpha_true) / max(abs(alpha_true), 1e-6);
    assert(rel_err < 0.01, sprintf('α=%.1e rel_err=%.3f', alpha_true, rel_err));
end

% 场景 B: 线性漂移
alpha_t = linspace(0, 3e-3, 100);  % 沿符号线性漂移
% 生成随符号漂移的 rx
% 验证 alpha_track RMSE < 5e-4
```

## Step 4: DSSS runner 集成（1.5h）

### 改动 `modules/13_SourceCode/src/Matlab/tests/DSSS/test_dsss_timevarying.m`

#### 顶部 mode 开关

```matlab
% 2026-04-22 新增
if ~exist('doppler_track_mode','var') || isempty(doppler_track_mode)
    doppler_track_mode = 'block';   % 默认块估计（向后兼容）
end
```

#### 在 α estimator 之后（现有 P4 patches 后）插入

```matlab
alpha_est_block = alpha_est;   % 保留块估计作 symbol mode 的先验

if strcmpi(doppler_track_mode, 'symbol')
    frame_cfg = struct('data_start_samples', ds, ...
                       'n_symbols', N_data_sym / spread_len, ...
                       'n_train', train_len / spread_len);
    track_cfg = struct('alpha_block', alpha_est_block, ...
                       'alpha_max', 3e-2, ...
                       'iir_beta', 0.7, ...
                       'use_subsample', true);
    [alpha_track, alpha_sym_avg, symbol_diag] = est_alpha_dsss_symbol(...
        bb_clean, gold_ref, sps, fs, fc, frame_cfg, track_cfg);
    % 用平均值做 resample（或逐符号 resample，需更深改造）
    alpha_est = alpha_sym_avg;
    % TODO: 未来用 alpha_track 做符号级 resample
end
```

### 切换回归跑法

```matlab
% block 模式（默认）
benchmark_e2e_baseline('A2', 'schemes', {'DSSS'});
benchmark_e2e_baseline('D', 'schemes', {'DSSS'});

% symbol 模式
doppler_track_mode = 'symbol';
benchmark_e2e_baseline('A2', 'schemes', {'DSSS'});
benchmark_e2e_baseline('D', 'schemes', {'DSSS'});
```

比较两组 CSV。

## Step 5: 分析 + 参数调优（0.5h）

可能调优：
- `alpha_max` 搜索半径（小则慢，大则噪声多）
- `iir_beta`（0.5 ~ 0.9）
- 最低 peak_snr 阈值

## Step 6: wiki + todo + commit（0.5h）

### wiki 新页

`wiki/modules/10_DopplerProc/DSSS符号级Doppler跟踪.md`：
- 原理（Sun-2020 引用）
- 接口 + 实现
- before/after D 表
- α_track 曲线图（符号级瞬时 α）

### commit

1. `feat(10_DopplerProc): est_alpha_dsss_symbol Sun-2020 符号级跟踪`
2. `feat(13_SourceCode/DSSS): symbol mode 集成 + A2/D 回归`
3. `docs(wiki+todo): DSSS 符号级跟踪突破 α=1e-2`

## 开放问题（实施中决议）

1. **是否逐符号 resample 而非均值**：若 α 动态漂移，逐符号 resample 精度更高但实现复杂
   - Phase 1 用均值；Phase 2 可选逐符号
2. **低 SNR 回退阈值**：peak_snr < 3 还是 < 2？
3. **IIR 初值**：用 alpha_block 初值，还是等前 5 个符号估出再开启滤波？
4. **Gold31 与 Gold 族其他成员切换**：暂不涉及

## 回滚策略

若 symbol 模式 BER 比 block 退化（α<1e-2 下）：
- 自动 fallback：当 alpha_sym_avg 与 alpha_block 差异 > 20%，用 alpha_block
- 或 runtime 配置 `doppler_track_mode='block'` 完全跳过新代码
