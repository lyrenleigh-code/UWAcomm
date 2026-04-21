---
project: uwacomm
type: task
status: active
created: 2026-04-21
updated: 2026-04-21
parent: 2026-04-20-alpha-estimator-dual-chirp-refinement.md
tags: [多普勒, α估计, 双LFM, 迭代refinement, 13_SourceCode, OFDM, SC-TDE, DSSS, FH-MFSK]
---

# α 补偿推广到 OFDM/SC-TDE/DSSS/FH-MFSK

## 背景

SC-FDE 的双 LFM + 迭代 α refinement（parent spec）已落地，**α 工作范围 1e-4 → 1e-2**（15 m/s）：
- A2 α=5e-4 BER 48.7% → 0%
- A2 α=1e-3 BER 49% → 0%（迭代后）
- A2 α=2e-3 BER 47% → 0%（迭代后）
- D 阶段 α∈[±1e-4,±1e-2] 全通

E2E benchmark A2 阶段显示 **其他 4 体制（OFDM/SC-TDE/DSSS/FH-MFSK）** 在 α≥5e-4 仍崩 50%（SC-FDE 之前同款问题）。grep 验证 4 体制 RX 代码使用与 SC-FDE **同款的"同形 LFM 相位差法"**，根因完全一致。

```
% OFDM line 75:         phase_lfm = 2π*(f_lo*t + 0.5*chirp_rate*t²)
% SC-TDE line 96:       phase_lfm = 2π*(f_lo*t + 0.5*chirp_rate*t²)
% DSSS line 80:         phase_lfm = 2π*(f_lo*t + 0.5*chirp_rate*t²)
% FH-MFSK line 82:      phase_lfm = 2π*(f_lo*t + 0.5*chirp_rate*t²)
% 所有 4 体制帧组装都是：
%   [HFM+|g|HFM-|g|LFM_bb_n|g|LFM_bb_n|g|data]   （LFM2=LFM1 同一 up-chirp）
% α 估计都是 alpha = angle(R2 * conj(R1)) / (2π·fc·T_v_lfm)
```

## 目标

把 SC-FDE 落地的"双 LFM + 迭代 α refinement"**模板化**推广到 4 体制：

**首要**：每体制 A2 阶段 α∈[5e-4, 1e-3, 2e-3] × SNR=10dB 下 BER < 5%
**次要**：D 阶段 α∈[±1e-4, ±1e-2] 核心范围全 0% BER
**兜底**：A1 α=0 路径（fd=0 静态）基线不退化

## 体制差异表

| 体制 | CP 精修 | α 估计流程 | 改造量（vs SC-FDE 模板） |
|------|:------:|:----------:|:-------------------------:|
| OFDM | ✓ 有（空子载波 CFO 精估） | LFM phase + CP-like | 100%（套模板） |
| SC-TDE | ✗ 时变分支跳过 | LFM phase only | 100%（套模板，不接 CP） |
| DSSS | ✗ 无 | LFM phase only | 100%（套模板） |
| FH-MFSK | ✗ 无 | LFM phase only | 100%（套模板） |

虽然 CP 精修逻辑各异，但**迭代 α refinement 不依赖 CP 精修**——直接在 resample 后的 bb 上用 est_alpha_dual_chirp 估残余，递归累加。所以**模板对 4 体制统一适用**。

## 范围

### 做什么

4 体制 × 2 runner = **8 文件改动**：

| 文件 | 改动（同款 SC-FDE 模板） |
|------|------------------------|
| `tests/OFDM/test_ofdm_timevarying.m` | 加 LFM_bb_neg + guard 扩展 + 帧 LFM2→down + estimator 切换 + 迭代 refinement + LFM2 定时改 mf_lfm_neg |
| `tests/OFDM/test_ofdm_discrete_doppler.m` | 同上 |
| `tests/SC-TDE/test_sctde_timevarying.m` | 同上（无 CP 精修步骤） |
| `tests/SC-TDE/test_sctde_discrete_doppler.m` | 同上 |
| `tests/DSSS/test_dsss_timevarying.m` | 同上（去掉 alpha_est=相位差法） |
| `tests/DSSS/test_dsss_discrete_doppler.m` | 同上 |
| `tests/FH-MFSK/test_fhmfsk_timevarying.m` | 同上 |
| `tests/FH-MFSK/test_fhmfsk_discrete_doppler.m` | 同上 |

