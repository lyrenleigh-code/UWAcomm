# SC-TDE 端到端调试日志

> 体制：SC-TDE | 当前版本：V5.4
> 关联模块：[[07_信道估计与均衡]] [[08_同步与帧结构]] [[09_脉冲成形与变频]] [[10_多普勒处理]] [[12_迭代调度器]]
> 关联笔记：[[端到端帧组装调试笔记]] [[UWAcomm MOC]] [[项目仪表盘]]
> 技术参考：[[水声信道估计与均衡器详解]] [[时变信道估计与均衡调试笔记]]
> Areas：[[信道估计与均衡]] [[同步技术]] [[多普勒处理]]

#SC-TDE #调试日志 #端到端

---

## 版本总览

| 版本 | 日期 | 核心变更 | 状态 |
|------|------|---------|------|
| V5.0 | 2026-04-09 | 两级分离架构+训练精估 | LFM检测bug |
| V5.1 | 2026-04-10 | LFM标称窗口修复 | 🔶 同步修复，时变待优化 |
| V5.2 | 2026-04-14 | 时变跳过训练精估 + nv_post 兜底 | ✅ 静态稳定 |
| V5.3 | 2026-04-23 | α>0 post-CFO 伪补偿 RCA（D0b→D10） | ✅ 根因锁定 |
| V5.4 | 2026-04-24 | 删 post-CFO + plan C 证伪 + fd=1Hz investigation 开单 | ✅ α 常数多普勒灾难关闭 |

---

## V5.0 — 两级分离架构 (2026-04-09)

**Git**: `c7e3305`

### 变更
- 帧结构对齐SC-FDE V4.0: `[HFM+|HFM-|LFM1|LFM2|data]`
- 训练精估替代CP精估（SC-TDE无CP结构）
- 代码完成，发现LFM检测bug → 转V5.1

---

## V5.1 — LFM检测修复 (2026-04-10)

**Git**: `08c03cf`
**修改文件**: 三体制 test_*_timevarying.m

### 问题描述

lfm_pos=6402（期望9601），偏差恰好3200样本（= N_lfm + guard_samp），数据提取锁定到LFM1而非LFM2。

### 根因分析（三层叠加）

1. **Phase 1 LFM1搜索包含HFM区域**: `max(corr(1:lfm1_end))` 中HFM-与LFM的互相关峰(~5600)被误识为LFM1
2. **Phase 1 基于错误LFM1推算LFM2位置**: 窗口被钳位到lfm2_start=8801，恰好是LFM1匹配滤波峰值(8800)旁
3. **Phase 2 lfm2_start与LFM1峰仅差1样本**: `max(corr(8801:end))` 在LFM1尾部和LFM2峰之间选到前者

### 修复方案

定义匹配滤波标称峰值位置（基于[[08_同步与帧结构|帧结构]]已知）：
- `lfm1_peak_nom = 2*N_preamble + 2*guard_samp + N_lfm` = 8800
- `lfm2_peak_nom = 2*N_preamble + 3*guard_samp + 2*N_lfm` = 12000
- `lfm_search_margin = max(sym_delays)*sps + 200` = 920

所有LFM搜索改为标称位置±margin窗口，两窗口间距1360样本完全不重叠。

OFDM/SC-FDE同步预防修复：跳过HFM区域搜索 + 去掉LFM1→LFM2窗口推算。

### 测试结果

#### LFM定位修复

| 场景 | V5.0 lfm_pos | V5.1 lfm_pos | expected |
|------|-------------|-------------|----------|
| static | 6402 | **9601** | 9601 |
| fd=1Hz | 9600 | 9600 | 9601 |
| fd=5Hz | 6402 | **9598** | 9601 |

#### BER对比

| 场景/SNR | 5dB | 10dB | 15dB | 20dB |
|----------|-----|------|------|------|
| static(V5.0) | 50.25% | 0.55% | 0.10% | 0.00% |
| static(V5.1) | **1.95%** | 0.55% | 0.10% | 0.00% |
| fd=1Hz | 46.80% | 13.91% | **0.76%** | 1.60% |
| fd=5Hz | ~45% | ~46% | ~46% | ~45% |

### 剩余问题

1. **fd=1Hz [[10_多普勒处理|多普勒]]估计误差88.4%**: LFM相位法被Jakes衰落相位污染。对策：仅用alpha_lfm（对齐OFDM V4.3策略）
2. **fd=1Hz@20dB(1.60%)比15dB(0.76%)差**: 疑似nv_post高SNR过度自信（对齐OFDM V4.2经验）
3. **fd=5Hz ~45%**: 物理极限

### 下一步

- [ ] 时变信道跳过训练精估（对齐OFDM策略: alpha_est = alpha_lfm）
- [ ] 添加nv_post实测噪声兜底

---

## V5.3 — α>0 下 post-CFO 伪补偿 RCA (2026-04-23)

**Git**: 待提交
**Spec**: `specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md`
**关联模块**: [[10_多普勒处理]] [[07_信道估计与均衡]] [[12_迭代调度器]]

