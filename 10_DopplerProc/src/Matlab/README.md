# 多普勒估计与补偿模块 (DopplerProc)

接收链路中的多普勒处理模块，分为10-1粗多普勒估计+重采样补偿（去CP前）和10-2残余CFO/ICI补偿（均衡后），共15个文件。含阵列信道仿真（M阵元ULA）。

## 对外接口

其他模块/端到端应调用的函数：

### `doppler_coarse_compensate`

10-1粗多普勒补偿统一入口（估计+重采样一步完成）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `y` | 1xN complex | 接收信号 | (必需) |
| `preamble` | 1xL complex | 前导码 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `'est_method'` | string | 估计方法: `'xcorr'`/`'caf'`/`'cp'`/`'zoomfft'` | `'xcorr'` |
| `'comp_method'` | string | 补偿方法: `'spline'`/`'farrow'`/`'polyphase'` | `'spline'` |
| `'comp_mode'` | string | 运行模式: `'fast'`/`'accurate'` | `'fast'` |
| `'fc'` | scalar (Hz) | 载频（xcorr/zoomfft需要） | 12000 |
| `'T_v'` | scalar (s) | 前后导码间隔（xcorr需要） | 0.5 |
| `'N_fft'` | integer | FFT点数（cp方法需要） | 256 |
| `'N_cp'` | integer | CP长度（cp方法需要） | 64 |
| `'alpha_range'` | 1x2 | CAF搜索范围 [min, max] | [-0.02, 0.02] |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `y_comp` | 1xN complex | 粗补偿后信号 |
| `alpha_est` | scalar | 多普勒因子估计值 |
| `est_info` | struct | 估计详细信息结构体 |

---

### `doppler_residual_compensate`

10-2残余多普勒补偿统一入口（CFO旋转/ICI矩阵）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `y` | 1xN 或 KxN_fft | 信号（时域或频域） | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `'method'` | string | 补偿方法: `'cfo_rotate'`/`'ici_matrix'` | `'cfo_rotate'` |
| `'cfo_hz'` | scalar (Hz) | 残余CFO频偏（cfo_rotate需要） | 0 |
| `'alpha_res'` | scalar | 残余α（ici_matrix需要） | 0 |
| `'N_fft'` | integer | FFT点数（ici_matrix需要） | 256 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `y_comp` | 同输入 | 补偿后信号 |
| `residual_info` | struct | 补偿信息结构体（含method、cfo_hz或alpha_res） |

---

### `est_doppler_caf`

二维CAF搜索法多普勒估计（通用高精度离线方法）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `r` | 1xN complex | 接收信号 | (必需) |
| `preamble` | 1xL complex | 已知前导码 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `alpha_range` | 1x2 | α搜索范围 [min, max] | [-0.02, 0.02] |
| `alpha_step` | scalar | 搜索步长 | 1e-4 |
| `tau_range` | 1x2 (s) | 时延搜索范围 [min, max] | [0, 0.1] |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `alpha_est` | scalar | 多普勒因子估计值 |
| `tau_est` | scalar (s) | 帧到达时延估计值 |
| `caf_map` | N_tau x N_alpha | CAF搜索面 |

---

### `est_doppler_xcorr`

复自相关幅相联合法多普勒估计（SC-FDE/SC-TDE推荐）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `r` | 1xN complex | 接收信号（含前导/后导） | (必需) |
| `x_pilot` | 1xL complex | 测速导频序列（chirp或m序列） | (必需) |
| `T_v` | scalar (s) | 前后测速序列发送时间间隔 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `fc` | scalar (Hz) | 载频 | (必需) |
| `alpha_bound` | scalar | 预期最大\|alpha\| | 0.02 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `alpha_est` | scalar | 精细α估计（幅相联合+解模糊） |
| `alpha_coarse` | scalar | 粗α估计（仅幅度） |
| `tau_est` | scalar (s) | 帧到达时延 |

---

### `est_doppler_cp`

CP自相关法多普勒估计（OFDM专用）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `r` | 1xM complex | 接收OFDM信号 | (必需) |
| `N_fft` | integer | FFT点数 | (必需) |
| `N_cp` | integer | CP长度 | (必需) |
| `interp_flag` | logical | 是否用抛物线插值精化 | true |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `alpha_est` | scalar | 多普勒因子估计 |
| `corr_vals` | 1xN_fft | 自相关序列（供调试） |

---

### `est_doppler_zoomfft`

