# 信道估计与均衡模块 (ChannelEstEq)

接收链路核心模块，覆盖静态/时变/OTFS 信道估计、信道跟踪、时域/频域/OTFS 均衡器、Turbo 迭代软信息接口。共 48 个文件（2026-04-17 统计）：40 个对外函数（含 3 个 OTFS 专用估计器 + 1 个 TV FDE 均衡器的 IC 版） + 3 个可视化 + 2 个测试 + 3 个辅助。

---

## 对外接口

### 1 静态信道估计（10个）

| 函数 | 签名 | 说明 |
|------|------|------|
| `ch_est_ls` | `[H_est, h_est] = ch_est_ls(Y_pilot, X_pilot, N, pilot_indices)` | LS最小二乘，频域导频处直接相除 |
| `ch_est_mmse` | `[H_est, h_est] = ch_est_mmse(Y_pilot, X_pilot, N, noise_var, pilot_indices)` | MMSE正则化，利用噪声方差抑制噪声增强 |
| `ch_est_omp` | `[h_est, H_est, support] = ch_est_omp(y, Phi, N, K_sparse, noise_var)` | OMP正交匹配追踪，稀疏恢复 |
| `ch_est_sbl` | `[h_est, H_est, gamma] = ch_est_sbl(y, Phi, N, max_iter, tol)` | SBL稀疏贝叶斯学习 |
| `ch_est_gamp` | `[h_est, H_est] = ch_est_gamp(y, Phi, N, max_iter, noise_var)` | GAMP广义近似消息传递 |
| `ch_est_amp` | `[h_est, H_est, mse_history] = ch_est_amp(y, Phi, N, max_iter, damping)` | AMP近似消息传递 |
| `ch_est_vamp` | `[h_est, H_est, mse_history] = ch_est_vamp(y, Phi, N, max_iter, noise_var, K_sparse)` | VAMP变分近似消息传递 |
| `ch_est_turbo_vamp` | `[h_est, H_est, mse_history, rho_out] = ch_est_turbo_vamp(y, Phi, N, max_iter, K_sparse, noise_var)` | Turbo-VAMP + BG先验 + EM自适应 |
| `ch_est_turbo_amp` | `[h_est, H_est, mse_history] = ch_est_turbo_amp(y, Phi, N, max_iter, K_sparse)` | Turbo-AMP，伯努利-高斯先验 |
| `ch_est_ws_turbo_vamp` | `[h_est, H_est, mse_history, rho_out] = ch_est_ws_turbo_vamp(y, Phi, N, max_iter, K_sparse, noise_var, rho_prev, beta)` | 热启动Turbo-VAMP，利用前帧支撑概率 |

#### 静态估计参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `y` / `Y_pilot` | 复数向量 | 观测向量（时域Mx1）或频域导频值（1xP） |
| `Phi` / `X_pilot` | 矩阵 | 测量矩阵（MxN，如Toeplitz/部分DFT）或频域导频发送值 |
| `N` | 正整数 | 信道长度 / FFT点数 |
| `K_sparse` | 正整数 | 稀疏度上限，默认 `ceil(N/10)` |
| `noise_var` | 正实数 | 噪声方差，部分算法可自动估计 |
| `max_iter` | 正整数 | 最大迭代次数（SBL/GAMP默认100，Turbo-VAMP默认50） |
| `pilot_indices` | 1xP向量 | 导频子载波索引，LS/MMSE可选 |
| `rho_prev` | Nx1向量 | WS-Turbo-VAMP热启动用前帧后验支撑概率 |
| `beta` | 0~1标量 | WS-Turbo-VAMP时间相关系数，默认0.6 |

### 2 时变信道估计（4个）

