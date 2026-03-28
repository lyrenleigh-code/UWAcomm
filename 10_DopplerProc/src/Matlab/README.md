# 多普勒估计与补偿模块 (DopplerProc)

水声通信系统多普勒处理算法库，覆盖10-1粗多普勒估计与重采样补偿、10-2残余多普勒补偿，含时变多普勒信道模型和可视化工具。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `gen_doppler_channel.m` | 时变多普勒水声信道模型 | 信道模型 |
| `est_doppler_caf.m` | 二维CAF搜索估计（通用高精度） | 10-1估计 |
| `est_doppler_cp.m` | CP自相关估计（OFDM专用） | 10-1估计 |
| `est_doppler_xcorr.m` | 复自相关幅相联合估计（SC推荐） | 10-1估计 |
| `est_doppler_zoomfft.m` | Zoom-FFT频谱细化估计 | 10-1估计 |
| `comp_resample_spline.m` | 三次样条重采样（fast/accurate双模式） | 10-1补偿 |
| `comp_resample_farrow.m` | Farrow滤波器重采样（fast/accurate双模式） | 10-1补偿 |
| `cubic_spline_interp.m` | 自实现三次样条插值（Thomas算法） | 底层工具 |
| `comp_cfo_rotate.m` | 残余CFO相位旋转补偿 | 10-2补偿 |
| `comp_ici_matrix.m` | ICI矩阵补偿（OFDM高速） | 10-2补偿 |
| `doppler_coarse_compensate.m` | 10-1统一入口（估计+重采样） | 统一入口 |
| `doppler_residual_compensate.m` | 10-2统一入口（CFO/ICI） | 统一入口 |
| `plot_doppler_estimation.m` | 估计与补偿结果可视化 | 可视化 |
| `test_doppler.m` | 单元测试（12项） | 测试 |

## 模块功能与接口概述

模块10位于接收链路中，分为两个处理阶段：

- **10-1 粗多普勒补偿**（模块6'去CP逆变换之前）：估计宽带多普勒因子α，通过重采样去除整体时间压缩/扩展。如果不做此步，CP对齐失效、FFT频点扩散。
- **10-2 残余多普勒补偿**（模块7'信道估计均衡之后）：基于信道估计结果修正残余载波频偏(CFO)相位旋转，或在OFDM高速场景下做ICI矩阵补偿。

数据流：
- 上游：模块8'(同步帧解析) → 模块11(阵列预处理,可选) → **10-1** → 模块6'(去CP逆变换)
- 下游：模块7'(信道估计均衡) → **10-2** → 迭代回环/符号判决

模块8(Sync)的 `cfo_estimate.m` 中CP法已重构为调用本模块的 `est_doppler_cp`。

## 四种估计算法对比

| 算法 | 函数 | 复杂度 | 精度 | 适用体制 |
|------|------|--------|------|----------|
| CAF搜索 | `est_doppler_caf` | O(N_α·N·logN) | 最高（两级搜索） | 通用，离线 |
| CP自相关 | `est_doppler_cp` | O(N) | 中等 | OFDM专用 |
| 复自相关幅相联合 | `est_doppler_xcorr` | O(N·logN) | 高（相位解模糊） | SC-TDE/SC-FDE |
| Zoom-FFT | `est_doppler_zoomfft` | O(N·logN) | 高（频率细化） | 通用 |

## 两种重采样方法对比

| 方法 | 函数 | fast模式 | accurate模式 |
|------|------|----------|-------------|
| Spline | `comp_resample_spline` | Catmull-Rom局部三次(C1) | 自然三次样条Thomas全局(C2) |
| Farrow | `comp_resample_farrow` | 三阶Lagrange(4点) | 五阶Lagrange(6点) |

两种方法均全向量化（fast模式无for循环），不调用MATLAB系统插值函数，全部自实现。

## 时变多普勒信道模型

```matlab
% 3种时变模型
tv = struct('enable', true, 'model', 'random_walk', ...
            'drift_rate', 0.0001, 'jitter_std', 0.00002);
[r, info] = gen_doppler_channel(s, fs, alpha, paths, snr_db, tv);
% info.alpha_true 为瞬时α序列（1xN）
```

| 模型 | 说明 |
|------|------|
| `linear_drift` | α线性漂移：α(t) = α₀ + drift_rate·t |
| `sinusoidal` | 正弦波动：α(t) = α₀ + A·sin(2πf_osc·t) |
| `random_walk` | 随机游走：α(t) = α₀ + cumsum(噪声)，限幅[0.5α₀, 1.5α₀] |

## 调用示例