Zoom-FFT频谱细化法多普勒估计。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `r` | 1xN complex | 接收信号 | (必需) |
| `preamble` | 1xL complex | 已知前导码 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `fc` | scalar (Hz) | 载频 | (必需) |
| `zoom_factor` | integer | 频率细化倍数 | 16 |
| `freq_range` | 1x2 (Hz) | 搜索频率范围 [f_min, f_max] | fc +/- fs*0.02 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `alpha_est` | scalar | 多普勒因子估计 |
| `freq_est` | scalar (Hz) | 估计的接收频率 |
| `spectrum` | 1xK | Zoom-FFT频谱 |

---

### `comp_resample_spline`

三次样条重采样多普勒补偿。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `y` | 1xN complex/real | 接收信号 | (必需) |
| `alpha_est` | scalar | 估计的多普勒因子（正=靠近/压缩） | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `mode` | string | `'fast'`(Catmull-Rom,C1) / `'accurate'`(自然三次样条,C2) | `'fast'` |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `y_resampled` | 1xN | 重采样后信号（长度与输入一致） |

---

### `comp_resample_farrow`

Farrow滤波器重采样多普勒补偿。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `y` | 1xN complex/real | 接收信号 | (必需) |
| `alpha_est` | scalar | 估计的多普勒因子 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `mode` | string | `'fast'`(三阶4点Lagrange) / `'accurate'`(五阶6点Lagrange) | `'fast'` |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `y_resampled` | 1xN | 重采样后信号（长度与输入一致） |

---

### `comp_cfo_rotate`

残余CFO相位旋转补偿（10-2）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `y` | 1xN complex | 接收信号 | (必需) |
| `cfo_hz` | scalar (Hz) | 残余载波频偏 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `y_comp` | 1xN complex | 频偏补偿后信号 |

---

### `comp_ici_matrix`

ICI矩阵补偿（10-2，OFDM高速场景）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `Y` | 1xN_fft 或 KxN_fft | 频域接收信号（K个OFDM符号） | (必需) |
| `alpha_est` | scalar | 残余多普勒因子 | (必需) |
| `N_fft` | integer | FFT点数 | (必需) |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `Y_comp` | 同输入 | ICI补偿后的频域信号 |

---

### `gen_doppler_channel`

时变多普勒水声信道模型（alpha随时间波动）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `s` | 1xN complex | 发射基带信号 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `alpha_base` | scalar | 基础多普勒因子 α=v/c | 0.001 |
| `paths` | struct | 多径参数：`.delays`(1xP秒), `.gains`(1xP复增益) | 3径默认 |
| `snr_db` | scalar (dB) | 信噪比 | 20 |
| `time_varying` | struct | `.enable`(bool), `.drift_rate`, `.jitter_std`, `.model`(`'linear_drift'`/`'sinusoidal'`/`'random_walk'`) | enable=true, random_walk |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `r` | 1xM complex | 接收信号 |
| `channel_info` | struct | `.alpha_true`(1xM瞬时α), `.alpha_base`, `.noise_var`, `.paths`, `.fs` |

---

### `gen_uwa_channel_array`

阵列水声信道仿真（M阵元ULA，精确空间时延）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `s` | 1xN complex | 发射基带信号 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `alpha_base` | scalar | 基础多普勒因子 | (必需) |
| `paths` | struct | 多径参数（同gen_doppler_channel） | [] |
| `snr_db` | scalar (dB) | 信噪比 | 20 |
| `time_varying` | struct | 时变参数（同gen_doppler_channel） | enable=false |
| `array` | struct | `.M`(阵元数,4), `.d`(间距,lambda/2), `.theta`(入射角弧度,0), `.c`(声速,1500), `.fc`(载频,12000) | 见各字段默认 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `R_array` | MxN_rx complex | 各阵元接收信号（每行一个阵元） |
| `channel_info` | struct | `.alpha_true`, `.array`, `.tau_spatial`(1xM秒), `.per_element`(cell) |

## 内部函数

辅助/测试函数（不建议外部直接调用）：

### `cubic_spline_interp` (internal)

自实现三次样条插值（Thomas算法，comp_resample_spline accurate模式的底层工具）。

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `y` | 1xN | 均匀网格上的采样值（对应网格点1,2,...,N） | (必需) |
| `xq` | 1xM | 查询位置（浮点索引，范围[1,N]） | (必需) |
| **输出** `yq` | 1xM | 插值结果 | |

### `plot_doppler_estimation` (internal)

多普勒估计与补偿结果可视化四格图。

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `alpha_true` | scalar 或 1xN | 真实α | (必需) |
| `alpha_est_list` | cell | 各方法估计的α | (必需) |
| `est_names` | cell | 方法名称 | (必需) |
| `comp_results` | struct | `.y_orig`, `.y_comp`, `.y_ref`（可选） | [] |
| `title_str` | string | 标题 | `'Doppler Estimation'` |