| 函数 | 签名 | 说明 |
|------|------|------|
| `ch_est_bem` | `[h_tv, c_bem, info] = ch_est_bem(y_obs, x_known, obs_times, N_total, delays, fd_est, sym_rate, noise_var, bem_type, options)` | BEM基扩展时变估计，支持CE/DCT基，V2向量化 |
| `ch_est_bem_dd` | `[h_tv, info] = ch_est_bem_dd(rx, training, sym_delays, fd_est, sym_rate, noise_var, h_init, dd_opts)` | 判决辅助迭代BEM(DD-BEM)，FDE均衡→硬判决→扩展导频→重估 |
| `ch_est_tsbl` | `[H_tv, h_snapshots, gamma_tv, info] = ch_est_tsbl(Y_multi, Phi, N, T, max_iter, tol, alpha_ar)` | T-SBL时序稀疏贝叶斯，多快照联合稀疏+AR(1)时间相关 |
| `ch_est_sage` | `[params, h_est, info] = ch_est_sage(y, x_ref, fs, K_paths, max_iter, delay_range, doppler_range)` | SAGE/EM高分辨率参数估计，输出时延/增益/多普勒 |

#### 时变估计参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `y_obs` | Mx1复数 | 导频位置接收值 |
| `x_known` | MxP矩阵 | 导频位置已知发送符号（M个导频 x P条径） |
| `obs_times` | Mx1整数 | 导频在帧中的时刻索引（1-based） |
| `N_total` | 正整数 | 帧总符号数 |
| `delays` | 1xP向量 | 各径符号级时延 |
| `fd_est` | 正实数(Hz) | 估计的最大多普勒频率 |
| `sym_rate` | 正实数(Hz) | 符号率 |
| `bem_type` | 字符串 | BEM基函数类型：`'ce'`(复指数) / `'dct'`(离散余弦) |
| `dd_opts` | 结构体 | DD-BEM选项：`.num_iter`(默认3), `.dd_step`(默认3), `.bem_type`(默认'ce') |
| `Y_multi` | MxT矩阵 | T-SBL多快照观测 |
| `alpha_ar` | 0~1标量 | T-SBL的AR(1)相关系数，默认0.95 |
| `delay_range` | 1x2向量 | SAGE时延搜索范围 [min max]（采样点） |
| `doppler_range` | 1x2向量 | SAGE多普勒搜索范围 [min max]（Hz） |

### 3 OTFS信道估计（3个）

| 函数 | 签名 | 说明 |
|------|------|------|
| `ch_est_otfs_dd` | `[h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M)` | DD域嵌入导频信道估计，提取稀疏路径参数 |
| `ch_est_otfs_zc` | `[h_dd, info] = ch_est_otfs_zc(Y_dd, pilot_cfg, N, M)` | ZC 序列导频的 DD 信道估计（B 方案，降 PAPR 9dB，见 2026-04-13 OTFS PAPR 决策）|
| `ch_est_otfs_superimposed` | `[h_dd, info] = ch_est_otfs_superimposed(Y_dd, pilot_cfg, N, M)` | 叠加导频估计（C 方案，导频和数据共享同一 DD 网格，能效最优） |

#### OTFS估计参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `Y_dd` | NxM复数矩阵 | 接收DD域帧 |
| `pilot_info` | 结构体 | 导频信息（由 `otfs_pilot_embed` 生成） |
| `N` | 正整数 | 多普勒格点数 |
| `M` | 正整数 | 时延格点数 |
| `path_info` | 结构体数组 | 输出：`.delay_idx`, `.doppler_idx`, `.gain`, `.num_paths` |

### 4 信道跟踪（1个）

| 函数 | 签名 | 说明 |
|------|------|------|
| `ch_track_kalman` | `[h_tracked, P_cov, info] = ch_track_kalman(y, x_ref, delays, h_init, fd_hz, sym_rate, noise_var, opts)` | 稀疏Kalman AR(1)逐符号跟踪 |

#### 跟踪参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `y` | 1xN复数 | 接收信号序列 |
| `x_ref` | 1xN复数 | 参考符号（已知或软判决） |
| `delays` | 1xP向量 | 各径符号级时延 |
| `h_init` | 1xP复数 | 初始信道增益 |
| `fd_hz` | 正实数(Hz) | 最大多普勒频率 |
| `opts.alpha` | 标量 | AR(1)系数，默认自动 `J_0(2*pi*fd/fs)` |
| `opts.q_proc` | 标量 | 过程噪声方差，默认 `(1-alpha^2)*mean(abs(h_init)^2)` |
| `opts.K_target` | 标量 | 稀疏修剪阈值比例，默认5% |

### 5 TDE均衡器（时域，6个）

