# 符号映射/判决模块 (Modulation)

将比特流映射为复数调制符号（QAM/PSK）或频率索引（MFSK），接收端支持硬判决和软判决LLR输出。

## 对外接口列表

其他模块/端到端应调用的函数：

### qam_modulate

**功能**：QAM/PSK符号映射，支持BPSK/QPSK/8QAM/16QAM/64QAM

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | bits | 1xN 数组 | 比特序列（0/1，N须为log2(M)的整数倍） | 无（必填） |
| 输入 | M | 整数 | 调制阶数（2/4/8/16/64） | 无（必填） |
| 输入 | mapping | 字符串 | 映射方式：'gray' 或 'natural' | 'gray' |
| 输出 | symbols | 1x(N/log2(M)) 复数数组 | 调制后的符号序列 | — |
| 输出 | constellation | 1xM 复数数组 | 星座点集合（归一化为单位平均功率） | — |
| 输出 | bit_map | Mxlog2(M) 矩阵 | 各星座点对应的比特模式 | — |

### qam_demodulate

**功能**：QAM/PSK硬判决 + 软判决LLR

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | symbols | 1xL 复数数组 | 接收符号序列 | 无（必填） |
| 输入 | M | 整数 | 调制阶数（2/4/8/16/64） | 无（必填） |
| 输入 | mapping | 字符串 | 映射方式：'gray' 或 'natural' | 'gray' |
| 输入 | noise_var | 正实数 | 噪声方差sigma^2（可选，提供时计算LLR） | []（不计算LLR） |
| 输出 | bits | 1x(L*log2(M)) 数组 | 硬判决比特序列 | — |
| 输出 | LLR | 1x(L*log2(M)) 数组 | 软判决LLR（正值→bit 1, 负值→bit 0；未提供noise_var时为[]） | — |

### mfsk_modulate

**功能**：MFSK符号映射，比特序列转频率索引

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | bits | 1xN 数组 | 比特序列（0/1，N须为log2(M)的整数倍） | 无（必填） |
| 输入 | M | 整数 | 频率数（2的幂：2/4/8/16/...） | 4 |
| 输入 | mapping | 字符串 | 映射方式：'gray' 或 'natural' | 'gray' |
| 输出 | freq_indices | 1x(N/log2(M)) 数组 | 频率索引序列，取值 0 ~ M-1 | — |
| 输出 | M | 整数 | 实际频率数 | — |
| 输出 | bit_map | Mxlog2(M) 矩阵 | 比特到索引映射表 | — |

### mfsk_demodulate

**功能**：MFSK符号判决，频率索引转比特序列

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | freq_indices | 1xL 数组 | 频率索引序列（取值 0 ~ M-1） | 无（必填） |
| 输入 | M | 整数 | 频率数（须与调制端一致） | 4 |
| 输入 | mapping | 字符串 | 映射方式（须与调制端一致） | 'gray' |
| 输出 | bits | 1x(L*log2(M)) 数组 | 解调后的比特序列 | — |

## 内部函数接口列表

以下为辅助函数，不建议外部直接调用：

### generate_constellation（qam_modulate.m内部）

**功能**：生成归一化星座图和对应比特映射表

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | M | 整数 | 调制阶数 | 无 |
| 输入 | mapping | 字符串 | 'gray' 或 'natural' | 无 |
| 输出 | constellation | 1xM 复数数组 | 单位平均功率星座点 | — |
| 输出 | bit_map | Mxlog2(M) 矩阵 | 比特映射 | — |

### gen_pam_levels（qam_modulate.m内部）

**功能**：生成K级PAM电平和对应比特映射

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | K | 整数 | 电平数（2的幂） | 无 |
| 输入 | mapping | 字符串 | 'gray' 或 'natural' | 无 |
| 输出 | pam | 1xK 结构体数组 | 每个元素含 .level(幅度) 和 .bits(比特) | — |

### gray_code_order（qam_modulate.m内部）

**功能**：生成K个Gray码索引（反射二进制码）

### generate_constellation_demod（qam_demodulate.m内部）

**功能**：生成解调参考星座图（内部调用qam_modulate复用逻辑）

### plot_constellation.m

**功能**：绘制QAM/PSK星座图，标注比特映射，可选叠加接收符号散点

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | M | 整数 | 调制阶数（2/4/8/16/64） | 无（必填） |
| 输入 | mapping | 字符串 | 映射方式 | 'gray' |
| 输入 | received_symbols | 1xL 复数数组 | 接收端符号（可选，蓝色散点叠加） | [] |

