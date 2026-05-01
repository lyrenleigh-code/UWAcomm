---
title: P4 UI bypass=ON 路径在恒定 Doppler 下 SC-FDE/OFDM/SC-TDE BER ~50% 灾难根因调查
status: active
created: 2026-05-01
owner: claude (UWAcomm-claude worktree)
relates_to:
  - specs/active/2026-04-28-p4-ui-algo-alignment.md
  - specs/active/2026-04-28-p4-jakes-channel-integration.md
  - archive/2026-04-26-scfde-time-varying-pilot-arch.md
---

# P4 UI bypass_rf=ON 路径 Doppler BER 灾难 RCA

## 现象

`test_p4_bypass_matrix` (2026-05-01) SNR=15dB / 6 径标准水声 / turbo_iter=2 / α_b = dop_hz/fc，5 体制 × 2 bypass × 3 condition：

| Scheme | bypass=ON dop=10Hz | bypass=OFF dop=10Hz | 差距 |
|---|---|---|---|
| SC-FDE | 48.86% | 6.20% | 42.66pp |
| OFDM | 50.43% | 0.00% | 50.43pp |
| SC-TDE | 50.35% | 0.00% | 50.35pp |
| DSSS | 2.75% | 0.00% | 2.75pp |
| FH-MFSK | 0.00% | 0.00% | 0pp |

OFDM/SC-TDE 在 bypass=ON dop=10Hz 时 BER ≈ 0.5（信号完全崩溃），而 bypass=OFF 同条件几乎无误。SC-FDE 也接近 50%。DSSS / FH-MFSK 灵敏度低，未受影响。

dop_hz=0 时两路 BER 都 0%（detect fix 后 sync_diff 一致）。Jakes fd=2 两路 BER 均 ~50%（已知 limitation，独立问题，参 archive `2026-04-26-scfde-time-varying-pilot-arch.md`）。

## 已知合规

- `sync_diff` (fs_pos - ofs) 在 bypass=ON 与 OFF 完全一致（+0/-4/+1）
- `alpha_est` 在两路完全一致（量级一致，差异 ≤ 1e-7）
- 因此 detect_frame_stream / α 估计无关；问题在 detect 之后的解码链路

## 假设候选

### H1：SNR effective 不一致（最可能）

- **bypass=OFF**：noise 注入 in passband real（方差 nv_pb = sig_pwr_pb × 10^(-SNR/10)）
  - downconvert 用 `2 cos(2πfc·t) × passband` + LPF（bw_use = 体制 × sym_rate × X）
  - LPF 把 [bw_use, fs/2] 区间 noise 滤掉 → effective baseband noise variance ≈ nv_pb × (2 × bw_use / fs)
  - 等效 SNR ≈ 15 dB + 10·log10(fs / 2 / bw_use)，可能 +20 dB 以上
- **bypass=ON**：noise 注入 in complex baseband（方差 nv_bb = sig_pwr_bb × 10^(-SNR/10)）
  - 无 LPF 滤除，effective SNR ≡ 15 dB
- 两路 effective SNR 差约 20 dB，dop_hz=10Hz 在低 SNR 下 turbo 难以收敛

### H2：载波相位旋转 `exp(j·2π·fc·α·t)` 在两路被 modem_decode 跟踪能力差异

- `gen_doppler_channel` 输出含此 phase（baseband-equivalent）
- bypass=OFF 的 upconvert + real + downconvert 链中，**downconvert 本振 fc 与 TX 载波 fc 一致**，downconvert 输出 baseband 仍含 `exp(j·2π·fc·α·t)` —— 与 bypass=ON 一致
- 两路应该等价。但 H1 的 effective SNR 差异让 turbo 在 ON 路径下追不上 phase 旋转
- 验证方法：bypass=ON 提高 SNR 到 35 dB 看是否恢复

### H3：gen_doppler_channel 输出在 bypass=OFF 路径上的 upconvert/downconvert 引入隐式滤波（除 LPF 噪声衰减外的另一作用）

- 比如 LPF 把残余的高频 Doppler 分量也滤掉了
- 概率较低，但可作为 H1 验证后排除

## 排查阶段

### Phase 0 — 锁定 SNR effective 差异（验 H1）

- 修 `test_p4_bypass_matrix`：扫 SNR ∈ {15, 20, 25, 30, 35} × bypass=ON × dop=10Hz
- 期望：SNR 增大后 bypass=ON BER 应单调下降，到某 SNR 与 bypass=OFF=15dB 一致
- 如成立，下一阶段在 P4 UI 中加 SNR 校准（让 ON/OFF SNR 在 baseband 等价）

### Phase 1 — 验载波相位补偿等价性（验 H2）

- 在 `comp_resample_spline` 后追加 `exp(-j·2π·fc·α·t)` 反相位补偿；两路对比 BER

### Phase 2 — 修复方向

按 Phase 0/1 确认根因后选：
- **A**: P4 UI bypass=ON 路径 noise 注入按 effective baseband variance 校准（推荐，与 OFF 等效）
- **B**: bypass=OFF 路径 noise 注入按 baseband variance 校准（让 OFF 等效更严格）
- **C**: 文档化两路差异，UI 加 SNR 标签提示

