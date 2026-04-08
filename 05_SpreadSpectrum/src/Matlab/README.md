# 扩频/解扩模块 (SpreadSpectrum)

提供扩频处理能力，覆盖DSSS直接序列扩频、CSK循环移位键控、M-ary组合扩频、FH跳频四种方案，含扩频码生成器（m序列/Gold码/Walsh-Hadamard码/Kasami码）和差分检测器（DCD/DED）。

## 对外接口

其他模块/端到端应调用的函数：

### gen_msequence — m序列生成

基于线性反馈移位寄存器(LFSR)生成最大长度序列。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| degree | 输入 | 正整数 | 移位寄存器级数，序列长度 = 2^degree - 1 | 必填 |
| poly | 输入 | 1x(degree+1) 二进制数组 | 生成多项式系数，高位在前 | 预置本原多项式(degree=2~15) |
| init_state | 输入 | 1xdegree 二进制数组 | 寄存器初始状态，不可全0 | 全1 |
| seq | 输出 | 1x(2^degree-1) 数组 | m序列，值为 0/1 | — |
| poly | 输出 | 1x(degree+1) 数组 | 实际使用的生成多项式 | — |

### gen_gold_code — Gold码生成

两条m序列（优选对）异或生成Gold码。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| degree | 输入 | 正整数 | m序列级数 | 必填 |
| shift | 输入 | 整数 | 第二条m序列的循环移位量，取值 0 ~ 2^degree-2 | 0 |
| poly1 | 输入 | 1x(degree+1) 二进制数组 | 第一条m序列生成多项式 | 预置优选对(degree=5/6/7/9/10/11) |
| poly2 | 输入 | 1x(degree+1) 二进制数组 | 第二条m序列生成多项式 | 预置优选对 |
| code | 输出 | 1x(2^degree-1) 数组 | Gold码，值为 0/1 | — |
| seq1 | 输出 | 1x(2^degree-1) 数组 | 第一条m序列 | — |
| seq2 | 输出 | 1x(2^degree-1) 数组 | 第二条m序列（移位后） | — |

### gen_walsh_hadamard — Walsh-Hadamard正交码矩阵

递归Sylvester构造生成NxN正交码集。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| N | 输入 | 正整数 | 码长，必须为2的幂（2/4/8/16/...） | 必填 |
| W | 输出 | NxN 矩阵 | Walsh-Hadamard矩阵，值为 +1/-1，任意两行正交 | — |

### gen_kasami_code — Kasami码小集合

由一条m序列及其抽取序列生成，互相关性能优于Gold码。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| degree | 输入 | 偶数正整数 | m序列级数，>=4（如 4/6/8/10） | 必填 |
| codes | 输出 | (num_codes)x(2^degree-1) 矩阵 | Kasami码集合，值为 0/1 | — |
| num_codes | 输出 | 正整数 | 码字数量 = 2^(degree/2) + 1 | — |

### dsss_spread — DSSS直接序列扩频

每个符号乘以扩频码。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| symbols | 输入 | 1xN 数组 | 调制后符号序列，实数或复数，通常为+-1 | 必填 |
| code | 输入 | 1xL 数组 | 扩频码，值为 +1/-1 或 0/1（自动转+-1） | 必填 |
| spread_signal | 输出 | 1x(N*L) 数组 | 扩频后的码片序列 | — |

### dsss_despread — DSSS相关解扩

标准相关解扩恢复符号。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| received | 输入 | 1xM 数组 | 接收码片序列，M须为码长L的整数倍 | 必填 |
| code | 输入 | 1xL 数组 | 扩频码，值为 +1/-1 或 0/1 | 必填 |
| symbols | 输出 | 1x(M/L) 数组 | 解扩后的符号序列 | — |
| corr_values | 输出 | 1x(M/L) 复数数组 | 各符号的相关值，供DCD/DED检测器使用 | — |

### csk_spread — CSK循环移位键控扩频