### test_modulation.m

**功能**：符号映射/判决模块单元测试（25项）

## 核心算法技术描述

### QAM星座映射

**算法原理**：将比特组映射到复平面上的星座点。方形QAM由两个正交PAM维度组成：I分量和Q分量各独立映射。8QAM使用4x2矩形构型。所有星座归一化为单位平均功率 E[|s|^2]=1。

**关键公式**：

PAM电平（K级）：

$$
\text{levels} = -(K-1), -(K-3), \ldots, (K-3), (K-1)
$$

方形QAM星座点（K = sqrt(M)）：

$$
s = (I_{level} + j \cdot Q_{level}) / \sqrt{E[|s|^2]}
$$

功率归一化：

$$
s_{norm} = s / \sqrt{\text{mean}(|s|^2)}
$$

Gray码生成（反射二进制码）：

$$
\text{gray}(n) = n \oplus (n \gg 1)
$$

Gray映射保证相邻星座点（最小欧氏距离）仅差1个比特，最小化高SNR下的BER。

**支持的星座构型**：
- BPSK(M=2): 实轴 {-1, +1}
- QPSK(M=4): 2x2方形
- 8QAM(M=8): 4x2矩形（I:4级, Q:2级）
- 16QAM(M=16): 4x4方形
- 64QAM(M=64): 8x8方形

**参数选择依据**：
- BPSK/QPSK：水声信道低SNR首选，抗噪性能最强
- 16/64QAM：高SNR时提升频谱效率，但对相位噪声敏感

**适用条件与局限性**：
- 适用：所有线性调制体制（SC-TDE/SC-FDE/OFDM/OTFS）
- 局限：高阶QAM（64QAM）在水声信道中易受多普勒和多径影响

### QAM软判决（Max-Log-MAP LLR）

**算法原理**：对接收符号的每个比特位，分别找比特为0和比特为1时距离最近的星座点，用距离差计算对数似然比。

**关键公式**：

Max-Log-MAP近似LLR：

$$
LLR_k = \frac{1}{\sigma^2} \left( \min_{s: b_k=0} |y - s|^2 - \min_{s: b_k=1} |y - s|^2 \right)
$$

其中 y 为接收符号，s 为参考星座点，b_k 为第k个比特位，sigma^2 为噪声方差。

LLR > 0 表示比特1更可能，LLR < 0 表示比特0更可能。|LLR|越大表示判决置信度越高。

硬判决（最小欧氏距离）：

$$
\hat{s} = \arg\min_s |y - s|^2
$$
$$
\text{bits} = \text{bit\_map}(\hat{s})
$$

**参数选择依据**：
- noise_var：须准确估计，过大导致LLR偏软（置信度低），过小导致LLR过度自信
- SNR越高，|LLR|越大

**适用条件与局限性**：
- Max-Log-MAP比真MAP近似有微小损失，但计算简单
- LLR硬判决结果与最近邻硬判决完全一致
- 在Turbo迭代中，LLR软值供SISO译码器使用

### MFSK频率映射

**算法原理**：将log2(M)个比特映射到M个频率索引之一。仅完成比特到频率索引的映射，实际FSK波形生成在上变频模块(09)实现。

**关键公式**：

每符号比特数：

$$
bps = \log_2(M)
$$

Gray码映射：

$$
\text{freq\_index} = \text{gray\_code}(\text{bit\_group\_decimal})
$$

频谱效率：

$$
\eta = \log_2(M) / M \quad \text{(bit/s/Hz)}
$$

**参数选择依据**：
- M=2: 1 bit/符号，最简单，频谱效率低
- M=4/8: 水声跳频MFSK常用
- M越大频谱效率越低但抗噪性能越强（非相干检测）

**适用条件与局限性**：
- 适用：FH-MFSK（跳频多频移键控）体制
- 局限：频谱效率随M增大递减；本模块仅映射索引，波形生成需配合模块09

## 使用示例