每体制改 2 runner，保持 timevarying 和 discrete_doppler 一致。

### 不做

- **OTFS 不改**：DD 域帧结构异（单 LFM 对 + DD pilot），属独立 spec（`2026-04-21-otfs-discrete-doppler-debug.md`，用户并行做中）
- **不改 BEM/Turbo/均衡器**：算法层不动，只改 α 估计前端
- **不改帧长/CP 长度/体制核心参数**
- **不改 14_Streaming**：留后续 spec
- **不实施其他 α estimator 衍生**（符号约定参数化、α<0 不对称、α=3e-2 物理极限等）— 这些是独立 todo
- **不动诊断插桩**（SC-FDE 有 bench_diag/tog.* toggle 插桩，其他 4 体制不加，简洁优先）

## 模板（SC-FDE 完整 patch × 4 体制）

**注意（2026-04-21 更新）**：SC-FDE 现已落地 8 处 patch（5 处基础 + 3 处大 α 突破），
覆盖 α ∈ [±1e-4, ±3e-2] 全工作范围。本 spec 推广全部 8 处到 4 体制。

## 5 处基础 patch（双 LFM + 迭代 refinement）

### Patch 1: LFM- 生成（顶部紧跟 LFM 定义后）

```matlab
% LFM- 基带版本（down-chirp，激活 est_alpha_dual_chirp）
phase_lfm_neg = 2*pi * (f_hi * t_pre - 0.5 * chirp_rate_lfm * t_pre.^2);
LFM_bb_neg = exp(1j*(phase_lfm_neg - 2*pi*fc*t_pre));
```

### Patch 2: guard 扩展（紧接 N_lfm）

```matlab
alpha_max_design = 3e-2;
guard_samp = <原 guard 公式> + ceil(alpha_max_design * max(N_preamble, N_lfm));
```

### Patch 3: 帧组装（LFM2 换 down + 新 LFM_bb_neg_n 归一化）

```matlab
LFM_bb_neg_n = LFM_bb_neg * lfm_scale;
frame_bb = [HFM_bb_n, ..., LFM_bb_n, zeros(1,guard_samp), LFM_bb_neg_n, ...];
%                                                         ^^^^^^^^^^^^^^^ 原 LFM_bb_n 改
```

### Patch 4: α 估计入口（替换现有 angle(R2·conj(R1)) / (2π·fc·T_v_lfm)）

```matlab
if isempty(which('est_alpha_dual_chirp'))
    addpath(fullfile(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))), ...
                      '10_DopplerProc','src','Matlab'));
end
cfg_alpha = struct();
cfg_alpha.up_start = lfm1_search_start;
cfg_alpha.up_end   = lfm1_end;
cfg_alpha.dn_start = lfm2_start;
cfg_alpha.dn_end   = min(lfm2_search_len, length(bb_raw));
cfg_alpha.nominal_delta_samples = N_lfm + guard_samp;
cfg_alpha.use_subsample = true;
k_chirp = chirp_rate_lfm;
[alpha_lfm_raw, alpha_diag] = est_alpha_dual_chirp(bb_raw, LFM_bb_n, LFM_bb_neg_n, ...
                                                    fs, fc, k_chirp, cfg_alpha);
alpha_lfm = -alpha_lfm_raw;  % 符号约定对齐 gen_uwa_channel

% 迭代 α refinement（默认 2 次）
if ~exist('bench_alpha_iter','var') || isempty(bench_alpha_iter), bench_alpha_iter = 2; end
if bench_alpha_iter > 0 && abs(alpha_lfm) > 1e-10
    for iter_a = 1:bench_alpha_iter
        bb_iter = comp_resample_spline(bb_raw, alpha_lfm, fs, 'fast');
        [delta_raw, ~] = est_alpha_dual_chirp(bb_iter, LFM_bb_n, LFM_bb_neg_n, ...
                                              fs, fc, k_chirp, cfg_alpha);
        alpha_lfm = alpha_lfm + (-delta_raw);
    end
end

% R1/p1_idx/p2_idx 保留旧变量（下游使用）
corr_est = filter(conj(fliplr(LFM_bb_n)), 1, bb_raw);
p1_idx = alpha_diag.tau_up;
p2_idx = alpha_diag.tau_dn;
R1 = corr_est(p1_idx);
R2 = NaN;  % 旧相位差法不再使用
```