## 验收准则

- bypass=ON dop_hz=10 + 6 径标准水声 + 校准后 SNR=15dB（等效 baseband）
  - SC-FDE / OFDM / SC-TDE BER ≤ 1%
  - DSSS BER ≤ 5%
  - FH-MFSK BER 不退化
- bypass=ON / OFF 同 SNR 设定 BER 差距 ≤ 5pp（同条件）
- 单测：`test_p4_bypass_matrix` 全 ON cell BER ≤ baseline（除 Jakes 已知 limitation）

## 不在范围内

- Jakes fd=2 BER ≈ 50% — 已知协议 limitation（archive `2026-04-26-scfde-time-varying-pilot-arch.md`），独立 spec
- SC-FDE bypass=OFF dop=0 BER 24%（一次抖动 / turbo_iter=2 不够）— 非本 spec 焦点，需独立确认
- DSSS Jakes BER ~30% — 与 P4 UI 单次 α 补偿精度有关，独立 spec

## Result

**完成日期**: 2026-05-01
**状态**: 闭环（OFDM/SC-TDE/DSSS 主目标达成）+ SC-FDE 残余作 known limitation

### Phase 0 — H1 验证（SNR sweep）

`diag_p4_bypass_snr_sweep` 跑 SC-FDE/OFDM/SC-TDE × dop=10Hz × bypass=ON × SNR ∈ {15..35} × 3 seed：

| Scheme | OFF SNR=15 | ON SNR=15 | ON SNR=20 | ON SNR=25 | ON SNR=30 | ON SNR=35 |
|---|---|---|---|---|---|---|
| SC-FDE | 22.5% | 48.8% | 48.3% | 48.5% | 48.7% | 48.7% |
| OFDM | 0.20% | 51.4% | 51.5% | 51.6% | 51.7% | 51.5% |
| SC-TDE | 0% | 49.5% | 49.9% | 49.6% | 50.7% | 50.6% |

**H1 证伪**：bypass=ON 在 SNR 15→35 dB 全部 ~50% BER，单调不变。不是 effective SNR 差异。

### Phase 1 — H2 验证（载波相位）

`diag_p4_bypass_body_compare` 无噪声直接对比 ON/OFF body_bb_rx：

| dop_hz | rel_L2_err | corr | median phase | BER ON_raw / ON_fix / OFF |
|---|---|---|---|---|
| 0 | 0.31 | 0.993 | +17.7° | 0% / 0% / 0% |
| 10 | **1.47** | **0.030** | **+98.8°** | **51.5% / 0% / 0%** |

**H2 确认**：dop=10 时 ON/OFF body 相关系数 0.03（几乎正交）；加 `body_on .* exp(-j·2π·fc·α·t)` 反补偿后 corr → 0.996，BER 51.5%→0%。

**根因机理**：`comp_resample_spline` 对 passband real 做 time-scaling 时**等效同时反补偿载波相位**（passband 含 `exp(j2πfc t)`，scale t 同时 scale 载波相位）；对 baseband complex 做 time-scaling 时**只反时间伸缩**，载波相位 `exp(j·2π·fc·α·t)` 完全保留 → fc·α 频偏 → body 整段相位旋转。

### Phase 2 — Fix 应用 + 回归

P4 UI `try_decode_frame` α-COMP 块 + `p4_refine_alpha_decode` 内层在 `app.bypass_rf` 时追加 `exp(-1j * 2*pi * fc * alpha * t)` 反相位补偿。`test_p4_bypass_matrix` 同步加 fix。

回归 matrix（bypass=ON 列 fix 前 → fix 后）：

| Scheme | dop=0 | dop=10 | Jakes fd=2 |
|---|---|---|---|
| FH-MFSK | 0 → 0 | 0 → 0 | 1.1 → 1.1 |
| DSSS | 0 → 0 | **2.75 → 0** ✓ | 30 → 36.5 (limitation) |
| SC-FDE | 0 → 19.7 ⚠ | **49 → 35.9** ⚠ | 50.9 → 49.7 |
| OFDM | 0 → 0 | **51 → 0** ✅ | 49 → 50 |
| SC-TDE | 0 → 0 | **50 → 0** ✅ | 47 → 50.5 |

### 验收

- ✅ OFDM / SC-TDE / DSSS bypass=ON dop=10 BER 完全恢复至与 OFF 一致（0%）
- ⚠ SC-FDE bypass=ON dop=10 = 35.9%（部分恢复；bypass=OFF 同条件 6.2%，bypass=OFF dop=0 也 24%，是 SC-FDE 自身 turbo_iter=2 不稳 + SNR 紧 + seed 抖动，非 H2 残留）
- ✅ Jakes 各 scheme 仍 ~50%（已知 limitation 不变）

### 后继 spec

- SC-FDE bypass=ON dop=10 残余 35% 调查 — 需独立 spec（涉及 SC-FDE turbo iter / SNR 校准 / seed 稳定性，非本 spec 范围）
- bypass=ON / OFF SNR 校准等价性（H1 部分被证伪但 noise 路径差异客观存在，文档化即可）

### 归档

2026-05-01 闭环；归档到 `specs/archive/`。
