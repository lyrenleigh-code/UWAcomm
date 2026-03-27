# 符号映射/判决模块 (Modulation)

水声通信系统调制解调算法库，覆盖QAM/PSK和MFSK两大类，支持Gray/自然映射及硬/软判决。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `qam_modulate.m` | QAM/PSK符号映射（比特→复数符号） | QAM/PSK |
| `qam_demodulate.m` | QAM/PSK符号判决（硬判决+软判决LLR） | QAM/PSK |
| `mfsk_modulate.m` | MFSK符号映射（比特→频率索引） | MFSK |
| `mfsk_demodulate.m` | MFSK符号判决（频率索引→比特） | MFSK |
| `plot_constellation.m` | 星座图绘制（含比特标注和接收散点） | 辅助 |
| `test_modulation.m` | 单元测试（25项） | 测试 |

## 模块功能与接口概述

模块4位于交织之后。输入为交织后的二进制比特流，输出为复数调制符号（QAM/PSK）或频率索引（MFSK）。下游接模块5（扩频,可选）或模块6（多载波,可选）。接收端：输入为均衡后的复数符号，输出为硬判决比特或软判决LLR。软判决LLR可直接输入Turbo/LDPC软译码器。

## 支持的调制方式

| 调制 | M | 比特/符号 | 星座结构 | 适用场景 |
|------|---|-----------|----------|----------|
| BPSK | 2 | 1 | 实轴 ±1 | 低SNR，最大鲁棒性 |
| QPSK | 4 | 2 | 2×2方形 | 中等速率，平衡性能 |
| 8QAM | 8 | 3 | 4×2矩形 | 非标准，特定应用 |
| 16QAM | 16 | 4 | 4×4方形 | 高速率 |
| 64QAM | 64 | 6 | 8×8方形 | 极高速率，需高SNR |
| M-FSK | 2/4/8/16 | log2(M) | 频率索引 | 抗多径，能量检测 |

## 调制解调说明

### 1. QAM/PSK调制解调

```matlab
% 调制
bits = randi([0 1], 1, 400);
[symbols, constellation, bit_map] = qam_modulate(bits, 16, 'gray');

% 硬判决解调
[bits_hard, ~] = qam_demodulate(symbols, 16, 'gray');

% 软判决解调（需提供噪声方差）
noise_var = 0.1;
rx = symbols + sqrt(noise_var/2) * (randn(size(symbols)) + 1j*randn(size(symbols)));
[bits_hard, LLR] = qam_demodulate(rx, 16, 'gray', noise_var);
```

### 2. MFSK调制解调

```matlab
% 调制（仅比特→频率索引映射）
bits = randi([0 1], 1, 30);
[freq_indices, ~, ~] = mfsk_modulate(bits, 8, 'gray');

% 解调（频率索引→比特）
bits_out = mfsk_demodulate(freq_indices, 8, 'gray');
```

### 3. 星座图绘制

```matlab
% 绘制16QAM星座图，叠加接收散点
plot_constellation(16, 'gray', rx_symbols);
```

## Gray映射 vs 自然映射

- **Gray映射（默认）**：相邻星座点仅差1比特，1个符号错误通常只引起1比特错误，BER更优
- **自然映射**：按二进制自然顺序编号，实现简单但BER性能较差

```matlab
% Gray映射
[sym_gray, ~, ~] = qam_modulate(bits, 16, 'gray');

% 自然映射
[sym_nat, ~, ~] = qam_modulate(bits, 16, 'natural');
```

## 软判决LLR说明

Max-Log-MAP近似计算每个比特的对数似然比：

```
LLR_k = (1/σ²)(min_{s:b_k=0}|y-s|² - min_{s:b_k=1}|y-s|²)
```

- `LLR > 0` → 比特1更可能
- `LLR < 0` → 比特0更可能
- `|LLR|` 越大 → 判决信心越高
- SNR越高 → LLR幅度越大

软判决LLR可直接输入Turbo/LDPC译码器，获得比硬判决更好的纠错性能。

## 输入输出约定

- **调制输入**：0/1比特数组，长度须为 log2(M) 的整数倍
- **调制输出**：复数符号，星座归一化为单位平均功率 E[|s|²]=1
- **解调输入**：复数接收符号（含噪声）
- **LLR约定**：正值→比特1，负值→比特0（与Turbo/LDPC模块一致）
- **MFSK索引**：整数 0 ~ M-1，对应M个频率

## 函数接口说明

### qam_modulate.m