| 函数 | 签名 | 说明 |
|------|------|------|
| `eq_rls` | `[x_hat, w_final, mse_history] = eq_rls(y, training, lambda, num_taps, data_len)` | RLS居中延迟自适应均衡，抽头甜点=4xL_h |
| `eq_lms` | `[x_hat, w_final, mse_history] = eq_lms(y, training, mu, num_taps, data_len)` | LMS自适应均衡 |
| `eq_linear_rls` | `[LLR_out, x_hat, noise_var_est] = eq_linear_rls(y, training, num_taps, lambda_rls, pll_params)` | RLS线性均衡+PLL，Turbo iter1用，输出LLR |
| `eq_dfe` | `[LLR_out, x_hat, noise_var_est] = eq_dfe(y, h_est, training, num_ff, num_fb, lambda_rls, pll_params)` | RLS-DFE+PLL+LLR输出，V3.1 |
| `eq_bidirectional_dfe` | `[LLR_out, x_hat, noise_var_est] = eq_bidirectional_dfe(y, h_est, training, num_ff, num_fb, lambda_rls, pll_params)` | 双向DFE，前向+后向联合判决抑制错误传播 |
| `eq_rake` | `[x_hat, w] = eq_rake(y, h_est, delays)` | Rake 合并器，DSSS 多径能量捕获 |

#### TDE均衡器参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `y` | 1xN复数 | 接收信号（训练段+数据段） |
| `training` | 1xT复数 | 已知训练序列 |
| `lambda` / `lambda_rls` | 0~1标量 | RLS遗忘因子，建议0.9995（长序列防遗忘） |
| `mu` | 正实数 | LMS步长，默认0.01 |
| `num_taps` / `num_ff` | 正整数 | 前馈滤波器阶数，最优=4x信道长度 |
| `num_fb` | 正整数 | 反馈滤波器阶数，建议=max(delays) |
| `h_est` | 1xL复数 | 信道估计（DFE初始化用，可选；不传则纯RLS训练） |
| `pll_params` | 结构体 | `.enable`(bool), `.Kp`(默认0.01), `.Ki`(默认0.005)；静态信道必须关闭 |

### 6 FDE均衡器（频域，6个）

| 函数 | 签名 | 说明 |
|------|------|------|
| `eq_ofdm_zf` | `[X_hat, H_inv] = eq_ofdm_zf(Y_freq, H_est)` | OFDM ZF迫零，信道零点处噪声放大 |
| `eq_mmse_fde` | `[x_hat, X_hat_freq] = eq_mmse_fde(Y_freq, H_est, noise_var)` | MMSE频域均衡，SC-FDE/OFDM通用 |
| `eq_mmse_ic_fde` | `[x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var)` | 迭代MMSE-IC频域均衡，Turbo核心 |
| `eq_mmse_tv_fde` | `[x_hat, H_tv] = eq_mmse_tv_fde(Y_freq, h_time_block, delays_sym, N_fft, noise_var)` | 时变MMSE-FDE，构建ICI矩阵求逆 |
| `eq_mmse_ic_tv_fde` | `[x_tilde, mu, nv_tilde] = eq_mmse_ic_tv_fde(Y_freq, H_tv, x_bar, var_x, noise_var)` | 时变 MMSE-IC FDE（Turbo 迭代 + ICI 消除版，接 eq_mmse_tv_fde 输出） |
| `eq_bem_turbo_fde` | `[bits_out, iter_info] = eq_bem_turbo_fde(Y_freq, h_time_block, delays_sym, N_fft, noise_var, codec_params, num_outer_iter)` | BEM-Turbo迭代ICI消除FDE |

#### FDE均衡器参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `Y_freq` | 1xN复数 | 频域接收信号 |
| `H_est` | 1xN复数 | 频域信道估计 |
| `noise_var` | 正实数 | 噪声方差 |
| `x_bar` | 1xN复数 | MMSE-IC用时域软符号先验，首次迭代全0 |
| `var_x` | 正实数 | MMSE-IC用残余符号方差，首次迭代=1 |
| `h_time_block` | PxN矩阵 | 时变FDE用块内时变信道增益（P径 x N符号时刻） |
| `delays_sym` | 1xP向量 | 各径符号级时延 |
| `codec_params` | 结构体 | BEM-Turbo用编解码参数 |

