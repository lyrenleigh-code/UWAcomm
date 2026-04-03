# 信源编解码模块 (SourceCoding)

水声通信发射链路最前端，负责原始数据的无损压缩（Huffman编码）和有损压缩（均匀量化），输出压缩后的二进制比特流供下游信道编码使用。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| huffman_encode | 对符号序列进行Huffman编码 | symbols（非负整数序列） | bitstream, codebook, compress_ratio |
| huffman_decode | 根据码本对Huffman比特流解码 | bitstream, codebook, num_symbols | symbols |
| uniform_quantize | 均匀量化连续信号 | signal, num_bits, val_range | indices, levels, quantized_signal |
| uniform_dequantize | 均匀反量化重建信号 | indices, num_bits, val_range | reconstructed |

## 使用示例

```matlab
%% 发射端：量化 + Huffman编码
signal = 0.8 * sin(2*pi*5*(0:999)/1000);
[indices, levels, ~] = uniform_quantize(signal, 8, [-1, 1]);
[bitstream, codebook, cr] = huffman_encode(indices);

%% 接收端：Huffman解码 + 反量化
indices_rx = huffman_decode(bitstream, codebook, length(indices));
signal_rx  = uniform_dequantize(indices_rx, 8, [-1, 1]);
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- test_source_coding.m -- 单元测试（14项），覆盖Huffman编解码、均匀量化/反量化、联合流程和异常输入

## 依赖关系

- 无外部模块依赖（发射链路首模块）
- 下游：模块02（信道编码）接收本模块输出的比特流
