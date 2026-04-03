# 扩频/解扩模块 (SpreadSpectrum)

提供扩频处理能力，覆盖DSSS直接序列扩频、CSK循环移位键控、M-ary组合扩频、FH跳频四种方案，含扩频码生成器和差分检测器。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| dsss_spread | DSSS直扩（符号乘扩频码） | symbols, code | spread_signal |
| dsss_despread | DSSS解扩（相关检测） | received, code | symbols, corr_values |
| gen_msequence | m序列生成（LFSR, degree=2~15） | degree, poly, init_state | seq, poly |
| gen_gold_code | Gold码生成（优选对m序列异或） | degree, shift, poly1, poly2 | code, seq1, seq2 |
| gen_walsh_hadamard | Walsh-Hadamard正交码矩阵 | N | W |
| gen_kasami_code | Kasami码小集合（偶数degree） | degree | codes, num_codes |
| csk_spread | CSK循环移位键控扩频 | bits, base_code, M | spread_signal, shift_amounts |
| csk_despread | CSK解扩（全移位相关检测） | received, base_code, M | bits, corr_matrix |
| mary_spread | M-ary扩频（码字选择映射） | bits, code_set | spread_signal |
| mary_despread | M-ary解扩（多码相关检测） | received, code_set | bits, corr_matrix |
| gen_hop_pattern | 伪随机跳频图案生成 | num_hops, num_freqs, seed | pattern, num_freqs |
| fh_spread | 跳频扩频（频率索引+偏移） | freq_indices, pattern, num_freqs | hopped_indices |
| fh_despread | 去跳频（频率索引-偏移） | hopped_indices, pattern, num_freqs | freq_indices |
| det_dcd | 差分相关检测器（抗载波相位偏移） | corr_values | decisions, diff_corr |
| det_ded | 差分能量检测器（抗快速相位波动） | corr_values | decisions, diff_energy |

## 使用示例

```matlab
%% DSSS直扩
code = 2*gen_msequence(7) - 1;           % 127码片m序列
symbols = [1 -1 1 1 -1];
spread = dsss_spread(symbols, code);
[despread, corr] = dsss_despread(spread, code);

%% FH-MFSK全链路（配合模块04）
[freq_idx, ~, ~] = mfsk_modulate(bits, 8, 'gray');
[pattern, ~] = gen_hop_pattern(length(freq_idx), 16, 42);
hopped = fh_spread(freq_idx, pattern, 16);
dehopped = fh_despread(hopped, pattern, 16);
bits_out = mfsk_demodulate(dehopped, 8, 'gray');
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- plot_code_correlation.m -- 扩频码自相关和互相关可视化
- test_spread_spectrum.m -- 单元测试（19项），覆盖扩频码生成、DSSS、CSK、M-ary、差分检测器、跳频和异常输入

## 依赖关系

- FH-MFSK全链路依赖模块04（调制）的 mfsk_modulate / mfsk_demodulate
- 上游：模块04（符号映射）输出的调制符号或比特
- 下游：模块07（导频插入）接收扩频后的码片序列
