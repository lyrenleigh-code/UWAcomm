# 信道估计与均衡模块 (ChannelEstEq)

接收链路核心模块，覆盖静态/时变/OTFS信道估计、信道跟踪、均衡器和Turbo迭代软信息接口。共42个文件（35个对外+7个内部/测试）。

## 对外接口

### ① 静态信道估计（10个）

| 函数 | 方法 | NMSE@15dB | 推荐度 |
|------|------|-----------|--------|
| `ch_est_ls` | LS最小二乘 | -12.6dB | 基线 |
| `ch_est_mmse` | MMSE正则化 | -12.6dB | ★★ |
| `ch_est_omp` | OMP稀疏恢复 | -34.2dB | ★★★ |
| `ch_est_sbl` | SBL贝叶斯 | -28.1dB | ★★ |
| `ch_est_gamp` | GAMP消息传递 | -34.2dB | **★★★ 推荐** |
| `ch_est_amp` | AMP近似消息传递 | — | ★★ |
| `ch_est_vamp` | VAMP变分AMP | -34.3dB | ★★★ |
| `ch_est_turbo_vamp` | Turbo-VAMP+EM | -34.3dB | **★★★ 最优** |
| `ch_est_turbo_amp` | Turbo-AMP(伯努利-高斯先验) | — | ★★★ |
| `ch_est_ws_turbo_vamp` | 热启动Turbo-VAMP | — | ★★★ |

### ② 时变信道估计（4个）

| 函数 | 版本 | 方法 | 说明 |
|------|------|------|------|
| `ch_est_bem` | **V2** | BEM基扩展(CE/DCT) | 向量化重构+自适应正则化+可选BIC |
| `ch_est_bem_dd` | V1 | DD-BEM判决辅助迭代 | FDE块均衡→硬判决→扩展导频→重估BEM |
| `ch_est_tsbl` | V2 | T-SBL时序稀疏贝叶斯 | 多快照联合稀疏+时间相关 |
| `ch_est_sage` | V1 | SAGE/EM参数估计 | 高分辨率时延/增益/多普勒, 时延0误差 |

### ②-b OTFS信道估计（1个）

| 函数 | 方法 | 说明 |
|------|------|------|
| `ch_est_otfs_dd` | DD域嵌入导频 | 从接收DD域帧提取稀疏路径参数(时延/多普勒/增益) |

### ③ 信道跟踪（1个）

| 函数 | 方法 | 说明 |
|------|------|------|
| `ch_track_kalman` V1 | 稀疏Kalman AR(1) | α=0.5^(4fd/fs), K_target=5% |

### ④ 均衡器（13个）

| 函数 | 版本 | 类型 | 适用体制 | 备注 |
|------|------|------|---------|------|
| `eq_rls` | V1 | RLS居中延迟 | SC-TDE | 抽头数甜点=4×L_h |
| `eq_lms` | **V1.1** | LMS自适应 | SC-TDE | 修复DD QPSK判决 |
| `eq_linear_rls` | V1 | RLS线性均衡+PLL | SC-TDE | Turbo iter1用, 输出LLR |
| `eq_dfe` | V3.1 | RLS-DFE | SC-TDE | 静态信道关PLL, λ=0.9995 |
| `eq_bidirectional_dfe` | V3 | 双向DFE | SC-TDE | 需前向输出作后向伪训练 |
| `eq_mmse_ic_fde` | V2 | **LMMSE-IC迭代** | **SC-FDE/OFDM Turbo核心** | |
| `eq_mmse_fde` | V1 | 频域MMSE | SC-FDE/OFDM单次 | |
| `eq_mmse_tv_fde` | V1 | 时变MMSE-FDE | SC-FDE时变 | 构建ICI矩阵+MMSE求逆 |
| `eq_bem_turbo_fde` | V1 | BEM-Turbo迭代ICI消除FDE | OFDM/SC-FDE时变 | |
| `eq_ofdm_zf` | V1 | 频域ZF | OFDM | 噪声放大, 仅高SNR |
| `eq_otfs_mp` | V3 | OTFS消息传递均衡 | OTFS | 高斯近似BP |
| `eq_otfs_mp_simplified` | V1 | OTFS简化MP | OTFS | MMSE低复杂度近似 |
| `eq_ptrm` | V1 | PTR被动时反转 | 多通道聚焦 | |

### ⑤ 工具函数（6个）

| 函数 | 功能 |
|------|------|
| `build_scattered_obs` | 从帧结构(训练+散布导频)构建BEM观测矩阵 |
| `soft_demapper` | 均衡输出→LLR |
| `soft_mapper` | LLR→软符号+方差 |
| `llr_to_symbol` | LLR软信息→软符号估计（译码器→均衡器接口） |
| `symbol_to_llr` | 均衡后符号→LLR软信息（均衡器→译码器接口） |
| `interference_cancel` | 干扰消除（从接收信号减去已知干扰分量） |

## 验证结果 (test_channel_est_eq.m V2, 24项测试全通过)

### 时变信道估计 — 散布导频 vs 仅训练（fd=5Hz, SNR=15dB）

| 方法 | 仅训练 | 散布导频 | 增益 |
|------|--------|---------|------|
| BEM(CE) | 2.2dB | -9.6dB | +11.8dB |
| **BEM(DCT)** | 2.3dB | **-19.4dB** | **+21.7dB** |
| DD-BEM | 0.2dB | -13.9dB | +14.1dB |

**散布导频是精度决定性因素，BEM(DCT)+散布导频最优**

### 时变均衡（RRC过采样+gen_uwa_channel+散布导频BEM+Turbo BCJR）

| 条件 | oracle | BEM(CE) | BEM(DCT) | DD-BEM |
|------|--------|---------|----------|--------|
| fd≤5Hz 5dB+ | 0% | 0% | 0% | 0% |
| fd=10Hz 5dB | 0.3% | 4.4% | **1.2%** | 9.0% |

### Turbo TDE vs FDE（同一6径信道）

| SNR | TDE iter6 | FDE iter1 |
|-----|-----------|-----------|
| 0dB | 34.6% | **21.1%** |
| 5dB | 0.6% | **0%** |

**长时延信道下FDE全面优于TDE（5dB编码增益优势）**

### 均衡器调试要点

| 要点 | 说明 |
|------|------|
| DFE+PLL | 静态信道必须关PLL，否则发散 |
| DFE λ | 0.998→0.9995，防长序列遗忘 |
| DFE h_est | 不传h_est，纯RLS训练更稳定 |
| BiDFE | 单侧训练时需前向输出作后向伪训练 |
| 抽头数 | 甜点=4×信道长度，过多过少均降性能 |

## 测试文件

| 文件 | 版本 | 内容 |
|------|------|------|
| `test_channel_est_eq.m` | **V2** | **统一测试(24项+6图)**: 静态估计/时变估计/均衡器SNR-SER/Turbo TDE-FDE/时变均衡 |

## 依赖关系

- 模块02 `siso_decode_conv`（Turbo内部）
- 模块03 `random_interleave`（Turbo内部）
- 模块09 `pulse_shape`/`match_filter`（RRC过采样）
- 模块12 `turbo_equalizer_sctde` / `turbo_equalizer_scfde_crossblock`（Turbo均衡）
- 模块13 `gen_uwa_channel`（时变信道生成）
- 被模块12/13调用
