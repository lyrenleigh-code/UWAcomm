# 信源编解码模块 (SourceCoding)

水声通信发射链路最前端，负责原始数据的无损压缩（Huffman编码）和有损压缩（均匀量化），输出压缩后的二进制比特流供下游信道编码使用。

## 对外接口列表

其他模块/端到端应调用的函数：

### huffman_encode

**功能**：对输入符号序列进行Huffman编码，输出比特流和码本

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | symbols | 1xN 数值数组 | 待编码的符号序列，元素须为非负整数 | 无（必填） |
| 输出 | bitstream | 1xM logical数组 | 编码后的比特流 | — |
| 输出 | codebook | 结构体数组（.symbol, .code, .prob） | 码本，每个元素含符号值、Huffman码字(字符串)、出现概率 | — |
| 输出 | compress_ratio | 标量 | 压缩比 = 原始比特数 / 编码比特数 | — |

### huffman_decode

**功能**：根据码本对Huffman比特流进行解码，还原符号序列

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | bitstream | 1xM logical数组 | 编码后的比特流 | 无（必填） |
| 输入 | codebook | 结构体数组 | 码本（由huffman_encode生成） | 无（必填） |
| 输入 | num_symbols | 正整数 | 原始符号序列长度，用于确定解码终止位置 | inf（解码至比特流耗尽） |
| 输出 | symbols | 1xN 数值数组 | 解码还原的符号序列 | — |

### uniform_quantize

**功能**：对连续信号进行均匀量化，输出量化索引、量化电平和量化后信号

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | signal | 任意尺寸数值数组 | 待量化的连续信号 | 无（必填） |
| 输入 | num_bits | 正整数 | 量化比特数（如8表示256级量化） | 无（必填） |
| 输入 | val_range | 1x2数组 [xmin, xmax] | 量化范围，超出范围的值截断到边界 | 无（必填） |
| 输出 | indices | 与signal同尺寸 | 量化索引，取值 0 ~ 2^num_bits-1 | — |
| 输出 | levels | 1x2^num_bits 数组 | 全部量化电平值 | — |
| 输出 | quantized_signal | 与signal同尺寸 | 量化后的信号（对应量化电平值） | — |

### uniform_dequantize

**功能**：根据量化索引和量化参数，反量化重建连续信号

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | indices | 任意尺寸数值数组 | 量化索引，取值 0 ~ 2^num_bits-1 | 无（必填） |
| 输入 | num_bits | 正整数 | 量化比特数（须与编码端一致） | 无（必填） |
| 输入 | val_range | 1x2数组 [xmin, xmax] | 量化范围（须与编码端一致） | 无（必填） |
| 输出 | reconstructed | 与indices同尺寸 | 反量化重建的信号 | — |

## 内部函数接口列表

以下为辅助函数，不建议外部直接调用：

### build_huffman_tree（huffman_encode.m内部）

**功能**：基于符号概率构建Huffman二叉树，返回各符号码字

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | unique_syms | 1xK 数组 | 不重复的符号值 | 无 |
| 输入 | sym_probs | 1xK 数组 | 各符号对应概率（和为1） | 无 |
| 输出 | codes | 1xK cell数组 | 各符号的Huffman码字（字符串） | — |

### test_source_coding.m

**功能**：信源编解码模块单元测试（14项），覆盖Huffman编解码、均匀量化/反量化、联合流程和异常输入。

## 核心算法技术描述

### Huffman编码

**算法原理**：Huffman编码是一种最优前缀码，基于符号出现概率构建二叉树。高概率符号分配短码字，低概率符号分配长码字，使平均码长最小化。

**关键公式推导**：

信源熵（理论最低平均码长下界）：

$$
H = -\sum_{i=1}^{K} p_i \cdot \log_2(p_i)
$$

Huffman编码保证平均码长 L_avg 满足：

$$
H \leq L_{avg} < H + 1
$$

压缩比计算：

$$
\text{compress\_ratio} = \frac{\lceil \log_2(\max(\text{symbol})+1) \rceil \times N}{\text{total\_coded\_bits}}
$$

**构建过程**：
1. 统计各符号出现频率，计算概率
2. 将每个符号初始化为叶子节点
3. 迭代合并概率最小的两个节点，左子树添加前缀'0'，右子树添加前缀'1'
4. 直到只剩一个根节点，得到所有符号的码字