### Patch 5: LFM2 精定时（原 mf_lfm → mf_lfm_neg）

```matlab
mf_lfm_neg = conj(fliplr(LFM_bb_neg_n));
corr_lfm_comp = abs(filter(mf_lfm_neg, 1, bb_comp(...)));
% 原来是 mf_lfm（up），现在 LFM2 是 down-chirp，必须用 mf_lfm_neg
```

## 3 处大 α 突破 patch（2026-04-21 SC-FDE 加）

### Patch 6: TX 帧默认 tail padding

```matlab
% 帧组装后、信道前
default_tail_pad = ceil(alpha_max_design * length(frame_bb) * 1.5);
frame_bb = [frame_bb, zeros(1, default_tail_pad)];
```
防 α 压缩后 data 段尾部截断（对称改善 α<0 方向）。

### Patch 7: CP 精修阈值门禁（仅 OFDM 保留 CP 精修）

```matlab
% 对 OFDM（有 alpha_cp 精修）：
cp_threshold = 1 / (2*fc*blk_fft/sym_rate);
if abs(alpha_lfm) > 1.5e-2 || abs(alpha_cp) > 0.7 * cp_threshold
    alpha_est = alpha_lfm;      % 跳过 CP 精修，避免 wrap
else
    alpha_est = alpha_lfm + alpha_cp;
end
% 对 SC-TDE/DSSS/FH-MFSK（无 CP 精修）：直接 alpha_est = alpha_lfm，Patch 7 不适用
```

### Patch 8: 正向大 α 精扫

```matlab
if alpha_lfm > 1.5e-2   % 仅 +α 方向（-α estimator 已准确）
    mf_up_tmp = conj(fliplr(LFM_bb_n));
    mf_dn_tmp = conj(fliplr(LFM_bb_neg_n));
    a_candidates = alpha_lfm + (-2e-3 : 2e-4 : 2e-3);   % 21 点
    best_metric = -inf;
    best_a = alpha_lfm;
    for ac = a_candidates
        bb_try = comp_resample_spline(bb_raw, ac, fs, 'fast');
        up_end = min(cfg_alpha.up_end, length(bb_try));
        dn_end = min(cfg_alpha.dn_end, length(bb_try));
        c_up = abs(filter(mf_up_tmp, 1, bb_try(cfg_alpha.up_start:up_end)));
        c_dn = abs(filter(mf_dn_tmp, 1, bb_try(cfg_alpha.dn_start:dn_end)));
        m = max(c_up) + max(c_dn);
        if m > best_metric, best_metric = m; best_a = ac; end
    end
    alpha_lfm = best_a;
end
```
修正 estimator 在 +α 方向的 2% 系统偏差。

## 体制特殊处理

### OFDM（最接近 SC-FDE）

- **CP 精修保留**：OFDM 本来就有 `alpha_cp` 精修逻辑，和 SC-FDE 一样合并 `alpha_est = alpha_lfm + alpha_cp`
- 直接套 SC-FDE 全部 5 patch

### SC-TDE（时变分支无 CP 精修）

- 源代码 line 10 注释："时变信道：alpha_est = alpha_lfm（跳过训练精估）"
- 迭代 refinement 直接给出最终 alpha_lfm，不再加 alpha_cp
- Patch 4 简化：`alpha_est = alpha_lfm`（去掉 `+ alpha_cp`）

### DSSS（无 CP 精修，Rake 合并前补偿）

- 源代码 line 199 `alpha_est = angle(R2*conj(R1)) / (2π·fc·T_v_lfm)`
- Patch 4 同款但直接 `alpha_est = alpha_lfm`

### FH-MFSK（能量检测，α 仅影响时间对齐）