用码序列的不同循环移位表示不同符号。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| bits | 输入 | 1xN 数组 | 比特序列，N须为 log2(M) 的整数倍 | 必填 |
| base_code | 输入 | 1xL 数组 | 基础扩频码，值为 +1/-1 或 0/1 | 必填 |
| M | 输入 | 正整数 | 调制阶数，2的幂 | 2 |
| spread_signal | 输出 | 1x(num_symbols*L) 数组 | 扩频后码片序列 | — |
| shift_amounts | 输出 | 1xnum_symbols 数组 | 各符号对应的循环移位量 | — |

### csk_despread — CSK解扩

全移位相关检测，选择相关峰最大的移位量解码。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| received | 输入 | 1xN 数组 | 接收码片序列，N须为码长L的整数倍 | 必填 |
| base_code | 输入 | 1xL 数组 | 基础扩频码，须与发端一致 | 必填 |
| M | 输入 | 正整数 | 调制阶数，须与发端一致 | 2 |
| bits | 输出 | 1x(num_symbols*log2(M)) 数组 | 解调后比特序列 | — |
| corr_matrix | 输出 | num_symbols x M 矩阵 | 各符号与M个移位码的相关矩阵 | — |

### mary_spread — M-ary组合扩频

每log2(M)个比特选择一个码字发送。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| bits | 输入 | 1xN 数组 | 比特序列，N须为 log2(M) 的整数倍 | 必填 |
| code_set | 输入 | MxL 矩阵 | 码字集合，M个码字各长L，值为 +1/-1 或 0/1 | 必填 |
| spread_signal | 输出 | 1x(num_symbols*L) 数组 | 扩频后码片序列 | — |

### mary_despread — M-ary解扩

与所有码字相关，选最大相关值解码。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| received | 输入 | 1xN 数组 | 接收码片序列，N须为码长L的整数倍 | 必填 |
| code_set | 输入 | MxL 矩阵 | 码字集合，须与发端一致 | 必填 |
| bits | 输出 | 1x(num_symbols*log2(M)) 数组 | 解调后比特序列 | — |
| corr_matrix | 输出 | num_symbols x M 矩阵 | 各符号与M个码字的相关矩阵 | — |

### gen_hop_pattern — 伪随机跳频图案生成

基于随机种子生成确定性跳频图案，收发须一致。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| num_hops | 输入 | 正整数 | 跳频次数/图案长度 | 必填 |
| num_freqs | 输入 | 正整数 | 可用频率数，>=2 | 16 |
| seed | 输入 | 非负整数 | 随机种子，收发须一致 | 0 |
| pattern | 输出 | 1xnum_hops 数组 | 跳频图案，取值 0 ~ num_freqs-1 | — |
| num_freqs | 输出 | 正整数 | 实际使用的频率数 | — |

### fh_spread — 跳频扩频

对频率索引施加伪随机跳频偏移。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| freq_indices | 输入 | 1xN 数组 | 原始频率索引，取值 0 ~ num_freqs-1 | 必填 |
| pattern | 输入 | 1xN 数组 | 跳频图案，须与freq_indices等长 | 必填 |
| num_freqs | 输入 | 正整数 | 可用频率总数 | 必填 |
| hopped_indices | 输出 | 1xN 数组 | 跳频后的频率索引，取值 0 ~ num_freqs-1 | — |

### fh_despread — 去跳频

移除跳频偏移，还原原始频率索引。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| hopped_indices | 输入 | 1xN 数组 | 跳频后的频率索引 | 必填 |
| pattern | 输入 | 1xN 数组 | 跳频图案，须与发端完全一致 | 必填 |
| num_freqs | 输入 | 正整数 | 可用频率总数，须与发端一致 | 必填 |
| freq_indices | 输出 | 1xN 数组 | 还原的原始频率索引，取值 0 ~ num_freqs-1 | — |

### det_dcd — 差分相关检测器