### 触发事件

2026-04-23 Phase c `diag_5scheme_monte_carlo` 首次定量：SC-TDE @ `ftype=static + dop_rate=+1e-2 + SNR=10 dB` 下 15/15 seed 全灾难，mean BER=49.73%, **std=1.05%**（极低方差 = 确定性失败）。

对比基线：SC-FDE 同配置 0/15、OFDM 0/15、FH-MFSK 0/15，DSSS 15/15（独立 spec）。

### RCA 过程（10 步 diag 级联）

| 步 | 目标 | 结果 | 证伪层 |
|----|------|------|--------|
| D0b | 插桩不破坏默认路径（α=0） | BER mean ≤1%，Gate 通过 | — |
| D1 | Oracle α | mean 49.50%，仍灾难 | ❌ α 估计 |
| D2 | Oracle h | FT mean 48.42% / TT 50.51%，仍灾难 | ❌ GAMP 发散 |
| D3 | turbo_iter sweep {1,2,3,5,10} | 全部 ~50%，iter=1 就崩 | ❌ Turbo iter≥2 放大 |
| D5 | Turbo 前信号层 | corr(1:50)=0.055 / SNR_emp=-3.2 dB | 确认 Turbo 输入已损坏 |
| D6 | bb_comp 级 pre-CFO | corr 升到 0.101，但 LFM 定时偏 36 samples | 位置错 |
| D7 | rx_data_bb 级 pre-CFO | LFM 定时正确但 BER 仍 50% | ❌ 不是 CFO 补偿位置 |
| D9 | rx_filt 波形对比 α=0 vs α=+1e-2 | **sps scan off=0 \|corr\|=0.817（CFO 补偿前）但 DIAG-S=0.055（CFO 补偿后）** | 定位 CFO 补偿是元凶 |
| D10 | 禁用 post-CFO 补偿验证 | **α=+1e-2 BER 50%→0.29%** ✓✓✓ | 根因锁定 |

### 真根因

**runner `test_sctde_timevarying.m:436-441` 的 `rx_sym_recv .* exp(-j·2π·α·fc·t)` 补偿是伪操作**：

```matlab
if abs(alpha_est) > 1e-10
    cfo_res_hz = alpha_est * fc;                         % ← α=1e-2 → 120 Hz
    t_sym_vec = (0:length(rx_sym_recv)-1) / sym_rate;
    rx_sym_recv = rx_sym_recv .* exp(-1j*2*pi*cfo_res_hz*t_sym_vec);  % ← 凭空加 120 Hz 频偏
end
```

**物理解释**：[[10_多普勒处理|gen_uwa_channel]] 工作在**基带**，多普勒 = 纯时间伸缩 `s_bb((1+α)t)`，**不产生 fc·α 载波频偏**（基带信号无载波项）。`upconvert → +noise → downconvert` 中 fc 的出入相互抵消。`comp_resample_spline` 补偿时间伸缩后 `bb_comp` **完全干净，无 CFO**。

runner 错误假设"存在 fc·α 残余 CFO"（可能是 passband Doppler 模型遗留），补偿 120 Hz 后每符号累积 7.2° 相位旋转，50 符号累积 360°，`sum(rx·conj(training))` 完全抵消 → corr 从 0.82 → 0.05 → Turbo 输入纯噪声 → 50% BER。

### 关键验证数据（D10）

| α | baseline BER | disable_cfo BER |
|---|-------------|----------------|
| 0 | 1.84±1.63% | **0.04±0.09%** |
| +1e-3 | **50.66%** | **0.00%** |
| +1e-2 | 50.36% | **0.29±0.44%** |

### 副发现（与历史认知矛盾）

1. **α=+1e-3 static 路径原来也是 100% 灾难**（之前记"能 work"实为 bench_seed=42 默认下的个例假象）
2. **α=0 baseline 也被微伪频偏污染**（`alpha_est`≈-3.89e-6 乘 fc → -0.047 Hz 伪偏差，累积 1.4°）
3. post-CFO 补偿**在任何 α ≥ 0 场景**都有害，不只是 α=+1e-2

### 为何 SC-FDE 同 bug 但灾难率只 10%

SC-FDE 用频域均衡（FDE + FFT），`exp(-j·2π·α·fc·t)` 产生的线性相位旋转在频域转为 1-2 个子载波偏移，FDE 的 ZF/MMSE 自然吸收。SC-TDE 时域 DFE 无此免疫。

### 下一步（独立 spec）

- [x] Fix spec：删除 line 436-441 的 post-CFO 补偿 + 回归 benchmark 验证 → V5.4 完成（见下）
- [ ] 横向检查 spec：OFDM/DSSS/FH-MFSK/SC-FDE/OTFS runner 是否有同操作（`specs/active/2026-04-24-cfo-postcomp-cross-scheme-audit.md`）
- [ ] 若 `gen_uwa_channel` 未来改为 passband Doppler 模型，需按信道类型选择性启用 post-CFO

---

## V5.4 — post-CFO 删除 fix + plan C 证伪 (2026-04-24)

