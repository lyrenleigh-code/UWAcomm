# 脉冲成形与上下变频模块 (Waveform)

发射链路末端和接收链路前端的物理层波形处理，负责脉冲成形/匹配滤波、数字上下变频、FSK波形生成和DA/AD转换仿真。

## 对外接口

其他模块/端到端应调用的函数：

#### `pulse_shape` -- 脉冲成形（上采样+RC/RRC/矩形/高斯滤波）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `symbols` | 输入 | 1xN 复/实数组 | 符号序列 | 无 |
| `sps` | 输入 | 正整数 | 每符号采样数（上采样因子） | 8 |
| `filter_type` | 输入 | 字符串 | 'rc'(升余弦) / 'rrc'(根升余弦) / 'rect'(矩形) / 'gauss'(高斯) | 'rrc' |
| `rolloff` | 输入 | 实数 (0~1) | 滚降系数（rc/rrc用）；高斯脉冲时为BT积 | 0.35 |
| `span` | 输入 | 正整数 | 滤波器截断长度（符号数），总长 = span*sps+1 | 6 |
| `shaped_signal` | 输出 | 1xM 数组 | 成形后基带信号 | -- |
| `filter_coeff` | 输出 | 1xL 数组 | 滤波器系数（归一化为单位能量） | -- |
| `t_filter` | 输出 | 1xL 数组 | 滤波器时间轴（符号周期为单位） | -- |

#### `match_filter` -- 匹配滤波（成形滤波器时间反转共轭）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `signal` | 输入 | 1xM 复/实数组 | 接收基带信号 | 无 |
| `sps` | 输入 | 正整数 | 每符号采样数（须与发端一致） | 8 |
| `filter_type` | 输入 | 字符串 | 滤波器类型（须与发端一致） | 'rrc' |
| `rolloff` | 输入 | 实数 (0~1) | 滚降系数（须与发端一致） | 0.35 |
| `span` | 输入 | 正整数 | 滤波器截断长度（须与发端一致） | 6 |
| `filtered` | 输出 | 1xM 数组 | 滤波后信号（可下采样提取符号） | -- |
| `filter_coeff` | 输出 | 1xL 数组 | 匹配滤波器系数 | -- |

#### `upconvert` -- 数字上变频（复基带转通带实信号）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `baseband` | 输入 | 1xN 复数数组 | 复基带信号 | 无 |
| `fs` | 输入 | 正实数 | 采样率 (Hz)，须满足 fs >= 2*(fc + B/2) | 无 |
| `fc` | 输入 | 正实数 | 载波频率 (Hz) | 无 |
| `passband` | 输出 | 1xN 实数数组 | 通带实信号 | -- |
| `t` | 输出 | 1xN 数组 | 时间轴 (秒) | -- |

#### `downconvert` -- 数字下变频（通带转复基带，含LPF）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `passband` | 输入 | 1xN 实数数组 | 通带实信号 | 无 |
| `fs` | 输入 | 正实数 | 采样率 (Hz)，须与发端一致 | 无 |
| `fc` | 输入 | 正实数 | 载波频率 (Hz)，须与发端一致 | 无 |
| `lpf_bandwidth` | 输入 | 正实数 | 低通滤波器截止频率 (Hz) | fc/2 |
| `baseband` | 输出 | 1xN 复数数组 | 复基带信号 | -- |
| `t` | 输出 | 1xN 数组 | 时间轴 (秒) | -- |

#### `gen_fsk_waveform` -- FSK波形生成（频率索引转正弦波形，CPFSK）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `freq_indices` | 输入 | 1xL 数组 | 频率索引序列，取值 0~M-1 | 无 |
| `M` | 输入 | 正整数 | 频率数 | 无 |
| `f0` | 输入 | 正实数 | 最低频率 (Hz) | 1000 |
| `freq_spacing` | 输入 | 正实数 | 频率间隔 (Hz)，第k个频率 = f0 + k*spacing | 100 |
| `fs` | 输入 | 正实数 | 采样率 (Hz) | 8000 |
| `sym_duration` | 输入 | 正实数 | 每符号持续时间 (秒) | 0.01 |
| `waveform` | 输出 | 1xN 实数数组 | FSK时域波形 | -- |
| `t` | 输出 | 1xN 数组 | 时间轴 (秒) | -- |
| `freqs` | 输出 | 1xM 数组 | M个频率值 (Hz) | -- |

