# 水声通信多普勒估计与补偿 —— MATLAB 代码编写规范文档 v2.0

> **文档用途**：本文档作为 MATLAB 仿真代码的编写依据，涵盖系统模型、各模块数学定义、接口规范、测试用例及验证指标，供开发者按模块独立实现后集成。
>
> **v2.0 新增**：SC-FDE 单载波频域均衡完整链路、OTFS 时延-多普勒域调制收发系统、阵列波束形成增强多普勒估计。

---

## 目录

1. [系统总体架构](#1-系统总体架构)
2. [信号与信道模型](#2-信号与信道模型)
3. [模块一：仿真信道生成](#3-模块一仿真信道生成)
4. [模块二：多普勒估计算法](#4-模块二多普勒估计算法)
   - 4.1 二维 CAF 搜索法
   - 4.2 CP 自相关法（OFDM）
   - 4.3 复自相关幅相联合法（SC）
   - 4.4 Zoom-FFT 频谱细化法
5. [模块三：多普勒补偿算法](#5-模块三多普勒补偿算法)
   - 5.1 重采样补偿
   - 5.2 残余 CFO 相位旋转
   - 5.3 ICI 矩阵补偿（OFDM）
6. [模块四：信道估计与均衡（OFDM）](#6-模块四信道估计与均衡ofdm)
7. [模块五：SC-FDE 单载波频域均衡系统](#7-模块五sc-fde单载波频域均衡系统)
   - 7.1 SC-FDE 系统模型
   - 7.2 发射端帧结构生成
   - 7.3 接收机：多普勒估计（复自相关幅相联合）
   - 7.4 接收机：重采样 + 时域均衡预处理
   - 7.5 接收机：SC-FDE 频域均衡
   - 7.6 接收机：Turbo 迭代均衡
   - 7.7 SC-FDE 仿真主流程
8. [模块六：OTFS 调制收发系统](#8-模块六otfs调制收发系统)
   - 8.1 OTFS 系统模型与变换原理
   - 8.2 OTFS 发射端
   - 8.3 OTFS 时延-多普勒域信道模型
   - 8.4 OTFS 接收端：信道估计
   - 8.5 OTFS 接收端：消息传递均衡器（MP-Detector）
   - 8.6 OTFS 仿真主流程
9. [模块七：阵列波束形成增强多普勒估计](#9-模块七阵列波束形成增强多普勒估计)
   - 9.1 阵列信号模型
   - 9.2 空时联合非均匀变采样
   - 9.3 波束域信号重建
   - 9.4 基于波束域信号的多普勒高精度估计
   - 9.5 阵列多普勒估计仿真主流程
10. [系统集成：统一仿真入口](#10-系统集成统一仿真入口)
11. [性能评估指标](#11-性能评估指标)
12. [参数配置表](#12-参数配置表)
13. [函数接口汇总](#13-函数接口汇总)
14. [附录](#14-附录)

---

## 1. 系统总体架构

本文档覆盖三种调制体制的完整收发链路，各体制共享信道生成模块和基础多普勒估计/补偿模块：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         发射端（三种体制可选）                               │
│  信源比特 → 编码(LDPC/Turbo) → 调制(QPSK/QAM)                              │
│     ├── [OFDM]   → IFFT + 加CP + 导频插入                                   │
│     ├── [SC-FDE] → 分块 + 加CP/ZP + 前导码                                  │
│     └── [OTFS]   → ISFFT(时延-多普勒) → Heisenberg变换 → 脉冲成形            │
│                           ↓ 加前导码/后导码                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                             ↓ 信号经过水声信道
┌─────────────────────────────────────────────────────────────────────────────┐
│                    水声信道（gen_uwa_channel.m）                              │
│     多径叠加 + 宽带多普勒伸缩(α) + 时延扩展 + AWGN                           │
│     [阵列接收] 每个阵元独立经历信道，但具有精确空间相位差                     │
└─────────────────────────────────────────────────────────────────────────────┘
                             ↓ 接收信号 r[n] （或 r_m[n], m=1..M 阵元）
┌─────────────────────────────────────────────────────────────────────────────┐
│                         接收端公共前端                                       │
│  帧同步 → [模块七: 阵列波束形成（可选）] → 多普勒估计(α̂) → 重采样补偿        │
│     ├── [OFDM]   → FFT → 残余CFO补偿 → LS信道估计 → FDE均衡                 │
│     ├── [SC-FDE] → 分块FFT → FDE均衡 → IFFT → [Turbo迭代]                  │
│     └── [OTFS]   → Wigner变换 → SFFT → DD域信道估计 → MP均衡器              │
│                           ↓                                                 │
│                    解调 → 译码 → 输出比特                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

**代码文件结构**：

```
project/
├── main_sim.m                      % 统一仿真入口（支持三种体制切换）
├── params/
│   ├── sys_params_ofdm.m           % OFDM 参数
│   ├── sys_params_scfde.m          % SC-FDE 参数
│   └── sys_params_otfs.m           % OTFS 参数
├── channel/
│   ├── gen_uwa_channel.m           % 单路水声信道仿真
│   └── gen_uwa_channel_array.m     % 阵列水声信道仿真（M 阵元）
├── doppler_estimation/
│   ├── est_doppler_caf.m           % 二维 CAF 搜索
│   ├── est_doppler_cp.m            % CP 自相关法（OFDM）
│   ├── est_doppler_xcorr.m         % 复自相关幅相联合（SC）
│   ├── est_doppler_zoomfft.m       % Zoom-FFT 法
│   └── est_doppler_beamforming.m   % 阵列空时变采样法
├── doppler_compensation/
│   ├── comp_resample.m             % 重采样（三次样条/Farrow）
│   ├── comp_cfo.m                  % 残余 CFO 相位旋转
│   └── comp_ici_matrix.m           % ICI 矩阵补偿
├── ofdm/
│   ├── gen_ofdm_signal.m           % OFDM 调制（含导频插入）
│   ├── ch_est_ls.m                 % LS 信道估计
│   └── equalizer_fde_ofdm.m       % OFDM 频域均衡
├── scfde/
│   ├── gen_scfde_signal.m          % SC-FDE 帧生成（含前/后导码、ZP/CP）
│   ├── est_doppler_scfde.m         % SC-FDE 专用复自相关估计
│   ├── ch_est_scfde.m              % SC-FDE 信道估计（LS + 时域转频域）
│   ├── equalizer_fde_sc.m          % SC-FDE 频域均衡（MMSE）
│   └── turbo_equalizer.m           % Turbo 迭代软均衡
├── otfs/
│   ├── gen_otfs_signal.m           % OTFS 调制（ISFFT + Heisenberg）
│   ├── otfs_channel_model.m        % OTFS 时延-多普勒域信道矩阵构建
│   ├── ch_est_otfs.m               % OTFS 嵌入导频信道估计
│   └── mp_detector.m              % 消息传递检测器（MP-Detector）
├── beamforming/
│   ├── gen_uwa_channel_array.m     % 阵列信道仿真
│   ├── bf_delay_calibration.m      % 阵元时延标定
│   ├── bf_nonuniform_resample.m    % 空时联合非均匀变采样重建
│   ├── bf_conventional.m           % 常规时延求和波束形成
│   └── est_doppler_beamforming.m   % 基于波束域信号的多普勒估计
└── utils/
    ├── add_preamble.m              % 插入前导/后导码
    ├── gen_mseq.m                  % m 序列生成
    ├── gen_chirp.m                 % Chirp 信号生成
    ├── cubic_interp.m              % 三次样条插值（实/虚分离）
    ├── farrow_filter.m             % Farrow 滤波器实现
    └── calc_ber.m                  % BER / FER 计算
```

---

## 2. 信号与信道模型

### 2.1 宽带多普勒信道模型

水声多径宽带信道连续时间输入输出关系：

$$r(t) = \sum_{p=1}^{P} a_p \cdot s\!\left(\frac{t - \tau_p}{1 + \alpha_p}\right) + n(t)$$

**一致多普勒简化模型**（各路径共享同一因子 $\alpha = v/c$）：

$$r(t) = \sum_{p=1}^{P} a_p \cdot s\!\left(\frac{t}{1+\alpha} - \tau_p\right) e^{j\phi_p} + n(t)$$

离散化后（采样率 $f_s$，$T_s = 1/f_s$）：

$$r[n] = \sum_{p=1}^{P} a_p \cdot s\!\left[\text{round}\!\left(\frac{n}{1+\alpha} - \frac{\tau_p}{T_s}\right)\right] e^{j\phi_p} + n[n]$$

### 2.2 OFDM 信号模型

发射第 $m$ 个 OFDM 符号（含 CP，FFT 点数 $N$，CP 长度 $N_{cp}$）：

$$s_m[n] = \frac{1}{\sqrt{N}} \sum_{k=0}^{N-1} X_m[k] \cdot e^{j2\pi kn/N}, \quad n = -N_{cp}, \ldots, N-1$$

宽带多普勒导致 ICI，频域接收信号：

$$Y_m[k] = \sum_{l=0}^{N-1} D_{kl}(\alpha) H_m[l] X_m[l] + W_m[k]$$

ICI 系数：$D_{kl}(\alpha) = \frac{1}{N}\sum_{n=0}^{N-1} e^{j2\pi(l-k(1+\alpha))n/N}$

### 2.3 SC-FDE 信号模型

SC-FDE 将 $N_{data}$ 个调制符号分成每块 $K$ 个，每块附加循环前缀（CP）或补零（ZP）：

**带CP的块结构**：$[\underbrace{x[K-N_{cp}],\ldots,x[K-1]}_{CP} | \underbrace{x[0],\ldots,x[K-1]}_{数据块}]$

频域（对每块去CP后做FFT）：

$$Y[k] = H[k] \cdot X[k] + W[k], \quad k=0,\ldots,K-1$$

其中 $H[k] = \sum_{l=0}^{L-1} h[l] e^{-j2\pi kl/K}$ 为信道频率响应。

MMSE 均衡后做 IFFT 还原时域判决：

$$\hat{X}[k] = \frac{H^*[k]}{|H[k]|^2 + \sigma_n^2/\sigma_x^2} Y[k], \quad \hat{x}[n] = \text{IFFT}\{\hat{X}[k]\}$$

### 2.4 OTFS 信号模型

OTFS 在 $N \times M$ 的时延-多普勒（DD）网格上调制，网格分辨率：

$$\Delta\tau = \frac{1}{M \Delta f}, \quad \Delta\nu = \frac{1}{NT}$$

其中 $\Delta f$ 为子载波间隔，$T = 1/\Delta f$ 为 OFDM 符号周期。

**发射端**（ISFFT + Heisenberg 变换）：

$$X[n,m] = \sum_{k=0}^{N-1}\sum_{l=0}^{M-1} x_{DD}[k,l] \cdot e^{j2\pi\left(\frac{nk}{N} - \frac{ml}{M}\right)}$$

$$s(t) = \sum_{n=0}^{N-1} \sum_{m=0}^{M-1} X[n,m] \cdot g_{tx}(t - nT) \cdot e^{j2\pi m\Delta f (t-nT)}$$

**时延-多普勒域信道**（$P$ 条稀疏路径）：

$$h(\tau,\nu) = \sum_{i=1}^{P} h_i \cdot \delta(\tau - l_i/M\Delta f) \cdot \delta(\nu - k_i/NT)$$

**接收端**（Wigner 变换 + SFFT），DD 域输入输出关系：

$$y_{DD}[k,l] = \sum_{i=1}^{P} h_i \cdot x_{DD}[(k-k_i)_N, (l-l_i)_M] \cdot e^{j2\pi k_i l_i/(NM)} + w[k,l]$$

该关系在 DD 域为**循环卷积**，且信道系数 $\{h_i, l_i, k_i\}$ 是**稀疏且时不变**的，这是 OTFS 对抗多普勒的根本原因。

### 2.5 阵列信号模型

$M$ 阵元均匀线阵（ULA），阵元间距 $d$，信号入射角 $\theta$（相对法线方向），第 $m$ 阵元接收信号：

$$r_m(t) = s\!\left(t - \tau_m\right) + n_m(t), \quad \tau_m = (m-1)\frac{d\cos\theta}{c}, \quad m = 1,\ldots,M$$

加入宽带多普勒后：

$$r_m(t) = \sum_{p=1}^{P} a_p \cdot s\!\left(\frac{t - \tau_{m,p}}{1+\alpha}\right) + n_m(t)$$

---

## 3. 模块一：仿真信道生成

### 3.1 单路信道：`gen_uwa_channel.m`

**功能**：对发射信号施加宽带多普勒伸缩、多径叠加和 AWGN。

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `s_tx` | `[1×N_tx]` complex | 发射基带信号 |
| `channel` | struct | 见下方字段 |
| `SNR_dB` | scalar | 信噪比（dB，相对信号功率） |

**`channel` 结构体**：

```matlab
channel.alpha    % 多普勒因子 α = v/c，scalar
channel.delays   % 各径时延 [1×P]（秒）
channel.gains    % 各径复增益 [1×P] complex
channel.P        % 多径数
channel.fs       % 采样率（Hz）
channel.c        % 声速，默认 1500 m/s
```

**输出**：`r_rx [1×N_rx]`，`noise_var`（噪声方差，供 MMSE 使用）

**实现逻辑**：

```
步骤1：多普勒时间伸缩
  t_orig     = (0 : N_tx-1) / fs
  t_stretched = t_orig / (1 + alpha)          % 伸缩后对应的原始时刻
  s_doppler  = interp1(t_orig, s_tx, t_stretched, 'spline', 0)
  N_rx       = length(s_doppler)

步骤2：多径叠加
  r_multipath = zeros(1, N_rx + max_delay_samp)
  for p = 1:P
      delay_samp = round(delays(p) * fs)
      r_multipath(1+delay_samp : N_rx+delay_samp) += gains(p) * s_doppler

步骤3：AWGN
  P_sig      = mean(abs(r_multipath).^2)
  noise_var  = P_sig / 10^(SNR_dB/10)
  noise      = sqrt(noise_var/2) * (randn(size) + 1j*randn(size))
  r_rx       = r_multipath + noise
```

### 3.2 阵列信道：`gen_uwa_channel_array.m`

**功能**：为 $M$ 阵元均匀线阵生成各阵元接收信号，每阵元有精确已知的空间时延 $\tau_m$。

**输入**：在 `gen_uwa_channel` 基础上增加阵列参数：

```matlab
array.M        % 阵元数
array.d        % 阵元间距（米），典型值 = lambda/2
array.theta    % 信号入射角（弧度）
array.fc       % 载频（Hz），用于计算波长
```

**输出**：`R_array [M×N_rx]`（每行为一个阵元的接收信号）

**实现逻辑**：

```
对每个阵元 m = 1, ..., M：
  tau_m = (m-1) * d * cos(theta) / c        % 精确空间时延（秒）
  将 tau_m 叠加到信道结构体的各径时延上
  调用 gen_uwa_channel → R_array(m, :)
```

**注意**：`tau_m` 的精确计算是后续空时变采样估计精度的关键，需保留浮点精度，不可四舍五入为整数样点。

---

## 4. 模块二：多普勒估计算法

### 4.1 二维 CAF 搜索法

**函数**：`est_doppler_caf.m`

**适用场景**：OFDM/SC/OTFS 均可，离线高精度处理。

**数学原理**：

$$\text{CAF}(\tau, \alpha) = \left|\sum_{n} r[n] \cdot p^*\!\left[\text{round}\!\left(\frac{n - \tau f_s}{1+\alpha}\right)\right]\right|^2$$

$$(\hat{\tau}, \hat{\alpha}) = \arg\max_{\tau \in \mathcal{T},\, \alpha \in \mathcal{A}} \text{CAF}(\tau, \alpha)$$

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `r` | `[1×N]` complex | 接收信号 |
| `p` | `[1×L]` complex | 已知前导码 |
| `fs` | scalar | 采样率（Hz） |
| `alpha_range` | `[1×2]` | 搜索范围，如 `[-0.02, 0.02]` |
| `alpha_step` | scalar | 粗搜索步长，如 `1e-4` |
| `tau_range` | `[1×2]` | 时延范围（秒） |

**输出**：`alpha_est`，`tau_est`，`caf_map [N_tau×N_alpha]`

**实现逻辑**：

```matlab
alpha_vec = alpha_range(1) : alpha_step : alpha_range(2);
tau_vec   = tau_range(1)   : 1/fs     : tau_range(2);
caf_map   = zeros(length(tau_vec), length(alpha_vec));

for i = 1:length(alpha_vec)
    n_orig   = 0 : length(p)-1;
    n_scaled = n_orig / (1 + alpha_vec(i));
    p_scaled = interp1(n_orig, p, n_scaled, 'spline', 0);

    corr_out = abs(xcorr(r, p_scaled)).^2;    % 互相关平方

    % 截取时延搜索范围对应的段
    lag_offset = length(r);                    % xcorr 输出零延迟位置
    tau_idx    = round(tau_vec * fs) + lag_offset;
    tau_idx    = max(1, min(tau_idx, length(corr_out)));
    caf_map(:, i) = corr_out(tau_idx);
end

[~, peak_idx]          = max(caf_map(:));
[ti, ai]               = ind2sub(size(caf_map), peak_idx);
alpha_est              = alpha_vec(ai);
tau_est                = tau_vec(ti);

% 可选：在峰值附近用细步长精化（alpha_step_fine = 1e-5）
```

**复杂度**：$O(N_\alpha \times N \log N)$，建议两级搜索（粗 $10^{-3}$ + 细 $10^{-5}$）。

---

### 4.2 CP 自相关法（OFDM）

**函数**：`est_doppler_cp.m`

**数学原理**：利用 CP 结构，相关峰漂移量 $\Delta n$ 与多普勒因子的关系：

$$\hat{\alpha}_{coarse} = \frac{\Delta n}{N}, \quad R(m) = \sum_{n=0}^{N_{cp}-1} r[n+m] \cdot r^*[n+m+N]$$

抛物线插值精化：

$$\hat{\alpha}_{fine} = \hat{\alpha}_{coarse} + \frac{R_{+1} - R_{-1}}{2(2R_0 - R_{+1} - R_{-1})} \cdot \frac{1}{N}$$

**输入**：`r [1×N_total]`，`N`（FFT 点数），`Ncp`，`interp_flag`

**输出**：`alpha_est`，`corr_vals`（自相关序列，供调试）

**实现逻辑**：

```matlab
Ns = N + Ncp;
corr_energy = zeros(1, N);
for offset = 1:N
    seg1 = r(offset : offset+Ncp-1);
    seg2 = r(offset+N : offset+N+Ncp-1);
    corr_energy(offset) = abs(sum(seg1 .* conj(seg2)))^2;
end

[~, peak_pos] = max(corr_energy);
alpha_coarse  = (peak_pos - 1) / N;   % 粗估计（归一化）

if interp_flag
    R_m1 = corr_energy(mod(peak_pos-2, N)+1);
    R_0  = corr_energy(peak_pos);
    R_p1 = corr_energy(mod(peak_pos,   N)+1);
    delta     = (R_p1 - R_m1) / (2*(2*R_0 - R_p1 - R_m1));
    alpha_est = alpha_coarse + delta / N;
else
    alpha_est = alpha_coarse;
end
corr_vals = corr_energy;
```

---

### 4.3 复自相关幅相联合法（SC-FDE 推荐）

**函数**：`est_doppler_xcorr.m`

**数学原理**：

对帧首尾两个测速序列（间距 $T_v$）分别计算互相关：

$$R_i[\tau] = \sum_{n=0}^{L-1} r[n + \tau] \cdot x^*[n]$$

- **粗估计（幅度）**：两个峰值位置差 $\Delta n = \tau_2 - \tau_1$

$$\hat{\alpha}_{coarse} = \frac{\Delta n / f_s - T_v}{T_v}$$

- **精细估计（相位）**：在粗估计确定搜索范围后，相位法：

$$\hat{\alpha}_{phase} = \frac{\angle(R[\tau_2] \cdot R^*[\tau_1])}{2\pi f_c T_v}$$

- **解模糊**：选取与 $\hat{\alpha}_{coarse}$ 最近的相位估计值（消除 $2\pi k$ 模糊）：

$$k = \text{round}\!\left[(\hat{\alpha}_{coarse} - \hat{\alpha}_{phase}) \cdot f_c \cdot T_v\right]$$
$$\hat{\alpha}_{est} = \hat{\alpha}_{phase} + \frac{k}{f_c \cdot T_v}$$

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `r` | `[1×N]` complex | 接收信号（含前导/后导） |
| `x_pilot` | `[1×L]` complex | 测速导频序列（chirp 或 m 序列） |
| `T_v` | scalar | 前后测速序列发送时间间隔（秒） |
| `fs` | scalar | 采样率（Hz） |
| `fc` | scalar | 载频（Hz） |
| `alpha_bound` | scalar | 预期最大 $|\alpha|$，用于粗估搜索范围 |

**输出**：`alpha_est`，`alpha_coarse`，`tau_est`（帧起始时延，秒）

**实现逻辑**：

```matlab
L = length(x_pilot);

% 第一个测速序列互相关
corr1 = abs(xcorr(r, x_pilot));
[~, idx1] = max(corr1);
idx1 = idx1 - length(x_pilot) + 1;  % 修正 xcorr 偏移

% 第二个测速序列（在 T_v 附近搜索）
search_start = idx1 + round((T_v - 5/fs) * fs);
search_end   = idx1 + round((T_v + 5/fs) * fs);
search_start = max(1, search_start);
search_end   = min(length(r) - L, search_end);

corr2_seg = zeros(1, search_end - search_start + 1);
for ii = search_start:search_end
    corr2_seg(ii - search_start + 1) = abs(sum(r(ii:ii+L-1) .* conj(x_pilot)))^2;
end
[~, local_idx2] = max(corr2_seg);
idx2 = search_start + local_idx2 - 1;

% 粗估计
T_v_rx       = (idx2 - idx1) / fs;
alpha_coarse = (T_v_rx - T_v) / T_v;

% 精细相位估计
R1 = sum(r(idx1 : idx1+L-1) .* conj(x_pilot));
R2 = sum(r(idx2 : idx2+L-1) .* conj(x_pilot));
phase_diff   = angle(R2 * conj(R1));
alpha_phase  = phase_diff / (2*pi*fc*T_v);

% 解模糊
k_unwrap  = round((alpha_coarse - alpha_phase) * fc * T_v);
alpha_est = alpha_phase + k_unwrap / (fc * T_v);

tau_est = (idx1 - 1) / fs;   % 帧到达时延
```

---

### 4.4 Zoom-FFT 频谱细化法

**函数**：`est_doppler_zoomfft.m`

**数学原理**：三步骤——混频至基带 → LPF + 抽取 → 高分辨率 FFT

$$r_{mix}[n] = r[n] \cdot e^{-j2\pi f_0 n/f_s}$$
$$r_{down}[m] = \text{LPF}\{r_{mix}\}|_{n=mM}, \quad M = \lfloor f_s / B_z \rfloor$$
$$\hat{f} = \arg\max_f |\text{FFT}_{N_{zoom}}(r_{down})[f]| \cdot \frac{B_z}{N_{zoom}} + f_0 - B_z/2$$
$$\hat{\alpha} = (\hat{f} - f_0) / f_0$$

**输入**：`r`，`f0`（辅助单频），`fs`，`Bz`（Zoom 带宽），`N_zoom`，`window_type`

**输出**：`alpha_est`，`f_est`，`spec_zoom`

**实现逻辑**：

```matlab
n = 0 : length(r)-1;
r_mix  = r .* exp(-1j * 2*pi * f0 * n / fs);

M      = round(fs / Bz);
fir_h  = fir1(64, Bz/fs);          % 低通 FIR，截止 Bz/2
r_filt = filter(fir_h, 1, r_mix);
r_down = r_filt(1 : M : end);

L   = length(r_down);
win = window(str2func(window_type), L).';
R   = fft(r_down .* win, N_zoom);
spec_zoom = abs(R(1 : N_zoom/2));

[~, pk] = max(spec_zoom);
f_axis  = (0 : N_zoom/2 - 1) * Bz / N_zoom + (f0 - Bz/2);

% 抛物线插值
if pk > 1 && pk < N_zoom/2
    A = spec_zoom(pk-1); B0 = spec_zoom(pk); C = spec_zoom(pk+1);
    delta = (C - A) / (2*(2*B0 - A - C));
    f_est = f_axis(pk) + delta * (Bz / N_zoom);
else
    f_est = f_axis(pk);
end
alpha_est = (f_est - f0) / f0;
```

---

## 5. 模块三：多普勒补偿算法

### 5.1 重采样补偿

**函数**：`comp_resample.m`

**数学原理**：以新时刻 $t'_k = k / (1+\hat{\alpha})$ 对 $r[n]$ 进行插值，输出长度 $N_{out} = \text{round}(N_{in}(1+\hat{\alpha}))$。

**输入**：`r [1×N]`，`alpha_est`，`interp_method`（`'spline'`/`'pchip'`/`'linear'`）

**输出**：`r_comp [1×N_out]`，`N_out`

**实现逻辑**：

```matlab
N_in  = length(r);
N_out = round(N_in * (1 + alpha_est));
t_orig = 0 : N_in - 1;
t_new  = (0 : N_out-1) / (1 + alpha_est);
t_new  = min(t_new, N_in - 1);     % 防止外推

% 实虚部分离插值（更稳定）
r_comp = interp1(t_orig, real(r), t_new, interp_method) + ...
    1j * interp1(t_orig, imag(r), t_new, interp_method);
```

**注意**：丢弃首尾各 $\lceil|\hat{\alpha}| \times N_{out}\rceil$ 个样点，避免边界伪影。

---

### 5.2 残余 CFO 相位旋转

**函数**：`comp_cfo.m`

**数学原理**：利用导频 LS 估计归一化 CFO $\hat{\epsilon}$，时域相位旋转消除：

$$\hat{\epsilon} = \frac{1}{N_p} \sum_{p} \angle\!\left(Y[k_p] \cdot X^*[k_p]\right) \cdot \frac{N}{2\pi k_p}$$

$$\tilde{r}[n] = r_{comp}[n] \cdot e^{-j2\pi\hat{\epsilon}n/N}$$

**输入**：`r_comp`，`Y_pilot`，`X_pilot`，`pilot_idx`，`N`

**输出**：`r_cfo_comp`，`epsilon_est`（归一化 CFO）

---

### 5.3 ICI 矩阵补偿（OFDM 高速场景）

**函数**：`comp_ici_matrix.m`

**数学原理**：ICI 矩阵第 $(k,l)$ 元素：

$$D_{kl}(\epsilon) = \frac{\sin(\pi(l-k+\epsilon))}{N\sin\!\left(\frac{\pi(l-k+\epsilon)}{N}\right)} e^{j\pi\frac{(N-1)(l-k+\epsilon)}{N}}$$

带状近似（保留 $|k-l| \leq K$ 对角线）后求解 $\mathbf{D}_{banded}\, \tilde{\mathbf{Y}} = \mathbf{Y}$。

**输入**：`Y [N×1]`，`epsilon_est`，`N`，`K_bands`（默认 5）

**输出**：`Y_comp [N×1]`，`D_mat`（可选）

**实现逻辑**：

```matlab
D_mat = zeros(N, N);
for k = 1:N
    for l = max(1,k-K_bands) : min(N,k+K_bands)
        delta = l - k + epsilon_est;
        if abs(delta) < 1e-10
            D_mat(k,l) = 1;
        else
            D_mat(k,l) = sin(pi*delta) / (N*sin(pi*delta/N)) ...
                         * exp(1j*pi*(N-1)*delta/N);
        end
    end
end
Y_comp = D_mat \ Y;    % 比 inv(D_mat)*Y 更高效
```

---

## 6. 模块四：信道估计与均衡（OFDM）

### 6.1 `ch_est_ls.m`

LS 导频估计 + 线性/MMSE 插值：

$$\hat{H}[k_p] = Y[k_p] / X[k_p], \quad \hat{H}[k] = \text{interp1}(k_p,\, \hat{H}[k_p],\, k,\, \text{'spline'})$$

**输入**：`Y [N×1]`，`X_pilot [1×Np]`，`pilot_idx [1×Np]`，`N`

**输出**：`H_est [N×1]`

### 6.2 `equalizer_fde_ofdm.m`

MMSE 频域均衡：

$$W[k] = \frac{\hat{H}^*[k]}{|\hat{H}[k]|^2 + \sigma_n^2/\sigma_x^2}, \quad \hat{X}[k] = W[k] \cdot \tilde{Y}[k]$$

**输入**：`Y [N×1]`，`H_est [N×1]`，`noise_var`，`sig_var`（默认 1）

**输出**：`X_eq [N×1]`

---

## 7. 模块五：SC-FDE 单载波频域均衡系统

### 7.1 SC-FDE 系统模型

SC-FDE 与 OFDM 在频域均衡结构上高度相似，但发射端不做 IFFT，保持时域符号序列，峰均比（PAPR）更低，对多普勒的鲁棒性更强。

```
发射端：
  比特 → 编码 → QAM调制 → 分块（每块K符号）
       → 插入CP/ZP → 插入前导码和后导码（测速）→ 发送

接收端：
  r[n] → 多普勒估计（复自相关幅相联合）
       → 重采样补偿 → 帧同步 → 去前导码
       → 逐块处理：去CP → FFT（K点）→ 信道估计 → MMSE均衡
       → IFFT → 软判决 → [Turbo迭代] → 译码输出
```

**帧结构**（时域样点排列）：

```
| Preamble(L_p) | GI(L_g) | Block_1(K+Ncp) | GI(L_g) | Block_2(K+Ncp) | ... | Postamble(L_p) |
```

- `Preamble / Postamble`：chirp 或 m 序列，长度 $L_p$，用于帧同步与多普勒估计
- `GI`：保护间隔（零填充），长度 $\geq \tau_{max} \cdot f_s$
- `Block_i`：CP（$N_{cp}$ 样点）+ 数据（$K$ 样点）

### 7.2 发射端：`gen_scfde_signal.m`

**功能**：将调制符号封装为带 CP 的 SC-FDE 帧，插入测速序列。

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `symbols` | `[1×N_sym]` complex | QAM 调制符号 |
| `P` | struct | 系统参数（见参数配置表） |

**输出**：`s_frame [1×N_frame]`，`preamble [1×L_p]`

**实现逻辑**：

```matlab
% 生成前/后导码（chirp 或 m 序列）
preamble   = gen_chirp(P.L_preamble, P.fs, P.f_start, P.f_end);
postamble  = preamble;   % 发送同一序列，间隔 T_v

% 对调制符号分块，每块加 CP
N_blocks   = ceil(length(symbols) / P.K);
s_data     = zeros(1, N_blocks * (P.K + P.Ncp_sc));
GI         = zeros(1, P.L_gi);

for b = 1:N_blocks
    blk  = symbols((b-1)*P.K+1 : min(b*P.K, end)); % 取一块数据
    blk  = [blk, zeros(1, P.K - length(blk))];      % 补零对齐
    cp   = blk(end - P.Ncp_sc + 1 : end);            % 循环前缀
    s_data((b-1)*(P.K+P.Ncp_sc)+1 : b*(P.K+P.Ncp_sc)) = [cp, blk];
end

% 帧封装
s_frame = [preamble, GI, s_data, GI, postamble];
```

### 7.3 接收机：多普勒估计

调用 `est_doppler_xcorr.m`，利用帧首 preamble 和帧尾 postamble 做复自相关幅相联合估计，获取 $\hat{\alpha}$。

关键参数：$T_v = $ 帧总时长（秒）$\approx$ 帧长 / $f_s$。

### 7.4 接收机：重采样与帧同步

1. 调用 `comp_resample(r_rx, alpha_est, 'spline')` 获得 `r_comp`
2. 在 `r_comp` 中用 `est_doppler_xcorr` 返回的 `tau_est` 定位帧起始位置
3. 跳过 preamble 和 GI，提取各数据块

### 7.5 接收机：信道估计（`ch_est_scfde.m`）

**功能**：利用已知 preamble 序列（或专用训练块）估计信道冲激响应，转换到频域供均衡使用。

**数学原理**：

设 preamble 序列频域为 $P[k] = \text{FFT}(p[n])$，接收端对应段频域为 $Y_p[k]$，LS 信道频率响应估计：

$$\hat{H}[k] = Y_p[k] / P[k], \quad k = 0, \ldots, K-1$$

时域信道冲激响应（用于后续 IFFT 截断处理噪声）：

$$\hat{h}[n] = \text{IFFT}(\hat{H}[k]) \cdot \mathbf{1}_{n < L_{ch}}$$

再变换回频域：$\hat{H}_{clean}[k] = \text{FFT}(\hat{h}[n], K)$

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `r_preamble` | `[1×L_p]` complex | 接收到的前导码段 |
| `preamble` | `[1×L_p]` complex | 已知发送前导码 |
| `K` | integer | 均衡块长度（FFT 点数） |
| `L_ch` | integer | 信道最大长度（样点数），用于截断去噪 |

**输出**：`H_est [K×1]`，`h_est [L_ch×1]`

**实现逻辑**：

```matlab
% FFT 对齐到 K 点
P_freq  = fft(preamble, K);
Yp_freq = fft(r_preamble(1:K), K);

% LS 估计
H_raw = Yp_freq ./ P_freq;

% 时域截断去噪
h_raw    = ifft(H_raw, K);
h_est    = h_raw(1 : L_ch);      % 保留有效信道长度内的抽头
H_est    = fft(h_est, K);        % 重新变换为频域
```

### 7.6 接收机：SC-FDE 频域均衡（`equalizer_fde_sc.m`）

**功能**：对每个数据块在频域做 MMSE 均衡后变换回时域。

**对每块的处理流程**：

```
去CP → FFT(K点) → MMSE均衡 → IFFT(K点) → 软判决（软输出供Turbo）
```

**MMSE 均衡系数**：

$$W[k] = \frac{\hat{H}^*[k]}{|\hat{H}[k]|^2 + \sigma_n^2 / \sigma_x^2}$$

**输入**：`r_block [1×K]`（去 CP 后），`H_est [K×1]`，`noise_var`，`sig_var`

**输出**：`x_eq [1×K]`（时域均衡后符号），`llr [1×K×log2M]`（对数似然比，供 Turbo 迭代）

**实现逻辑**：

```matlab
% 对每块
Y_block = fft(r_block, K);

% MMSE 均衡
W       = conj(H_est) ./ (abs(H_est).^2 + noise_var / sig_var);
X_eq    = W .* Y_block;

% 时域转换
x_eq    = ifft(X_eq, K);

% 软输出（对数似然比，QPSK 示例）
% llr[i] = 2*real(x_eq[i]) * sqrt(2) / noise_var_eff
noise_var_eff = mean(abs(1 - W .* H_est).^2) * sig_var + noise_var * mean(abs(W).^2);
llr = 2 * sqrt(2) * real(x_eq) / noise_var_eff;
```

### 7.7 接收机：Turbo 迭代均衡（`turbo_equalizer.m`）

**功能**：利用信道译码器的软输出反馈给均衡器，迭代提升性能（外部信息传递，EXIT 图分析）。

**迭代框架**（SISO 均衡 + SISO 解码）：

```
初始先验 LLR = 0
for iter = 1 : N_iter
    [x_eq, L_e_eq]  = MMSE_equalizer(r, H_est, L_a_eq)  % 均衡器外信息
    L_a_dec = L_e_eq                                       % 送入解码器作为先验
    [L_e_dec, bits] = BCJR_decoder(L_a_dec, trellis)      % 解码器外信息
    L_a_eq  = L_e_dec                                      % 反馈给均衡器
end
```

**MMSE 均衡器（含先验 LLR 的软干扰消除）**：

均衡器在每次迭代中利用先验信息 $L_a[n]$ 计算符号软均值 $\bar{x}[n]$ 和方差 $\sigma_x^2[n]$：

$$\bar{x}[n] = E[x[n]|L_a[n]] = \tanh(L_a[n]/2) \quad \text{（BPSK）}$$

$$\sigma_x^2[n] = 1 - |\bar{x}[n]|^2$$

减去软干扰后的 MMSE 系数（逐样点不同）：

$$W[n] = \frac{\hat{h}^*[n]}{\|\hat{H}\|^2 \sigma_x^2 + \sigma_n^2}$$

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `r_blocks` | `[N_blk×K]` complex | 去 CP 后各块时域信号 |
| `H_est` | `[K×1]` complex | 信道频率响应 |
| `noise_var` | scalar | 噪声方差 |
| `trellis` | struct | 信道编码网格结构（MATLAB `poly2trellis`） |
| `N_iter` | integer | 最大迭代次数（典型 3~6） |

**输出**：`bits_dec [1×N_bits]`，`llr_final [1×N_coded]`

### 7.8 SC-FDE 仿真主流程（`main_scfde.m`）

```matlab
%% main_scfde.m
clear; clc; close all;
run('params/sys_params_scfde.m');

%% 1. 发射端
bits_tx  = randi([0,1], 1, P.N_bits);
bits_enc = convenc(bits_tx, P.trellis);          % 卷积编码
symbols  = qammod(bits_enc, P.M_qam, 'InputType','bit', 'UnitAveragePower',true);
[s_frame, preamble] = gen_scfde_signal(symbols, P);

%% 2. 信道
[r_rx, noise_var] = gen_uwa_channel(s_frame, P.channel, P.SNR_dB);

%% 3. 多普勒估计（复自相关幅相联合）
[alpha_est, alpha_coarse, tau_est] = est_doppler_xcorr(...
    r_rx, preamble, P.T_v, P.fs, P.fc, P.alpha_bound);
fprintf('α_true=%.5f  α_est=%.5f  err=%.2e\n', ...
    P.channel.alpha, alpha_est, abs(alpha_est-P.channel.alpha));

%% 4. 重采样补偿
r_comp = comp_resample(r_rx, alpha_est, 'spline');

%% 5. 帧同步：定位数据块起始
frame_start = round(tau_est * P.fs) + P.L_preamble + P.L_gi + 1;
r_data_raw  = r_comp(frame_start : frame_start + P.N_blocks*(P.K+P.Ncp_sc) - 1);

%% 6. 信道估计
r_preamble = r_comp(round(tau_est*P.fs)+1 : round(tau_est*P.fs)+P.L_preamble);
H_est      = ch_est_scfde(r_preamble, preamble, P.K, P.L_ch);

%% 7. 逐块 SC-FDE 均衡
x_eq_all = [];
for b = 1:P.N_blocks
    blk_start = (b-1)*(P.K + P.Ncp_sc) + 1;
    blk       = r_data_raw(blk_start+P.Ncp_sc : blk_start+P.Ncp_sc+P.K-1);  % 去CP
    x_eq      = equalizer_fde_sc(blk, H_est, noise_var);
    x_eq_all  = [x_eq_all, x_eq];
end

%% 8. Turbo 迭代均衡（可选）
if P.use_turbo
    r_blocks = reshape(r_data_raw, P.K+P.Ncp_sc, P.N_blocks).';
    r_blocks = r_blocks(:, P.Ncp_sc+1:end);  % 去CP
    bits_dec = turbo_equalizer(r_blocks, H_est, noise_var, P.trellis, P.N_iter);
else
    bits_dec = qamdemod(x_eq_all(1:length(bits_enc)), P.M_qam, ...
        'OutputType','bit', 'UnitAveragePower',true);
    bits_dec = vitdec(bits_dec, P.trellis, 5, 'trunc', 'hard');
end

%% 9. 性能评估
[BER, errs] = calc_ber(bits_tx, bits_dec(1:P.N_bits));
fprintf('SC-FDE BER = %.4e  (%d errors)\n', BER, errs);
```

---

## 8. 模块六：OTFS 调制收发系统

### 8.1 OTFS 系统模型与变换原理

OTFS 使用 $N \times M$ 时延-多普勒（DD）符号网格，物理含义：

| 符号 | 含义 |
|------|------|
| $N$ | 多普勒轴符号数（时间分辨率块数） |
| $M$ | 时延轴符号数（频率分辨率块数） |
| $\Delta f$ | 子载波间隔（Hz），决定时延分辨率 $1/(M\Delta f)$ |
| $T = 1/\Delta f$ | OFDM 符号周期（秒），决定多普勒分辨率 $1/(NT)$ |

**核心变换关系**：

```
DD域信号 x_{DD}[k,l]
   ↓ ISFFT（逆辛有限傅里叶变换）
时频域符号 X[n,m]
   ↓ Heisenberg变换（时频调制/OFDM结构）
时域发射信号 s(t)
```

**ISFFT**（DD → 时频）：

$$X[n,m] = \frac{1}{\sqrt{NM}}\sum_{k=0}^{N-1}\sum_{l=0}^{M-1} x_{DD}[k,l] \cdot e^{j2\pi\!\left(\frac{nk}{N} - \frac{ml}{M}\right)}$$

**SFFT**（时频 → DD，接收端）：

$$y_{DD}[k,l] = \frac{1}{\sqrt{NM}}\sum_{n=0}^{N-1}\sum_{m=0}^{M-1} Y[n,m] \cdot e^{-j2\pi\!\left(\frac{nk}{N} - \frac{ml}{M}\right)}$$

**DD 域输入输出**（理想矩形脉冲，忽略分数多普勒）：

$$y_{DD}[k,l] = \sum_{i=1}^{P} h_i \cdot e^{j2\pi \frac{k_i l_i}{NM}} \cdot x_{DD}[(k-k_i)_N,\, (l-l_i)_M] + w[k,l]$$

其中 $(k-k_i)_N$ 表示模 $N$ 的循环偏移。

### 8.2 OTFS 发射端（`gen_otfs_signal.m`）

**功能**：将 DD 域调制符号转换为时域发射信号，含 CP。

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `X_DD` | `[N×M]` complex | DD 域数据符号（已插入导频）|
| `P` | struct | 系统参数 |

**输出**：`s_tx [1×(NM+N_cp_otfs)]` complex（时域信号，整帧含 CP）

**实现逻辑**：

```matlab
N = P.N_otfs;  M = P.M_otfs;

%% Step 1: ISFFT（DD → 时频）
% 先做行方向 IDFT（多普勒轴），再做列方向 DFT（时延轴）
X_TF = zeros(N, M);
for m = 0:M-1
    % 对每一列（时延）做行方向（多普勒）IDFT
    X_TF(:, m+1) = ifft(X_DD(:, m+1)) * sqrt(N);  % N点IDFT，归一化
end
for n = 0:N-1
    % 对每一行（时间）做列方向（频率）DFT
    X_TF(n+1, :) = fft(X_TF(n+1, :)) / sqrt(M);   % M点DFT，归一化
end
% 等价于：X_TF = ifft(X_DD, N, 1) .* sqrt(N) 后 fft(·, M, 2) / sqrt(M)

%% Step 2: Heisenberg变换（OFDM调制，生成时域信号）
% 等价于：对每个时间符号 n 做 M 点 IFFT，拼接
s_tx_no_cp = zeros(1, N*M);
for n = 1:N
    s_ofdm_sym = ifft(X_TF(n, :), M) * sqrt(M);   % OFDM符号时域（M点）
    s_tx_no_cp((n-1)*M+1 : n*M) = s_ofdm_sym;
end

%% Step 3: 加循环前缀（整帧 CP，长度需覆盖最大时延 + 保护）
Ncp_otfs = P.Ncp_otfs;   % 建议 >= max_delay_samp + 10
cp       = s_tx_no_cp(end - Ncp_otfs + 1 : end);
s_tx     = [cp, s_tx_no_cp];
```

### 8.3 OTFS 时延-多普勒域信道矩阵构建（`otfs_channel_model.m`）

**功能**：根据信道参数 $\{h_i, \tau_i, \nu_i\}$ 构建 DD 域有效信道矩阵 $\mathbf{H}_{eff} \in \mathbb{C}^{NM \times NM}$，用于接收机均衡和验证。

**DD 域路径参数映射**：

$$l_i = \text{round}(\tau_i \cdot M \cdot \Delta f), \quad k_i = \text{round}(\nu_i \cdot N \cdot T)$$

其中 $\nu_i = \alpha_i \cdot f_c$ 为第 $i$ 条路径的多普勒频率。

**实现逻辑**：

```matlab
N = P.N_otfs;  M = P.M_otfs;
NM = N * M;

H_eff = zeros(NM, NM);

for i = 1:P.channel.P
    nu_i = P.channel.alpha * P.fc;  % 一致多普勒，单一多普勒频率
    l_i  = round(P.channel.delays(i) * M * P.df);    % 时延格点
    k_i  = round(nu_i * N * P.T_sym);                % 多普勒格点（对应 alpha）

    % 分数多普勒处理（若 k_i 非整数，保留最近两个格点）
    % 本文档简化为整数格点处理
    phase = exp(1j * 2*pi * k_i * l_i / (N*M));

    for q = 0:NM-1
        % DD域循环卷积结构
        [kq, lq] = ind2sub([N, M], q+1);
        kq = kq - 1;  lq = lq - 1;  % 0-indexed
        k_src = mod(kq - k_i, N);
        l_src = mod(lq - l_i, M);
        p_src = sub2ind([N, M], k_src+1, l_src+1);
        H_eff(q+1, p_src) = H_eff(q+1, p_src) + P.channel.gains(i) * phase;
    end
end
```

### 8.4 OTFS 接收端：嵌入导频信道估计（`ch_est_otfs.m`）

**导频放置策略**：在 DD 域插入单个脉冲导频 $x_p[k_p, l_p]$，周围保留保护区：

```
DD 网格示意（N=8, M=16）：
         l（时延轴）→
         0  1  2  3  4  5  6  ... 15
k  0  [  0  0  0  0  0  0  0  ...  0 ]
（  1  [  0  0  0  0  0  0  0  ...  0 ]
多  2  [  0  0  G  G  G  G  G  ...  0 ]  G=保护区
普  3  [  0  0  G  xp G  G  G  ...  0 ]  xp=导频脉冲
勒  4  [  0  0  G  G  G  G  G  ...  0 ]
轴  5  [  d  d  G  G  G  d  d  ...  d ]  d=数据符号
）  ...
```

**信道估计原理**：接收导频区域 $y_{DD}[k,l]$ 直接反映信道路径（归一化后）：

$$h_i \approx y_{DD}[k_p + k_i, l_p + l_i] / x_p$$

**保护区尺寸要求**：

$$\text{guard\_delay} \geq l_{max} = \text{round}(\tau_{max} \cdot M \cdot \Delta f)$$
$$\text{guard\_doppler} \geq k_{max} = \text{round}(|\alpha|_{max} \cdot f_c \cdot N \cdot T)$$

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `Y_DD` | `[N×M]` complex | 接收的 DD 域信号 |
| `kp`, `lp` | integer | 导频位置索引 |
| `xp_amp` | scalar | 导频符号幅度（已知） |
| `guard_k`, `guard_l` | integer | 保护区尺寸 |

**输出**：`h_dd [guard_k×guard_l]`（DD 域估计信道），`path_list`（路径列表：`[k_i, l_i, h_i]`）

**实现逻辑**：

```matlab
h_dd = zeros(2*guard_k+1, 2*guard_l+1);
path_list = [];

for dk = -guard_k : guard_k
    for dl = 0 : guard_l
        k_rcv = mod(kp + dk, N) + 1;
        l_rcv = mod(lp + dl, M) + 1;
        h_val = Y_DD(k_rcv, l_rcv) / xp_amp;

        if abs(h_val) > P.ch_est_threshold   % 阈值检测，滤除噪声
            h_dd(dk+guard_k+1, dl+1) = h_val;
            path_list = [path_list; dk, dl, h_val];
        end
    end
end
```

### 8.5 OTFS 接收端：消息传递均衡器（`mp_detector.m`）

**功能**：基于信道稀疏结构，用消息传递（Belief Propagation）算法在 DD 域高效实现 MAP 检测。

**因子图模型**：

DD 域输入输出关系 $\mathbf{y} = \mathbf{H}_{eff}\mathbf{x} + \mathbf{w}$ 对应一个稀疏因子图：

- **变量节点**：$x[q]$，$q = 0,\ldots,NM-1$（发送符号）
- **观测节点**：$y[q]$（观测值）
- **边**：仅在 $H_{eff}[q, p] \neq 0$ 时连接（稀疏，每个节点仅连接 $P$ 条边）

**消息更新规则**（高斯近似版本，复杂度 $O(P \cdot NM \cdot |\mathcal{X}|)$）：

初始化：每个变量节点的先验分布为均匀分布（无编码）或由译码器提供。

**从观测节点 $q$ 到变量节点 $p$ 的消息**（均值-方差近似）：

$$\mu_{q \to p}^{mean} = \frac{y[q] - \sum_{p' \neq p} H[q,p'] \cdot \hat{x}_{p' \to q}^{mean}}{H[q,p]}$$

$$\sigma_{q \to p}^2 = \frac{\sigma_n^2 + \sum_{p'\neq p}|H[q,p']|^2 \hat{x}_{p'\to q}^{var}}{|H[q,p]|^2}$$

**从变量节点 $p$ 到观测节点 $q$ 的消息**（MAP 软判决）：

对各星座点 $s \in \mathcal{X}$ 计算：

$$P_{p \to q}(x[p]=s) \propto \prod_{q' \neq q} \mathcal{CN}(s;\, \mu_{q'\to p}^{mean},\, \sigma_{q'\to p}^2) \cdot P_{prior}(s)$$

$$\hat{x}_{p \to q}^{mean} = \sum_s s \cdot P_{p\to q}(s), \quad \hat{x}_{p\to q}^{var} = \sum_s |s|^2 P_{p\to q}(s) - |\hat{x}_{p\to q}^{mean}|^2$$

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `Y_DD` | `[N×M]` complex | 接收 DD 域信号（矢量化为 `[NM×1]`） |
| `path_list` | `[P×3]` | 估计的路径 `[k_i, l_i, h_i]` |
| `N`, `M` | integer | DD 网格尺寸 |
| `constellation` | `[1×C]` | 星座点集合（QAM） |
| `noise_var` | scalar | 噪声方差 |
| `N_iter_mp` | integer | 消息传递迭代次数（典型 10~30） |
| `L_a` | `[NM×1]` | 先验 LLR（来自译码器，初始为 0） |

**输出**：`x_hat [NM×1]`（硬判决），`LLR_out [NM×log2C]`（软输出 LLR）

**实现逻辑（简化版）**：

```matlab
NM = N * M;
C  = length(constellation);
P_path = size(path_list, 1);

% 构建稀疏信道矩阵（仅存储非零项）
H_sp = sparse(NM, NM);
for i = 1:P_path
    ki = path_list(i,1);  li = path_list(i,2);  hi = path_list(i,3);
    phase = exp(1j*2*pi*ki*li/(N*M));
    for q = 0:NM-1
        [kq, lq] = ind2sub([N,M], q+1);
        kq=kq-1; lq=lq-1;
        k_src = mod(kq-ki, N); l_src = mod(lq-li, M);
        p_src = sub2ind([N,M], k_src+1, l_src+1);
        H_sp(q+1, p_src) = H_sp(q+1, p_src) + hi * phase;
    end
end

y_vec = Y_DD(:);     % NM×1

% 初始化：均匀先验
x_mean_v2o = zeros(NM, NM);    % 变量->观测 均值（稀疏，仅非零项有意义）
x_var_v2o  = ones(NM, NM);

for iter = 1:N_iter_mp
    % 观测节点 -> 变量节点 消息
    mu_o2v   = zeros(NM, NM);
    sig_o2v  = zeros(NM, NM);
    for q = 1:NM
        [~, p_list] = find(H_sp(q,:));  % q 连接的变量节点
        for p = p_list
            h_qp   = H_sp(q, p);
            interf = y_vec(q) - sum(H_sp(q,:) .* x_mean_v2o(q,:), 'all') ...
                     + h_qp * x_mean_v2o(q, p);
            var_interf = noise_var + sum(abs(H_sp(q,:)).^2 .* x_var_v2o(q,:), 'all') ...
                         - abs(h_qp)^2 * x_var_v2o(q, p);
            mu_o2v(p, q)  = interf / h_qp;
            sig_o2v(p, q) = var_interf / abs(h_qp)^2;
        end
    end

    % 变量节点 -> 观测节点 消息（软判决）
    for p = 1:NM
        [~, q_list] = find(H_sp(:, p));   % p 连接的观测节点
        for q = q_list'
            log_prob = zeros(1, C);
            for c = 1:C
                log_prob(c) = -abs(constellation(c) - mu_o2v(p,q))^2 / sig_o2v(p,q);
                % 加入其他观测节点的信息（乘积->对数求和）
                for q2 = q_list'
                    if q2 ~= q
                        log_prob(c) = log_prob(c) ...
                            - abs(constellation(c) - mu_o2v(p,q2))^2 / sig_o2v(p,q2);
                    end
                end
            end
            prob = exp(log_prob - max(log_prob));
            prob = prob / sum(prob);
            x_mean_v2o(q, p) = sum(constellation .* prob);
            x_var_v2o(q, p)  = sum(abs(constellation).^2 .* prob) - abs(x_mean_v2o(q,p))^2;
        end
    end
end

% 最终判决
x_hat = zeros(NM, 1);
for p = 1:NM
    [~, q_list] = find(H_sp(:,p));
    log_prob = zeros(1, C);
    for c = 1:C
        for q = q_list'
            log_prob(c) = log_prob(c) - abs(constellation(c)-mu_o2v(p,q))^2/sig_o2v(p,q);
        end
    end
    [~, best] = max(log_prob);
    x_hat(p)  = constellation(best);
end
```

### 8.6 OTFS 仿真主流程（`main_otfs.m`）

```matlab
%% main_otfs.m
clear; clc; close all;
run('params/sys_params_otfs.m');

N = P.N_otfs;  M = P.M_otfs;

%% 1. 发射端
bits_tx  = randi([0,1], 1, P.N_bits);
symbols  = qammod(bits_tx, P.M_qam, 'InputType','bit', 'UnitAveragePower',true);
N_data   = N*M - (2*P.guard_k+1)*(P.guard_l+1);  % 扣除导频保护区

% 构建 DD 域符号矩阵（嵌入导频）
X_DD = zeros(N, M);
data_idx_dd = get_data_indices(N, M, P.kp, P.lp, P.guard_k, P.guard_l);
X_DD(data_idx_dd) = symbols(1:length(data_idx_dd));
X_DD(P.kp+1, P.lp+1) = P.xp_amp;   % 插入导频

% OTFS 调制
s_tx = gen_otfs_signal(X_DD, P);

%% 2. 信道
[r_rx, noise_var] = gen_uwa_channel(s_tx, P.channel, P.SNR_dB);

%% 3. OTFS 解调（Wigner变换 + SFFT）
r_no_cp  = r_rx(P.Ncp_otfs+1 : P.Ncp_otfs+N*M);   % 去整帧CP
r_mat    = reshape(r_no_cp, M, N).';                 % N×M，每行一个OFDM符号
Y_TF     = zeros(N, M);
for n = 1:N
    Y_TF(n, :) = fft(r_mat(n, :), M) / sqrt(M);    % Wigner变换（FFT）
end

% SFFT（时频 -> DD）
Y_DD = zeros(N, M);
for m = 1:M
    Y_DD(:, m) = fft(Y_TF(:, m), N) / sqrt(N);
end
for n = 1:N
    Y_DD(n, :) = ifft(Y_DD(n, :), M) * sqrt(M);
end

%% 4. 信道估计（嵌入导频）
[h_dd, path_list] = ch_est_otfs(Y_DD, P.kp, P.lp, P.xp_amp, ...
    P.guard_k, P.guard_l, P);

fprintf('估计路径数: %d (真实: %d)\n', size(path_list,1), P.channel.P);

%% 5. MP 均衡器
constellation = qammod(0:P.M_qam-1, P.M_qam, 'UnitAveragePower',true);
x_hat = mp_detector(Y_DD, path_list, N, M, constellation, noise_var, P.N_iter_mp);

%% 6. 解调与 BER
x_hat_data = x_hat(data_idx_dd);
bits_rx    = qamdemod(x_hat_data, P.M_qam, 'OutputType','bit', 'UnitAveragePower',true);
[BER, errs] = calc_ber(bits_tx(1:length(bits_rx)), bits_rx);
fprintf('OTFS BER = %.4e  (%d errors)\n', BER, errs);

%% 7. 可视化 DD 域
figure;
subplot(1,2,1);
imagesc(abs(X_DD)); colorbar; title('发射 DD 域（含导频）');
xlabel('时延轴 l'); ylabel('多普勒轴 k');
subplot(1,2,2);
imagesc(abs(Y_DD)); colorbar; title('接收 DD 域');
xlabel('时延轴 l'); ylabel('多普勒轴 k');
```

---

## 9. 模块七：阵列波束形成增强多普勒估计

### 9.1 阵列信号模型

$M$ 阵元均匀线阵（ULA），阵元间距 $d = \lambda/2$（$\lambda = c/f_c$），信号入射角 $\theta$。

第 $m$ 阵元相对参考阵元（$m=1$）的精确时延：

$$\tau_m = (m-1) \frac{d \cos\theta}{c}, \quad m = 1, \ldots, M$$

第 $m$ 阵元接收信号（含多普勒）：

$$r_m[n] = \sum_{p=1}^{P} a_p \cdot s\!\left[\text{round}\!\left(\frac{n}{1+\alpha} - \frac{(\tau_p + \tau_m)}{T_s}\right)\right] + n_m[n]$$

**核心思路（空时联合变采样）**：$M$ 个阵元在时间轴上错开 $\tau_m$ 提供了"额外的"非整数延迟采样点。将各阵元的采样点合并排序后，等效采样率从 $f_s$ 提升至接近 $M \cdot f_s$，从而使多普勒估计的 Cramér-Rao 下界降低为原来的 $1/M^2$。

### 9.2 阵列时延标定（`bf_delay_calibration.m`）

**功能**：精确标定各阵元相对时延 $\hat{\tau}_m$，为非均匀重采样提供精确时刻。

**方法**：利用发射的已知前导码序列，通过互相关峰值定位各阵元接收信号的时间差：

$$\hat{\tau}_m = \frac{\arg\max_\tau |\sum_n r_m[n] \cdot p^*[n-\tau]|^2}{f_s} - \hat{\tau}_1$$

**输入**：`R_array [M×N]`（各阵元信号），`preamble [1×L]`，`fs`

**输出**：`tau_cal [1×M]`（各阵元相对时延估计，秒），参考阵元 $\tau_1 = 0$

**实现逻辑**：

```matlab
tau_cal = zeros(1, M);
corr1   = abs(xcorr(R_array(1,:), preamble));
[~, idx1] = max(corr1);

for m = 2:M
    corr_m    = abs(xcorr(R_array(m,:), preamble));
    [~, idxm] = max(corr_m);
    tau_cal(m) = (idxm - idx1) / fs;   % 相对参考阵元的时延（秒）
end

% 精细化：在粗时延附近用子样点插值
for m = 2:M
    lag_samp = round(tau_cal(m) * fs);
    interp_range = lag_samp + (-5:5);   % ±5 样点搜索
    corr_fine = zeros(1, length(interp_range));
    for ii = 1:length(interp_range)
        seg = circshift(R_array(m,:), -interp_range(ii));
        corr_fine(ii) = abs(sum(seg(1:L) .* conj(preamble)));
    end
    % 抛物线插值求峰值亚样点位置
    [~, pk] = max(corr_fine);
    if pk > 1 && pk < length(interp_fine)
        A=corr_fine(pk-1); B0=corr_fine(pk); C=corr_fine(pk+1);
        delta = (C-A)/(2*(2*B0-A-C));
        tau_cal(m) = (interp_range(pk) + delta) / fs;
    end
end
```

### 9.3 空时联合非均匀变采样重建（`bf_nonuniform_resample.m`）

**核心思想**：

各阵元的采样点 $r_m[n]$ 实际上对应信号在时刻 $t_{m,n} = nT_s + \tau_m$ 的采样。将 $M$ 个阵元的采样点集合：

$$\mathcal{T} = \{t_{m,n} = nT_s + \tau_m \mid m=1,\ldots,M,\; n=0,\ldots,N-1\}$$

这些时刻点是**非均匀分布**的（间距不等，由 $\tau_m$ 决定）。对这 $M \times N$ 个非均匀样本按时间排序，得到密度约为 $M/T_s$ 的时间序列，用三次样条或 sinc 插值重建高采样率均匀信号。

**双指针排序算法**（O($MN$) 时间复杂度）：

```matlab
% 所有采样时刻
all_times = zeros(M, N);
all_vals  = zeros(M, N);
for m = 1:M
    all_times(m, :) = (0:N-1)*Ts + tau_cal(m);
    all_vals(m, :)  = R_array(m, :);
end

% 展平并排序
all_times_vec = all_times(:).';
all_vals_vec  = all_vals(:).';
[t_sorted, sort_idx] = sort(all_times_vec);
r_sorted = all_vals_vec(sort_idx);
```

**插值到均匀高采样率网格**（等效 $f_{s,eff} \approx M \cdot f_s$）：

```matlab
Ts_eff   = Ts / M;                              % 等效采样间隔（精确）
t_uniform = 0 : Ts_eff : (N-1)*Ts;             % 均匀高速网格
r_highrate = interp1(t_sorted, r_sorted, t_uniform, 'spline');
```

**输出**：`r_highrate [1×(M*N)]`（等效高采样率信号），`Ts_eff`（等效采样间隔）

**功能**：`bf_nonuniform_resample(R_array, tau_cal, fs)`

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `R_array` | `[M×N]` complex | 各阵元接收信号 |
| `tau_cal` | `[1×M]` | 各阵元时延标定值（秒） |
| `fs` | scalar | 原始采样率（Hz） |

**输出**：`r_highrate [1×N_eff]`，`fs_eff`（等效采样率 ≈ $M \cdot f_s$）

### 9.4 波束形成（`bf_conventional.m`）

**功能**：时延求和（DAS）波束形成，将 $M$ 路信号对准到目标方向 $\theta_0$ 后叠加，获得阵列增益 $\approx M$（SNR 提升 $10\log_{10}M$ dB）。

**数学原理**：

$$y_{BF}[n] = \frac{1}{M}\sum_{m=1}^{M} r_m\!\left[n - \text{round}\!\left(\frac{\tau_m}{T_s}\right)\right] \cdot e^{-j2\pi f_c \tau_m}$$

**输入**：`R_array [M×N]`，`tau_cal [1×M]`，`fc`，`fs`，`theta_steer`（导向角，弧度）

**输出**：`y_bf [1×N]`（波束输出信号），`array_gain_dB`（阵列增益估计）

**实现逻辑**：

```matlab
y_bf = zeros(1, N);
for m = 1:M
    delay_samp_m = round(tau_cal(m) * fs);
    phase_comp   = exp(-1j * 2*pi * fc * tau_cal(m));
    r_aligned    = circshift(R_array(m,:), -delay_samp_m);
    y_bf         = y_bf + r_aligned * phase_comp;
end
y_bf = y_bf / M;
array_gain_dB = 10*log10(M);
```

### 9.5 基于波束域信号的多普勒估计（`est_doppler_beamforming.m`）

**完整流程**：

```
阵列信号 R_array [M×N]
    ↓
[Step 1] 时延标定 bf_delay_calibration → tau_cal [1×M]
    ↓
[Step 2] 空时变采样重建 bf_nonuniform_resample → r_highrate, fs_eff
    ↓
[Step 3] 基于 r_highrate 用 est_doppler_xcorr（或 CAF）估计多普勒
          精度提升约 √M 倍（CRLB 降低 M 倍）
    ↓
[Step 4] 可选：对波束域信号 y_bf 再次估计，利用阵列增益进一步提升低 SNR 性能
    ↓
alpha_est（高精度多普勒因子）
```

**CRLB 分析**：

单路信号多普勒估计 CRLB（基于信号带宽 $B$，时长 $T_{obs}$）：

$$\text{CRLB}_{single}(\alpha) = \frac{1}{\text{SNR} \cdot (2\pi f_c)^2 \cdot T_{obs}^2 \cdot \int_0^{T_{obs}} t^2 dt}$$

空时变采样后等效采样率提升 $M$ 倍，等效观测信息矩阵增大 $M^2$ 倍：

$$\text{CRLB}_{array}(\alpha) \approx \frac{\text{CRLB}_{single}(\alpha)}{M^2}$$

**输入**：

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `R_array` | `[M×N]` complex | 各阵元接收信号 |
| `preamble` | `[1×L]` complex | 已知前导码 |
| `P` | struct | 系统参数 |

**输出**：`alpha_est`，`tau_est`，`fs_eff`，`r_highrate`（高速率重建信号）

**实现逻辑**：

```matlab
function [alpha_est, tau_est, fs_eff, r_highrate] = ...
        est_doppler_beamforming(R_array, preamble, P)

[M, N] = size(R_array);

%% Step 1: 时延标定
tau_cal = bf_delay_calibration(R_array, preamble, P.fs);

%% Step 2: 空时变采样重建
[r_highrate, fs_eff] = bf_nonuniform_resample(R_array, tau_cal, P.fs);

%% Step 3: 高速率信号上估计多普勒
% 用复自相关幅相联合法（前后导码位于高速率信号中）
% 注意：preamble 也需相应插值到 fs_eff
n_orig  = 0 : length(preamble)-1;
n_new   = linspace(0, length(preamble)-1, round(length(preamble)*fs_eff/P.fs));
preamble_eff = interp1(n_orig, preamble, n_new, 'spline');
T_v_eff = P.T_v;   % 时间间隔不变

[alpha_est, ~, tau_est] = est_doppler_xcorr(...
    r_highrate, preamble_eff, T_v_eff, fs_eff, P.fc, P.alpha_bound);

% 可选：波束形成增益辅助（低SNR时）
if P.use_bf_assist
    y_bf = bf_conventional(R_array, tau_cal, P.fc, P.fs, P.theta_signal);
    [alpha_bf, ~] = est_doppler_xcorr(y_bf, preamble, P.T_v, P.fs, P.fc, P.alpha_bound);
    % 加权融合（高速率估计精度高，BF估计SNR高）
    w_eff = 1 / (1 + P.noise_weight);
    alpha_est = w_eff * alpha_est + (1-w_eff) * alpha_bf;
end
end
```

### 9.6 阵列多普勒估计仿真主流程（`main_beamforming.m`）

```matlab
%% main_beamforming.m - 阵列波束形成增强多普勒估计仿真
clear; clc; close all;
run('params/sys_params_scfde.m');   % 复用 SC-FDE 参数，增加阵列设置

%% 阵列参数
P.M_array  = 8;                     % 阵元数
P.d_array  = P.c / (2*P.fc);        % 半波长间距（米）
P.theta_signal = pi/6;              % 信号入射角（30度）

%% 1. 发射端（SC-FDE 帧）
bits_tx = randi([0,1], 1, P.N_bits);
symbols = qammod(bits_tx, P.M_qam, 'InputType','bit', 'UnitAveragePower',true);
[s_frame, preamble] = gen_scfde_signal(symbols, P);

%% 2. 阵列信道
P.array.M     = P.M_array;
P.array.d     = P.d_array;
P.array.theta = P.theta_signal;
P.array.fc    = P.fc;
R_array = gen_uwa_channel_array(s_frame, P.channel, P.SNR_dB, P.array);
% R_array: [M × N_rx]

%% 3. 对比三种方案的多普勒估计精度
%  方案A：单阵元
[alpha_single, ~, tau_single] = est_doppler_xcorr(...
    R_array(1,:), preamble, P.T_v, P.fs, P.fc, P.alpha_bound);

%  方案B：常规DAS波束形成后单路估计
tau_cal_approx = (0:P.M_array-1) * P.d_array * cos(P.theta_signal) / P.c;
y_bf = bf_conventional(R_array, tau_cal_approx, P.fc, P.fs, P.theta_signal);
[alpha_bf, ~, tau_bf] = est_doppler_xcorr(...
    y_bf, preamble, P.T_v, P.fs, P.fc, P.alpha_bound);

%  方案C：空时变采样（本方案）
[alpha_array, tau_array, fs_eff, r_highrate] = ...
    est_doppler_beamforming(R_array, preamble, P);

%% 4. 显示对比结果
fprintf('真实 α: %.6f\n', P.channel.alpha);
fprintf('方案A（单阵元）:  α̂=%.6f  误差=%.2e\n', alpha_single, abs(alpha_single-P.channel.alpha));
fprintf('方案B（DAS波束）: α̂=%.6f  误差=%.2e\n', alpha_bf,     abs(alpha_bf-P.channel.alpha));
fprintf('方案C（空时变采）: α̂=%.6f  误差=%.2e\n', alpha_array,  abs(alpha_array-P.channel.alpha));
fprintf('等效采样率提升比: %.1f×\n', fs_eff/P.fs);

%% 5. 用方案C的估计结果驱动SC-FDE接收机
r_comp    = comp_resample(r_highrate, alpha_array, 'spline');
% ... 后续 SC-FDE 均衡流程（参见 main_scfde.m）

%% 6. RMSE vs SNR 蒙特卡洛仿真
N_trials = 50;
snr_vec  = 0:3:24;
rmse_A   = zeros(size(snr_vec));
rmse_B   = zeros(size(snr_vec));
rmse_C   = zeros(size(snr_vec));

for si = 1:length(snr_vec)
    errs_A = 0; errs_B = 0; errs_C = 0;
    for t = 1:N_trials
        Ra = gen_uwa_channel_array(s_frame, P.channel, snr_vec(si), P.array);
        [aA] = est_doppler_xcorr(Ra(1,:), preamble, P.T_v, P.fs, P.fc, P.alpha_bound);
        yb  = bf_conventional(Ra, tau_cal_approx, P.fc, P.fs, P.theta_signal);
        [aB] = est_doppler_xcorr(yb, preamble, P.T_v, P.fs, P.fc, P.alpha_bound);
        [aC] = est_doppler_beamforming(Ra, preamble, P);
        errs_A = errs_A + (aA - P.channel.alpha)^2;
        errs_B = errs_B + (aB - P.channel.alpha)^2;
        errs_C = errs_C + (aC - P.channel.alpha)^2;
    end
    rmse_A(si) = sqrt(errs_A/N_trials);
    rmse_B(si) = sqrt(errs_B/N_trials);
    rmse_C(si) = sqrt(errs_C/N_trials);
end

figure; semilogy(snr_vec, rmse_A, 'r-o', snr_vec, rmse_B, 'b-s', ...
    snr_vec, rmse_C, 'g-^', 'LineWidth', 1.5);
legend('单阵元', 'DAS波束', '空时变采样');
xlabel('SNR (dB)'); ylabel('多普勒因子 RMSE'); grid on;
title(['阵列多普勒估计 RMSE 对比（M=', num2str(P.M_array), ' 阵元）']);
```

---

## 10. 系统集成：统一仿真入口

### 文件：`main_sim.m`

```matlab
%% main_sim.m - 统一仿真入口，支持 OFDM / SC-FDE / OTFS 三种体制
clear; clc; close all;

%% 选择调制体制
MODE = 'SCFDE';          % 可选: 'OFDM' | 'SCFDE' | 'OTFS'
USE_ARRAY = false;       % 是否使用阵列波束形成增强估计
N_TRIALS  = 100;         % 蒙特卡洛次数
SNR_VEC   = -5:3:25;     % 扫描 SNR（dB）

%% 加载对应参数
switch MODE
    case 'OFDM',  run('params/sys_params_ofdm.m');
    case 'SCFDE', run('params/sys_params_scfde.m');
    case 'OTFS',  run('params/sys_params_otfs.m');
end

BER_curve = zeros(size(SNR_VEC));

for si = 1:length(SNR_VEC)
    ber_trials = zeros(1, N_TRIALS);
    for t = 1:N_TRIALS

        %% 发射
        bits_tx = randi([0,1], 1, P.N_bits);
        switch MODE
            case 'OFDM'
                symbols = qammod(bits_tx, P.M_qam, 'InputType','bit', 'UnitAveragePower',true);
                [s_tx, preamble] = gen_ofdm_signal(symbols, P);
            case 'SCFDE'
                symbols = qammod(bits_tx, P.M_qam, 'InputType','bit', 'UnitAveragePower',true);
                [s_tx, preamble] = gen_scfde_signal(symbols, P);
            case 'OTFS'
                symbols = qammod(bits_tx, P.M_qam, 'InputType','bit', 'UnitAveragePower',true);
                [s_tx, preamble, X_DD] = gen_otfs_with_pilot(symbols, P);
        end

        %% 信道
        if USE_ARRAY
            R_raw = gen_uwa_channel_array(s_tx, P.channel, SNR_VEC(si), P.array);
        else
            [r_rx, noise_var] = gen_uwa_channel(s_tx, P.channel, SNR_VEC(si));
        end

        %% 多普勒估计
        if USE_ARRAY
            [alpha_est, tau_est] = est_doppler_beamforming(R_raw, preamble, P);
            r_rx = comp_resample(mean(R_raw, 1), alpha_est, 'spline');
            noise_var = P.channel.noise_var_ref / 10^(SNR_VEC(si)/10);
        else
            switch P.doppler_est_method
                case 'CAF',     [alpha_est,tau_est] = est_doppler_caf(r_rx,preamble,P.fs,P.alpha_range,P.alpha_step,P.tau_range);
                case 'CP',       alpha_est = est_doppler_cp(r_rx, P.N_fft, P.Ncp, true);
                case 'XCORR',   [alpha_est,~,tau_est] = est_doppler_xcorr(r_rx,preamble,P.T_v,P.fs,P.fc,P.alpha_bound);
                case 'ZOOMFFT', [alpha_est] = est_doppler_zoomfft(r_rx,P.f_tone,P.fs,P.Bz,P.N_zoom,'hann');
            end
            r_comp = comp_resample(r_rx, alpha_est, 'spline');
        end

        %% 接收机处理
        switch MODE
            case 'OFDM'
                r_data = r_comp(P.preamble_len+1:end);
                Y = fft(r_data(1:P.N_fft), P.N_fft);
                [r_cfo, ~] = comp_cfo(r_data, Y(P.pilot_idx), P.X_pilot, P.pilot_idx, P.N_fft);
                Y_final = fft(r_cfo(1:P.N_fft), P.N_fft);
                H_est   = ch_est_ls(Y_final, P.X_pilot, P.pilot_idx, P.N_fft);
                X_eq    = equalizer_fde_ofdm(Y_final, H_est, noise_var);
                bits_rx = qamdemod(X_eq(P.data_idx), P.M_qam, 'OutputType','bit', 'UnitAveragePower',true);

            case 'SCFDE'
                frame_start = round(tau_est*P.fs) + P.L_preamble + P.L_gi + 1;
                r_data_raw  = r_comp(frame_start : frame_start + P.N_blocks*(P.K+P.Ncp_sc)-1);
                r_pre_rx    = r_comp(round(tau_est*P.fs)+1 : round(tau_est*P.fs)+P.L_preamble);
                H_est       = ch_est_scfde(r_pre_rx, preamble, P.K, P.L_ch);
                if P.use_turbo
                    r_blks   = reshape(r_data_raw, P.K+P.Ncp_sc, P.N_blocks).';
                    bits_rx  = turbo_equalizer(r_blks(:,P.Ncp_sc+1:end), H_est, noise_var, P.trellis, P.N_iter);
                else
                    x_eq_all = [];
                    for b = 1:P.N_blocks
                        bs = (b-1)*(P.K+P.Ncp_sc)+P.Ncp_sc+1;
                        x_eq_all = [x_eq_all, equalizer_fde_sc(r_data_raw(bs:bs+P.K-1), H_est, noise_var)];
                    end
                    bits_rx = qamdemod(x_eq_all(1:length(bits_tx)), P.M_qam, 'OutputType','bit', 'UnitAveragePower',true);
                end

            case 'OTFS'
                r_no_cp  = r_comp(P.Ncp_otfs+1 : P.Ncp_otfs+P.N_otfs*P.M_otfs);
                r_mat    = reshape(r_no_cp, P.M_otfs, P.N_otfs).';
                Y_TF     = zeros(P.N_otfs, P.M_otfs);
                for nn = 1:P.N_otfs
                    Y_TF(nn,:) = fft(r_mat(nn,:), P.M_otfs) / sqrt(P.M_otfs);
                end
                Y_DD = zeros(P.N_otfs, P.M_otfs);
                for mm = 1:P.M_otfs, Y_DD(:,mm) = fft(Y_TF(:,mm), P.N_otfs)/sqrt(P.N_otfs); end
                for nn = 1:P.N_otfs, Y_DD(nn,:) = ifft(Y_DD(nn,:), P.M_otfs)*sqrt(P.M_otfs); end
                [~, path_list] = ch_est_otfs(Y_DD, P.kp, P.lp, P.xp_amp, P.guard_k, P.guard_l, P);
                const   = qammod(0:P.M_qam-1, P.M_qam, 'UnitAveragePower',true);
                x_hat   = mp_detector(Y_DD, path_list, P.N_otfs, P.M_otfs, const, noise_var, P.N_iter_mp);
                d_idx   = get_data_indices(P.N_otfs, P.M_otfs, P.kp, P.lp, P.guard_k, P.guard_l);
                bits_rx = qamdemod(x_hat(d_idx), P.M_qam, 'OutputType','bit', 'UnitAveragePower',true);
        end

        [ber_t, ~] = calc_ber(bits_tx(1:min(length(bits_rx),P.N_bits)), bits_rx(1:min(length(bits_rx),P.N_bits)));
        ber_trials(t) = ber_t;
    end
    BER_curve(si) = mean(ber_trials);
    fprintf('SNR=%3d dB  BER=%.4e\n', SNR_VEC(si), BER_curve(si));
end

%% 绘图
figure;
semilogy(SNR_VEC, BER_curve, '-o', 'LineWidth', 1.5, 'DisplayName', MODE);
hold on; grid on;
xlabel('SNR (dB)'); ylabel('BER');
title(['水声通信 BER vs SNR（', MODE, '，α=', num2str(P.channel.alpha), '）']);
legend; ylim([1e-5, 1]);
```

---

## 11. 性能评估指标

### 11.1 多普勒估计评估

| 指标 | 定义 | MATLAB 代码 |
|------|------|-------------|
| RMSE | $\sqrt{\frac{1}{N_t}\sum(\hat{\alpha}_i - \alpha)^2}$ | `sqrt(mean((alpha_est_vec - alpha_true).^2))` |
| 偏差（Bias） | $\bar{\hat{\alpha}} - \alpha$ | `mean(alpha_est_vec) - alpha_true` |
| 归一化 RMSE | RMSE / $|\alpha|$ | — |
| 阵列增益 | $10\log_{10}(M)$（理论） | 实测：RMSE 之比 |

**CRLB 参考公式**（基于信号宽度 $T_{obs}$，SNR，载频 $f_c$）：

$$\text{CRLB}_{single}(\alpha) = \frac{6}{\text{SNR} \cdot (2\pi f_c)^2 \cdot T_{obs}^3 / T_s}$$

$$\text{CRLB}_{array}(\alpha) = \text{CRLB}_{single}(\alpha) / M^2$$

### 11.2 通信系统评估

| 指标 | 公式 / 代码 |
|------|-------------|
| BER | `sum(bits_rx ~= bits_tx) / N_bits` |
| FER | `sum(any(reshape(bits_rx~=bits_tx, frame_len, []), 1)) / N_frames` |
| EVM（%） | `100*sqrt(mean(abs(X_eq-X_ideal).^2)/mean(abs(X_ideal).^2))` |
| 频谱效率 | $\eta = \log_2(M_{QAM}) \times (1 - N_{cp}/N) \times (1 - N_{pilot}/N)$ bit/s/Hz |

### 11.3 各体制性能预期对比

| 体制 | PAPR | 多普勒容忍度 | 频谱效率 | 接收机复杂度 |
|------|------|-------------|---------|-------------|
| OFDM | 高（约 9 dB） | 低（依赖两步补偿） | 高 | 中 |
| SC-FDE | 低（约 3 dB） | 中（单一 CFO） | 中（CP 开销） | 中（+Turbo 高） |
| OTFS | 低（约 3 dB） | **极强（天然对抗）** | 中（导频保护区开销） | **高（MP 迭代）** |

---

## 12. 参数配置表

### 12.1 `params/sys_params_scfde.m`

```matlab
%% SC-FDE 系统参数
P.mode         = 'SCFDE';
P.fs           = 48000;        % 采样率（Hz）
P.fc           = 12000;        % 载频（Hz）
P.M_qam        = 4;            % QPSK
P.N_bits       = 10240;
P.SNR_dB       = 15;

%% 块参数
P.K            = 512;          % 每块符号数（FFT 点数）
P.Ncp_sc       = 128;          % SC-FDE 循环前缀
P.N_blocks     = 20;           % 数据块数

%% 前/后导码参数
P.L_preamble   = 2048;         % 前导码长度（样点）
P.L_gi         = 256;          % 保护间隔（样点，>= 最大时延）
P.T_v          = (P.N_blocks*(P.K+P.Ncp_sc) + 2*P.L_gi + P.L_preamble) / P.fs;

%% 多普勒估计参数
P.doppler_est_method = 'XCORR';
P.alpha_bound  = 0.015;
P.L_ch         = 32;           % 信道有效长度（样点）

%% 水声信道
P.channel.c      = 1500;
P.channel.alpha  = 0.003;
P.channel.P      = 4;
P.channel.delays = [0, 5e-3, 12e-3, 20e-3];
P.channel.gains  = [1, 0.6*exp(1j*1.5), 0.35*exp(1j*2.8), 0.15*exp(1j*0.5)];
P.channel.fs     = P.fs;

%% Turbo 迭代参数
P.use_turbo    = true;
P.trellis      = poly2trellis(7, [171 133]);   % (7,1/2) 卷积码
P.N_iter       = 5;

%% 蒙特卡洛
P.N_trials     = 100;
P.SNR_range    = -5:3:25;
```

### 12.2 `params/sys_params_otfs.m`

```matlab
%% OTFS 系统参数
P.mode         = 'OTFS';
P.fs           = 48000;
P.fc           = 12000;
P.M_qam        = 4;
P.N_bits       = 8192;
P.SNR_dB       = 15;

%% OTFS 网格参数
P.N_otfs       = 32;           % 多普勒轴（时间块数）
P.M_otfs       = 64;           % 时延轴（子载波数）
P.df           = P.fs / P.M_otfs;   % 子载波间隔（Hz） = 750 Hz
P.T_sym        = 1 / P.df;    % OFDM 符号周期（秒）

%% CP 参数（整帧 CP）
P.Ncp_otfs     = 128;          % 整帧 CP 长度（>= max_delay_samp）

%% 导频参数（嵌入单脉冲导频）
P.kp           = P.N_otfs/2;   % 导频多普勒位置（0-indexed）
P.lp           = P.M_otfs/4;   % 导频时延位置（0-indexed）
P.xp_amp       = sqrt(P.N_otfs * P.M_otfs);   % 导频幅度（高功率）
P.guard_k      = ceil(P.fc * abs(P.channel.alpha_max) * P.N_otfs * P.T_sym) + 2;
P.guard_l      = ceil(P.channel.tau_max * P.M_otfs * P.df) + 2;
P.ch_est_threshold = 0.1;      % 路径检测归一化阈值

%% MP 均衡器参数
P.N_iter_mp    = 20;           % 消息传递迭代次数

%% 水声信道（含最大多普勒估计）
P.channel.c          = 1500;
P.channel.alpha      = 0.003;
P.channel.alpha_max  = 0.01;   % 用于保护区尺寸设计
P.channel.tau_max    = 0.025;  % 最大时延（秒）
P.channel.P          = 3;
P.channel.delays     = [0, 8e-3, 20e-3];
P.channel.gains      = [1, 0.6*exp(1j*1.0), 0.3*exp(1j*2.2)];
P.channel.fs         = P.fs;

%% 蒙特卡洛
P.N_trials     = 50;
P.SNR_range    = 0:3:24;
```

### 12.3 `params/sys_params_ofdm.m`

```matlab
%% OFDM 参数（沿用 v1.0，补充新字段）
P.mode          = 'OFDM';
P.fs            = 48000;
P.fc            = 12000;
P.N_fft         = 1024;
P.Ncp           = 256;
P.M_qam         = 4;
P.N_bits        = 10240;
P.SNR_dB        = 15;
P.pilot_spacing = 8;
P.pilot_idx     = 1:P.pilot_spacing:P.N_fft;
P.data_idx      = setdiff(1:P.N_fft, P.pilot_idx);
P.N_pilots      = length(P.pilot_idx);
P.X_pilot       = ones(1, P.N_pilots);
P.preamble_len  = 2048;
P.doppler_est_method = 'XCORR';
P.alpha_range   = [-0.02, 0.02];
P.alpha_step    = 1e-4;
P.tau_range     = [0, 0.1];
P.alpha_bound   = 0.01;
P.T_v           = 0.5;
P.K_bands       = 5;
P.channel.c     = 1500;
P.channel.alpha = 0.003;
P.channel.P     = 4;
P.channel.delays = [0, 5e-3, 12e-3, 20e-3];
P.channel.gains  = [1, 0.7*exp(1j*1.2), 0.4*exp(1j*2.5), 0.2*exp(1j*0.8)];
P.channel.fs    = P.fs;
P.N_trials      = 100;
P.SNR_range     = -5:2:25;
```

---

## 13. 函数接口汇总

### 13.1 公共模块

| 函数名 | 输入 | 输出 | 功能 |
|--------|------|------|------|
| `gen_uwa_channel(s_tx, channel, SNR_dB)` | 发射信号，信道参数，SNR | `r_rx, noise_var` | 单路水声信道仿真 |
| `gen_uwa_channel_array(s_tx, ch, SNR, arr)` | 同上+阵列参数 | `R_array [M×N]` | 阵列信道仿真 |
| `est_doppler_caf(r, p, fs, ar, as, tr)` | 信号，前导码，参数 | `alpha, tau, caf_map` | CAF 搜索估计 |
| `est_doppler_cp(r, N, Ncp, flag)` | OFDM 信号，参数 | `alpha, corr` | CP 自相关估计 |
| `est_doppler_xcorr(r, xp, Tv, fs, fc, ab)` | 信号，导频，参数 | `alpha, a_coarse, tau` | 幅相联合估计 |
| `est_doppler_zoomfft(r, f0, fs, Bz, Nz, win)` | 信号，参数 | `alpha, f_est, spec` | Zoom-FFT 估计 |
| `comp_resample(r, alpha, method)` | 信号，因子 | `r_comp, N_out` | 重采样补偿 |
| `comp_cfo(r, Yp, Xp, pidx, N)` | 信号，导频 | `r_out, epsilon` | CFO 旋转补偿 |
| `comp_ici_matrix(Y, eps, N, K)` | 频域信号，CFO | `Y_comp, D` | ICI 矩阵补偿 |
| `calc_ber(bits_tx, bits_rx)` | 发/收比特 | `BER, N_err` | BER 计算 |

### 13.2 OFDM 模块

| 函数名 | 输入 | 输出 | 功能 |
|--------|------|------|------|
| `gen_ofdm_signal(symbols, P)` | 调制符号，参数 | `s_tx, preamble` | OFDM 调制+导频插入 |
| `ch_est_ls(Y, Xp, pidx, N)` | 频域接收，导频 | `H_est [N×1]` | LS 信道估计 |
| `equalizer_fde_ofdm(Y, H, nv)` | 频域信号，信道，噪声 | `X_eq [N×1]` | MMSE 频域均衡 |

### 13.3 SC-FDE 模块

| 函数名 | 输入 | 输出 | 功能 |
|--------|------|------|------|
| `gen_scfde_signal(symbols, P)` | 调制符号，参数 | `s_frame, preamble` | SC-FDE 帧生成 |
| `ch_est_scfde(r_pre, preamble, K, Lch)` | 接收前导，已知序列 | `H_est [K×1]` | LS+截断信道估计 |
| `equalizer_fde_sc(r_blk, H, nv)` | 块信号，信道，噪声 | `x_eq, llr` | MMSE+软输出 |
| `turbo_equalizer(r_blks, H, nv, trellis, Ni)` | 多块信号，信道 | `bits_dec, llr` | Turbo 迭代均衡 |

### 13.4 OTFS 模块

| 函数名 | 输入 | 输出 | 功能 |
|--------|------|------|------|
| `gen_otfs_signal(X_DD, P)` | DD 域符号，参数 | `s_tx [1×NM+Ncp]` | OTFS 调制 |
| `otfs_channel_model(P)` | 参数 | `H_eff [NM×NM]` | DD 域信道矩阵 |
| `ch_est_otfs(Y_DD, kp, lp, xp, gk, gl, P)` | DD 域接收，导频位置 | `h_dd, path_list` | 嵌入导频估计 |
| `mp_detector(Y_DD, paths, N, M, const, nv, Ni)` | DD 域信号，路径 | `x_hat, LLR` | 消息传递均衡 |

### 13.5 阵列波束形成模块

| 函数名 | 输入 | 输出 | 功能 |
|--------|------|------|------|
| `bf_delay_calibration(R, p, fs)` | 阵列信号，前导码 | `tau_cal [1×M]` | 阵元时延标定 |
| `bf_nonuniform_resample(R, tau, fs)` | 阵列信号，时延 | `r_highrate, fs_eff` | 空时变采样重建 |
| `bf_conventional(R, tau, fc, fs, theta)` | 阵列信号，参数 | `y_bf, gain_dB` | 常规 DAS 波束 |
| `est_doppler_beamforming(R, p, P)` | 阵列信号，前导码 | `alpha, tau, fs_eff, r_hr` | 阵列增强估计 |

---

## 14. 附录

### 附录 A：插值方法性能对比

| 方法 | 精度阶数 | 典型 MSE（$f_s=48$ kHz，$\alpha=0.003$） | 实时性 |
|------|----------|----------------------------------------|--------|
| 线性 | $O(h^2)$ | $\sim 10^{-5}$ | 最高 |
| 三次样条 | $O(h^4)$ | $\sim 10^{-8}$ | 中 |
| PCHIP | $O(h^4)$（保形）| $\sim 10^{-7}$ | 中 |
| Farrow（4阶）| 等价三次 | $\sim 10^{-8}$ | 适合实时 |

> **推荐**：离线仿真用 `'spline'`；实时系统用 Farrow 结构。

### 附录 B：SC-FDE 与 OFDM 关键参数对应关系

| 参数 | OFDM | SC-FDE |
|------|------|--------|
| 块长 | $N_{fft}$ | $K$ |
| CP 长度 | $N_{cp} \geq \tau_{max}f_s$ | $N_{cp,sc} \geq \tau_{max}f_s$ |
| 导频 | 频域子载波 | 时域训练块 |
| PAPR | 高（~9 dB） | 低（~3 dB） |
| 均衡域 | 频域（每子载波） | 频域→时域 |
| 多普勒估计 | CP 自相关或前导码 | 前/后导码复自相关 |

### 附录 C：OTFS 分数多普勒处理

当多普勒频率 $\nu_i$ 不能精确落在 DD 网格格点时（即 $k_i = \nu_i \cdot NT$ 为非整数），能量泄漏到相邻格点，简单整数格点模型失效。处理方法：

1. **窗函数法**（发送端加窗）：对 OTFS 帧施加二维窗（如 Dolph-Chebyshev 窗），减小频谱泄漏，代价是导频保护区扩大。

2. **虚拟格点插值**：将连续多普勒近似为相邻两个整数格点的线性组合：
   $$h_{frac} \approx (1-\delta) h_{[k_i]} + \delta \cdot h_{[k_i+1]}, \quad \delta = k_i - \lfloor k_i \rfloor$$
   在信道估计中同时估计 $h_{[k_i]}$ 和 $h_{[k_i+1]}$。

3. **OTFS-OCDM 扩展**：用正交啁啾复用（OCDM）替换 DFT，获得更好的分数多普勒鲁棒性。

### 附录 D：常见问题与注意事项

1. **复信号插值**：`interp1` 支持复数，但建议实虚分离以避免精度损失。

2. **相位模糊范围**：复自相关无模糊范围 $|\alpha| < 1/(2f_c T_v)$，超出时必须先做粗估计。例如 $f_c=12$ kHz，$T_v=0.5$ s，无模糊范围约 $\pm 8.3 \times 10^{-5}$（$\pm 0.12$ m/s）。

3. **OTFS 导频功率**：导频幅度 $x_p$ 需远高于数据符号（典型 $10\sim 20$ dB），保护区内不放数据，直接影响频谱效率，需在功率与保护区尺寸间权衡。

4. **MP 均衡器收敛**：迭代次数通常 10~30 次可收敛。若信道路径估计偏差较大，迭代可能发散，建议加入阻尼系数 $\beta \in [0.5, 0.9]$：$\hat{x}_{new} = \beta \hat{x}_{iter} + (1-\beta)\hat{x}_{old}$。

5. **阵列时延标定精度**：空时变采样的精度上限受 $\tau_m$ 估计误差限制。若 $\sigma_{\tau_m} > T_s/(2M)$，则等效采样率提升失效，建议用高过采样率信号（$f_s = 4f_c$ 以上）进行标定。

6. **SNR 定义统一**：全文使用**每符号 SNR**（$E_s/N_0$）。换算：$E_b/N_0 = E_s/N_0 - 10\log_{10}(\log_2 M_{QAM})$。

7. **OTFS 与 OFDM 的等价性**：当 $N=1$ 时，OTFS 退化为单符号 OFDM；当 $M=1$ 时，退化为单载波。这可用于调试：先验证 $N=M=1$ 的 AWGN 情况，再逐步扩展。

---

*文档版本：v2.0 | 最后更新：2026-03 | 新增：SC-FDE + Turbo 均衡、OTFS 调制、阵列波束形成增强多普勒估计*
