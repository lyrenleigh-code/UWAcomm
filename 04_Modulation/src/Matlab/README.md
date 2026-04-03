# 符号映射/判决模块 (Modulation)

将比特流映射为复数调制符号（QAM/PSK）或频率索引（MFSK），接收端支持硬判决和软判决LLR输出。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| qam_modulate | QAM/PSK符号映射（支持BPSK/QPSK/8QAM/16QAM/64QAM） | bits, M, mapping | symbols, constellation, bit_map |
| qam_demodulate | QAM/PSK硬判决+软判决LLR | symbols, M, mapping, noise_var | bits, LLR |
| mfsk_modulate | MFSK符号映射（比特->频率索引） | bits, M, mapping | freq_indices, M, bit_map |
| mfsk_demodulate | MFSK符号判决（频率索引->比特） | freq_indices, M, mapping | bits |

## 使用示例

```matlab
%% QAM调制/解调
bits = randi([0 1], 1, 400);
[symbols, constellation, bit_map] = qam_modulate(bits, 16, 'gray');
[bits_hard, LLR] = qam_demodulate(symbols, 16, 'gray', 0.1);

%% MFSK调制/解调
bits = randi([0 1], 1, 30);
[freq_indices, ~, ~] = mfsk_modulate(bits, 8, 'gray');
bits_out = mfsk_demodulate(freq_indices, 8, 'gray');
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- plot_constellation.m -- 星座图绘制（含比特标注和接收散点叠加）
- test_modulation.m -- 单元测试（25项），覆盖QAM Gray/自然映射、软判决LLR、MFSK和异常输入

## 依赖关系

- 无外部模块依赖
- 上游：模块03（交织）输出的交织比特流
- 下游：模块05（扩频，可选）或模块06（多载波，可选）接收调制符号
- MFSK频率索引可被模块05（扩频）的跳频功能使用