利用相邻符号相关值的差分消除载波相位影响。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| corr_values | 输入 | 1xN 复数数组 | 连续符号的相关值序列，由dsss_despread产生，N>=2 | 必填 |
| decisions | 输出 | 1x(N-1) 数组 | 差分检测判决结果，+1/-1 | — |
| diff_corr | 输出 | 1x(N-1) 复数数组 | 差分相关输出 | — |

### det_ded — 差分能量检测器

基于差分相关的能量判决，更抗快速相位波动。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| corr_values | 输入 | 1xN 复数数组 | 连续符号的相关值序列，由dsss_despread产生，N>=3 | 必填 |
| decisions | 输出 | 1x(N-2) 数组 | 能量检测判决结果，+1/-1 | — |
| diff_energy | 输出 | 1x(N-2) 实数数组 | 差分能量输出 | — |

## 内部函数（不建议外部调用）

### plot_code_correlation — 扩频码相关性可视化

绘制扩频码集合的自相关和互相关图。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| codes | 输入 | KxL 矩阵 | 扩频码集合，每行一个码，值为+-1 | 必填 |
| code_names | 输入 | 1xK cell数组 | 码名称 | {'Code 1', 'Code 2', ...} |
| code_type | 输入 | 字符串 | 标题前缀 | 'Spreading Code' |

### test_spread_spectrum — 单元测试

覆盖扩频码生成、DSSS、CSK、M-ary、差分检测器、跳频和异常输入（共18项测试）。

### default_primitive_poly（gen_msequence.m内部函数）

返回degree=2~15的预置本原多项式。

### default_preferred_pair（gen_gold_code.m内部函数）

返回degree=5/6/7/9/10/11的Gold码优选m序列对。

## 核心算法技术描述

### 1. m序列（最大长度序列）

**算法原理**：基于n级线性反馈移位寄存器(LFSR)，输出为寄存器最后一位，反馈由本原多项式决定。

**关键公式**：

$$
L = 2^n - 1
$$
$$
\text{feedback} = \text{XOR}(\text{state}[\text{tap}_1], \text{state}[\text{tap}_2], \ldots, \text{state}[\text{tap}_k])
$$
$$
\text{state} = [\text{feedback}, \text{state}(1:\text{end}-1)]
$$

**自相关性质**（双极性映射后 c = 2*seq - 1）：

$$
R(0) = L \quad \text{(峰值)}
$$
$$
R(\tau) = -1, \quad \tau \neq 0 \quad \text{(旁瓣恒为-1)}
$$

**参数选择**：degree=2~15，预置本原多项式覆盖。degree越大码长越长，扩频增益越高。

**适用条件**：码集大小有限（仅1条码/多项式），适合单用户或码分多址需额外扩展。m序列互相关性能不受控。

### 2. Gold码

**算法原理**：两条m序列（优选对）异或生成，不同循环移位产生不同码字。

**关键公式**：

$$
\text{Gold}(\text{shift}) = \text{seq1} \oplus \text{circshift}(\text{seq2}, \text{shift})
$$
$$
\text{码族大小}: 2^n + 1 \text{ 个码字}
$$
$$
|R_{cross}| \leq t(n), \quad t(n) = \begin{cases} 2^{(n+1)/2} + 1 & n\text{为奇数} \\ 2^{(n+2)/2} + 1 & n\text{为偶数} \end{cases}
$$

**参数选择**：预置优选对覆盖degree=5/6/7/9/10/11。shift=0~L-1选择不同码字。

**适用条件**：码族大（2^n+1个），适合DS-CDMA多用户。互相关限界已知，便于系统设计。局限：互相关旁瓣比m序列高。

### 3. Kasami码（小集合）

**算法原理**：由一条m序列及其q-抽取短序列生成，仅degree为偶数时可用。

**关键公式**：

$$
q = 2^{n/2} + 1 \quad \text{(抽取因子)}
$$
$$
\text{短序列长度} = 2^{n/2} - 1, \quad \text{码字数} = 2^{n/2} + 1
$$
$$
\text{互相关峰值} \leq 2^{n/2} + 1 \quad \text{(优于Gold码的} t(n) \text{)}
$$
$$
\text{Kasami}(k) = m\_seq \oplus \text{circshift}(\text{short\_repeated}, k)
$$

