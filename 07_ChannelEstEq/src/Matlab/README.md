# 信道估计与均衡模块 (ChannelEstEq)

接收链路核心模块，覆盖静态/时变信道估计、信道跟踪、均衡器和Turbo迭代软信息接口。

## 对外接口

### ① 静态信道估计（11个）

| 函数 | 方法 | 推荐度 |
|------|------|--------|
| `ch_est_ls` | LS最小二乘 | 基线 |
| `ch_est_mmse` | MMSE正则化 | ★★ |
| `ch_est_omp` | OMP稀疏恢复 | ★★ |
| `ch_est_sbl` | SBL贝叶斯 | ★★ |
| `ch_est_gamp` | GAMP消息传递 | **★★★ 推荐** |
| `ch_est_vamp` | VAMP变分AMP | ★★★ |
| `ch_est_turbo_vamp` | Turbo-VAMP+EM | **★★★ 最优** |
| `ch_est_ws_turbo_vamp` | 热启动Turbo-VAMP | ★★★ |

### ② 时变信道估计（3个）

| 函数 | 方法 | 说明 |
|------|------|------|
| `ch_est_bem` V1 | **BEM基扩展(CE/P/DCT)** | 散布导频→MMSE-LS, **fd=5Hz NMSE≈0dB, 均衡后BER=0%** |
| `ch_est_tsbl` V2 | T-SBL时序稀疏贝叶斯 | 多快照联合稀疏+时间相关 |
| `ch_est_sage` V1 | SAGE/EM参数估计 | 高分辨率时延/增益/多普勒 |

### ③ 信道跟踪（1个）

| 函数 | 方法 | 说明 |
|------|------|------|
| `ch_track_kalman` V1 | 稀疏Kalman AR(1) | α=0.5^(4fd/fs), K_target=5% |

### ④ 均衡器（13个）

| 函数 | 类型 | 适用体制 |
|------|------|---------|
| `eq_dfe` V3.1 | RLS-DFE+PLL+h_est初始化 | SC-TDE |
| `eq_mmse_ic_fde` | **LMMSE-IC迭代** | **SC-FDE/OFDM/时变SC-TDE Turbo核心** |
| `eq_mmse_fde` | 频域MMSE | SC-FDE/OFDM单次 |
| `eq_bidirectional_dfe` | 双向DFE | 抗误差传播 |
| `eq_rls` | RLS居中延迟 | 非因果LE |
| `eq_bem_turbo_fde` | BEM-Turbo ICI消除 | 时变+编码 |
| `eq_ptrm` | PTR被动时反转 | 多通道聚焦 |

### ⑤ 软信息接口

| 函数 | 功能 |
|------|------|
| `soft_demapper` | 均衡输出→LLR |
| `soft_mapper` | LLR→软符号+方差 |

## 验证结果

### 时变均衡（test_tv_eq.m V3, RRC过采样+gen_uwa_channel+分块LMMSE-IC）

| 条件 | oracle | BEM(CE) |
|------|--------|---------|
| static 全SNR | 0% | 0% |
| fd=1Hz 全SNR | 0% | 0% |
| fd=5Hz 5dB+ | 0% | 0% |

### 静态信道估计对比（SC-TDE Turbo_DFE×6, SNR=0dB起无误码）

| 方法 | 0%起点 | -3dB BER | 推荐 |
|------|--------|---------|------|
| GAMP | 0dB | 12.96% | ★★★ |
| Turbo-VAMP | 0dB | 10.41% | ★★★ |

## 测试文件

| 文件 | 内容 |
|------|------|
| `test_tv_eq.m` V3 | **时变均衡**: oracle vs BEM(CE), RRC+gen_uwa_channel+分块LMMSE-IC |
| `test_tv_ch_est.m` | **信道估计NMSE**: BEM(CE/P/DCT)/Kalman/T-SBL/SAGE, 幅度+相位可视化 |
| `test_channel_est_eq.m` | 单元测试（16项，静态估计+均衡+异常输入） |

## 依赖关系

- 模块02 `siso_decode_conv`（Turbo内部）
- 模块03 `random_interleave`（Turbo内部）
- 模块09 `pulse_shape`/`match_filter`（test_tv_eq RRC过采样）
- 模块13 `gen_uwa_channel`（test_tv_eq信道生成）
- 被模块12/13调用