#### `da_convert` -- DA转换仿真（量化/理想模式）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `signal` | 输入 | 1xN 实数数组 | 输入信号 | 无 |
| `num_bits` | 输入 | 正整数 | DAC量化比特数 | 16 |
| `mode` | 输入 | 字符串 | 'quantize'(均匀量化) / 'ideal'(直通) | 'quantize' |
| `output` | 输出 | 1xN 实数数组 | 量化后信号 | -- |
| `scale_factor` | 输出 | 正实数 | 归一化缩放因子（用于AD还原） | -- |

#### `ad_convert` -- AD转换仿真（量化/理想模式，含截断）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `signal` | 输入 | 1xN 实数数组 | 输入模拟信号 | 无 |
| `num_bits` | 输入 | 正整数 | ADC量化比特数 | 16 |
| `mode` | 输入 | 字符串 | 'quantize'(均匀量化) / 'ideal'(直通) | 'quantize' |
| `full_scale` | 输入 | 正实数 | ADC满量程范围，超出截断 | 信号峰值*1.1 |
| `output` | 输出 | 1xN 实数数组 | 量化后数字信号 | -- |
| `scale_factor` | 输出 | 正实数 | 满量程值 | -- |

## 内部函数（不建议外部直接调用）

#### `plot_eye_diagram` -- 眼图绘制

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `signal` | 输入 | 1xN 复/实数组 | 脉冲成形后基带信号 | 无 |
| `sps` | 输入 | 正整数 | 每符号采样数 | 无 |
| `num_periods` | 输入 | 正整数 | 叠加的符号周期数（显示宽度） | 2 |
| `title_str` | 输入 | 字符串 | 图标题 | 'Eye Diagram' |

绘制双子图：左侧实部(I分量)眼图，右侧虚部(Q分量)眼图（实数信号时显示包络）。最多叠加200条轨迹，每条偏移1个符号周期。

#### `test_waveform.m` -- 单元测试（V1.1, 19项）

覆盖：脉冲成形、上下变频、FSK波形、DA/AD转换、与Modulation模块联合测试、异常输入 + 可视化。

#### 各函数内部辅助函数（internal）

- `pulse_shape` 内部: `rc_filter` (升余弦滤波器系数计算), `rrc_filter` (根升余弦滤波器系数计算)
- `downconvert` 内部: `lpf_filter` (FIR低通滤波器，自适应阶数，用于去除2fc分量)

## 核心算法技术描述

### 1. 脉冲成形滤波（pulse_shape）

**原理**: 将离散符号序列上采样（插零）后通过脉冲成形滤波器，控制信号带宽和码间干扰（ISI）。

#### 1a. 升余弦滤波器（RC）

**关键公式**:
$$h_{\text{RC}}(t) = \text{sinc}\!\left(\frac{t}{T}\right) \cdot \frac{\cos\!\left(\frac{\pi \beta t}{T}\right)}{1 - \left(\frac{2\beta t}{T}\right)^2}$$

其中: $T$ = 符号周期，$\beta$ = 滚降系数 (0~1)，带宽 $= (1+\beta)/(2T)$。

**特性**: 在整数符号间隔处满足Nyquist零ISI条件 h(nT)=0 (n!=0)。

#### 1b. 根升余弦滤波器（RRC）

**关键公式**:
$$h_{\text{RRC}}(0) = 1 - \beta + \frac{4\beta}{\pi}$$

$$h_{\text{RRC}}\!\left(\pm\frac{1}{4\beta}\right) = \frac{\beta}{\sqrt{2}} \left[\left(1+\frac{2}{\pi}\right)\sin\!\left(\frac{\pi}{4\beta}\right) + \left(1-\frac{2}{\pi}\right)\cos\!\left(\frac{\pi}{4\beta}\right)\right]$$