### `test_doppler` (internal)

单元测试脚本（V2.0, 13项）。

## 核心算法技术描述

### 1. 二维CAF搜索（est_doppler_caf）

**原理：** 在时延-多普勒二维平面上搜索使模糊函数最大化的参数对 (tau, alpha)。

```
CAF(τ, α) = |Σ_n r[n] · p*[round(n/(1+α) - τ·fs)]|²
```

- 对每个候选α，将前导码做时间伸缩后与接收信号互相关，找峰值位置作为tau估计
- 复杂度 `O(N_alpha × N × log(N))`，建议两级搜索（粗1e-3 + 细1e-5）
- **适用条件：** 通用高精度离线方法，适合已知前导码的任意体制
- **局限性：** 计算量大，不适合实时处理；搜索步长决定精度上限

### 2. 复自相关幅相联合估计（est_doppler_xcorr）

**原理：** 利用前后两段已知导频序列的互相关峰位置差（幅度估计）和相位差（精细估计）联合求解α。

```
粗估计（幅度）：α_coarse = (Δn/fs - T_v) / T_v
精细估计（相位）：α_phase = angle(R₂·R₁*) / (2π·fc·T_v)
```

其中R₁、R₂为前后导频的互相关复峰值，T_v为发送间隔。相位估计存在2π模糊，用粗估计解模糊。

- **适用条件：** 需要前后双导频；SC-FDE/SC-TDE推荐
- **局限性：** 需要载频fc信息；高速移动时相位估计可能跨越多个2π周期

### 3. CP自相关估计（est_doppler_cp）

**原理：** 利用OFDM的CP与数据尾部相同的结构特性。

```
R(m) = Σ_n r[n+m] · r*[n+m+N]
α_coarse = Δn_peak / N_fft
```

CP段与对应数据尾段的自相关峰位置偏移量反映多普勒伸缩。支持抛物线插值精化到亚样本精度。

- **适用条件：** OFDM专用，无需额外导频开销
- **局限性：** 精度受限于CP长度；仅适用于含CP的OFDM信号

### 4. Zoom-FFT频谱细化估计（est_doppler_zoomfft）

**原理：** 匹配滤波后在载频附近做高分辨率FFT，从频移推算α。

```
α = (f_est - fc) / fc
```

Zoom-FFT通过频移+低通+降采样+FFT实现频率细化，分辨率提高zoom_factor倍。

- **适用条件：** 适合窄带信号的频移估计
- **局限性：** 仅覆盖局部频带；多径环境下频谱扩展影响峰值定位

### 5. 三次样条重采样（comp_resample_spline）

**原理：** 对接收信号在新采样位置 `pos = (1:N)/(1+α)` 处做三次样条插值，恢复原始时间轴。

- **fast模式：** Catmull-Rom局部4点插值，全向量化，C1连续（一阶导连续）
- **accurate模式：** 自然三次样条，Thomas算法全局求解三对角系统，C2连续（二阶导连续）

V7改动：正alpha直接传入即可补偿压缩，无需取负。

### 6. Farrow滤波器重采样（comp_resample_farrow）

**原理：** 用多项式插值滤波器结构，将采样位置分为整数偏移和分数偏移两部分。

- **fast模式：** 三阶Lagrange (4点)，每样本7次乘法
- **accurate模式：** 五阶Lagrange (6点)，每样本15次乘法，旁瓣抑制更好
- 全向量化实现，不调用MATLAB系统插值函数

### 7. CFO相位旋转补偿（comp_cfo_rotate）

```
y_comp(n) = y(n) · exp(-j·2π·cfo·n/fs)
```

逐样本乘以补偿相位，消除残余载波频偏。

### 8. ICI矩阵补偿（comp_ici_matrix）

**原理：** 宽带多普勒导致OFDM子载波间干扰（ICI），建模为矩阵D乘法。

```
D_{k,l}(α) = (1/N) Σ_n exp(j2π(l - k(1+α))n/N)
Y_comp = (D'D + σ²I)^{-1} D' Y    (正则化MMSE求逆)
```

- 计算量 O(N^2)，仅在高速场景（|alpha|>1e-4）需要
- |alpha|<1e-6时跳过补偿直接返回

### 9. 阵列信道仿真（gen_uwa_channel_array）

**原理：** M阵元ULA，每阵元的空间时延为：

