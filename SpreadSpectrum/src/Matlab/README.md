# 扩频/解扩模块 (SpreadSpectrum)

水声通信系统扩频算法库，覆盖DSSS直接序列扩频、CSK循环移位键控、M-ary组合扩频三种方案，含四种扩频码生成器和两种差分检测器。

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
| `det_dcd.m` | 差分相关检测器（抗载波相位偏移） | 检测器 |
| `det_ded.m` | 差分能量检测器（抗快速相位波动） | 检测器 |
| `test_spread_spectrum.m` | 单元测试（15项） | 测试 |

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

**6. 异常输入（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 6.1 异常输入 | 9项空输入/非法参数均报错 | 覆盖所有函数的异常输入校验 |