### 7 OTFS均衡器（4个）

| 函数 | 签名 | 说明 |
|------|------|------|
| `eq_otfs_mp` | `[x_hat, LLR_out, x_mean_out] = eq_otfs_mp(Y_dd, h_dd, path_info, N, M, noise_var, max_iter, constellation, prior_mean, prior_var)` | OTFS消息传递(MP)均衡，高斯近似BP，V3 |
| `eq_otfs_mp_simplified` | `[x_hat] = eq_otfs_mp_simplified(Y_dd, h_dd, path_info, N, M, noise_var, max_iter)` | OTFS简化MP，MMSE低复杂度近似 |
| `eq_otfs_lmmse` | `[x_hat, info] = eq_otfs_lmmse(Y_dd, h_dd, path_info, N, M, noise_var)` | OTFS LMMSE 均衡（基于 DD 域稀疏路径构造协方差矩阵），作为 MP 的高 SNR 基准 |
| `eq_otfs_uamp` | `[x_hat, info] = eq_otfs_uamp(Y_dd, h_dd, path_info, N, M, noise_var, max_iter)` | OTFS UAMP 均衡（统一近似消息传递），离散 Doppler 场景收敛快 |

### 8 多通道均衡器（1个）

| 函数 | 签名 | 说明 |
|------|------|------|
| `eq_ptrm` | `[output, gain] = eq_ptrm(received, channel_est)` | PTR被动时反转，多通道匹配滤波空间聚焦 |

### 9 工具函数（6个）

| 函数 | 签名 | 说明 |
|------|------|------|
| `build_scattered_obs` | `[obs_y, obs_x, obs_t] = build_scattered_obs(rx, training, pilot_sym, pilot_positions, sym_delays, train_len, N_frame)` | 从帧结构（训练+散布导频）构建BEM观测矩阵 |
| `soft_demapper` | `Le_eq = soft_demapper(x_tilde, mu, nv_tilde, La_eq, mod_type)` | 均衡输出 -> 编码比特外信息LLR |
| `soft_mapper` | `[x_bar, var_x] = soft_mapper(L_posterior, mod_type)` | 后验LLR -> 软符号估计+残余方差 |
| `llr_to_symbol` | `soft_symbols = llr_to_symbol(LLR, mod_type)` | LLR -> 软符号（译码器->均衡器接口） |
| `symbol_to_llr` | `LLR = symbol_to_llr(symbols, noise_var, mod_type)` | 均衡后符号 -> LLR（均衡器->译码器接口） |
| `interference_cancel` | `y_clean = interference_cancel(y, soft_symbols, channel_est)` | 干扰消除，从接收信号减去已知干扰重构分量 |

---

## 内部函数

| 函数 | 类型 | 说明 |
|------|------|------|
| `gen_test_channel` | 测试辅助 | 生成简化多径信道（sparse/dense/exponential），供模块内测试 |
| `plot_channel_estimate` | 可视化 | 信道估计对比图（时域幅度/频域/NMSE柱状图） |
| `plot_eq_convergence` | 可视化 | 均衡器收敛曲线（滑动窗口MSE/BER） |
| `plot_equalizer_output` | 可视化 | 均衡前后对比（星座图/误差分布/BER柱状图） |
| `test_channel_est_eq` | 主测试 | V2统一测试（24项断言 + 6组可视化） |
| `test_ch_est_tv` | 独立测试 | 时变信道估计NMSE独立评价（不含均衡/译码） |

---

## 核心算法简述

### GAMP（广义近似消息传递）

将联合后验 `p(h|y)` 分解为因子图上的消息传递，通过高斯近似将复杂度从指数降至线性。支持非高斯先验（如稀疏先验），每次迭代在观测节点和变量节点间交替传递均值/方差消息。

**关键公式：**

$$\hat{p}(n) = \sum_m |\Phi(m,n)|^2 \cdot \tau_p(m) \quad \text{(方差传播)}$$

$$\hat{r}(n) = \hat{x}(n) + \hat{p}(n) \sum_m \Phi^*(m,n) \cdot s(m) \quad \text{(均值更新)}$$