```matlab
% 10-1 粗补偿（估计+重采样，一步完成）
[y_comp, alpha_est, info] = doppler_coarse_compensate(rx, preamble, fs, ...
    'est_method', 'xcorr', 'comp_method', 'spline', 'comp_mode', 'fast', ...
    'fc', 12000, 'T_v', 0.5);

% 10-2 残余CFO补偿
[y_comp, info] = doppler_residual_compensate(y, fs, ...
    'method', 'cfo_rotate', 'cfo_hz', 15.3);

% 10-2 ICI矩阵补偿（OFDM高速场景）
[Y_comp, info] = doppler_residual_compensate(Y_freq, fs, ...
    'method', 'ici_matrix', 'alpha_res', 1e-4, 'N_fft', 256);
```

## 函数接口说明

### gen_doppler_channel.m

**功能**：时变多普勒水声信道模型

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| s | 1xN 复数 | 发射基带信号 |
| fs | 正实数 | 采样率 (Hz) |
| alpha_base | 实数 | 基础多普勒因子 α=v/c |
| paths | 结构体 | 多径参数：`.delays`(各径时延秒)、`.gains`(各径复增益) |
| snr_db | 实数 | 信噪比 (dB) |
| time_varying | 结构体 | 时变参数：`.enable`、`.model`、`.drift_rate`、`.jitter_std` |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| r | 1xM 复数 | 接收信号 |
| channel_info | 结构体 | 含 `.alpha_true`(瞬时α序列)、`.noise_var`、`.paths` 等 |

---

### doppler_coarse_compensate.m

**功能**：10-1粗多普勒补偿统一入口

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| y | 1xN 复数 | 接收信号 |
| preamble | 1xL 复数 | 前导码 |
| fs | 正实数 | 采样率 |
| 'est_method' | 字符串 | 估计方法：'xcorr'(默认)/'caf'/'cp'/'zoomfft' |
| 'comp_method' | 字符串 | 补偿方法：'spline'(默认)/'farrow' |
| 'comp_mode' | 字符串 | 速度模式：'fast'(默认)/'accurate' |
| 'fc' | 实数 | 载频Hz（xcorr/zoomfft用） |
| 'T_v' | 实数 | 前后导码间隔秒（xcorr用） |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| y_comp | 1xN 复数 | 补偿后信号 |
| alpha_est | 标量 | 多普勒因子估计值 |
| est_info | 结构体 | 估计详细信息 |

---

### doppler_residual_compensate.m

**功能**：10-2残余多普勒补偿统一入口

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| y | 1xN 或 KxN | 信号（时域或频域） |
| fs | 正实数 | 采样率 |
| 'method' | 字符串 | 'cfo_rotate'(默认)/'ici_matrix' |
| 'cfo_hz' | 实数 | 残余CFO频偏Hz（cfo_rotate用） |
| 'alpha_res' | 实数 | 残余α（ici_matrix用） |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| y_comp | 与y同尺寸 | 补偿后信号 |
| residual_info | 结构体 | 补偿信息 |

---

### comp_resample_spline.m / comp_resample_farrow.m

**功能**：重采样补偿（两种方法，接口相同）

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| y | 1xN | 接收信号 |
| alpha_est | 标量 | 多普勒因子 |
| fs | 正实数 | 采样率 |
| mode | 字符串 | 'fast'(默认)/'accurate' |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| y_resampled | 1xN | 重采样后信号 |

---

### plot_doppler_estimation.m

估计与补偿结果可视化四格图。输入：`alpha_true`(真实α)、`alpha_est_list`(各方法估计cell)、`est_names`(名称)、`comp_results`(补偿结果结构体)、`title_str`。

---

### test_doppler.m

单元测试（12项），覆盖时变信道(固定/random_walk)、CAF/复自相关估计、重采样精度速度基准(多长度对比resample)、统一入口、残余CFO补偿、可视化和异常输入。

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\10_DopplerProc\src\Matlab');
run('test_doppler.m');
```

### 测试用例说明

**1. 时变多普勒信道（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 固定α | 输出非空，α记录正确 | α=0.002(3m/s)固定Doppler |
| 1.2 时变α | α序列有波动 | random_walk模型 |

**2. 多普勒估计（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1 CAF估计 | 速度误差<0.75m/s | 二维搜索，LFM前导码 |
| 2.2 复自相关 | 打印精度 | 幅相联合+解模糊 |

**3. 重采样补偿（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 精度速度对比 | 打印表格 | Spline/Farrow vs resample，多数据长度(10K~500K) |
| 3.2 长度保持 | 输入输出等长 | 重采样不改变信号长度 |

**4. 统一入口（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 粗补偿 | α误差合理 | CAF+Spline组合 |
| 4.2 残余CFO | 补偿后相位不旋转 | 10Hz频偏补偿验证 |

**5. 可视化（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 5.1 估计可视化 | 绘图无报错 | 误差柱状图+估计值+补偿效果 |

**6. 异常输入（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 6.1 空输入 | 4个函数均报错 | 信道/估计/补偿/CFO |
