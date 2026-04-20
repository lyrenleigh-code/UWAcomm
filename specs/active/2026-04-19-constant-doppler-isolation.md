---
project: uwacomm
type: task
status: active
created: 2026-04-19
updated: 2026-04-19
tags: [多普勒, 10_DopplerProc, 13_SourceCode, 测试矩阵, 恒定多普勒]
---

# 恒定多普勒隔离测试

## 背景

现有 E2E 测试矩阵（`wiki/comparisons/e2e-test-matrix.md`）把 `fd_hz`（Jakes 衰落速率）与
`dop_rate = fd_hz/fc`（载波伸缩因子 α）**绑定扫描**，如
`test_sctde_timevarying.m:106-110`：

```matlab
fading_cfgs = {
    'fd=1Hz', 'slow', 1, 1/fc;   % Jakes 散射 + α=1/fc
    'fd=5Hz', 'slow', 5, 5/fc;   % Jakes 散射 + α=5/fc
};
```

两种物理机制被混在一起：

| 机制 | 物理含义 | 补偿方法 |
|------|---------|---------|
| **恒定 α** | 收发平台匀速相对运动 → 载波频率+时间轴线性伸缩 | LFM1/LFM2 相位估计 + resample |
| **Jakes fd** | 多径散射体随机速度 → 时变衰落+频谱展宽（ICI） | BEM 跟踪 / Turbo 迭代 |

`conclusions.md` #4 给出的 "fd≤5Hz 下 oracle α 5dB+ 基本不变" 暗示只要 α 估得准，
恒定分量可彻底补偿，但**缺少独立验证**。现有 "fd=5Hz 50% BER" 的锅实为 Jakes ICI，
不是恒定 α。

## 目标

隔离测试**纯恒定多普勒**下 6 体制的工作极限：

1. 固定静态 6 径信道（关 Jakes `fading_type='static'`），仅开 `doppler_rate=α`
2. α 扫描多量级，覆盖 AUV/船舶/鱼雷典型工况
3. 产出：α 估计精度曲线 + 补偿残余曲线 + BER 矩阵
4. 回答核心问题："恒定多普勒在本系统能扛到多大？失效在 α 估计还是 resample？"

## 测试配置

### α 扫描点（水声 c≈1500 m/s）

| α | 对应相对速度 | 工况 |
|---|-------------|------|
| 0 | 0 m/s | 基线（静止） |
| 1e-4 | 0.15 m/s | 锚泊漂移 |
| 5e-4 | 0.75 m/s | 缓慢拖体 |
| 1e-3 | 1.5 m/s | 步行级 AUV |
| 3e-3 | 4.5 m/s | 中速 AUV |
| 1e-2 | 15 m/s | 快艇 / 高速 AUV |
| 3e-2 | 45 m/s | 鱼雷 / 拖曳声纳 |

每个 α 同时正负扫（远离/靠近），共 **13 个 α 点**（含 α=0）。

### SNR 扫描

`[0, 5, 10, 15, 20]` dB（与现有矩阵对齐）。

### 体制

| 体制 | decode 入口 | 备注 |
|------|-------------|------|
| SC-FDE | `modem_decode_scfde` | 主测试对象（两级分离架构典型） |
| OFDM | `modem_decode_ofdm` | 空子载波 CFO 精估链路 |
| SC-TDE | `modem_decode_sctde` | LFM 精估链路 |
| OTFS | `modem_decode_otfs` | DD 域对恒定 α 鲁棒性 |
| DSSS | `modem_decode_dsss` | Rake 合并 + DCD |
| FH-MFSK | `modem_decode_fhmfsk` | 跳频分集（天然抗 α？验证） |

### 信道

固定 6 径静态信道：`delays=[0,5,15,40,60,90] sym`，`gains` 按现有 `test_*_discrete_doppler.m`
复用。`fading_type='static'`，无 Jakes 散射。

### 帧结构

复用各体制现有帧结构 `[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]`。
不动 TX，只改 channel + RX。

## 评价指标

| 指标 | 计算 | 阈值 |
|------|------|------|
| **α 估计 RMSE** | `sqrt(mean((alpha_est - alpha_true)^2))` 随 α 扫描 | 相对误差 < 5% @ SNR=10dB |
| **α 估计 NMSE (dB)** | `20*log10(RMSE/|α_true|)` | < -20 dB |
| **resample 后残余 α** | `alpha_res = alpha_true - alpha_est` | 输入 BEM 的残余 ≤ 1e-4 |
| **帧检测成功率** | 10 次蒙特卡洛 HFM 峰成功检出率 | ≥ 95% @ SNR=5dB |
| **Coded BER** | 各 (α, SNR) 格点 1000 bit | 与 α=0 基线差 ≤ 一个 SNR 台阶 |

## 假设检验

**H1**：α 估计 RMSE 随 α 单调增大，存在饱和点（LFM 斜率分辨率极限）
**H2**：BER 退化由 α 估计精度主导，不是 resample 失真
**H3**：高速体制（SC-FDE/OFDM/SC-TDE/OTFS）在 α≤3e-3 下 10dB 内达 0% BER
**H4**：α=3e-2 时至少有一体制因 resample Nyquist 余量不足出现混叠
**H5**：FH-MFSK 对恒定 α 比高速体制更鲁棒（跳频 + 能量检测）

## 不做

- **不测 Jakes 衰落**（已由现有矩阵覆盖）
- **不测 Rician 混合**（已由 `离散Doppler全体制对比.md` 覆盖）
- **不引入时变 α**（`gen_doppler_channel.m` 已有 `random_walk`/`linear_drift` 留作后续 spec）
- **不修改 decode 层算法**（仅做配置扫描）
- **不触碰 14_Streaming**（先在 13_SourceCode 固化结论）

