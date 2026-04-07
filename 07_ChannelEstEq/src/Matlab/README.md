# 信道估计与均衡模块 (ChannelEstEq)

接收链路核心模块，负责从接收信号中估计水声信道并恢复发送符号。覆盖静态/时变信道估计、多种均衡器架构和Turbo迭代均衡。

## 模块架构

```
                    ┌─────────────────────────────────────────┐
                    │         07 信道估计与均衡模块             │
                    ├─────────────────────────────────────────┤
                    │                                         │
                    │  ① 信道估计（CIR恢复）                   │
                    │  ┌─────────────────────────────────┐   │
                    │  │ 经典方法: ch_est_ls / ch_est_mmse│   │
                    │  │ 稀疏恢复: ch_est_omp / ch_est_sbl│   │
                    │  │ 消息传递: ch_est_gamp / ch_est_vamp│  │
                    │  │ Turbo:   ch_est_turbo_vamp      │   │
                    │  │ 热启动:  ch_est_ws_turbo_vamp   │   │
                    │  └──────────────┬──────────────────┘   │
                    │                 │ h_est                 │
                    │                 ▼                       │
                    │  ② 信道跟踪（时变信道）                   │
                    │  ┌─────────────────────────────────┐   │
                    │  │ BEM基扩展: eq_bem_turbo_fde      │   │
                    │  │ Kalman跟踪: (test_ch_est_tv.m)  │   │
                    │  │ DD判决引导: 软判决→重估H          │   │
                    │  │ RLS自适应: eq_dfe内部跟踪        │   │
                    │  └──────────────┬──────────────────┘   │
                    │                 │ h_est(n) 时变         │
                    │                 ▼                       │
                    │  ③ 均衡器（ISI消除+符号恢复）             │
                    │  ┌─────────────────────────────────┐   │
                    │  │ 线性: eq_mmse_fde / eq_ofdm_zf  │   │
                    │  │ DFE:  eq_dfe / eq_bidirectional_dfe│  │
                    │  │ 自适应: eq_rls / eq_lms          │   │
                    │  │ 频域IC: eq_mmse_ic_fde (Turbo核心)│  │
                    │  │ 时变:  eq_mmse_tv_fde           │   │
                    │  │ BEM:   eq_bem_turbo_fde         │   │
                    │  │ PTR:   eq_ptrm (多通道聚焦)      │   │
                    │  └──────────────┬──────────────────┘   │
                    │                 │ x_hat / LLR          │
                    │                 ▼                       │
                    │  ④ 软信息接口（Turbo迭代）               │
                    │  ┌─────────────────────────────────┐   │
                    │  │ soft_demapper: x_tilde→LLR       │   │
                    │  │ soft_mapper:  LLR→x_bar, var_x  │   │
                    │  └─────────────────────────────────┘   │
                    └─────────────────────────────────────────┘
```

## 对外接口

### ① 信道估计（静态CIR恢复）

| 函数 | 方法 | 输入 | 输出 | 适用场景 |
|------|------|------|------|---------|
| `ch_est_ls` | LS最小二乘 | Y, X, N | H_est, h_est | 高SNR，无先验 |
| `ch_est_mmse` | MMSE正则化 | Y, X, N, σ² | H_est, h_est | 中低SNR，已知噪声 |
| `ch_est_omp` | OMP稀疏恢复 | y, Φ, N, K | h_est | 稀疏信道，欠定系统 |
| `ch_est_sbl` | SBL贝叶斯学习 | y, Φ, N | h_est, γ | 自动稀疏度 |
| `ch_est_gamp` | GAMP消息传递 | y, Φ, N, σ² | h_est | **SC-TDE推荐** |
| `ch_est_vamp` | VAMP变分AMP | y, Φ, N, σ², K | h_est | 高精度 |
| `ch_est_turbo_vamp` | Turbo-VAMP+EM | y, Φ, N, K, σ² | h_est | **最优精度，静态首选** |
| `ch_est_ws_turbo_vamp` | 热启动Turbo-VAMP | y, Φ, N, K, σ², prior | h_est | 利用前帧先验 |

### ② 信道跟踪（时变信道）

| 函数/方法 | 原理 | 适用场景 | 状态 |
|----------|------|---------|------|
| BEM+导频估计 | CE-BEM基扩展+散布导频→LS | 多普勒已知 | `eq_bem_turbo_fde`内嵌 |
| Kalman跟踪 | AR(1)状态空间+逐符号更新 | 已知符号驱动 | `test_ch_est_tv.m`验证 |
| DD判决引导 | 软判决→频域LS重估 | Turbo iter2+ | 端到端测试内嵌 |
| RLS自适应 | 遗忘因子+逐符号权重更新 | 在线自适应 | `eq_dfe`内嵌 |

### ③ 均衡器

