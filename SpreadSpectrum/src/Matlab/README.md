# 扩频/解扩模块 (SpreadSpectrum)

水声通信系统扩频算法库，覆盖DSSS直接序列扩频、CSK循环移位键控、M-ary组合扩频、FH跳频四种方案，含四种扩频码生成器和两种差分检测器。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `gen_msequence.m` | m序列生成（LFSR，预置本原多项式n=2~15） | 码生成 |
| `gen_gold_code.m` | Gold码生成（优选对m序列异或） | 码生成 |
| `gen_walsh_hadamard.m` | Walsh-Hadamard正交码矩阵 | 码生成 |
| `gen_kasami_code.m` | Kasami码小集合（偶数degree） | 码生成 |
| `dsss_spread.m` | DSSS直扩（符号×扩频码） | 扩频 |
| `dsss_despread.m` | DSSS解扩（相关检测） | 解扩 |
| `csk_spread.m` | CSK扩频（循环移位映射） | 扩频 |
| `csk_despread.m` | CSK解扩（全移位相关检测） | 解扩 |
| `mary_spread.m` | M-ary扩频（码字选择映射） | 扩频 |
| `mary_despread.m` | M-ary解扩（多码相关检测） | 解扩 |
| `gen_hop_pattern.m` | 伪随机跳频图案生成 | 跳频 |
| `fh_spread.m` | 跳频扩频（频率索引+偏移） | 跳频 |
| `fh_despread.m` | 去跳频（频率索引-偏移） | 跳频 |
| `det_dcd.m` | 差分相关检测器（抗载波相位偏移） | 检测器 |
| `det_ded.m` | 差分能量检测器（抗快速相位波动） | 检测器 |
| `test_spread_spectrum.m` | 单元测试（19项） | 测试 |

## 四种扩频码对比

| 码类型 | 码长 | 码集大小 | 互相关 | 适用场景 |
|--------|------|----------|--------|----------|
| m序列 | 2^n-1 | 1 | 旁瓣-1（自相关优） | DSSS单用户 |
| Gold码 | 2^n-1 | 2^n+1 | ≤2^((n+1)/2)+1 | CDMA多用户 |
| Walsh-Hadamard | N | N | 0（完全正交） | 同步CDMA |
| Kasami码 | 2^n-1 | 2^(n/2)+1 | ≤2^(n/2)+1 | 低互相关多用户 |

## 三种扩频方式说明

### 1. DSSS直接序列扩频

```matlab
code = 2*gen_msequence(7) - 1;            % 127码片m序列
symbols = [1 -1 1 1 -1];                  % BPSK符号
spread = dsss_spread(symbols, code);       % 扩频
[despread, corr] = dsss_despread(spread, code);  % 解扩
```

### 2. CSK循环移位键控

```matlab
base_code = 2*gen_msequence(7) - 1;
bits = randi([0 1], 1, 20);
spread = csk_spread(bits, base_code, 4);   % 4-CSK, 2bit/符号
bits_out = csk_despread(spread, base_code, 4);
```

### 3. M-ary组合扩频

```matlab
W = gen_walsh_hadamard(16);                % 16个正交码
bits = randi([0 1], 1, 40);               % 10个4-bit符号
spread = mary_spread(bits, W);
bits_out = mary_despread(spread, W);
```

## 4. FH跳频扩频

```matlab
% 跳频图案生成（收发端seed须一致）
num_freqs = 16;
[pattern, ~] = gen_hop_pattern(100, num_freqs, 42);

% FH-MFSK全链路：MFSK映射 → 跳频 → 去跳频 → MFSK解映射
[freq_idx, ~, ~] = mfsk_modulate(bits, 8, 'gray');
hopped = fh_spread(freq_idx, pattern, num_freqs);
% ... 经信道传输 ...
dehopped = fh_despread(hopped, pattern, num_freqs);
bits_out = mfsk_demodulate(dehopped, 8, 'gray');
```

- 跳频操作：`hopped = mod(freq_index + pattern, num_freqs)`，频域循环移位
- 去跳频：`freq_index = mod(hopped - pattern, num_freqs)`
- 抗窄带干扰：干扰仅影响部分跳频时隙，配合纠错码可恢复
- FSK波形生成留在Waveform模块，本模块仅处理索引级操作

## 差分检测器

移动水声通信中载波相位波动严重，标准相干检测失效。差分检测器通过相邻符号间的差分运算消除相位影响。

### DCD（差分相关检测）
```matlab
% 发端：差分编码 + DSSS扩频
% 收端：解扩获得corr_values后
[decisions, diff_corr] = det_dcd(corr_values);
```
- 原理：`diff(n) = Re{corr(n) * conj(corr(n-1))}`
- 适用：低速相位漂移
- 损失：~1-3 dB

