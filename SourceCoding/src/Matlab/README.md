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

### 测试用例说明

**1. Huffman编码/解码（6项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 常规多符号回环 | `symbols_out == symbols_in` 且 `cr > 0` | 5种符号、非均匀频率，编码→解码完全还原，压缩比为正 |
| 1.2 单一符号序列 | `symbols_out == symbols_in` 且码本仅1条 | 所有符号相同的退化情况，码字固定为'0' |
| 1.3 两符号等概率 | `symbols_out == symbols_in` 且两个码字均为1比特 | 等概率二元情况下每个符号恰好1位，编码效率最优 |
| 1.4 大规模随机回环 | 10000符号16种符号编解码完全一致 | 压力测试，验证大数据量下编解码正确性 |
| 1.5 非均匀分布压缩 | `symbols_out == symbols_in` 且平均码长 < H+1 | 验证Huffman编码逼近信息熵极限（Shannon第一定理） |
| 1.6 前缀码验证 | 无码字是另一个码字的前缀 | Huffman码必须满足前缀条件，否则无法唯一解码 |

**2. 均匀量化/反量化（5项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1 基本回环 | 量化误差 <= delta/2 且 `qsig == signal_out` | 中点量化策略下最大误差不超过半个步长 |
| 2.2 多比特数验证 | 1/2/4/8/12/16 bit全部满足误差 <= delta/2 | 不同量化精度下误差上界均成立 |
| 2.3 信号截断 | 截断后索引在 `[0, 2^N-1]`，信号在 `[xmin, xmax]` | 超出量化范围的样本被截断到边界，不产生越界索引 |
| 2.4 量化级数 | `length(levels) == 2^N` 且首末电平值正确 | 4-bit量化应有16级，首级=0.5，末级=15.5（步长1，范围[0,16]） |
| 2.5 量化噪声功率 | 实测噪声功率与理论值 `delta^2/12` 相对误差 < 5% | 均匀分布信号的量化噪声服从均匀分布，功率为delta^2/12 |

**3. 联合流程（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 全链路回环 | 量化索引完全一致（Huffman无损），重建SNR > 0 | 量化→Huffman编码→解码→反量化，无损编码不引入额外误差 |

**4. 异常输入（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 空输入拒绝 | `huffman_encode([])` 和 `uniform_quantize([])` 均抛出error | 两个编码函数拒绝空输入 |
| 4.2 非法参数拒绝 | 负比特数、范围倒置、索引越界均抛出error | 量化参数校验覆盖常见非法输入 |

## 函数接口说明

### huffman_encode.m

**功能**：对输入符号序列进行Huffman编码，输出比特流和码本

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| symbols | 1xN 数值数组 | 待编码的符号序列，元素为非负整数，行/列向量均可 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bitstream | 1xM logical数组 | 编码后的比特流，M为编码总比特数 |
| codebook | 结构体数组 | 码本，每个元素含 `.symbol`(符号值)、`.code`(Huffman码字字符串)、`.prob`(符号出现概率) |
| compress_ratio | 标量 | 压缩比 = 原始比特数 / 编码比特数 |

---

### huffman_decode.m

**功能**：根据码本对Huffman比特流进行解码，还原符号序列

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bitstream | 1xM logical数组 | 编码后的比特流 |
| codebook | 结构体数组 | 码本（由 huffman_encode 生成），每个元素含 `.symbol`、`.code`、`.prob` |
| num_symbols | 正整数 | 原始符号序列长度，用于确定解码终止位置；省略时解码到比特流耗尽 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| symbols | 1xN 数值数组 | 解码还原的符号序列 |

---

### uniform_quantize.m

**功能**：对连续信号进行均匀量化，输出量化索引、量化电平和量化后信号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 任意尺寸数值数组 | 待量化的连续信号 |
| num_bits | 正整数 | 量化比特数，如 8 表示256级量化 |
| val_range | 1x2 数组 | 量化范围 [xmin, xmax]，超出范围的信号值截断到边界 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| indices | 与signal同尺寸数组 | 量化索引，取值 0 ~ 2^num_bits-1 |
| levels | 1x(2^num_bits) 数组 | 全部量化电平值 |
| quantized_signal | 与signal同尺寸数组 | 量化后的信号，取值为对应量化电平 |

---

### uniform_dequantize.m

**功能**：根据量化索引和量化参数，反量化重建连续信号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| indices | 任意尺寸数值数组 | 量化索引，取值 0 ~ 2^num_bits-1 |
| num_bits | 正整数 | 量化比特数，必须与编码端一致 |
| val_range | 1x2 数组 | 量化范围 [xmin, xmax]，必须与编码端一致 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| reconstructed | 与indices同尺寸数组 | 反量化重建的信号，重建值 = xmin + (index + 0.5) * delta |

---

### test_source_coding.m

单元测试脚本（14项），覆盖Huffman编解码、均匀量化/反量化、联合流程和异常输入。