$$h_{\text{RRC}}(t) = \frac{\sin\!\left(\pi t(1-\beta)\right) + 4\beta t \cos\!\left(\pi t(1+\beta)\right)}{\pi t \left(1 - (4\beta t)^2\right)}$$

**关键性质**: RRC发 + RRC收（匹配滤波）= RC，级联后满足零ISI条件。单独的RRC不满足零ISI。

#### 1c. 矩形脉冲（rect）

$$h(t) = \begin{cases} 1, & |t| \le T/2 \\ 0, & \text{otherwise} \end{cases}$$

最简单的零阶保持成形，带宽无限大（sinc频谱），ISI最差。

#### 1d. 高斯脉冲（gauss）

$$h(t) = \sqrt{2\pi}\;\alpha \cdot \exp\!\left(-2(\pi \alpha t)^2\right)$$

$$\alpha = \frac{\sqrt{\ln 2 / 2}}{BT}$$

**参数选择**: BT积越小带宽越窄但ISI越大。GMSK用BT=0.3，典型语音FSK用BT=0.5。

**参数选择规则（通用）**:
- `rolloff`: 0.2~0.5，值越大带宽越宽但ISI抑制越好，水声典型取0.25~0.35
- `span`: 通常4~8，值越大截断误差越小但延迟越大
- `sps`: 通常4~16，须满足 sps >= 2*(1+rolloff) 避免混叠

**适用条件**: 所有线性调制体制（QAM/PSK/PAM）。FSK等频率调制不使用脉冲成形。

### 2. 匹配滤波（match_filter）

**原理**: 接收端使用发端脉冲成形滤波器的时间反转共轭作为匹配滤波器，最大化输出SNR。

**关键公式**:
$$h_{\text{MF}}(t) = h_{\text{TX}}^*(-t)$$

对于实数对称滤波器（RC/RRC/rect/gauss）: $h_{\text{MF}} = h_{\text{TX}}$（自身即为匹配）。

**RRC发 + RRC收 = RC:**

$$h_{\text{RC}}(t) = (h_{\text{RRC}} * h_{\text{RRC}})(t) \quad \text{(卷积)}$$

**最优采样点**: 匹配滤波后在 `delay + n*sps` 处下采样，`delay = span*sps/2`（两次'same'卷积时自动对齐）。

**适用条件**: 假设信道为AWGN或已均衡。多径信道需先均衡再匹配滤波，或使用自适应均衡替代。

### 3. 数字上变频（upconvert）

**原理**: 将复基带信号调制到通带载波频率，输出实信号。

**关键公式**:
$$s(t) = \mathrm{Re}\!\left\{x(t) \cdot e^{j 2\pi f_c t}\right\} = I(t)\cos(2\pi f_c t) - Q(t)\sin(2\pi f_c t)$$

其中: $I(t) = \mathrm{Re}\{x(t)\}$, $Q(t) = \mathrm{Im}\{x(t)\}$。

**参数选择**: 采样率须满足Nyquist条件 fs >= 2*(fc + B/2)，B为基带信号带宽。水声典型: fs=48000Hz, fc=8000~16000Hz。

**适用条件**: 仿真级，不涉及硬件DAC非线性。载波频率接近Nyquist时输出频谱可能折叠。

### 4. 数字下变频（downconvert）

**原理**: 通带信号与本振正交混频后低通滤波，恢复复基带。

**关键公式**:
$$I(t) = \text{LPF}\!\left\{2 \cdot s(t) \cdot \cos(2\pi f_c t)\right\}$$

$$Q(t) = \text{LPF}\!\left\{-2 \cdot s(t) \cdot \sin(2\pi f_c t)\right\}$$

$$x(t) = I(t) + j\,Q(t)$$

乘以2补偿正交混频的幅度衰减。LPF为自适应阶数FIR滤波器（阶数 = min(64, floor(N/4)*2)），截止频率默认fc/2。

**参数选择**: lpf_bandwidth应大于基带信号带宽但远小于2fc，典型取 fs/sps 或 fc/2。

**适用条件**: 仿真级。实际系统需考虑IQ不平衡、DC偏移等。

### 5. FSK波形生成（gen_fsk_waveform）