### DED（差分能量检测）
```matlab
[decisions, diff_energy] = det_ded(corr_values);
```
- 原理：利用两组差分相关的能量差判决
- 适用：快速相位波动
- 损失：~2-4 dB

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\SpreadSpectrum\src\Matlab');
run('test_spread_spectrum.m');
```

### 测试用例说明

**1. 扩频码生成（4项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 m序列 | 长度=2^7-1，自相关峰值=L，旁瓣=-1 | m序列最大长度和理想自相关特性验证 |
| 1.2 Gold码 | 不同shift→不同码，互相关≤t(n) | Gold码族互相关限界验证 |
| 1.3 Walsh-Hadamard | W*W'=N*I | 完全正交性验证 |
| 1.4 Kasami码 | 码字数=2^(n/2)+1，码长=2^n-1 | 小集合Kasami码参数验证 |

**2. DSSS（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1 无噪声回环 | 解扩符号与原始一致 | 扩频/解扩基本正确性 |
| 2.2 扩频增益 | 输入SNR≈0dB下BER<5% | 127码片m序列提供约21dB扩频增益 |

**3. CSK（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 2-CSK回环 | 比特完全还原 | 二进制CSK正确性 |
| 3.2 4-CSK回环 | 比特完全还原 | 4阶CSK正确性（2bit/符号） |

**4. M-ary（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 8-ary Walsh回环 | 比特完全还原 | Walsh正交码M-ary扩频正确性 |
| 4.2 16-ary抗噪声 | 打印BER | Walsh码扩频在噪声下的性能 |

**5. 差分检测器（3项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 5.1 DCD无噪声 | 差分编码+固定相偏下完全还原 | DCD消除固定载波相位偏移 |
| 5.2 DED无噪声 | 打印BER | DED基本功能验证 |
| 5.3 DCD抗相位漂移 | 相位0→360°漂移下BER<5% | DCD核心优势：在相位持续变化下仍能正确检测 |

**6. 跳频FH（4项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 6.1 图案生成 | 相同seed→相同图案，不同seed→不同，取值在[0,N-1] | 跳频图案确定性和合法性 |
| 6.2 FH回环 | 去跳频后索引完全还原 | 跳频/去跳频的mod运算正确性 |
| 6.3 FH-MFSK全链路 | MFSK映射→跳频→去跳频→解映射，60bit完全还原 | 联合Modulation模块的端到端验证 |
| 6.4 频率分散性 | 1600次跳频中各频率出现次数偏差<20% | 验证图案的伪随机均匀性 |

**7. 异常输入（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 7.1 异常输入 | 12项空输入/非法参数均报错 | 覆盖所有函数（含FH）的异常输入校验 |

## 函数接口说明

### gen_msequence.m

**功能**：生成m序列（最大长度序列），基于线性反馈移位寄存器(LFSR)

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| degree | 正整数 | 移位寄存器级数，序列长度 = 2^degree - 1。预置本原多项式覆盖 degree=2~15 |
| poly | 1x(degree+1) 二进制数组（可选） | 生成多项式系数，高位在前。默认使用预置本原多项式 |
| init_state | 1xdegree 二进制数组（可选） | 寄存器初始状态，默认全1，不可全0 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| seq | 1x(2^degree-1) 数组 | m序列，值为 0/1 |
| poly | 1x(degree+1) 数组 | 实际使用的生成多项式 |

---

### gen_gold_code.m

**功能**：生成Gold码（两条m序列异或）

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| degree | 正整数 | m序列级数 |
| shift | 0 ~ 2^degree-2 整数 | 第二条m序列的循环移位量，默认 0 |
| poly1 | 数组（可选） | 第一条m序列生成多项式，默认使用预置优选对 |
| poly2 | 数组（可选） | 第二条m序列生成多项式 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| code | 1x(2^degree-1) 数组 | Gold码，值为 0/1 |
| seq1 | 1x(2^degree-1) 数组 | 第一条m序列 |
| seq2 | 1x(2^degree-1) 数组 | 第二条m序列（移位后） |

---

### gen_walsh_hadamard.m

**功能**：生成Walsh-Hadamard码矩阵（NxN正交码集）

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| N | 正整数 | 码长，必须为2的幂（4/8/16/32/64/128） |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| W | NxN 矩阵 | Walsh-Hadamard矩阵，值为 +1/-1。每行为一个正交码字，任意两行满足 W(i,:)*W(j,:)'=0 (i!=j) |

---

### gen_kasami_code.m

**功能**：生成Kasami码（小集合），互相关性能优于Gold码

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| degree | 偶数正整数 | m序列级数，如 4/6/8/10 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| codes | num_codes x (2^degree-1) 矩阵 | Kasami码集合，值为 0/1 |
| num_codes | 整数 | 码字数量 = 2^(degree/2) + 1 |

---

### dsss_spread.m

**功能**：DSSS直接序列扩频——每个符号乘以扩频码

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| symbols | 1xN 数组 | 调制后符号序列（实数或复数，通常为+/-1） |
| code | 1xL 数组 | 扩频码，值为 +1/-1 或 0/1（0/1自动转为+/-1） |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| spread_signal | 1x(N*L) 数组 | 扩频后的码片序列 |

---

### dsss_despread.m

**功能**：DSSS直接序列解扩——相关解扩恢复符号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| received | 1xM 数组 | 接收码片序列，M须为码长L的整数倍 |
| code | 1xL 数组 | 扩频码，值为 +1/-1 或 0/1 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| symbols | 1x(M/L) 数组 | 解扩后的符号序列 |
| corr_values | 1x(M/L) 复数数组 | 各符号的相关值，供DCD/DED检测器使用 |

---

### csk_spread.m

**功能**：CSK循环移位键控扩频——用码序列的不同循环移位表示不同符号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bits | 1xN 数组 | 比特序列，N须为 log2(M) 的整数倍 |
| base_code | 1xL 数组 | 基础扩频码，值为 +1/-1 或 0/1 |
| M | 整数 | 调制阶数（2的幂），默认 2。M个循环移位量均匀分配 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| spread_signal | 1x(num_symbols*L) 数组 | 扩频后码片序列 |
| shift_amounts | 1xnum_symbols 数组 | 各符号对应的循环移位量 |

---

### csk_despread.m

**功能**：CSK循环移位键控解扩——相关检测确定移位量，恢复比特

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| received | 1xN 数组 | 接收码片序列，N须为码长L的整数倍 |
| base_code | 1xL 数组 | 基础扩频码，须与发端一致 |
| M | 整数 | 调制阶数，须与发端一致，默认 2 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bits | 1x(num_symbols*log2(M)) 数组 | 解调后比特序列 |
| corr_matrix | num_symbols x M 矩阵 | 各符号与M个移位码的相关矩阵 |

---

### mary_spread.m

**功能**：M-ary扩频——每log2(M)个比特选择一个码字发送

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bits | 1xN 数组 | 比特序列，N须为 log2(M) 的整数倍 |
| code_set | MxL 矩阵 | 码字集合，M个码字各长L，值为 +1/-1 或 0/1 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| spread_signal | 1x(num_symbols*L) 数组 | 扩频后码片序列 |

---

### mary_despread.m

**功能**：M-ary解扩——与所有码字相关，选最大相关值解码

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| received | 1xN 数组 | 接收码片序列，N须为码长L的整数倍 |
| code_set | MxL 矩阵 | 码字集合，须与发端一致 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| bits | 1x(num_symbols*log2(M)) 数组 | 解调后比特序列 |
| corr_matrix | num_symbols x M 矩阵 | 各符号与M个码字的相关矩阵 |

---

### gen_hop_pattern.m

**功能**：生成伪随机跳频图案

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| num_hops | 正整数 | 跳频次数/图案长度 |
| num_freqs | 正整数 | 可用频率数，默认 16 |
| seed | 非负整数 | 随机种子，默认 0，收发须一致 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| pattern | 1xnum_hops 数组 | 跳频图案，取值 0 ~ num_freqs-1 |
| num_freqs | 正整数 | 实际使用的频率数 |

---

### fh_spread.m

**功能**：跳频扩频——对频率索引施加伪随机跳频偏移

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| freq_indices | 1xN 数组 | 原始频率索引序列，取值 0 ~ num_freqs-1 |
| pattern | 1xN 数组 | 跳频图案，长度须与freq_indices一致 |
| num_freqs | 正整数 | 可用频率总数 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| hopped_indices | 1xN 数组 | 跳频后的频率索引，取值 0 ~ num_freqs-1 |

---

### fh_despread.m

**功能**：去跳频——移除跳频偏移，还原原始频率索引

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| hopped_indices | 1xN 数组 | 跳频后的频率索引 |
| pattern | 1xN 数组 | 跳频图案，须与发端完全一致 |
| num_freqs | 正整数 | 可用频率总数 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| freq_indices | 1xN 数组 | 还原的原始频率索引，取值 0 ~ num_freqs-1 |

---

### det_dcd.m

**功能**：差分相关检测器(DCD)——利用相邻符号相关值的差分消除载波相位影响

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| corr_values | 1xN 复数数组 | 连续符号的相关值序列（由dsss_despread产生），至少2个元素 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| decisions | 1x(N-1) 数组 | 差分检测判决结果，+1/-1 |
| diff_corr | 1x(N-1) 复数数组 | 差分相关输出 |

---

### det_ded.m

**功能**：差分能量检测器(DED)——基于差分相关的能量判决，更抗快速相位波动

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| corr_values | 1xN 复数数组 | 连续符号的相关值序列（由dsss_despread产生），至少3个元素 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| decisions | 1x(N-2) 数组 | 能量检测判决结果，+1/-1 |
| diff_energy | 1x(N-2) 实数数组 | 差分能量输出 |

---

### plot_code_correlation.m

扩频码自相关和互相关可视化。输入：`codes`(KxL码矩阵)、`code_names`(名称cell数组)、`code_type`(标题前缀)。

---

### test_spread_spectrum.m

单元测试脚本（19项），覆盖扩频码生成、DSSS、CSK、M-ary、差分检测器、跳频FH和异常输入。