**适用条件**：degree须为偶数(>=4)。码族比Gold码小，但互相关性能更优。适合对干扰抑制要求更高的场景。

### 4. Walsh-Hadamard码

**算法原理**：递归Sylvester构造完全正交码集。

**关键公式**：

$$
H(1) = [1]
$$
$$
H(2N) = \begin{bmatrix} H(N) & H(N) \\ H(N) & -H(N) \end{bmatrix}
$$
$$
W \cdot W^T = N \cdot I, \quad \text{码集大小} = \text{码长} = N
$$

**适用条件**：要求严格同步（零延迟完全正交），适合DS-CDMA同步多址。非零延迟时互相关不受控，不适合异步场景。

### 5. DSSS直接序列扩频/解扩

**算法原理**：发端每个符号乘以扩频码，展开为L个码片；收端对每个码片块做相关恢复符号。

**关键公式**：

$$
\text{扩频}: \text{spread}(n, l) = \text{symbol}(n) \cdot \text{code}(l), \quad l = 1,\ldots,L
$$
$$
\text{解扩}: \hat{\text{symbol}}(n) = \frac{1}{L} \sum_{l=1}^{L} \text{received}(n,l) \cdot \text{code}(l)
$$
$$
\text{扩频增益}: G = L, \quad \text{即 } 10 \cdot \log_{10}(L) \text{ dB}
$$
$$
\text{输出带宽} = \text{输入带宽} \times L
$$

**适用条件**：抗窄带干扰、抗截获（低功率密度）。性能取决于码的自相关特性。多用户时需码集互相关受控。

### 6. CSK循环移位键控

**算法原理**：用基础扩频码的不同循环移位表示不同M进制符号，利用m序列的自相关特性区分移位量。

**关键公式**：

$$
\text{shift}_k = k \cdot \lfloor L/M \rfloor, \quad k = 0, 1, \ldots, M-1
$$
$$
\text{spread} = \text{circshift}(\text{base\_code}, -\text{shift}_k), \quad k\text{由比特组决定}
$$
$$
\hat{k} = \arg\max_k \left| \sum(\text{received} \cdot \text{circshift}(\text{base\_code}, -\text{shift}_k)) \right|
$$
$$
\text{每符号传输比特数} = \log_2(M)
$$

**适用条件**：基于m序列时效果最佳（因自相关旁瓣为-1）。码长L应远大于M以保证移位间距足够。水声CSK常用于低速高可靠场景。

### 7. M-ary组合扩频

**算法原理**：从M个正交码字中选择一个发送，每符号传输log2(M)比特。

**关键公式**：

$$
\text{传输速率} = \log_2(M)/L \quad \text{(bit/chip)}
$$
$$
\text{idx} = \text{bi2de}(\text{bit\_group})
$$
$$
\text{spread} = \text{code\_set}(\text{idx}, :)
$$
$$
\hat{\text{idx}} = \arg\max_k \left| \sum(\text{received} \cdot \text{code\_set}(k,:)) / L \right|
$$

**适用条件**：通常使用Walsh-Hadamard码保证码字正交。相比DSSS的1/L bit/chip，M-ary通过码字选择提高速率。M越大速率越高但抗噪声能力下降。

### 8. 差分相关检测器(DCD)

**算法原理**：利用相邻符号相关值的共轭乘积消除公共相位偏移。

**关键公式**：

$$
\text{diff}(n) = \text{corr}(n) \cdot \text{conj}(\text{corr}(n-1))
$$
$$
\text{decision}(n) = \text{sign}(\text{Re}\{\text{diff}(n)\})
$$

当载波相位 phi 在相邻符号间近似不变时：

