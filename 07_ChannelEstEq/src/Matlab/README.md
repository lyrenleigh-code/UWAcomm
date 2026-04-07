# 信道估计与均衡模块 (ChannelEstEq)

接收链路核心模块，覆盖静态/时变信道估计、信道跟踪、多种均衡器和Turbo迭代软信息接口。

## 模块架构

```
① 静态信道估计（单快照CIR恢复）     ← 11个函数
② 时变信道估计（多快照/参数化）      ← 3个函数(新增)
③ 信道跟踪（逐符号更新）            ← 2个函数(新增)
④ 均衡器（ISI消除+符号恢复）        ← 13个函数
⑤ 软信息接口（Turbo迭代）           ← 2个函数
```

## 对外接口

### ① 静态信道估计（11个，已完成）

| 函数 | 方法 | 先验需求 | 推荐度 |
|------|------|---------|--------|
| `ch_est_ls` | LS最小二乘 | 无 | 基线 |
| `ch_est_mmse` | MMSE正则化 | σ² | ★★ |
| `ch_est_omp` | OMP稀疏恢复 | K(稀疏度) | ★★ |
| `ch_est_sbl` | SBL贝叶斯 | 自动 | ★★ |
| `ch_est_gamp` | GAMP消息传递 | σ² | **★★★ SC-TDE推荐** |
| `ch_est_vamp` | VAMP变分AMP | K, σ² | ★★★ |
| `ch_est_turbo_vamp` | Turbo-VAMP+EM | K, σ² | **★★★ 最优精度** |
| `ch_est_ws_turbo_vamp` | 热启动Turbo-VAMP | K, σ², prior | ★★★ |
| `ch_est_amp` | AMP(内部) | — | — |
| `ch_est_turbo_amp` | Turbo-AMP(内部) | — | — |
| `ch_est_otfs_dd` | OTFS DD域导频 | — | OTFS专用 |

### ② 时变信道估计（3个，新增）

| 函数 | 方法 | 先验需求 | NMSE(fd=5Hz) | 说明 |
|------|------|---------|-------------|------|
| `ch_est_bem` | **BEM基扩展** | fd, σ² | **-15.9dB** | CE/P/DCT三种基，散布导频，**最优** |
| `ch_est_tsbl` | T-SBL时序稀疏贝叶斯 | α_ar | 调试中 | 多快照联合稀疏+时间相关 |
| `ch_est_sage` | SAGE/EM参数估计 | K(径数) | 时延精确 | 高分辨率时延/增益/多普勒 |

### ③ 信道跟踪（2个，新增）

| 函数 | 方法 | 输入 | NMSE(fd=5Hz) | 说明 |
|------|------|------|-------------|------|
| `ch_track_kalman` | 稀疏Kalman AR(1) | h_init+参考符号 | 调优中 | α=0.5^(4fd/fs), K_target=5% |
| `ch_track_rls`⬜ | RLS遗忘因子 | — | — | 待开发 |

### ④ 均衡器（13个）

| 函数 | 类型 | 适用体制 |
|------|------|---------|
| `eq_dfe` V3.1 | RLS-DFE+PLL+h_est初始化 | **SC-TDE** |
| `eq_bidirectional_dfe` | 双向DFE | SC-TDE(抗误差传播) |
| `eq_linear_rls` | 线性RLS(DFE fb=0) | Turbo iter1备选 |
| `eq_rls` | RLS居中延迟 | 非因果LE |
| `eq_mmse_fde` | 频域MMSE | SC-FDE/OFDM单次 |
| `eq_ofdm_zf` | 频域ZF | 高SNR |
| `eq_mmse_ic_fde` | **LMMSE-IC迭代** | **SC-FDE/OFDM Turbo核心** |
| `eq_mmse_tv_fde` | 时变MMSE(ICI矩阵) | 时变频域 |
| `eq_bem_turbo_fde` | BEM-Turbo ICI消除 | 时变+编码 |
| `eq_ptrm` | PTR被动时反转 | 多通道聚焦 |
| `eq_lms` | LMS自适应 | 简单场景 |
| `eq_otfs_mp` | OTFS MP消息传递 | OTFS |
| `eq_otfs_mp_simplified` | OTFS MP简化版 | OTFS |

### ⑤ 软信息接口

| 函数 | 功能 |
|------|------|
| `soft_demapper` | 均衡输出→编码比特LLR |
| `soft_mapper` | 后验LLR→软符号+残余方差 |

## 使用示例

```matlab
%% 静态: Turbo-VAMP + DFE
T_mat = toeplitz_matrix(training, L_h);
[h_est,~,~,~] = ch_est_turbo_vamp(rx_train, T_mat, L_h, 30, K, noise_var);
[LLR, x_hat, nv] = eq_dfe(rx, h_est, training, 31, 90, 0.998, pll);

%% 时变: BEM + LMMSE-IC
[h_tv, c, info] = ch_est_bem(y_obs, x_known, obs_times, N, delays, fd, fs, nv, 'ce');
% 每块H_est → eq_mmse_ic_fde → soft_demapper → BCJR → soft_mapper

%% 信道跟踪: Kalman
[h_tracked, P, info] = ch_track_kalman(rx, x_ref, delays, h_init, fd, fs, nv);

%% 参数估计: SAGE
[params, h_est, info] = ch_est_sage(rx, training, fs, K, 20, [0 100], [-10 10]);
```

## 信道估计性能对比

### 静态（SC-TDE, Turbo_DFE×6, SNR=0dB起无误码）

| 方法 | 0%BER起点 | -3dB BER |
|------|----------|---------|
| Oracle | 0dB | 12.91% |
| **GAMP** | **0dB** | **12.96%** |
| **Turbo-VAMP** | **0dB** | **10.41%** |

### 时变NMSE（fd=5Hz, SNR=15dB）

| 方法 | NMSE | 说明 |
|------|------|------|
| **BEM(CE)** | **-15.9dB** | Q=9, 散布导频+前后包围 |
| BEM(DCT) | -7.3dB | 边界好但整体弱 |
| Kalman | 调优中 | 增益K_target=5% |
| GAMP(固定) | 0.1dB | 时变下无效 |

## 测试文件

| 文件 | 覆盖内容 |
|------|---------|
| `test_channel_est_eq.m` | 16项单元测试（静态估计+均衡+异常输入） |
| `test_tv_eq.m` | 时变均衡对比（FDE分块+BEM+DD, oracle基线） |
| `test_tv_ch_est.m` | **时变信道估计NMSE对比（BEM/Kalman/T-SBL/SAGE, 幅度+相位可视化）** |

## 依赖关系

- 依赖模块02 `siso_decode_conv`（eq_bem_turbo_fde内部）
- 依赖模块03 `random_interleave`（Turbo内部）
- 被模块12调用：turbo_equalizer_*
- 被模块13调用：端到端测试