**参数选择依据**：无需手动调参，码字由概率分布自动确定。

**适用条件与局限性**：
- 适用：符号概率分布不均匀时压缩效果显著
- 局限：等概率分布时无压缩增益；码字为整数比特长度，对短序列效率不如算术编码

### 均匀量化

**算法原理**：将连续信号值域 [xmin, xmax] 均匀划分为 L = 2^B 个量化区间，每个区间用中点值代表。

**关键公式推导**：

量化步长：

$$
\delta = (x_{max} - x_{min}) / L, \quad L = 2^{\text{num\_bits}}
$$

量化索引：

$$
\text{index} = \lfloor (x - x_{min}) / \delta \rfloor, \quad \text{index} \in [0, L-1]
$$

量化电平（中点量化策略）：

$$
\text{level}_k = x_{min} + (k + 0.5) \cdot \delta, \quad k = 0, 1, \ldots, L-1
$$

反量化重建：

$$
\hat{x} = x_{min} + (\text{index} + 0.5) \cdot \delta
$$

量化噪声功率（均匀分布输入信号时）：

$$
\sigma_q^2 = \delta^2 / 12
$$

信号量化信噪比(SQNR)：

$$
\text{SQNR(dB)} \approx 6.02 \times \text{num\_bits} + 1.76 \quad \text{(对满量程正弦信号)}
$$

**参数选择依据**：
- num_bits：8bit适合一般语音/数据，12~16bit用于高精度信号
- val_range：须覆盖信号动态范围，过窄导致截断失真，过宽导致量化精度下降

**适用条件与局限性**：
- 适用：信号幅度分布近似均匀时最优
- 局限：对非均匀分布信号（如语音）效率不及非均匀量化（如mu-law、A-law）

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

## 依赖关系

- 无外部模块依赖（发射链路首模块）
- 下游：模块02（信道编码）接收本模块输出的比特流

## 测试覆盖 (test_source_coding.m V1.0.0, 14项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|---------|---------|------|
| 1.1 | 常规多符号回环 | isequal(symbols_out, symbols_in), cr > 0 | 5种符号编解码一致，压缩比为正 |
| 1.2 | 单一符号序列 | isequal(symbols_out, symbols_in), isscalar(codebook) | 单符号解码正确，码本仅1条目 |
| 1.3 | 两符号等概率 | isequal(symbols_out, symbols_in), 码字长度均为1 | 等概率时码字各为1比特 |
| 1.4 | 大规模随机回环 | isequal(symbols_out, symbols_in) | 10000符号16种符号解码一致 |
| 1.5 | 非均匀分布压缩 | isequal(symbols_out, symbols_in), avg_len < H + 1 | 平均码长小于熵+1 |
| 1.6 | 前缀码验证 | 无码字是另一码字的前缀 | 满足前缀码条件（无二义性） |
| 2.1 | 基本量化反量化回环 | max_err <= delta/2 + eps, qsig == signal_out | 8bit量化误差不超过半步长 |
| 2.2 | 不同量化比特数 | max_err <= delta/2 + 1e-10 (1/2/4/8/12/16 bit) | 6种比特数下误差均在理论范围内 |
| 2.3 | 信号截断 | indices in [0, 2^B-1], qsig in [xmin, xmax] | 超范围样本被正确截断 |
| 2.4 | 量化级数验证 | length(levels)==L, levels(1)≈0.5, levels(end)≈15.5 | 4bit产生16级，电平值正确 |
| 2.5 | 量化噪声功率 | abs(noise_power - delta^2/12) / (delta^2/12) < 0.05 | 实测噪声功率偏离理论值<5% |
| 3.1 | 全链路回环 | isequal(indices_rx, indices_tx) | 量化+Huffman编码+解码+反量化，索引完全一致 |
| 4.1 | 空输入拒绝 | huffman_encode([])报错, uniform_quantize([])报错 | 两个函数均正确拒绝空输入 |
| 4.2 | 非法参数拒绝 | 负比特数/范围倒置/索引越界均报错 | 3种非法参数均被正确捕获 |

## 可视化说明

test_source_coding.m V1.0.0 无独立figure输出（纯数值验证测试）。
