# 脉冲成形/上下变频模块 (Waveform)

水声通信系统物理层波形处理算法库，覆盖脉冲成形、匹配滤波、数字上下变频、FSK波形生成和DA/AD转换仿真。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `pulse_shape.m` | 脉冲成形（RC/RRC/矩形/高斯，上采样+滤波） | 成形滤波 |
| `match_filter.m` | 匹配滤波（成形滤波器的时间反转共轭） | 成形滤波 |
| `upconvert.m` | 数字上变频（复基带→通带实信号） | 变频 |
| `downconvert.m` | 数字下变频（通带→复基带，含LPF） | 变频 |
| `gen_fsk_waveform.m` | FSK波形生成（频率索引→正弦波形，CPFSK） | 波形生成 |
| `da_convert.m` | DA转换仿真（量化/理想模式） | DA/AD |
| `ad_convert.m` | AD转换仿真（量化/理想模式，含截断） | DA/AD |
| `test_waveform.m` | 单元测试（20项） | 测试 |

## 各功能说明

### 1. 脉冲成形 + 匹配滤波

```matlab
sps = 8; rolloff = 0.35; span = 6;

% 发端成形
[shaped, h, t] = pulse_shape(symbols, sps, 'rrc', rolloff, span);

% 收端匹配
[filtered, ~] = match_filter(received, sps, 'rrc', rolloff, span);

% 下采样提取符号
delay = span*sps/2;
sampled = filtered(delay+1 : sps : end);
```

四种滤波器：

| 类型 | 频域特性 | 适用场景 |
|------|----------|----------|
| RC（升余弦） | 零ISI，Nyquist脉冲 | 理论分析 |
| RRC（根升余弦） | 发收级联=RC，实际系统标配 | PSK/QAM通信 |
| 矩形 | 零阶保持 | 简单系统、OFDM |
| 高斯 | 恒包络，低旁瓣 | GMSK、低PAPR需求 |

### 2. 数字上下变频

```matlab
fs = 48000;   % 采样率 48kHz
fc = 12000;   % 载波频率 12kHz

% 上变频：复基带 → 通带实信号
[passband, t] = upconvert(baseband, fs, fc);

% 下变频：通带 → 复基带（含低通滤波去2fc）
[baseband, t] = downconvert(passband, fs, fc, fc/2);
```

- 上变频：`s(t) = I(t)cos(2πfct) - Q(t)sin(2πfct)`
- 下变频：正交混频 + FIR低通滤波
- 采样率须满足：`fs >= 2*(fc + B/2)`

### 3. FSK波形生成

```matlab
M = 8; f0 = 1000; spacing = 100; fs = 8000; dur = 0.01;
[waveform, t, freqs] = gen_fsk_waveform(freq_indices, M, f0, spacing, fs, dur);
```

- 将MFSK/FH模块的频率索引转为实际正弦波
- 连续相位FSK (CPFSK)：符号边界相位连续
- 正交条件：`freq_spacing >= 1/sym_duration`

### 4. DA/AD转换仿真

```matlab
% DA转换（发端）
[da_out, scale] = da_convert(signal, 12, 'quantize');  % 12bit量化
[da_out, ~]     = da_convert(signal, 16, 'ideal');      % 理想直通

% AD转换（收端）
[ad_out, ~] = ad_convert(received, 14, 'quantize', full_scale);
[ad_out, ~] = ad_convert(received, 16, 'ideal');
```

- 量化模式：均匀量化，SQNR ≈ 6.02×bits + 1.76 dB
- 理想模式：浮点直通，不引入量化噪声
- AD支持指定满量程范围，超出时截断并warning

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\Waveform\src\Matlab');
run('test_waveform.m');
```

### 测试用例说明

**1. 脉冲成形（3项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 四种滤波器 | 滤波器长度 = span×sps+1 | RC/RRC/矩形/高斯四种类型均可正确生成 |
| 1.2 RRC零ISI | ISI/峰值 < 5% | RRC发+RRC收级联后在符号间隔采样点满足零ISI条件 |
| 1.3 成形+匹配回环 | 100符号BER=0 | 无噪声下脉冲成形→匹配滤波→下采样→判决完全正确 |

**2. 上下变频（3项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1 上下变频回环 | 相关系数 > 0.95 | 上变频→下变频后基带信号保持高相关性 |
| 2.2 通带实数 | `isreal(passband)` | 上变频输出必须是实数信号（物理可发射） |
| 2.3 BPSK端到端 | BER < 5% | 成形→上变频→下变频→匹配→判决全链路验证 |

**3. FSK波形（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 基本波形 | 长度、频率表正确 | 4-FSK波形参数验证 |
| 3.2 频率检测 | FFT检测20符号全部正确 | 每段波形的FFT主峰与预期频率一致 |

**4. DA/AD转换（4项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 理想直通 | 输出=输入 | ideal模式不做任何量化 |
| 4.2 SQNR递增 | 8/12/14/16bit SQNR递增 | 量化比特数越多SQNR越高 |
| 4.3 AD截断 | 超量程截断到满量程内 | 超出full_scale的采样被正确截断 |
| 4.4 DA→AD回环 | 相对误差 < 1% | 16bit DA后再16bit AD，误差极小 |

**5. Modulation联合测试（6项）**

基带回环 vs 全链路对比：

| | 基带回环 | 全链路 |
|--|---------|--------|
| 信号域 | 始终在复基带 | 基带→通带→基带 |
| 上下变频 | 无 | 有（cos/sin载波调制 + 正交混频 + LPF） |
| DA/AD | 无 | 有（引入量化噪声） |
| 损失来源 | 仅滤波器边缘截断 | + LPF带通损失 + 量化噪声 + 混频器泄漏 |
| BER预期 | 0（中间段） | 允许少量损失 |

| 测试 | 断言 | 说明 |
|------|------|------|
| 5.1 QPSK全链路 | BER < 15% | 映射→RRC→14bit DA→上变频→AD→下变频→匹配→判决，含DA/AD量化的完整通带回环 |
| 5.2 16QAM基带回环 | 中间段BER=0 | 映射→RRC成形→RRC匹配→AGC→判决，跳过首尾边缘符号验证算法正确性 |
| 5.3 MFSK+FSK波形回环 | 20符号BER=0 | MFSK映射→FSK波形生成→相关频率检测→MFSK解映射，验证FSK波形生成闭环 |
| 5.4 64QAM基带回环 | 中间段BER=0 | 同5.2，64QAM(6bit/符号)高阶调制验证，星座更密，对滤波精度要求更高 |
| 5.5 16QAM全链路 | BER < 15% | 映射→RRC→14bit DA→上变频→14bit AD→下变频→匹配→AGC→判决 |
| 5.6 64QAM全链路 | BER < 15% | 同上，16bit DA/AD + fs=96kHz + sps=16，更高精度保障64QAM的密集星座 |

**6. 异常输入（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 6.1 空输入拒绝 | 7个函数均报错 | 所有函数拒绝空输入 |