**Git**: 待提交
**Spec**: `specs/archive/2026-04-24-sctde-remove-post-cfo-compensation.md`
**Parent RCA**: `specs/archive/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md`
**新开 spec**: `specs/active/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md`
**关联模块**: [[10_多普勒处理]] [[12_迭代调度器]]

### 改动摘要

| 改动 | 内容 |
|------|------|
| runner 主改 | `test_sctde_timevarying.m` L499-511 post-CFO 改默认 skip，`diag_enable_legacy_cfo` 反义 toggle |
| D6/D7 清理 | 删 L394-404（bb_comp 级 pre-CFO）+ L428-439（数据段级 pre-CFO）插桩（已证伪） |
| CSV 字段补全 | `row.alpha_est = alpha_est_matrix(fi_b, si_b)` 加入 bench CSV 输出 |
| 新验证脚本 | `verify_alpha_sweep.m`：V1 α 扫描 8α×5seed + V2 α=0 SNR gate 3SNR×5seed（55 trial） |

### 三阶段验证

**V1（α 扫描 @ SNR=10，5 seed）**：

| α | mean BER | std | α_est mean | vs 历史 |
|---|---------|-----|-----------|---------|
| +1e-4 | **0.00%** | 0 | +1.132e-4 | — |
| +1e-3 | **0.00%** | 0 | +1.007e-3 | **50.66% → 0%** ✓ |
| +3e-3 | **0.00%** | 0 | +2.994e-3 | — |
| +1e-2 | **0.29%** | 0.44 | +9.958e-3 | **50.36% → 0.29%** ✓ |
| +3e-2 | 49.86% | 0.93 | +3.177e-2 | 物理极限（α_est 精度 OK，pipeline OK，Turbo 不收敛）|
| -1e-3 | 0.00% | 0 | -9.844e-4 | — |
| -1e-2 | 0.00% | 0 | -9.963e-3 | — |
| -1e-4 | 0.00% | 0 | -1.086e-4 | — |

**V2（α=0 × 3 SNR）**：

| SNR | mean BER | vs 历史 V5.2 |
|-----|---------|-------------|
| 10 | 0.040% | **1.84% (D10) → 0.04%** ✓ |
| 15 | 0.000% | — |
| 20 | 0.000% | — |

**V3（默认 runner 3 fading × 4 SNR）**：

| 场景 | 5dB | 10dB | 15dB | 20dB |
|------|-----|------|------|------|
| static | 0.00% | 0.00% | 0.00% | 0.00% |
| fd=1Hz | 21.70% | 17.39% | 27.96% | 0.00% |
| fd=5Hz | 45.48% | 45.76% | 46.87% | 47.15% |

### plan C 证伪（时变路径 apply post-CFO 实验）

**假设**：`gen_uwa_channel` 在 fd>0 Jakes 时变下可能累积真 CFO，post-CFO 补偿对时变分支有真实作用。

**实测**（`ftype!='static'` 时 apply post-CFO）：

| 场景 | plan A skip | plan C apply |
|------|-------------|-------------|
| fd=1Hz 5dB | 21.70% | 20.03% |
| fd=1Hz 10dB | 17.39% | **47.71%** |
| fd=1Hz 15dB | 27.96% | 35.74% |
| fd=1Hz 20dB | **0.00%** | **37.20%** |

**结论**：plan C 反而把 fd=1Hz 全盘打崩（SNR=20 从 0% 到 37%）。**时变路径也不需 post-CFO**。回滚到 plan A（无条件 skip）。

历史 V5.2 fd=1Hz SNR=15 = 0.76% **不可复现**：代码演化累积（bench_seed 注入、alpha_est 门禁调整等）带来的差异，非 post-CFO 贡献。

### fd=1Hz 非单调 BER vs SNR（known limitation）

V3 fd=1Hz 出现非单调（SNR=10→17%, SNR=15→27%, SNR=20→0%），Turbo 在高 SNR 救回。疑似 Turbo+BEM 在 Jakes 时变下的稀有触发，类似 SC-FDE Phase J ~10% deterministic 灾难模式。

独立调研 spec：`specs/active/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md`（5 疑似根因 H1-H5，3 阶段调研矩阵）。

### 主目标达成

- ✅ α 常数多普勒下 SC-TDE 100% 灾难关闭（α=±1e-3 / ±1e-2 / +3e-3 / ±1e-4 全 ≤ 1%）
- ✅ α=0 副带红利（1.84% → 0.04%）
- ✅ D0b / V2 gate 通过
- ✅ `diag_enable_legacy_cfo` 反义 toggle 保留供历史对照
- 🟡 α=+3e-2 物理极限未动（与 post-CFO 无关）
- 🟡 fd=1Hz 非单调 → 独立 spec 调研

### 下一步

- [ ] CFO postcomp 横向审计（spec `2026-04-24-cfo-postcomp-cross-scheme-audit.md`）
- [ ] fd=1Hz 非单调 investigation（spec `2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md`）
- [ ] 主 fix 归档 + commit