## 交付物

1. `modules/10_DopplerProc/src/Matlab/test_constant_doppler_sweep.m`（主测试脚本）
2. `modules/10_DopplerProc/src/Matlab/plot_constant_doppler_sweep.m`（可视化）
3. `wiki/modules/10_DopplerProc/恒定多普勒隔离测试.md`（结论与数据表）
4. 更新 `wiki/comparisons/e2e-test-matrix.md` 增一节 "恒定多普勒隔离"
5. 可能补 `wiki/conclusions.md` 1-2 条

## 时间估计

| 阶段 | 工时 |
|------|------|
| 公共信道适配层（复用 apply_channel 或直接 gen_uwa_channel） | 0.5h |
| 主测试脚本（6 体制 × 13 α × 5 SNR 扫描框架） | 1.5h |
| 可视化 + 诊断输出 | 0.5h |
| 运行 + 结果分析 | 1h（串行 390 格点 × 1000 bit） |
| wiki 整理 | 0.5h |
| **合计** | **4h** |

## 风险

- **运行时间**：13×5×6=390 格点若每格 10s → 65min，可接受
- **OTFS 帧结构**：OTFS 帧不含 LFM1/LFM2 对，改用 LFM + CP 估 α，估计器不同，需单独处理
- **FH-MFSK 帧**：需确认其同步链路是否走 LFM，若走 HFM-only 需用 HFM 斜率估 α

## 后续衍生

若本 spec 结论显示 α 估计是瓶颈，可开衍生 spec：
- `2026-04-20-lfm-alpha-estimator-refinement.md`（LFM 估计器高精度改造）
- `2026-04-21-timevarying-alpha-tracker.md`（时变 α Kalman/PLL 跟踪）

## Log

- 2026-04-19 创建 spec + plan（设想走 modem_dispatch 统一入口）
- 2026-04-19 **诊断跑通 (SC-FDE only)**：复用 E2E benchmark 基础设施扩 stage D，
  α=[0, ±1e-4, ±5e-4, ±1e-3, ±3e-3, ±1e-2, ±3e-2] × SNR=10dB = 13 点，
  耗时 29.7s，CSV: `modules/13_SourceCode/src/Matlab/tests/bench_results/e2e_baseline_D.csv`，
  图：`wiki/comparisons/figures/D_{alpha_est_vs_true,alpha_rel_error,ber_vs_alpha}.png`
- 2026-04-19 **核心发现（surprising）**：α 估计**全部失效**——所有非零 α 都估成
  1e-4~1e-5 量级噪声，**估计误差 ≈ α_true 本身**。例如：
  | α_true | α_est | BER |
  |--------|-------|-----|
  | 0 | +2.3e-6 | 0% |
  | +1e-4 | +2.5e-6 | 0%（偶发通过，未真估到） |
  | -1e-4 | +1.1e-5 | 50% |
  | +5e-4 | +1.2e-6 | 49% |
  | +1e-3 | +2.2e-5 | 49% |
  | +3e-3 | -2.3e-4 | 49% |
  | +1e-2 | -4.9e-5 | 50% |
  | +3e-2 | +2.3e-7 | 50% |
- 2026-04-19 **根因定位**：
  - 帧结构 `[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]` 设计**允许**精确
    估 α，但当前 RX 代码（`test_scfde_timevarying.m:200-210`）**只用双 LFM 相位差**，
    且 **LFM1=LFM2 是同一波形**（`LFM_bb_n`）。
  - 相同 LFM 的双相关峰相位差对 α 不敏感（数学上只能测时钟/相位偏置）
  - 真正能无模糊估 α 的是**双 HFM（up+down chirp）时延差法**（HFM+ 是 up-chirp、
    HFM- 是 down-chirp，α 会让它们的相关峰反向漂移，差值 ∝ 2α），但代码没实现
  - 之前提出的"LFM 8.3e-4 模糊阈值"预测**过于乐观**——在相同 LFM 方案下连 1e-4
    都测不到
- 2026-04-19 **下一步决策**：本 spec 目的（隔离测恒定 α 的工作极限）已部分完成
  （证明 SC-FDE 当前 estimator **完全不工作**）。建议路径：
  - 升格衍生 spec `2026-04-20-lfm-alpha-estimator-refinement.md`（原"后续衍生"
    位置）为**主线改造 spec**
  - 在 `modules/10_DopplerProc/src/Matlab/` 新建 `est_alpha_dual_hfm.m`
    （双 HFM 时延差 α 粗估，无模糊）
  - SC-FDE/OFDM/SC-TDE/DSSS/FH-MFSK 5 runner 的 α 估计入口统一替换
  - 改造后回归跑 stage D 对比 before/after
  - OTFS 延后（帧结构异，无 HFM）
- 其他体制（OFDM/SC-TDE/OTFS/DSSS/FH-MFSK）在 D 阶段扫描 **延后到 refinement spec**，
  因为当前估计器全部共享同样的双 LFM 代码模式，结论必然一致
- 2026-04-20 **refinement spec 已落地**（`2026-04-20-alpha-estimator-dual-chirp-refinement.md`）：
  SC-FDE 激活双 LFM（up+down）时延差法后，A2 α=5e-4 @ SNR=10 BER **48.7% → 0%**，
  α=1e-3 **49% → 2%**；本诊断 spec 目标达成（证明当前 estimator 不工作并定位根因），
  实际改造结论详见 [[modules/10_DopplerProc/双LFM-α估计器]]