**功能**：QAM/PSK符号映射，支持BPSK/QPSK/8QAM/16QAM/64QAM

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bits | 1xN 数组 | 比特序列，N须为 log2(M) 的整数倍 |
| M | 整数 | 调制阶数，支持 2/4/8/16/64 |
| mapping | 字符串 | 映射方式，'gray'(默认) 或 'natural' |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| symbols | 1x(N/log2(M)) 复数数组 | 调制后的复数符号序列 |
| constellation | 1xM 复数数组 | 星座点集合，归一化为单位平均功率 E[\|s\|^2]=1 |
| bit_map | M x log2(M) 矩阵 | 各星座点对应的比特模式 |

---

### qam_demodulate.m

**功能**：QAM/PSK符号判决，支持硬判决和软判决(LLR)

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| symbols | 1xL 复数数组 | 接收符号序列 |
| M | 整数 | 调制阶数，支持 2/4/8/16/64 |
| mapping | 字符串 | 映射方式，'gray'(默认) 或 'natural' |
| noise_var | 正实数（可选） | 噪声方差 sigma^2，提供时计算软判决LLR |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bits | 1x(L*log2(M)) 数组 | 硬判决比特序列 |
| LLR | 1x(L*log2(M)) 数组 | 软判决对数似然比。正值表示比特1更可能，负值表示比特0更可能。未提供noise_var时为空 [] |

---

### mfsk_modulate.m

**功能**：MFSK符号映射，比特序列转频率索引

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bits | 1xN 数组 | 比特序列，N须为 log2(M) 的整数倍 |
| M | 整数 | 频率数，2的幂（2/4/8/16），默认 4 |
| mapping | 字符串 | 映射方式，'gray'(默认) 或 'natural' |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| freq_indices | 1x(N/log2(M)) 数组 | 频率索引序列，取值 0 ~ M-1 |
| M | 整数 | 实际使用的频率数 |
| bit_map | M x log2(M) 矩阵 | 比特到索引映射表 |

---

### mfsk_demodulate.m

**功能**：MFSK符号判决，频率索引转比特序列

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| freq_indices | 1xL 数组 | 频率索引序列，取值 0 ~ M-1 |
| M | 整数 | 频率数，须与调制端一致 |
| mapping | 字符串 | 映射方式，'gray'(默认) 或 'natural' |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bits | 1x(L*log2(M)) 数组 | 解调后的比特序列 |

---

### plot_constellation.m

绘制QAM/PSK星座图，标注比特映射，可选叠加接收符号散点。输入：`M`(调制阶数)、`mapping`(映射方式)、`received_symbols`(接收符号，可选)。

---

### test_modulation.m

单元测试脚本（25项），覆盖QAM Gray/自然映射回环、Gray特性验证、软判决LLR、MFSK、星座图绘制和异常输入。

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\Modulation\src\Matlab');
run('test_modulation.m');
```

### 测试用例说明

**1. QAM Gray回环（5项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1~1.5 BPSK/QPSK/8QAM/16QAM/64QAM | `bits_out == bits_in` 且平均功率=1 | 各阶数Gray映射编解调无差错回环，星座归一化验证 |

**2. QAM自然映射回环（5项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1~2.5 各阶数 | `bits_out == bits_in` | natural映射也能正确回环 |

**3. Gray映射特性（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 最近邻汉明距离 | 所有星座点的最近邻汉明距离=1 | Gray码核心性质：相邻点仅差1比特 |
| 3.2 比特映射唯一性 | M个比特模式互不重复 | 每个星座点对应唯一比特组合 |

**4. 软判决LLR（3项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 无噪声LLR符号 | `sign(LLR) == bits` | 极小噪声下LLR符号应完全匹配原始比特 |
| 4.2 LLR硬判决一致性 | LLR硬判决 = 最近邻硬判决 | Max-Log-MAP的硬判决结果应与最小距离判决一致 |
| 4.3 LLR幅度趋势 | 平均\|LLR\|随SNR递增 | SNR越高判决信心越高，LLR幅度越大 |

**5. MFSK（5项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 5.1~5.4 2/4/8/16-FSK | `bits_out == bits_in` 且索引在[0,M-1] | 各阶数Gray映射回环正确 |
| 5.5 8-FSK natural | `bits_out == bits_in` | 自然映射也能正确回环 |

**6. 星座图绘制（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 6.1 绘制16QAM | 函数执行无报错 | 验证星座图绘制含接收散点叠加 |

**7. 异常输入（3项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 7.1 空输入 | 4个函数均报错 | 拒绝空输入 |
| 7.2 非法M值 | M=3和M=32均报错 | 仅接受支持的调制阶数 |
| 7.3 比特长度不匹配 | 3bit输入QPSK报错 | 比特数须为log2(M)整数倍 |
