# 阵列接收预处理模块 (ArrayProc)

可选的接收链路前端预处理模块，对多通道阵列信号进行波束形成或非均匀变采样重建，输出单路高质量信号供下游模块透明使用。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `gen_array_config` | 阵列配置生成（ULA/UCA/自定义） | array_type, M, d, fc | config |
| `gen_doppler_channel_array` | 多通道阵列信道仿真 | s, fs, alpha, paths, snr, array_config, theta | R_array, channel_info |
| `bf_das` | DAS常规波束形成（时延对齐+相干叠加） | R_array, tau_delays, fs | output, snr_gain |
| `bf_mvdr` | MVDR/Capon自适应波束形成 | R_array, steering_vector, diag_loading | output, weights |
| `bf_delay_calibration` | 阵元时延标定（互相关法） | R_array, preamble, fs | tau_est, tau_error |
| `bf_nonuniform_resample` | 空时联合非均匀变采样重建 | R_array, tau_delays, fs | output, effective_fs |

## 使用示例

```matlab
% 配置8元ULA + 仿真多通道信道
cfg = gen_array_config('ula', 8, [], 12000);
[R, info] = gen_doppler_channel_array(s, fs, alpha, paths, snr, cfg, theta);

% 模式B: DAS波束形成（SNR增益约10*log10(M) dB）
[y_das, gain] = bf_das(R, info.tau_array, fs);

% 模式B: MVDR自适应波束形成（干扰抑制）
a = exp(-1j*2*pi*fc*cfg.positions*look_dir.'/cfg.c);
[y_mvdr, w] = bf_mvdr(R, a, 0.01);

% 模式A: 非均匀变采样重建（等效采样率提升至M*fs）
[y_hi, eff_fs] = bf_nonuniform_resample(R, info.tau_array, fs);
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- `plot_beampattern.m` — 波束方向图可视化（直角+极坐标）
- `test_array_proc.m` — 单元测试（11项，覆盖阵列配置/多通道信道/DAS/MVDR/标定/方向图/非均匀重建/模块10联合测试）

## 依赖关系

- 依赖模块10 (DopplerProc) 的 `gen_doppler_channel`（gen_doppler_channel_array内部扩展为多通道）
- 依赖模块10 (DopplerProc) 的 `est_doppler_caf`（联合测试中对比DAS增强后的多普勒估计精度）