```
τ_m = (m-1) · d · cos(θ) / c
```

其中d为阵元间距，theta为入射角，c为声速。tau_m叠加到各径时延后，逐阵元独立调用gen_doppler_channel。保持浮点精度，不四舍五入为整数样点。

## 使用示例

```matlab
% 10-1 粗多普勒补偿（推荐使用统一入口）
[y_comp, alpha_est, info] = doppler_coarse_compensate(rx, preamble, fs, ...
    'est_method', 'xcorr', 'comp_method', 'spline', 'comp_mode', 'fast', ...
    'fc', 12000, 'T_v', 0.5);

% 10-2 残余CFO补偿
[y_comp, info] = doppler_residual_compensate(y, fs, 'method', 'cfo_rotate', 'cfo_hz', 15.3);

% V7重采样：正alpha直接传入即可补偿压缩
y_comp = comp_resample_spline(rx, alpha_est, fs, 'fast');

% 阵列信道仿真（M阵元ULA）
arr = struct('M', 4, 'fc', 12000, 'c', 1500, 'theta', pi/6);
[R_array, arr_info] = gen_uwa_channel_array(tx, fs, alpha, paths, snr, tv, arr);
% R_array: 4xN矩阵，每行为一个阵元的接收信号
```

## 依赖关系

- 无外部模块依赖（独立的多普勒处理模块）
- 模块08 (Sync) 的 `cfo_estimate` CP法调用本模块的 `est_doppler_cp`
- 模块08 (Sync) 的 `gen_lfm` 在测试中用于生成LFM前导码
- 模块09 (Waveform) 在ZoomFFT测试中提供gen_lfm
- 被模块11 (ArrayProc) 的 `gen_doppler_channel_array` 调用
- 被模块13 (SourceCode) 端到端测试中的时变信道测试调用

## 测试覆盖 (test_doppler.m V2.0, 13项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|---------|---------|------|
| 1.1 | 固定alpha信道 | `~isempty(r)`, `abs(ch_info.alpha_base - alpha) < 1e-10` | 接收信号非空，alpha记录精确 |
| 1.2 | 时变alpha信道(random_walk) | `length(ch_tv.alpha_true) == length(s)`, `std(ch_tv.alpha_true) > 0` | alpha序列长度匹配，时变有波动 |
| 2.1 | CAF估计 | `abs(a_caf - alpha_true) < 5e-4` | 误差<0.75m/s（alpha_true=0.002, v=3m/s） |
| 2.2 | 复自相关幅相联合估计 | 不抛异常（try/catch） | 返回alpha_est和alpha_coarse |
| 3.1 | 重采样精度+速度对比 | 不抛异常，多长度(1w/5w/20w/50w)对比 | Spline/Farrow/resample三种方法计时+相关性 |
| 3.2 | 重采样后信号长度保持 | `length(y_spline) == N_test`, `length(y_farrow) == N_test` | 输入输出长度一致 |
| 4.1 | 粗补偿(CAF+Spline) | `abs(alpha_coarse - alpha_true) < 1e-3`, `length(y_coarse) == length(rx_sig)` | 粗估计误差<1e-3，输出长度不变 |
| 4.2 | 残余CFO补偿 | `var(angle(y_res(100:end))) < 0.1` | 补偿后相位方差<0.1（接近DC） |
| 5.1 | ZoomFFT多普勒估计 | 不抛异常 | 返回alpha_est及频谱 |
| 6.1 | ICI矩阵补偿 | `err_after < err_before` | 补偿后MSE小于补偿前 |
| 7.1 | 阵列信道生成 | `size(R_arr,1)==4`, `size(R_arr,2)>0`, `length(arr_info.tau_spatial)==4`, `arr_info.tau_spatial(1)==0` | 4阵元输出，时延正确 |
| 7.2 | 阵列相位差验证 | 不抛异常 | 验证相邻阵元相位差与理论一致 |
| 8.1 | 空输入拒绝 | `caught == 5`（5个函数对空输入均报错） | gen_doppler_channel/est_caf/spline/cfo/array |

## 可视化说明

测试生成3个figure：

- **Figure 1 — 多普勒估计对比：** 左图：各估计方法的alpha值与真实值对比柱状图；右图：各方法速度误差(m/s)对比柱状图
- **Figure 2 — 重采样补偿波形：** 上图：补偿前发射信号 vs 含多普勒接收信号波形；下图：补偿后信号 vs 发射信号波形对比
- **Figure 3 — 阵列信道：** 左图：4阵元接收信号波形（偏移显示）；右图：阵元间归一化互相关矩阵热力图