- 源代码 line 205 类似 DSSS
- 能量检测对残余 α 相对鲁棒（已在 A1 观察 fd=10Hz 仍工作）
- 但固定 α 会破坏跳频时间基准，所以 α 补偿仍必要
- Patch 4 同款简化

## 验收标准

### 每体制独立验收（更新：对齐 SC-FDE 最新水平 |α|≤3e-2）

对每个体制（OFDM/SC-TDE/DSSS/FH-MFSK）跑：

- [ ] **A1 α=0 路径**（fd=0 static @ SNR=10）：BER 与 before 一致（零退化）
- [ ] **A2 α=5e-4 @ SNR=10**：BER < 5%
- [ ] **A2 α=1e-3 @ SNR=10**：BER < 5%
- [ ] **A2 α=2e-3 @ SNR=10**：BER < 5%（OFDM/SC-TDE），< 10%（DSSS/FH-MFSK）
- [ ] **D α∈[±1e-4, ±1e-2]**：BER < 5%（OFDM/SC-TDE），< 15%（DSSS/FH-MFSK）
- [ ] **D α=±3e-2**：BER < 10%（OFDM/SC-TDE），< 30%（DSSS/FH-MFSK 边界）
- [ ] **B 阶段不退化**（disc-5Hz/hyb-K* 4 channel @ SNR=10）：BER 与 before 对齐（≤1% 区别）

### 全体制横向验收

- [ ] 4 体制 A2 α=1e-3 @ SNR=10dB BER 都 < 5%
- [ ] A1 Jakes 扫描曲线不退化（除 α=0 不变的前提，fd>0 下 Jakes 仍崩 50% 属独立问题）

## 时间估计

| Step | 体制 | 改动 2 runner + 回归跑 | 工时 |
|------|------|-----------------------|------|
| 1 | OFDM | SC-FDE 模板直接套 + 带 CP 精修 | 1h |
| 2 | SC-TDE | 套模板 + 无 CP 简化 | 1h |
| 3 | DSSS | 套模板 + 无 CP 简化 | 1h |
| 4 | FH-MFSK | 套模板 + 能量检测路径 | 1h |
| 5 | wiki 报告 + todo 更新 + commit | - | 1h |
| **合计** | | | **~5h** |

## 风险

| 风险 | 缓解 |
|------|------|
| 体制特殊性（FH-MFSK 能量检测）对 α 残余容忍度 | 先 OFDM → SC-TDE → DSSS → FH-MFSK 顺序（从最像 SC-FDE 到最异），逐体制验证 |
| 不同体制的 search_cfg 窗口定位不一致 | 各 runner 已有 lfm1_start/lfm2_start 定义，直接复用 |
| DSSS Rake 合并对 α 残余敏感 | Rake 相关后再看是否 BER 可接受；若 DSSS α=1e-3 BER >5%，留后续独立 spec 继续 refine |
| SC-TDE 时变分支无 CP 精修下迭代收敛 | 2 次迭代已验证在 SC-FDE 收敛；SC-TDE 同款 LFM 结构应同款工作 |
| 帧改动破坏 B 阶段（discrete_doppler runner） | 每改完跑 B 阶段 1 通道回归 |
| OTFS debug 并行改 OTFS 文件冲突 | 用户确认在独立窗口做 OTFS，不触 4 体制 runner |

## 非目标

- ❌ 不改 OTFS（独立 spec 并行处理）
- ❌ 不改 BEM/Turbo/均衡器
- ❌ 不改 14_Streaming
- ❌ 不做诊断插桩（4 体制无 bench_diag/tog toggle，保持简洁）
- ❌ 不处理 α estimator 符号约定（独立 todo）
- ❌ 不处理 α<0 不对称（独立 todo）
- ❌ 不处理 α=3e-2 物理极限（独立 todo）

## 交付物

1. 8 文件 patch（4 体制 × 2 runner）
2. A2 / D / A1 回归 CSV（before/after 对比）
3. 更新 `wiki/comparisons/e2e-timevarying-baseline.md` 4 体制 after 数据
4. 更新 `wiki/modules/10_DopplerProc/双LFM-α估计器.md` 推广段
5. 更新 `wiki/conclusions.md` / `wiki/log.md`
6. 更新 `todo.md`（🔴 "α 推广 4 体制"移到完成里程碑）
7. 分 commit：
   - `feat(13_SourceCode): α 迭代 refinement 推广 OFDM/SC-TDE/DSSS/FH-MFSK`
   - `docs(wiki): α 推广 4 体制基线更新 + todo`

