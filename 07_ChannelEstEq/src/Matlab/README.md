# 信道估计与均衡模块 (ChannelEstEq)

接收链路核心模块，提供10种信道估计算法、8种基础均衡器、3种Turbo均衡接口和2种时变信道均衡器，覆盖SC-TDE/SC-FDE/OFDM/OTFS四种体制。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `ch_est_ls` | LS最小二乘信道估计 | Y_freq, X_pilot | H_est |
| `ch_est_mmse` | MMSE信道估计（噪声正则化） | Y_freq, X_pilot, noise_var | H_est |
| `ch_est_omp` | OMP正交匹配追踪（自适应稀疏度） | Y_freq, A, K | H_est |
| `ch_est_sbl` | SBL稀疏贝叶斯学习 | Y_freq, A | H_est |
| `ch_est_gamp` | GAMP广义AMP（伯努利-高斯先验，SC-TDE推荐） | Y_freq, A | H_est |
| `ch_est_vamp` | VAMP变分AMP（BG去噪+EM自适应） | Y_freq, A | H_est |
| `ch_est_turbo_vamp` | Turbo-VAMP（标准VAMP+积极EM） | Y_freq, A, K | H_est |
| `ch_est_ws_turbo_vamp` | WS-Turbo-VAMP（热启动，利用前帧先验） | Y_freq, A, K, prior | H_est |
| `eq_dfe` | RLS自适应DFE均衡器（含PLL+h_est初始化，V3.1） | y, h_est, training | LLR_out, x_hat, noise_var_est |
| `eq_linear_rls` | 线性RLS均衡器（DFE反馈阶=0） | y, h_est, training | LLR_out, x_hat |
| `eq_mmse_fde` | MMSE频域均衡（非迭代版） | Y_freq, H_est, noise_var | x_hat |
| `eq_ofdm_zf` | ZF迫零均衡 | Y_freq, H_est | x_hat |
| `eq_mmse_ic_fde` | 迭代MMSE-IC频域均衡器（Turbo均衡核心） | Y_freq, H_est, x_bar, var_x, noise_var | x_tilde, mu, nv_tilde |
| `soft_demapper` | 均衡输出转编码比特外信息LLR | x_tilde, mu, nv_tilde, La_eq | Le_eq |
| `soft_mapper` | 后验LLR转软符号和残余方差 | L_posterior | x_bar, var_x |
| `eq_mmse_tv_fde` | 时变信道MMSE频域均衡（ICI矩阵求逆） | Y_freq, h_time_block, delays_sym, N_fft, noise_var | x_hat, H_tv |
| `eq_bem_turbo_fde` | BEM-Turbo迭代ICI消除频域均衡器 | Y_freq, h_time_block, delays_sym, N_fft, noise_var, codec_params | bits_out, iter_info |
| `eq_ptrm` | PTR被动时反转（多通道空间聚焦） | R_array, h_est | y_out |
| `eq_bidirectional_dfe` | 双向DFE（减少误差传播） | y, h_est, training | x_hat |

## 使用示例

```matlab
% SC-TDE: GAMP信道估计 + DFE均衡（V3.1，h_est初始化）
h_est = ch_est_gamp(Y_pilot, A_matrix);
[LLR, x_hat, nv] = eq_dfe(rx, h_est, training, 21, 10, 0.998);

% SC-FDE Turbo均衡: MMSE-IC + soft_demapper + soft_mapper
[x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var);
Le_eq = soft_demapper(x_tilde, mu, nv_tilde, La_eq, 'qpsk');
[x_bar, var_x] = soft_mapper(L_posterior, 'qpsk');

% 时变信道: BEM-Turbo迭代ICI消除
[bits, info] = eq_bem_turbo_fde(Y_freq, h_tv_block, delays, N_fft, nv, codec);
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- `ch_est_amp.m` — AMP近似消息传递（GAMP/VAMP更通用）
- `ch_est_turbo_amp.m` — Turbo-AMP（Turbo-VAMP更优）
- `ch_est_otfs_dd.m` — OTFS DD域嵌入导频信道估计
- `eq_lms.m` — LMS自适应均衡器（收敛慢，RLS更优）
- `eq_rls.m` — RLS自适应均衡器（eq_dfe已含RLS+PLL）
- `eq_otfs_mp.m` — OTFS MP消息传递均衡（完整高斯BP）
- `eq_otfs_mp_simplified.m` — OTFS MP简化版（MMSE+SIC）
- `interference_cancel.m` — 干扰消除（旧版简单减法）
- `llr_to_symbol.m` — LLR转软符号（向后兼容，soft_mapper更完整）
- `symbol_to_llr.m` — 符号转LLR（基础版，soft_demapper更完整）
- `gen_test_channel.m` — 简化多径信道模型（测试用）
- `plot_channel_estimate.m` — 信道估计对比四格图
- `plot_equalizer_output.m` — 均衡结果星座图+BER对比
- `plot_eq_convergence.m` — 均衡器收敛曲线可视化（滑动窗MSE/BER）
- `test_channel_est_eq.m` — 单元测试（16项，覆盖信道估计+均衡+异常输入）
- `test_tv_eq.m` — 时变信道估计+均衡测试（oracle/GAMP固定/GAMP+Kalman对比）

## 依赖关系

- 依赖模块02 (ChannelCoding) 的 `siso_decode_conv`、`conv_encode`（eq_bem_turbo_fde内部调用）
- 依赖模块03 (Interleaving) 的 `random_interleave`、`random_deinterleave`（eq_bem_turbo_fde内部调用）
