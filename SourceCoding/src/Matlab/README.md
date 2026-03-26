# 信源编解码模块 (SourceCoding)

水声通信系统信源编解码算法库，覆盖无损压缩（Huffman编码）和有损压缩（均匀量化）两类方案。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `huffman_encode.m` | Huffman编码（符号序列→比特流+码本） | 无损压缩 |
| `huffman_decode.m` | Huffman解码（比特流+码本→符号序列） | 无损压缩 |
| `uniform_quantize.m` | 均匀量化（连续信号→量化索引+电平） | 有损压缩 |
| `uniform_dequantize.m` | 均匀反量化（量化索引→重建信号） | 有损压缩 |
| `test_source_coding.m` | 单元测试（14项） | 测试 |

## 各编码方案说明

### 1. Huffman编码（无损压缩）

- 根据符号出现概率构建最优二叉树，生成前缀码
- 高概率符号分配短码字，低概率符号分配长码字
- 平均码长逼近信息熵 H，满足 H <= 平均码长 < H+1
- 输入须为非负整数符号序列

```matlab
symbols = [0 1 1 2 2 2 3 3 3 3];
[bitstream, codebook, compress_ratio] = huffman_encode(symbols);
symbols_out = huffman_decode(bitstream, codebook, length(symbols));
```

### 2. 均匀量化/反量化（有损压缩）

- 将连续幅度信号离散化为有限级别
- 量化级数 L = 2^num_bits，步长 delta = (xmax - xmin) / L
- 采用中点量化策略，每级代表值为区间中点
- 量化噪声功率（均匀分布信号）：delta^2 / 12
- 超出量化范围的信号截断到边界

```matlab
signal = 0.8 * sin(2*pi*5*(0:999)/1000);
num_bits = 8;
val_range = [-1, 1];

[indices, levels, quantized] = uniform_quantize(signal, num_bits, val_range);
reconstructed = uniform_dequantize(indices, num_bits, val_range);
```

## 典型联合调用流程

```matlab
%% 发射端：量化 + Huffman编码
signal = 0.8 * sin(2*pi*5*(0:999)/1000);
[indices, levels, ~] = uniform_quantize(signal, 8, [-1, 1]);
[bitstream, codebook, cr] = huffman_encode(indices);

%% 接收端：Huffman解码 + 反量化
indices_rx = huffman_decode(bitstream, codebook, length(indices));
signal_rx  = uniform_dequantize(indices_rx, 8, [-1, 1]);
```

## 输入输出约定

- **Huffman输入**：非负整数符号序列（如量化索引），行向量或列向量均可
- **Huffman输出**：logical比特流 + 结构体码本（含symbol/code/prob字段）
- **量化输入**：任意尺寸数值数组，超范围值自动截断并给出warning
- **量化索引**：取值 0 ~ 2^num_bits - 1，与量化电平表一一对应

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\SourceCoding\src\Matlab');
run('test_source_coding.m');
```

测试覆盖：编解码回环、压缩效果、前缀码验证、多比特数量化、量化噪声功率、全链路联合测试、异常输入拒绝。
