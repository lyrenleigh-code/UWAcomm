# 脉冲成形与上下变频模块 (Waveform)

发射链路末端和接收链路前端的物理层波形处理，负责脉冲成形/匹配滤波、数字上下变频、FSK波形生成和DA/AD转换仿真。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `pulse_shape` | 脉冲成形（上采样+RC/RRC/矩形/高斯滤波） | symbols, sps, filter_type, rolloff, span | shaped_signal, filter_coeff, t_filter |
| `match_filter` | 匹配滤波（成形滤波器时间反转共轭） | signal, sps, filter_type, rolloff, span | filtered, filter_coeff |
| `upconvert` | 数字上变频（复基带转通带实信号） | baseband, fs, fc | passband, t |
| `downconvert` | 数字下变频（通带转复基带，含LPF） | passband, fs, fc, lpf_bandwidth | baseband, t |
| `gen_fsk_waveform` | FSK波形生成（频率索引转正弦波形，CPFSK） | freq_indices, M, f0, spacing, fs, dur | waveform, t, freqs |
| `da_convert` | DA转换仿真（量化/理想模式） | signal, num_bits, mode | output, scale_factor |
| `ad_convert` | AD转换仿真（量化/理想模式，含截断） | signal, num_bits, mode, full_scale | output, scale_factor |

## 使用示例

```matlab
% 发端：脉冲成形 → DA → 上变频
[shaped, h, t] = pulse_shape(symbols, 8, 'rrc', 0.35, 6);
[da_out, scale] = da_convert(real(shaped), 14, 'quantize');
[passband, t] = upconvert(shaped, 48000, 12000);

% 收端：下变频 → 匹配滤波 → 下采样
[baseband, t] = downconvert(passband, 48000, 12000, 6000);
[filtered, ~] = match_filter(baseband, 8, 'rrc', 0.35, 6);
sampled = filtered(25:8:end);  % delay = span*sps/2 = 24
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- `plot_eye_diagram.m` — 眼图绘制（观测脉冲成形后码间干扰和定时余量）
- `test_waveform.m` — 单元测试（20项，覆盖成形/变频/FSK/DA-AD/联合回环/异常输入）

## 依赖关系

- 无外部模块依赖（独立的物理层波形处理模块）
- 被模块08 (Sync)、模块13 (SourceCode) 端到端测试广泛调用