$$
\text{corr}(n) = s(n) \cdot e^{j\phi}, \quad \text{corr}(n-1) = s(n-1) \cdot e^{j\phi}
$$
$$
\text{diff}(n) = s(n) \cdot s(n-1) \cdot |e^{j\phi}|^2 = s(n) \cdot s(n-1) \quad \text{(相位消除)}
$$

**适用条件**：低载波相位波动场景。性能损失约1-3 dB（相比相干检测），但无需载波相位估计。需发端做差分预编码。

### 9. 差分能量检测器(DED)

**算法原理**：利用两组差分相关的能量差做判决，利用更多观测量对抗快速相位波动。

**关键公式**：

$$
d_1(n) = \text{corr}(n) \cdot \text{conj}(\text{corr}(n-1))
$$
$$
d_2(n) = \text{corr}(n-1) \cdot \text{conj}(\text{corr}(n-2))
$$
$$
E_{sum} = |d_1 + d_2|^2, \quad E_{diff} = |d_1 - d_2|^2
$$
$$
\text{decision} = \text{sign}(E_{sum} - E_{diff})
$$

**适用条件**：需至少3个连续符号，输出长度=N-2。在快速相位波动下比DCD更鲁棒。性能损失约2-4 dB，但可工作于相干检测完全失效的场景。

### 10. 跳频(FH)扩频

**算法原理**：对频率索引施加伪随机偏移，将信号分散到不同频率。

**关键公式**：

$$
\text{hopped} = \bmod(\text{freq\_index} + \text{pattern}, \text{num\_freqs})
$$
$$
\text{freq\_index} = \bmod(\text{hopped} - \text{pattern}, \text{num\_freqs})
$$
$$
\text{pattern} = \text{randi}([0, \text{num\_freqs}-1], 1, \text{num\_hops}) \quad \text{(seed固定)}
$$

**适用条件**：抗窄带干扰（干扰仅影响部分跳频时隙）。要求收发端跳频图案完全一致（相同seed和参数）。常与MFSK联合使用(FH-MFSK)。

## 使用示例

```matlab
%% DSSS直扩
code = 2*gen_msequence(7) - 1;           % 127码片m序列（双极性）
symbols = [1 -1 1 1 -1];
spread = dsss_spread(symbols, code);
[despread, corr] = dsss_despread(spread, code);

%% CSK循环移位键控
base_code = 2*gen_msequence(7) - 1;
bits = randi([0 1], 1, 20);
spread = csk_spread(bits, base_code, 2);     % 2-CSK
[bits_out, corr_mat] = csk_despread(spread, base_code, 2);

%% M-ary Walsh码扩频
W = gen_walsh_hadamard(8);                   % 8个正交码
bits = randi([0 1], 1, 30);                 % 10个3-bit符号
spread = mary_spread(bits, W);
[bits_out, corr_mat] = mary_despread(spread, W);

%% FH-MFSK全链路（配合模块04）
[freq_idx, ~, ~] = mfsk_modulate(bits, 8, 'gray');
[pattern, ~] = gen_hop_pattern(length(freq_idx), 16, 42);
hopped = fh_spread(freq_idx, pattern, 16);
dehopped = fh_despread(hopped, pattern, 16);
bits_out = mfsk_demodulate(dehopped, 8, 'gray');

%% 差分检测
[symbols_out, corr_values] = dsss_despread(received, code);
[decisions_dcd, ~] = det_dcd(corr_values);   % 差分相关检测
[decisions_ded, ~] = det_ded(corr_values);   % 差分能量检测
```

## 依赖关系

- FH-MFSK全链路依赖模块04（调制）的 `mfsk_modulate` / `mfsk_demodulate`
- 上游：模块04（符号映射）输出的调制符号或比特
- 下游：模块07（导频插入）接收扩频后的码片序列