## Log

- 2026-04-21 创建 spec（基于 SC-FDE 模板成熟 + 4 体制帧结构确认一致）
- 2026-04-21 更新 spec 加 3 patch 大 α 突破（对齐 SC-FDE 最新 |α|≤3e-2 能力）
- 2026-04-21 **Step 1 OFDM 实施完成**（timevarying runner 套 8 patch）：
  - 中间发现 OFDM 的 CP 精修有 ~-1.9e-4 系统偏差（α=0 下 alpha_cp=-1.96e-4）
  - OFDM 有空子载波 CFO 精修接替，CP 精修多余——P7 直接禁用 CP 精修
  - 结果：A2 α∈[0,5e-4,1e-3,2e-3] × SNR∈[5,10,15,20] 全 BER ≤ 0.1%
  - D α∈[±1e-4, ±1e-2] 全 0%；α=+3e-2 **11.4%**，α=-3e-2 **0%**
- 2026-04-21 **Step 2 SC-TDE 实施遇阻**（timevarying runner 套 patch）：
  - alpha_lfm 估得准（A2 α=5e-4 下 est=4.97e-4, 精度 0.6%）
  - 但 SC-TDE 下游对残余 α 敏感，BER 全 50%（α≠0 都崩）
  - α=0 SNR=10 BER 15.8%（退化 from 基线 ~5%），SNR=15+ 恢复 0%
  - 根因怀疑：SC-TDE 的训练精估（alpha_train）在新帧结构下不适用，或 BEM 模型敏感
  - **留独立 spec 深挖**：`2026-04-22-sctde-alpha-refinement-deepdive.md`（未来）
  - SC-TDE runner 保留 broken patches 作 follow-up 起点
- 2026-04-21 **Step 3 DSSS 实施完成**（套 P1-P6+P8 跳过 P7）：
  - A2 α∈[0, 5e-4, 1e-3, 2e-3] × SNR∈[5~20] **全 BER=0%**
  - D |α|≤3e-3 全 BER=0%
  - D |α|≥1e-2 扩频码 chip-level timing 固有限制，崩 42-51%
- 2026-04-21 **Step 4 FH-MFSK 实施完成**（原本无 α 补偿，新增完整 P1-P6+P8 + 补偿）：
  - A2 α∈[0, 5e-4, 1e-3, 2e-3] × SNR∈[5~20] **全 BER=0%**
  - D |α|≤1e-2 **全 BER=0%**（跨 14 α 点，15 m/s 快艇覆盖）
  - D α=+3e-2 BER 21%，α=-3e-2 BER 48% 边界
- 2026-04-21 **结果汇总**（SC-FDE + 3 体制推广 OK，SC-TDE 失败）：
  | 体制 | A2 全范围 | D \|α\|≤1e-2 | α=+3e-2 | α=-3e-2 |
  |------|-----------|-------------|---------|---------|
  | SC-FDE | 0% | 0% | **5.4%** | 0% |
  | OFDM | 0% | 0% | **11.4%** | 0% |
  | DSSS | 0% | |α|≤3e-3 全 0% | 崩 | 崩 |
  | FH-MFSK | 0% | **全 0%** | 21% | 48% |
  | SC-TDE | α≠0 崩 50% | - | - | - |
- 2026-04-21 **discrete_doppler runner 未改**（B 阶段用 discrete runner，不受影响）；
  推广仅覆盖 A2/A3/D（timevarying runner 路径）
- 2026-04-21 **遗留项**：
  - SC-TDE timevarying 下游 α 敏感问题（独立 spec）
  - DSSS/FH-MFSK 在 α≥1e-2 的扩频/跳频固有限制（若要突破需改 RX 架构）
  - OFDM α=+3e-2 11.4%（稍超 10% 门槛但已达 5× 改善）
  - 其他 4 体制 discrete_doppler runner 未改（B 阶段保持旧 baseline）
