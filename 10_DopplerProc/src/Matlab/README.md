# 多普勒估计与补偿模块 (DopplerProc)

接收链路中的多普勒处理模块，分为10-1粗多普勒估计+重采样补偿（去CP前）和10-2残余CFO/ICI补偿（均衡后），共14个文件。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `doppler_coarse_compensate` | 10-1统一入口（估计+重采样一步完成） | y, preamble, fs, Name-Value | y_comp, alpha_est, est_info |
| `doppler_residual_compensate` | 10-2统一入口（CFO旋转/ICI矩阵） | y, fs, Name-Value | y_comp, residual_info |
| `est_doppler_caf` | 二维CAF搜索估计（通用高精度） | y, preamble, fs, alpha_range | alpha_est, info |
| `est_doppler_xcorr` | 复自相关幅相联合估计（SC推荐） | y, preamble, fs, fc, T_v | alpha_est, info |
| `est_doppler_cp` | CP自相关估计（OFDM专用） | y, cp_len, N_fft, fs | alpha_est, info |
| `est_doppler_zoomfft` | Zoom-FFT频谱细化估计 | y, preamble, fs | alpha_est, info |
| `comp_resample_spline` | 三次样条重采样补偿（V7: pos=(1:N)/(1+alpha)，正alpha=补偿压缩） | y, alpha_est, fs, mode | y_resampled |
| `comp_resample_farrow` | Farrow滤波器重采样补偿 | y, alpha_est, fs, mode | y_resampled |
| `comp_cfo_rotate` | 残余CFO相位旋转补偿 | y, cfo_hz, fs | y_comp |
| `comp_ici_matrix` | ICI矩阵补偿（OFDM高速场景） | Y_freq, alpha_res, N_fft | Y_comp |
| `gen_doppler_channel` | 时变多普勒水声信道模型 | s, fs, alpha, paths, snr, tv | r, channel_info |

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
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- `cubic_spline_interp.m` — 自实现三次样条插值（Thomas算法，comp_resample_spline accurate模式的底层工具）
- `plot_doppler_estimation.m` — 估计与补偿结果可视化四格图
- `test_doppler.m` — 单元测试（12项，覆盖时变信道/CAF/xcorr估计/重采样精度/统一入口/CFO/异常输入）

## 依赖关系

- 无外部模块依赖（独立的多普勒处理模块）
- 模块08 (Sync) 的 `cfo_estimate` CP法调用本模块的 `est_doppler_cp`
- 被模块13 (SourceCode) 端到端测试中的时变信道测试调用