| 函数 | 类型 | 输入 | 输出 | 适用场景 |
|------|------|------|------|---------|
| `eq_mmse_fde` | 频域MMSE线性 | Y, H, σ² | x_hat | SC-FDE/OFDM单次 |
| `eq_ofdm_zf` | 频域ZF | Y, H | X_hat | 高SNR |
| `eq_dfe` | RLS-DFE+PLL(V3.1) | y, h_est, train | LLR, x_hat | **SC-TDE核心，h_est初始化** |
| `eq_bidirectional_dfe` | 双向DFE | y, h_est, train | LLR, x_hat | 抑制DFE误差传播 |
| `eq_linear_rls` | 线性RLS(DFE fb=0) | y, train | LLR, x_hat | Turbo iter1备选 |
| `eq_rls` | RLS居中延迟 | y, train | x_hat | 非因果LE |
| `eq_mmse_ic_fde` | **LMMSE-IC迭代(Turbo核心)** | Y, H, x̄, var_x, σ² | x̃, μ, σ̃² | **SC-FDE/OFDM/SC-TDE Turbo** |
| `eq_mmse_tv_fde` | 时变MMSE(ICI矩阵) | Y, h_tv, delays | x_hat | 时变频域 |
| `eq_bem_turbo_fde` | BEM-Turbo ICI消除 | Y, h_tv, delays | bits_out | 时变+编码 |
| `eq_ptrm` | PTR被动时反转 | R_array, h | y_out | 多通道聚焦 |

### ④ 软信息接口

| 函数 | 功能 | 调用位置 |
|------|------|---------|
| `soft_demapper` | 均衡输出→编码比特LLR | Turbo迭代：均衡→译码 |
| `soft_mapper` | 后验LLR→软符号+残余方差 | Turbo迭代：译码→均衡 |

## 使用示例

```matlab
%% 静态信道：GAMP估计 + DFE均衡
T_mat = toeplitz_matrix(training, L_h);  % Toeplitz观测矩阵
[h_gamp, ~] = ch_est_gamp(rx_train, T_mat, L_h, 50, noise_var);
[LLR, x_hat, nv] = eq_dfe(rx, h_gamp, training, 31, 90, 0.998, pll);

%% SC-FDE/OFDM Turbo均衡
[x_tilde, mu, nv_t] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var);
Le_eq = soft_demapper(x_tilde, mu, nv_t, zeros(1,M), 'qpsk');
% → BCJR → soft_mapper → 下一轮

%% 时变信道：BEM+散布导频
% 帧: [训练|数据|导频|数据|导频|...|数据|尾导频]
% CE-BEM: h_p(n) = Σ_q c_pq·b_q(n), Q=2⌈fd·T⌉+3
c_bem = (Phi'*Phi + σ²I) \ (Phi'*y_obs);
% 重构每块H_est → eq_mmse_ic_fde
```

## 信道估计方法对比（SC-TDE静态，Turbo_DFE×6次）

| 方法 | 0%BER起点 | -3dB BER | 推荐度 |
|------|----------|---------|--------|
| Oracle | 0dB | 12.91% | 基准(不可用于端到端) |
| MMSE | 3dB | 38.99% | 不推荐 |
| OMP | 0dB | 13.76% | ★★ |
| **GAMP** | **0dB** | **12.96%** | **★★★ 推荐** |
| VAMP | 0dB | 13.26% | ★★★ |
| **Turbo-VAMP** | **0dB** | **10.41%** | **★★★ 最优** |

## 时变信道处理方案

| 方案 | 原理 | fd=5Hz 10dB | fd=1Hz 20dB | 状态 |
|------|------|------------|------------|------|
| 固定h_est | 训练段一次估计 | ~48% | ~47% | 不可用 |
| BEM+散布导频 | CE-BEM基扩展+前后导频包围 | **0%** | **0.95%** | 验证中 |
| BEM+DD精化 | BEM初始+Turbo DD更新 | 0% | 0.95% | 提升有限 |
| Oracle | 每块真实h(n) | 0% | 0% | 对比基准 |

## 内部函数

- `ch_est_amp.m` — AMP（GAMP/VAMP更通用）
- `ch_est_turbo_amp.m` — Turbo-AMP（Turbo-VAMP更优）
- `ch_est_otfs_dd.m` — OTFS DD域导频信道估计
- `eq_lms.m` — LMS自适应（RLS更优）
- `eq_otfs_mp.m` — OTFS MP消息传递均衡
- `eq_otfs_mp_simplified.m` — OTFS MP简化版
- `interference_cancel.m` — 干扰消除（旧版）
- `llr_to_symbol.m` — LLR→符号（向后兼容）
- `symbol_to_llr.m` — 符号→LLR（基础版）
- `gen_test_channel.m` — 测试用信道模型
- `plot_*.m` — 可视化工具（3个）
- `test_channel_est_eq.m` — 单元测试（16项）
- `test_tv_eq.m` — 时变均衡测试（FDE分块+BEM+DD对比）
- `test_ch_est_tv.m` — 时变信道估计NMSE独立评价

## 依赖关系

- 依赖模块02 `siso_decode_conv`、`conv_encode`（eq_bem_turbo_fde/Turbo内部）
- 依赖模块03 `random_interleave`、`random_deinterleave`（Turbo内部）
- 被模块12 (IterativeProc) 调用：turbo_equalizer_*调用eq_mmse_ic_fde/eq_dfe/soft_*
- 被模块13 (SourceCode) 端到端测试调用：ch_est_gamp + eq_mmse_ic_fde