## 测试覆盖 (test_spread_spectrum.m V1.1, 18项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|----------|----------|------|
| 1.1 | m序列(n=7) | `length(seq)==127`; 自相关峰值=L(`abs(acorr(1)-L)<1e-6`); 旁瓣=-1(`all(abs(acorr(2:end)+1)<1e-6)`) | LFSR生成127码片m序列，验证周期性和自相关性质 |
| 1.2 | Gold码(n=7) | `length(code)==127`; 不同shift码不同(`~isequal`); 互相关<=t(n)=17(`xcorr_val<=t_bound`) | Gold码长度和互相关限界验证 |
| 1.3 | Walsh-Hadamard(16) | `size(W)==[16,16]`; `W*W'==16*I` | 16x16正交码矩阵完全正交性 |
| 1.4 | Kasami码(n=6) | `nc==9`(码字数); `size(codes,2)==63`(码长); `size(codes,1)==9` | 小集合Kasami码集大小和码长 |
| 2.1 | DSSS无噪声回环 | `isequal(sign(symbols_out), symbols_in)`; `length(spread)==N*L` | 10符号DSSS扩频/解扩完全还原 |
| 2.2 | DSSS扩频增益 | `ber<0.05`（输入SNR约0dB，扩频增益约21dB后BER应很低） | L=127码长m序列，验证扩频增益性能 |
| 3.1 | 2-CSK无噪声回环 | `isequal(bits_out, bits_in)` | 20比特2-CSK扩频/解扩完全还原 |
| 3.2 | 4-CSK无噪声回环 | `isequal(bits_out, bits_in)` | 40比特4-CSK扩频/解扩完全还原 |
| 4.1 | 8-ary Walsh回环 | `isequal(bits_out, bits_in)` | 30比特8-ary Walsh码扩频/解扩完全还原 |
| 4.2 | 16-ary抗噪声 | 无显式assert阈值（记录BER） | 16-ary Walsh码在噪声sigma=0.5下的BER |
| 5.1 | DCD无噪声 | `isequal(bits_dcd, bits_orig)` | 50比特差分编码+固定相偏(30度)下DCD完全恢复 |
| 5.2 | DED无噪声 | BER记录（`ber`计算但无显式阈值断言） | 50比特双差分编码+固定相偏(45度)下DED性能 |
| 5.3 | DCD抗相位漂移 | `ber_dcd<0.05` | 200比特，相位从0到360度线性漂移，DCD BER<5% |
| 6.1 | 跳频图案生成 | `isequal(pat1,pat2)`(同seed同图案); `~isequal(pat1,pat3)`(不同seed不同); `all(pat>=0 & pat<num_freqs)`; `length(unique)>1` | 100跳16频率，seed确定性和取值范围验证 |
| 6.2 | FH回环 | `isequal(freq_out, freq_in)`; `~isequal(hopped, freq_in)`; `all(hopped>=0 & hopped<num_freqs)` | 10符号8频率跳频/去跳频完全还原 |
| 6.3 | FH-MFSK全链路 | `isequal(bits_out, bits_in)` | 8FSK+16频跳频，60比特完全还原（依赖模块04） |
| 6.4 | 频率分散性 | `max_dev<0.2`（各频率出现次数与理想均匀偏差<20%） | 1600跳16频率的均匀分布验证 |
| 7.1 | 异常输入拒绝 | `caught==12`（12个空/非法输入均正确抛出错误） | 覆盖dsss/csk/mary/det/fh/gen函数的空输入和非法参数 |

## 可视化说明

测试生成以下figure（位于独立try/catch块中，不影响测试计数）：

- **Figure 1: 扩频码相关特性** — 三子图：(1) m序列(L=127)自相关（峰值=L，旁瓣=-1），(2) Gold码互相关波形，(3) Walsh-Hadamard W*W' 对角矩阵热图
- **Figure 2: DSSS扩频波形** — 四子图：(1) 原始符号，(2) 扩频后码片信号，(3) 加噪后信号(SNR约0dB)，(4) 解扩恢复与原始对比
- **Figure 3: 跳频图案** — 两子图：(1) 跳频时频散点图（100跳x16频率），(2) 频率使用分布柱状图与理想均匀线对比