```matlab
%% QAM调制/解调
bits = randi([0 1], 1, 400);
[symbols, constellation, bit_map] = qam_modulate(bits, 16, 'gray');
noise_var = 0.1;
noise = sqrt(noise_var/2) * (randn(size(symbols)) + 1j*randn(size(symbols)));
[bits_hard, LLR] = qam_demodulate(symbols + noise, 16, 'gray', noise_var);

%% MFSK调制/解调
bits = randi([0 1], 1, 30);
[freq_indices, ~, ~] = mfsk_modulate(bits, 8, 'gray');
bits_out = mfsk_demodulate(freq_indices, 8, 'gray');

%% 星座图绘制
plot_constellation(16, 'gray', symbols + noise);
```

## 依赖关系

- 无外部模块依赖
- 上游：模块03（交织）输出的交织比特流
- 下游：模块05（扩频，可选）或模块06（多载波，可选）接收调制符号
- MFSK频率索引可被模块05（扩频）的跳频功能使用

## 测试覆盖 (test_modulation.m V1.0.0, 25项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|---------|---------|------|
| 1.1 | BPSK Gray回环 | isequal(bits_out, bits_in), len(symbols)==200, abs(avg_power-1)<1e-10 | 无噪声硬判决完全一致，功率归一化 |
| 1.2 | QPSK Gray回环 | isequal(bits_out, bits_in), len(symbols)==200, abs(avg_power-1)<1e-10 | 同上 |
| 1.3 | 8QAM Gray回环 | isequal(bits_out, bits_in), len(symbols)==200, abs(avg_power-1)<1e-10 | 同上 |
| 1.4 | 16QAM Gray回环 | isequal(bits_out, bits_in), len(symbols)==200, abs(avg_power-1)<1e-10 | 同上 |
| 1.5 | 64QAM Gray回环 | isequal(bits_out, bits_in), len(symbols)==200, abs(avg_power-1)<1e-10 | 同上 |
| 2.1 | BPSK natural回环 | isequal(bits_out, bits_in) | natural映射解调一致 |
| 2.2 | QPSK natural回环 | isequal(bits_out, bits_in) | 同上 |
| 2.3 | 8QAM natural回环 | isequal(bits_out, bits_in) | 同上 |
| 2.4 | 16QAM natural回环 | isequal(bits_out, bits_in) | 同上 |
| 2.5 | 64QAM natural回环 | isequal(bits_out, bits_in) | 同上 |
| 3.1 | Gray最近邻汉明距离 | QPSK/16QAM/64QAM每个星座点最近邻汉明距离==1 | Gray码特性验证 |
| 3.2 | 比特映射唯一性 | 5种阶数(2/4/8/16/64)全部无重复映射 | M个星座点映射互不相同 |
| 4.1 | 无噪声LLR符号 | LLR>0与bit==1完全对应 | 16QAM，极小方差下LLR符号正确 |
| 4.2 | LLR硬判决一致性 | (LLR>0)硬判决 == 最近邻硬判决 | 16QAM AWGN下两种硬判决一致 |
| 4.3 | LLR幅度趋势 | avg_llr(0dB) < avg_llr(10dB) < avg_llr(20dB) | SNR越高LLR幅度越大 |
| 5.1 | 2-FSK Gray回环 | isequal(bits_out, bits_in), freq_idx in [0, M-1] | 100符号 |
| 5.2 | 4-FSK Gray回环 | isequal(bits_out, bits_in), freq_idx in [0, M-1] | 100符号 |
| 5.3 | 8-FSK Gray回环 | isequal(bits_out, bits_in), freq_idx in [0, M-1] | 100符号 |
| 5.4 | 16-FSK Gray回环 | isequal(bits_out, bits_in), freq_idx in [0, M-1] | 100符号 |
| 5.5 | 8-FSK natural回环 | isequal(bits_out, bits_in) | natural映射验证 |
| 6.1 | 16QAM星座图绘制 | plot_constellation(16, 'gray', rx)不报错 | 含接收散点的星座图 |
| 7.1 | 空输入拒绝 | qam_modulate/demodulate/mfsk_modulate/demodulate对[]均报错 | 4个函数 |
| 7.2 | 非法M值拒绝 | M=3和M=32均报错 | QAM仅支持2/4/8/16/64 |
| 7.3 | 比特长度校验 | 3bit输入到QPSK(log2(4)=2)报错 | 非整数倍被拒绝 |

## 可视化说明

- **Figure 1**（test_modulation.m 测试6.1）：16QAM Gray映射星座图，红色圆圈为参考星座点（标注比特模式），蓝色散点为AWGN接收符号
- **plot_constellation.m**：可独立调用，支持所有QAM阶数和Gray/natural映射，可选叠加接收符号散点