$$\hat{x}(n) = g_{\text{in}}(\hat{r}(n),\; \hat{p}(n)) \quad \text{(先验去噪函数)}$$

参数规则：`max_iter` 50~100次足够；`noise_var` 需提供或自动估计。局限：测量矩阵非i.i.d.时收敛不保证，此时用VAMP/Turbo-VAMP。

### BEM（基扩展模型）

将时变信道 `h(n,p)` 展开为 Q+1 个基函数的线性组合 `h(n,p) = sum_q c(q,p)*b_q(n)`，将连续时变问题转化为有限维参数估计。基函数数 `Q = 2*ceil(fd*N/sym_rate)` 由多普勒扩展决定。

**关键公式：**

$$h(n,p) = \sum_{q=0}^{Q} c(q,p) \cdot b_q(n)$$

$$\text{CE基：} b_q(n) = e^{j 2\pi q n / N}$$

$$\text{DCT基：} b_q(n) = \cos\!\left(\frac{\pi q (2n+1)}{2N}\right)$$

$$\text{最小二乘：} \mathbf{c} = (\mathbf{B}^H \mathbf{B} + \lambda \mathbf{I})^{-1} \mathbf{B}^H \mathbf{y}_{\text{obs}}$$

参数规则：DCT基在有限长帧下频谱泄漏小于CE，推荐优先用DCT；`fd_est` 过小会截断基函数导致建模误差，过大则过参数化。局限：仅适用于块级慢变信道，快变时需配合散布导频。

### MMSE-IC（最小均方误差干扰消除）

Turbo迭代核心。每次迭代利用译码器反馈的软符号做干扰消除后，用MMSE滤波器对残余信号均衡。随迭代进行，软信息精度提高，干扰消除更完全，形成正反馈。

**关键公式（频域，每子载波k）：**

$$G(k) = \frac{H^*(k) \cdot \sigma_x^2}{|H(k)|^2 \cdot \sigma_x^2 + \sigma_w^2}$$

$$\tilde{x} = \text{IFFT}\!\left\{G \cdot \left(Y - H \cdot \text{FFT}(\bar{x})\right)\right\} + \bar{x}$$

$$\mu = \mathrm{mean}(G \cdot H) \quad \text{(等效增益)}$$

$$\tilde{\nu} = \mu (1 - \mu) \quad \text{(等效噪声方差)}$$

参数规则：首次迭代 `x_bar=0, var_x=1`（无先验），后续由 `soft_mapper` 提供；`var_x` 需下限截断 `max(var_x, noise_var)` 防止数值不稳定。局限：假设信道块内不变，时变信道需先做BEM估计再分块FDE。

### DFE（判决反馈均衡器）

前馈滤波器补偿ISI，反馈滤波器利用已判决符号消除拖尾ISI。RLS自适应更新权重，收敛速度远快于LMS。错误传播是DFE固有问题，双向DFE(BiDFE)通过前向+后向联合判决缓解。

**关键公式：**

$$d(n) = \mathbf{w}_{\text{ff}}^H \mathbf{y}(n) - \mathbf{w}_{\text{fb}}^H \hat{\mathbf{x}}(n-1:-1:n-N_{\text{fb}})$$

$$e(n) = x_{\text{ref}}(n) - d(n)$$

$$\text{RLS更新：} \mathbf{k} = \frac{\mathbf{P}(n-1) \mathbf{y}}{\lambda + \mathbf{y}^H \mathbf{P}(n-1) \mathbf{y}}, \quad \mathbf{P}(n) = \frac{\mathbf{P}(n-1) - \mathbf{k} \mathbf{y}^H \mathbf{P}(n-1)}{\lambda}$$

参数规则：前馈阶数最优 = 4x信道长度；`lambda=0.9995` 防长序列遗忘；静态信道必须关PLL（`pll.enable=false`），否则发散。局限：错误传播在低SNR下严重，长时延扩展信道下不如FDE。

### Kalman信道跟踪

将各径信道增益建模为AR(1)过程 `h(n+1) = alpha*h(n) + w(n)`，用Kalman滤波器逐符号更新。仅跟踪已知时延位置的径（稀疏），计算量 O(P^2) 而非 O(N^2)。

**关键公式：**