**原理**: 将频率索引映射为对应频率的正弦波段，相位在符号边界连续（CPFSK）。

**关键公式**:
$$f_k = f_0 + k \cdot \Delta f, \quad k = 0, \ldots, M-1$$

$$\text{waveform}_s(t) = \cos(2\pi f_k t + \varphi_s)$$

$$\varphi_{s+1} = \varphi_s + 2\pi f_k T_{\text{sym}} \pmod{2\pi} \quad \text{(相位连续)}$$

$$\text{正交条件: } \Delta f \ge 1 / T_{\text{sym}}$$

**参数选择**: spacing=1/dur为最小正交间隔（最大频谱效率）。spacing越大频率隔离越好但带宽越大。最高频率须满足 f0+(M-1)*spacing < fs/2。

**适用条件**: M-FSK/CPFSK调制的波形生成。需配合模块05的MFSK映射使用。

### 6. DA/AD转换仿真

#### 6a. DA转换（da_convert）

**原理**: 将浮点信号均匀量化为有限精度，模拟DAC行为。

**关键公式**:
$$L = 2^{N_{\text{bits}}}, \quad \Delta = \frac{2 \cdot \text{peak}}{L} \quad \text{(自动适配信号幅度)}$$

$$q(n) = \text{round}\!\left(\frac{x(n)}{\Delta}\right) \cdot \Delta$$

$$\sigma_q^2 = \frac{\Delta^2}{12}, \quad \text{SQNR} = 6.02 \cdot N_{\text{bits}} + 1.76 \;\text{dB} \quad \text{(满量程正弦输入)}$$

#### 6b. AD转换（ad_convert）

**原理**: 模拟ADC行为，含满量程截断和均匀量化。

**关键公式**:
$$x_{\text{clip}}(n) = \max\!\left(\min\!\left(x(n),\; \text{full\_scale}\right),\; -\text{full\_scale}\right)$$

量化同DA转换。$\text{ENOB} \approx N_{\text{bits}} - 1$（考虑符号位）。

**参数选择**: full_scale应略大于信号峰值（默认+10%余量），防止截断失真。num_bits水声典型14~16bit。复数信号需分别对I/Q分量调用。

**适用条件**: 仿真级均匀量化模型。不含非线性失真、时钟抖动、热噪声等实际ADC/DAC非理想因素。

## 使用示例

```matlab
% 发端：脉冲成形 -> DA -> 上变频
[shaped, h, t] = pulse_shape(symbols, 8, 'rrc', 0.35, 6);
[da_out, scale] = da_convert(real(shaped), 14, 'quantize');
[passband, t] = upconvert(shaped, 48000, 12000);

% 收端：下变频 -> 匹配滤波 -> 下采样
[baseband, t] = downconvert(passband, 48000, 12000, 6000);
[filtered, ~] = match_filter(baseband, 8, 'rrc', 0.35, 6);
sampled = filtered(25:8:end);  % delay = span*sps/2 = 24

% FSK波形生成（配合模块05 MFSK映射）
[freq_idx, ~, ~] = mfsk_modulate(bits, 4, 'gray');
[waveform, t, freqs] = gen_fsk_waveform(freq_idx, 4, 1000, 200, 8000, 0.01);

% DA+AD回环验证
[da_out, sf] = da_convert(signal, 16, 'quantize');
[ad_out, ~] = ad_convert(da_out, 16, 'quantize', sf*1.1);

% QPSK全链路（含DA/AD）
[symbols, ~, ~] = qam_modulate(bits, 4, 'gray');
[shaped, ~, ~] = pulse_shape(symbols, 8, 'rrc', 0.35, 6);
[da_I, ~] = da_convert(real(shaped), 14, 'quantize');
[da_Q, ~] = da_convert(imag(shaped), 14, 'quantize');
[passband, ~] = upconvert(da_I + 1j*da_Q, 48000, 12000);
```

## 依赖关系

- 无外部模块依赖（独立的物理层波形处理模块）
- 被模块08 (Sync) 的 `timing_fine` 测试依赖 `pulse_shape`/`match_filter`
- 被模块13 (SourceCode) 端到端测试广泛调用
- 联合测试依赖模块04 (Modulation) 的 `qam_modulate`/`qam_demodulate` 和模块05 (SpreadSpectrum) 的 `mfsk_modulate`/`mfsk_demodulate`