$$\text{预测：} \mathbf{h}_{\text{pred}} = \alpha \cdot \mathbf{h}(n), \quad \mathbf{P}_{\text{pred}} = \alpha^2 \mathbf{P}(n) + \mathbf{Q}$$

$$\text{更新：} \mathbf{K} = \frac{\mathbf{P}_{\text{pred}} \mathbf{a}^H}{\mathbf{a} \mathbf{P}_{\text{pred}} \mathbf{a}^H + \sigma_w^2}$$

$$\mathbf{h}(n+1) = \mathbf{h}_{\text{pred}} + \mathbf{K} \cdot (y(n) - \mathbf{a} \cdot \mathbf{h}_{\text{pred}})$$

其中 $\mathbf{a} = x_{\text{ref}}(n - \text{delays})$ 为观测向量，$\alpha = J_0(2\pi f_d / f_s)$ 即零阶贝塞尔函数。

参数规则：`alpha` 由多普勒频率自动计算；`K_target=5%` 修剪弱径防止维数膨胀。局限：需已知多径时延结构（由GAMP/OMP/SAGE预估），对突变信道响应滞后。

### OTFS-MP（OTFS消息传递均衡）

在DD域因子图上做高斯近似BP。每个观测节点 `Y(k,l)` 连接到 P 条路径对应的数据节点，消息在观测-数据节点间迭代传递。支持先验软信息输入实现Turbo迭代。

**关键公式（观测节点m到数据节点n的消息）：**

$$\mu_{m \to n} = \frac{Y(m) - \sum_{n' \neq n} h_{n'} \cdot \mu_{n' \to m}}{h_n}$$

$$\sigma^2_{m \to n} = \frac{\sigma_w^2 + \sum_{n' \neq n} |h_{n'}|^2 \cdot v_{n' \to m}}{|h_n|^2}$$

**数据节点合并：**

$$\mu_n = v_n \sum_m \frac{h_m^* \cdot \mu_{m \to n}}{\sigma^2_{m \to n}}, \quad v_n = \left(\frac{1}{v_{\text{prior}}} + \sum_m \frac{|h_m|^2}{\sigma^2_{m \to n}}\right)^{-1}$$

参数规则：`max_iter=10` 通常足够收敛；复杂度 `O(iter*P*NM*Q)`，简化版用MMSE近似降至 `O(P*NM)`。局限：路径数P增大时因子图环路加长，BP近似精度下降。

---

## 使用示例

### 静态信道估计（GAMP）

```matlab
% 生成测试信号
training = qpsk_symbols(500);
h_true = [1, 0, 0, 0, 0, 0.7*exp(1j*0.3), zeros(1,9), 0.5*exp(1j*1.2)];
rx = conv(training, h_true); rx = rx(1:500);
rx = rx + sqrt(0.01/2)*(randn(size(rx))+1j*randn(size(rx)));

% 构建Toeplitz测量矩阵
L_h = length(h_true);
T_mat = zeros(500, L_h);
for col = 1:L_h
    T_mat(col:500, col) = training(1:500-col+1).';
end

% GAMP估计
[h_est, H_est] = ch_est_gamp(rx(:), T_mat, L_h, 50, 0.01);
```

### Turbo MMSE-IC FDE迭代

```matlab
% 首次均衡（无先验）
x_bar = zeros(1, N_fft);
var_x = 1;
[x_tilde, mu, nv] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var);

% 软解映射 -> 译码 -> 软映射 -> 再均衡
for iter = 1:3
    Le = soft_demapper(x_tilde, mu, nv, La_prior, 'qpsk');
    % ... 译码器处理，得到后验LLR L_post ...
    [x_bar, var_x] = soft_mapper(L_post, 'qpsk');
    var_x = max(var_x, noise_var);  % 下限截断
    [x_tilde, mu, nv] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var);
end
```

### 时变信道BEM估计 + 散布导频

```matlab
% 构建散布导频观测
[obs_y, obs_x, obs_t] = build_scattered_obs(rx, training, pilot_sym, ...
    pilot_positions, sym_delays, train_len, N_frame);

% BEM(DCT)估计
[h_tv, c_bem, info] = ch_est_bem(obs_y, obs_x, obs_t, N_frame, ...
    sym_delays, fd_est, sym_rate, noise_var, 'dct');
```

---

## 依赖关系

| 依赖方向 | 模块 | 函数 | 用途 |
|----------|------|------|------|
| 本模块调用 | 02_ChannelCoding | `siso_decode_conv` | Turbo均衡内部BCJR译码 |
| 本模块调用 | 03_Interleaving | `random_interleave` | Turbo均衡内部交织 |
| 本模块调用 | 09_Waveform | `pulse_shape`, `match_filter` | RRC脉冲成形与匹配滤波 |
| 本模块调用 | 13_SourceCode | `gen_uwa_channel` | 时变信道生成（测试用） |
| 被调用 | 12_IterativeProc | `turbo_equalizer_sctde`, `turbo_equalizer_scfde_crossblock` | Turbo均衡器主流程 |
| 被调用 | 13_SourceCode | SC-TDE/SC-FDE仿真主程序 | 系统级仿真 |

---

## 测试覆盖（test_channel_est_eq.m V2，24项全通过）

| # | 测试项 | 断言条件 | 类别 |
|---|--------|----------|------|
| 1 | LS 静态NMSE | 运行不报错 | 静态估计 |
| 2 | MMSE 静态NMSE | 运行不报错 | 静态估计 |
| 3 | OMP 静态NMSE | 运行不报错 | 静态估计 |
| 4 | SBL 静态NMSE | 运行不报错 | 静态估计 |
| 5 | GAMP 静态NMSE | 运行不报错 | 静态估计 |
| 6 | VAMP 静态NMSE | 运行不报错 | 静态估计 |
| 7 | TurboVAMP 静态NMSE | 运行不报错 | 静态估计 |
| 8 | 2A BEM NMSE vs fd | CE/DCT双基在4个fd下运行 | 时变估计 |
| 9 | 2B BEM(CE) NMSE vs SNR | 5个SNR点运行 | 时变估计 |
| 10 | 2C DD-BEM迭代精化 | 3次DD迭代运行 | 时变估计 |
| 11 | 2D SAGE参数估计 | 时延误差可计算 | 时变估计 |
| 12 | 2E Kalman跟踪 | NMSE可计算 | 信道跟踪 |
| 13 | 2F 训练 vs 散布导频 | 4种方法NMSE对比完成 | 时变估计 |
| 14 | eq_rls SER@20dB | SER < 3% | TDE均衡 |
| 15 | eq_lms SER@20dB | SER < 5% | TDE均衡 |
| 16 | eq_dfe SER@20dB | SER < 1% | TDE均衡 |
| 17 | BiDFE SER@20dB | SER < 1% | TDE均衡 |
| 18 | ZF SER@20dB | SER < 2% | FDE均衡 |
| 19 | MMSE-FDE SER@20dB | SER < 0.5% | FDE均衡 |
| 20 | MMSE-IC(1) SER@20dB | SER < 0.5% | FDE均衡 |
| 21 | MMSE-IC(3) SER@20dB | SER < 0.5% | FDE均衡 |
| 22 | Turbo TDE (6径) | SNR vs iter BER矩阵完成 | Turbo均衡 |
| 23 | Turbo FDE (6径) | SNR vs iter BER矩阵完成 | Turbo均衡 |
| 24 | 时变均衡(RRC+BEM+FDE) | 4个fd x 7个SNR x 4种方法BER完成 | 时变均衡 |

---

## 可视化说明（6组图表）

| 图 | 内容 | 对应测试 |
|----|------|----------|
| Fig.1 | 静态信道估计：时域幅度对比 / 频域幅度对比 / NMSE柱状图 | 第一节(7种方法) |
| Fig.2 | 时变估计综合8子图：BEM NMSE vs fd / BEM vs SNR / SAGE时延 / Kalman跟踪 / 散布导频增益 / T-SBL等 | 第二节(2A~2F) |
| Fig.3 | 时域均衡器：SNR vs SER曲线 / 星座图@5dB | 第三节(4A) |
| Fig.4 | 频域均衡器：SNR vs SER曲线 / 信道频响(真实 vs GAMP) | 第三节(4B) |
| Fig.5 | Turbo TDE vs FDE：BER vs SNR(多迭代次数) | 第三节(3C) |
| Fig.6 | 时变均衡BER：fd=5Hz全方法 / fd=10Hz全方法 / CE vs DCT各fd | 第四节 |

---

## 关键实验结论

### 静态信道估计NMSE@15dB

| 方法 | NMSE | 推荐度 |
|------|------|--------|
| LS | -12.6dB | 基线 |
| MMSE | -12.6dB | -- |
| OMP | -34.2dB | --- |
| SBL | -28.1dB | -- |
| **GAMP** | **-34.2dB** | **---推荐** |
| VAMP | -34.3dB | --- |
| **Turbo-VAMP** | **-34.3dB** | **---最优** |

### 散布导频增益（fd=5Hz, SNR=15dB）

| 方法 | 仅训练 | 散布导频 | 增益 |
|------|--------|---------|------|
| BEM(CE) | 2.2dB | -9.6dB | +11.8dB |
| **BEM(DCT)** | 2.3dB | **-19.4dB** | **+21.7dB** |
| DD-BEM | 0.2dB | -13.9dB | +14.1dB |

### 均衡器调试要点

| 要点 | 说明 |
|------|------|
| DFE+PLL | 静态信道必须关PLL，否则发散 |
| DFE lambda | 0.998 -> 0.9995，防长序列遗忘 |
| DFE h_est | 不传h_est，纯RLS训练更稳定 |
| BiDFE | 单侧训练时需前向输出作后向伪训练 |
| 抽头数 | 甜点=4x信道长度，过多过少均降性能 |
| FDE优势 | 长时延信道下FDE全面优于TDE（5dB编码增益优势） |

### 时变均衡基线（doppler_rate=fd/fc, fc=12kHz, oracle alpha 补偿）

**fd=1Hz**（BER%）

| SNR | -3dB | 0dB | 3dB | 5dB | 10dB | 15dB | 20dB |
|-----|------|-----|-----|-----|------|------|------|
| oracle | 0.22 | 0.11 | 0 | 0 | 0 | 0 | 0 |
| BEM(CE) | 0.61 | 0.11 | 0 | 0 | 0 | 0 | 0 |
| BEM(DCT) | 0.34 | 0.11 | 0 | 0 | 0 | 0 | 0 |
| DD-BEM | 1.17 | 0.34 | 0 | 0 | 0 | 0.11 | 0.11 |

**fd=5Hz**（BER%）

| SNR | -3dB | 0dB | 3dB | 5dB | 10dB | 15dB | 20dB |
|-----|------|-----|-----|-----|------|------|------|
| oracle | 0.89 | 0.16 | 0 | 0.05 | 0 | 0.05 | 0 |
| BEM(CE) | 2.92 | 0.47 | 0 | 0 | 0 | 0.16 | 0 |
| BEM(DCT) | 3.44 | 0.36 | 0 | 0.10 | 0 | 0.10 | 0 |
| DD-BEM | 5.06 | 0.78 | 0.05 | 0.21 | 0 | 0.10 | 0.26 |

**fd=10Hz**（BER%）

| SNR | -3dB | 0dB | 3dB | 5dB | 10dB | 15dB | 20dB |
|-----|------|-----|-----|-----|------|------|------|
| oracle | 3.02 | 1.36 | 0.36 | 0.31 | 0.73 | 3.28 | 3.65 |
| BEM(CE) | 20.23 | 8.39 | 6.93 | 4.43 | 9.18 | 11.16 | 13.76 |
| BEM(DCT) | 15.12 | 4.95 | 4.48 | 1.15 | 3.08 | 4.48 | 6.10 |
| DD-BEM | 17.15 | 10.27 | 4.59 | 9.02 | 9.18 | 14.23 | 15.33 |

**关键发现**：
1. fd≤5Hz 影响可控，oracle alpha 补偿后 5dB+ 基本不变
2. BEM(DCT) 在全部 fd 下优于 CE-BEM 和 DD-BEM
3. fd=10Hz 是系统级 ICI 极限：oracle 在高 SNR 非单调反弹（0.73→3.28→3.65%），非算法缺陷
4. DD-BEM 高 SNR 地板：fd=5Hz@20dB 残留 0.26%，判决误差通过迭代传播