## 测试覆盖 (test_waveform.m V1.1, 19项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|---------|---------|------|
| 1.1 | 四种滤波器生成 | `length(h) == span*sps+1`（四种类型全部通过） | rc/rrc/rect/gauss，滤波器长度=49 |
| 1.2 | RRC+RRC=RC零ISI | `max_isi/peak_val < 0.05` | 冲激响应经RRC成形+匹配后，整数符号间隔ISI<5% |
| 1.3 | 成形+匹配滤波回环 | `best_ber == 0` | 100个BPSK符号，无噪声回环BER=0 |
| 2.1 | 上下变频回环 | `corr_coeff > 0.95` | fs=48kHz, fc=12kHz，归一化相关系数>0.95 |
| 2.2 | 通带信号为实数 | `isreal(passband)` | 上变频输出应为纯实数 |
| 2.3 | BPSK端到端 | `best_ber < 0.1` | 50符号，成形+上变频+下变频+匹配+判决，BER<10% |
| 3.1 | 4-FSK波形生成 | `length(waveform) == 4*samples_per_sym`, `length(freqs) == M`, `freqs(1) == f0`, `freqs(end) == f0+(M-1)*spacing` | 波形长度/频率表/频率值全部正确 |
| 3.2 | FSK频率检测 | `ber == 0` | 20符号逐段FFT频率检测，全部正确 |
| 4.1 | 理想DA/AD直通 | `isequal(da_out, signal)`, `isequal(ad_out, signal)` | ideal模式输出与输入完全一致 |
| 4.2 | DA量化SQNR | `all(diff(sqnr_list) > 0)` | 8/12/14/16bit SQNR递增（每bit约6dB） |
| 4.3 | AD截断 | `all(abs(ad_out) <= 1.0)` | 满量程+-1，超量程采样正确截断 |
| 4.4 | DA+AD回环 | `rel_err < 0.01` | 16bit DA->AD，最大相对误差<1% |
| 5.1 | QPSK全链路 | `best_ber < 0.15` | 200符号，14bit DA/AD，映射+成形+上变频+AD+下变频+匹配+判决 |
| 5.2 | 16QAM基带回环 | `best_ber == 0` | 300符号取中间段（跳过边缘），纯基带成形+匹配，BER=0 |
| 5.3 | MFSK+FSK波形回环 | `ber == 0` | 4-FSK，20符号，MFSK映射+波形生成+频率检测+解映射，BER=0 |
| 5.4 | 64QAM基带回环 | `best_ber == 0` | 400符号取中间段，纯基带高阶调制回环，BER=0 |
| 5.5 | 16QAM全链路 | `best_ber < 0.15` | 300符号中间段，14bit DA/AD，含上下变频，BER<15% |
| 5.6 | 64QAM全链路 | `best_ber < 0.15` | 400符号中间段，16bit DA/AD，fs=96kHz sps=16高精度，BER<15% |
| 6.1 | 空输入拒绝 | `caught == 7`（7个函数全部报错） | pulse_shape/match_filter/upconvert/downconvert/gen_fsk/da/ad |

## 可视化说明

测试生成以下figure（V1.1新增，在独立try/catch中，不影响测试计数）：

| Figure | 名称 | 内容 |
|--------|------|------|
| Figure 1 | 脉冲成形 | 左: 四种滤波器(RC/RRC/Rect/Gauss)冲激响应对比；中: RRC+RRC=RC零ISI验证（标注ISI采样点和峰值）；右: 眼图（sps=4, 叠加80条轨迹） |
| Figure 2 | 上下变频频谱 | 左: 基带信号频谱；中: 通带信号频谱（标注fc=12kHz）；右: 下变频恢复基带频谱 |
| Figure 3 | DA/AD与星座图 | 左: DA量化SQNR柱状图（8/12/14/16bit实测 vs 理论6.02N+1.76线）；右: QPSK全链路星座图（灰色RX散点 + 红色TX理想星座） |
