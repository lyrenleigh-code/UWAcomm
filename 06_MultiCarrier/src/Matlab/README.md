# 多载波/多域变换模块 (MultiCarrier)

将频域/DD域符号变换为时域发射信号，覆盖OFDM(CP/ZP)、SC-FDE和OTFS(DFT/Zak)三种方案，含导频插入提取和PAPR计算/抑制。

## 对外接口

其他模块/端到端应调用的函数：

### ofdm_modulate — OFDM调制

频域符号经IFFT变换+CP/ZP插入生成时域信号。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| freq_symbols | 输入 | 1xM 数组 | 频域数据符号，M须为N的整数倍，每N个组成一个OFDM符号 | 必填 |
| N | 输入 | 正整数 | FFT/IFFT点数（子载波数），建议2的幂 | 256 |
| cp_len | 输入 | 非负整数 | CP/ZP长度（采样点数） | N/4 |
| cp_type | 输入 | 字符串 | 前缀类型：'cp'循环前缀 或 'zp'补零 | 'cp' |
| signal | 输出 | 1xL 数组 | 时域OFDM信号 | — |
| params_out | 输出 | 结构体 | 参数（.N, .cp_len, .cp_type, .num_symbols, .symbol_len） | — |

### ofdm_demodulate — OFDM解调

去CP/ZP + FFT恢复频域符号。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| signal | 输入 | 1xL 数组 | 时域OFDM信号 | 必填 |
| N | 输入 | 正整数 | FFT点数，须与调制端一致 | 必填 |
| cp_len | 输入 | 非负整数 | CP/ZP长度，须与调制端一致 | 必填 |
| cp_type | 输入 | 字符串 | 前缀类型，须与调制端一致 | 'cp' |
| freq_symbols | 输出 | 1xM 数组 | 恢复的频域符号 | — |

### ofdm_pilot_insert — 频域导频插入

支持梳状、块状、离散和自定义导频模式。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| data_symbols | 输入 | 1xM 数组 | 数据符号 | 必填 |
| N | 输入 | 正整数 | 子载波总数（FFT点数） | 必填 |
| pilot_pattern | 输入 | 字符串或1xK数组 | 导频模式：'comb_4'(每4插1)/'comb_8'(每8插1)/'scattered_4'(离散间隔4每符号偏移1)/'scattered_8'(离散间隔8每符号偏移2)/'block'(首符号全导频)/自定义索引数组 | 'comb_4' |
| pilot_values | 输入 | 标量或1xK数组 | 导频符号值 | +1 |
| symbols_with_pilot | 输出 | 1xL 数组 | 含导频的频域符号，L为N的整数倍 | — |
| pilot_indices | 输出 | 1xK 数组 | 导频子载波索引（1-based） | — |
| data_indices | 输出 | 1xJ 数组 | 数据子载波索引 | — |

### ofdm_pilot_extract — 频域导频提取

分离导频和数据子载波。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| freq_symbols | 输入 | 1xL 数组 | 含导频的频域符号，L为N的整数倍 | 必填 |
| N | 输入 | 正整数 | 子载波总数 | 必填 |
| pilot_pattern | 输入 | 字符串或数组 | 导频模式，须与插入端一致 | 'comb_4' |
| data_symbols | 输出 | 1xM 数组 | 数据子载波符号 | — |
| pilot_rx | 输出 | num_symbols x num_pilots 矩阵 | 接收到的导频值 | — |
| pilot_indices | 输出 | 1xK 数组 | 导频子载波索引 | — |
| data_indices | 输出 | 1xJ 数组 | 数据子载波索引 | — |

### scfde_add_cp — SC-FDE分块CP插入

将数据分块，每块添加循环前缀。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| data_symbols | 输入 | 1xN 数组 | 数据符号序列 | 必填 |
| block_size | 输入 | 正整数 | 每块数据长度，>=2 | 256 |
| cp_len | 输入 | 非负整数 | CP长度 | block_size/4 |
| signal | 输出 | 1xL 数组 | 加CP后的时域信号 | — |
| params_out | 输出 | 结构体 | 参数（.block_size, .cp_len, .num_blocks, .pad_len） | — |

### scfde_remove_cp — SC-FDE去CP + 分块FFT

接收端前处理：去CP后每块做FFT。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| signal | 输入 | 1xL 数组 | 接收信号 | 必填 |
| block_size | 输入 | 正整数 | 每块数据长度，须与发端一致 | 必填 |
| cp_len | 输入 | 非负整数 | CP长度，须与发端一致 | 必填 |
| freq_blocks | 输出 | num_blocks x block_size 复数矩阵 | 频域块矩阵（每行=一个块的FFT结果） | — |
| time_blocks | 输出 | num_blocks x block_size 矩阵 | 去CP后的时域块矩阵 | — |

### otfs_modulate — OTFS调制

DD域符号经ISFFT+Heisenberg变换生成时域信号。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| dd_symbols | 输入 | NxM 矩阵 或 1x(N*M) 向量 | DD域数据符号，N=多普勒维度，M=时延维度 | 必填 |
| N | 输入 | 正整数 | 多普勒格点数（OFDM符号数） | 8 |
| M | 输入 | 正整数 | 时延格点数（子载波数） | 32 |
| cp_len | 输入 | 非负整数 | 整帧CP长度（采样点数） | M/4 |
| method | 输入 | 字符串 | 实现方式：'dft'标准DFT 或 'zak'Zak域 | 'dft' |
| signal | 输出 | 1xL 数组 | 时域OTFS帧信号（含整帧CP） | — |
| params_out | 输出 | 结构体 | 参数（.N, .M, .cp_len, .method, .X_tf, .total_len） | — |

### otfs_demodulate — OTFS解调

去整帧CP + Wigner变换 + SFFT恢复DD域符号。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| signal | 输入 | 1xL 数组 | 接收时域信号（含整帧CP） | 必填 |
| N | 输入 | 正整数 | 多普勒格点数，须与调制端一致 | 必填 |
| M | 输入 | 正整数 | 时延格点数，须与调制端一致 | 必填 |
| cp_len | 输入 | 非负整数 | 整帧CP长度，须与调制端一致 | 必填 |
| method | 输入 | 字符串 | 实现方式，须与调制端一致 | 'dft' |
| dd_symbols | 输出 | NxM 复数矩阵 | DD域符号 | — |
| Y_tf | 输出 | NxM 矩阵 | 时频域信号（Wigner变换输出） | — |

### otfs_pilot_embed — DD域导频嵌入

支持5种导频方案：单脉冲、多脉冲、叠加导频、序列导频、自适应保护区。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| data_symbols | 输入 | 1xK 向量 | 数据符号 | 必填 |
| N | 输入 | 正整数 | 多普勒格点数 | 必填 |
| M | 输入 | 正整数 | 时延格点数 | 必填 |
| pilot_config | 输入 | 结构体 | 导频配置（详见下方） | struct() |
| dd_frame | 输出 | NxM 矩阵 | DD域帧 | — |
| pilot_info | 输出 | 结构体 | 导频信息（.mode, .positions, .values, .guard_mask等） | — |
| guard_mask | 输出 | NxM 逻辑矩阵 | 保护区掩模（1=保护/导频，0=数据） | — |
| data_indices | 输出 | 1xK 数组 | 数据格点线性索引 | — |

**pilot_config 结构体字段**：

| 字段 | 含义 | 默认值 | 适用模式 |
|------|------|--------|----------|
| .mode | 导频模式 | 'impulse' | 全部 |
| .pilot_value | 导频幅度 | 1 | 全部 |
| .guard_k | 多普勒保护格点数 | 2 | impulse/multi_pulse/sequence/adaptive |
| .guard_l | 时延保护格点数 | 2 | impulse/multi_pulse/sequence/adaptive |
| .pilot_k | 导频多普勒索引 | ceil(N/2) | impulse/sequence/adaptive |
| .pilot_l | 导频时延索引 | ceil(M/2) | impulse/sequence/adaptive |
| .pilot_positions | Px2矩阵，每行[k,l] | 四象限各一个 | multi_pulse |
| .pilot_power | 导频功率缩放因子 | 0.2 | superimposed |
| .seq_type | 序列类型：'zc'或'random' | 'zc' | sequence |
| .seq_root | ZC序列根索引 | 1 | sequence |
| .max_delay_spread | 最大时延扩展（格点数） | 3 | adaptive |
| .max_doppler_spread | 最大多普勒扩展（格点数） | 2 | adaptive |

### otfs_get_data_indices — DD域数据格点索引

获取OTFS DD域数据格点索引（去除导频和保护区）。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| N | 输入 | 正整数 | 多普勒格点数 | 必填 |
| M | 输入 | 正整数 | 时延格点数 | 必填 |
| pilot_config | 输入 | 结构体 | 导频配置（须与otfs_pilot_embed一致） | struct() |
| data_indices | 输出 | 1xK 数组 | 数据格点线性索引 | — |
| guard_mask | 输出 | NxM 逻辑矩阵 | 保护区掩模 | — |
| num_data | 输出 | 正整数 | 可用数据格点总数 | — |

### papr_calculate — 峰均功率比计算

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| signal | 输入 | 1xN 数组 | 时域信号（复数/实数） | 必填 |
| papr_db | 输出 | 实数 | PAPR值 (dB) | — |
| peak_power | 输出 | 实数 | 峰值功率 | — |
| avg_power | 输出 | 实数 | 平均功率 | — |

### papr_clip — PAPR抑制

限幅或幅度缩放降低峰均功率比。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| signal | 输入 | 1xN 复数数组 | 时域OFDM/OTFS信号 | 必填 |
| target_papr_db | 输入 | 实数 | 目标PAPR上限 (dB) | 6 |
| method | 输入 | 字符串 | 抑制方法：'clip'硬限幅/'clip_filter'限幅+滤波/'scale'幅度缩放 | 'clip' |
| clipped | 输出 | 1xN 数组 | 限幅后信号 | — |
| clip_ratio | 输出 | 实数 | 被限幅样本比例 (0~1) | — |

## 内部函数（不建议外部调用）

### plot_ofdm_spectrum — OFDM信号可视化

绘制时域波形、瞬时功率、功率谱密度和PAPR CCDF。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| signal | 输入 | 1xN 数组 | 时域OFDM信号 | 必填 |
| fs | 输入 | 实数 | 采样率 (Hz) | 1 |
| title_str | 输入 | 字符串 | 图标题 | 'OFDM Signal' |

### plot_otfs_dd_grid — OTFS DD域格点可视化

绘制DD域幅度热图和相位热图，可标注导频位置。

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| dd_frame | 输入 | NxM 矩阵 | DD域帧数据（复数矩阵） | 必填 |
| title_str | 输入 | 字符串 | 图标题 | 'OTFS DD Grid' |
| pilot_pos | 输入 | [k, l] 数组 | 导频位置，用于标注 | [] |

### test_multicarrier — 单元测试

覆盖OFDM(CP/ZP)、导频、SC-FDE、OTFS(DFT/Zak)、PAPR和异常输入（共18项测试）。

### 各.m文件内部辅助函数

- `otfs_modulate.m`: `otfs_mod_dft`(标准DFT方法), `otfs_mod_zak`(Zak域方法)
- `otfs_pilot_embed.m`: `embed_impulse`, `embed_multi_pulse`, `embed_superimposed`, `embed_sequence`, `embed_adaptive`, `build_guard_mask`, `pad_data`
- `otfs_get_data_indices.m`: `build_guard`

## 核心算法技术描述

### 1. OFDM调制/解调

**算法原理**：将N个频域符号通过N点IFFT变换为时域信号，添加循环前缀(CP)或补零(ZP)以抵抗多径信道的符号间干扰(ISI)。

**关键公式**：

$$
x(n) = \frac{1}{\sqrt{N}} \sum_{k=0}^{N-1} X(k) \cdot e^{j 2\pi k n / N}, \quad n=0,\ldots,N-1
$$

CP插入: $x_{cp} = [x(N-cp\_len+1:N), x(1:N)]$

ZP插入: $x_{zp} = [x(1:N), \text{zeros}(1, cp\_len)]$

解调(FFT):
- CP模式: 丢弃前cp\_len样本 -> $X = \text{fft}(x, N) / \sqrt{N}$
- ZP模式: overlap-add(尾部cp\_len叠加到头部) -> $X = \text{fft}(x, N) / \sqrt{N}$

**参数选择**：
- N取2的幂以利用FFT效率。水声典型值: N=64~1024
- CP长度应大于信道最大时延扩展: `cp_len >= tau_max * fs`
- 通常 cp_len = N/4（25%开销）

**适用条件**：CP长度须大于信道最大时延扩展，否则出现ISI。对多普勒扩展敏感（子载波间干扰ICI）。ZP-OFDM比CP-OFDM更适合深衰落信道（保证可逆性），但接收端需overlap-add处理。

### 2. OFDM导频插入/提取

**算法原理**：在频域OFDM符号中插入已知导频符号，用于接收端信道估计和均衡。

**导频模式**：

**梳状(comb\_K):** 每K个子载波插1个导频，所有OFDM符号导频位置相同

$$
\text{pilot\_indices} = 1:K:N
$$

适合时变信道（每符号都有导频可跟踪信道变化）

**离散(scattered\_K):** 每K个子载波插1个导频，每个OFDM符号偏移S位

$$
\text{pilot\_indices}_s = \bmod(\text{base\_indices} - 1 + (s-1) \cdot S, N) + 1
$$

适合时频双选信道（导频覆盖全时频域）

**块状(block):** 首个OFDM符号全部为导频，适合频选但时不变信道

**自定义:** 用户指定导频子载波索引数组

**频谱效率**：
- comb_4: 数据子载波占比 = (N - N/4) / N = 75%
- comb_8: 数据子载波占比 = 87.5%

**适用条件**：导频位置需在收发端一致。梳状导频适合慢变信道，离散导频适合快变信道，块状导频适合频选信道。

### 3. SC-FDE分块CP

**算法原理**：将数据符号序列分块，每块添加循环前缀。接收端去CP后对每块做FFT，在频域进行MMSE均衡。

**关键公式**：

$$\text{发端: } [\text{CP} \mid \text{data\_block}], \quad \text{CP} = \text{data\_block}(\text{end}-\text{cp\_len}+1:\text{end})$$

$$\text{收端: 去CP} \to \text{FFT} \to Y(k) = H(k) X(k) + W(k)$$

$$\hat{X}(k) = \frac{H^*(k)}{|H(k)|^2 + \sigma^2} \cdot Y(k)$$

**参数选择**：
- block_size: 与OFDM的N对应，通常取2的幂
- cp_len: 同OFDM，须大于信道最大时延扩展

**适用条件**：PAPR低于OFDM（单载波特性），适合功放非线性敏感的水声场景。需频域均衡（后续模块实现）。不足一块时自动补零。

### 4. OTFS调制/解调

**算法原理**：在时延-多普勒(DD)域传输数据，通过ISFFT+Heisenberg变换映射到时域。DD域的稀疏信道表示使OTFS在高多普勒场景下优于OFDM。

**DFT方法关键公式**：

**ISFFT (DD -> TF):**

$$X_{\text{tf}}[n,m] = \frac{1}{\sqrt{N}} \sum_{k=0}^{N-1} x_{\text{dd}}[k,m] \cdot e^{j 2\pi n k / N}$$

（实现: 对每列做N点IFFT * sqrt(N)）

**Heisenberg变换 (TF -> 时域):**

$$s_n = \text{IFFT}(X_{\text{tf}}[n,:]) \cdot \sqrt{M} \quad \text{(M点IFFT)}$$

$$s = [s_1, s_2, \ldots, s_N] \quad \text{(拼接)}$$

**整帧CP:** $\text{signal} = [s(\text{end}-\text{cp\_len}+1:\text{end}),\; s]$

**解调逆过程:** 去CP -> Wigner变换(行FFT/$\sqrt{M}$) -> SFFT(列FFT/$\sqrt{N}$) -> DD域符号

**Zak域方法**：

$$\text{调制: } S = \text{ifft2}(X_{\text{dd}}) \cdot \sqrt{NM} \quad \text{(二维IFFT一步完成)}$$

$$\text{解调: } X_{\text{dd}} = \text{fft2}(R) / \sqrt{NM} \quad \text{(二维FFT一步完成)}$$

DFT方法和Zak方法数学等价，输出一致。

**参数选择**：
- N: 多普勒分辨率相关，N越大分辨率越高
- M: 时延分辨率相关，M越大分辨率越高
- cp_len: 整帧CP须覆盖最大时延扩展
- 总帧长 = N*M + cp_len

**适用条件**：高多普勒场景（水声通信、高速移动）优于OFDM。DD域信道表示稀疏（少量路径参数化），有利于信道估计。局限：帧结构固定，时延大；低多普勒场景下与OFDM性能相当但复杂度更高。

### 5. OTFS DD域导频方案

**5种模式对比**：

| 模式 | 原理 | 频谱效率 | 估计精度 | 复杂度 |
|------|------|----------|----------|--------|
| impulse | 单点大功率脉冲+矩形保护区 | 低 | 高(SNR足够时) | 低 |
| multi_pulse | 多个位置放导频脉冲 | 较低 | 更高(多观测点抗噪声) | 低 |
| superimposed | 导频叠加在数据上(功率缩放) | 最高(100%) | 需迭代消除数据干扰 | 高 |
| sequence | ZC序列替代脉冲 | 中 | 高(低PAPR) | 中 |
| adaptive | 保护区随信道扩展自适应调整 | 自适应 | 高 | 中 |

**impulse模式关键公式**：

$$\text{dd\_frame}(\text{pilot\_k},\; \text{pilot\_l}) = \text{pilot\_value}$$

$$\text{保护区: } (2 \cdot \text{guard\_k} + 1) \times (2 \cdot \text{guard\_l} + 1) \text{ 矩形区域（周期边界）}$$

$$\text{可用数据格点: } N \times M - \text{保护区面积}$$

**adaptive模式**：

$$\text{guard\_l\_adapt} = \text{max\_delay\_spread} + 1$$

$$\text{guard\_k\_adapt} = \text{max\_doppler\_spread} + 1$$

大扩展信道 -> 大保护区 -> 少数据格点；小扩展信道 -> 小保护区 -> 多数据格点。

**superimposed模式**：

$$\text{dd\_frame} = \text{data\_matrix} + \text{pilot\_pattern}$$

$$\text{pilot\_pattern} = \text{BPSK}(\pm 1) \cdot \sqrt{\text{pilot\_power}} \quad \text{(seed=0固定)}$$

收端需迭代: 先粗估信道 -> 消除数据干扰 -> 精估信道。

### 6. PAPR计算与抑制

**算法原理**：PAPR衡量信号峰值功率与平均功率之比，OFDM因多子载波叠加PAPR较高（8~13dB），影响功放效率。

**关键公式**：

$$\text{PAPR} = \frac{\max |s(t)|^2}{\mathrm{mean}(|s(t)|^2)}, \quad \text{PAPR}_{\text{dB}} = 10 \log_{10}(\text{PAPR})$$

**硬限幅:**

$$\text{threshold} = \sqrt{P_{\text{avg}} \cdot 10^{\text{target\_papr}/10}}$$

$$\text{clipped}(n) = \begin{cases} \text{threshold} \cdot e^{j \angle s(n)}, & |s(n)| > \text{threshold} \\ s(n), & \text{otherwise} \end{cases}$$

**限幅+滤波:** 硬限幅后3阶移动平均滤波减少带外辐射

**幅度缩放:** $\text{scale} = \min(\text{threshold} / |s(n)|,\; 1)$; $\text{clipped} = s \cdot \text{scale}$

**参数选择**：
- target_papr_db: 通常6~8dB，与功放特性相关
- 限幅比例越大，PAPR降低越多但BER性能损失越大

**适用条件**：硬限幅简单有效但引入非线性失真；clip_filter减少带外辐射但信号略有失真；scale保持波形形状但效果有限。PAPR抑制存在BER与PAPR的折中。

## 使用示例

```matlab
%% CP-OFDM调制/解调
symbols = qam_modulate(bits, 16, 'gray');     % 来自模块04
[signal, params] = ofdm_modulate(symbols, 256, 64, 'cp');
freq_out = ofdm_demodulate(signal, 256, 64, 'cp');

%% 导频插入/提取
[with_pilot, p_idx, d_idx] = ofdm_pilot_insert(data, 64, 'comb_4', 1+1j);
[data_rx, pilot_rx, ~, ~] = ofdm_pilot_extract(with_pilot, 64, 'comb_4');

%% SC-FDE发端
[signal, params] = scfde_add_cp(data, 128, 32);
[freq_blocks, time_blocks] = scfde_remove_cp(signal, 128, 32);

%% OTFS调制/解调（DFT方法）
dd_data = randn(8, 32) + 1j*randn(8, 32);
[signal, params] = otfs_modulate(dd_data, 8, 32, 8, 'dft');
[dd_out, Y_tf] = otfs_demodulate(signal, 8, 32, 8, 'dft');

%% OTFS导频嵌入
cfg = struct('mode','impulse','pilot_k',4,'pilot_l',16,...
             'pilot_value',sqrt(8*32),'guard_k',2,'guard_l',3);
[data_idx, ~, num_data] = otfs_get_data_indices(8, 32, cfg);
data = randn(1, num_data) + 1j*randn(1, num_data);
[dd_frame, pilot_info, guard_mask, ~] = otfs_pilot_embed(data, 8, 32, cfg);

%% PAPR计算与抑制
[papr_db, ~, ~] = papr_calculate(signal);
[clipped, ratio] = papr_clip(signal, 6, 'clip');
```

## 依赖关系

- 无外部模块依赖
- 上游：模块04（调制）或模块05（扩频）输出的符号
- 下游：模块07（信道/导频插入）或直接输出时域信号供信道传输

## 测试覆盖 (test_multicarrier.m V1.0, 18项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|----------|----------|------|
| 1.1 | CP-OFDM回环 | `max(abs(recovered-data))<1e-10`; `params.num_symbols==10` | 10符号N=64 CP=16无噪声回环 |
| 1.2 | ZP-OFDM回环 | `max(abs(recovered-data))<1e-10` | 5符号ZP-OFDM无噪声回环(overlap-add) |
| 1.3 | 导频插入/提取(comb_4) | `all(abs(pilot_rx(:)-(1+1j))<1e-10)`(导频值一致); `max(abs(data_rx-data))<1e-10`(数据回环) | 梳状导频comb_4模式，导频值=1+1j |
| 1.4 | 离散导频(scattered_4) | `all(abs(pilot_rx(:)-1)<1e-10)`; `max(abs(data_rx-data))<1e-10`; `~isequal(sym1_pilots,sym2_pilots)`(不同符号导频位置不同) | 离散导频交错位置验证 |
| 2.1 | SC-FDE CP回环 | 每块时域误差`<1e-10`; `fft(time_blocks)==freq_blocks`误差`<1e-10` | 4块block_size=128 CP=32时域和频域一致性 |
| 3.1 | OTFS DFT回环 | `max(abs(dd_rx(:)-dd_data(:)))<1e-8` | N=8 M=32 DFT方法无噪声回环 |
| 3.2 | OTFS Zak回环 | `max(abs(dd_rx(:)-dd_data(:)))<1e-8` | N=8 M=32 Zak方法无噪声回环 |
| 3.3 | DFT/Zak一致性 | `max(abs(sig_dft-sig_zak))<1e-8` | 两种方法输出信号一致（cp_len=0） |
| 3.4 | DD域导频(impulse) | `abs(dd_frame(4,16)-sqrt(N*M))<1e-10`(导频值); `max(abs(dd_frame(data_idx)-data))<1e-10`(数据); 保护区(除导频外)全零 | 单脉冲导频位置、数据、保护区验证 |
| 3.5 | 多脉冲导频 | 4个导频位置值`==2`(`<1e-10`); `info.mode=='multi_pulse'` | 4脉冲multi_pulse模式 |
| 3.6 | 叠加导频 | `~any(gmask(:))`(无保护区); `dd-data_mat==pilot_pattern`(`<1e-10`); `info.mode=='superimposed'` | superimposed模式全格点利用，导频图案可分离 |
| 3.7 | 序列导频(ZC) | `all(abs(pilot_row_vals)>0.1)`(导频非零); `info.mode=='sequence'`; `length(info.values)==positions数` | ZC序列导频非零值和模式验证 |
| 3.8 | 自适应保护区 | `ndata_small>ndata_large`(大扩展信道数据格点更少); `abs(dd_s(4,16)-3)<1e-10`(导频值) | 自适应保护区大小随信道扩展调整 |
| 4.1 | PAPR计算 | `papr_const<0.1`(恒模信号PAPR约0dB); `papr_ofdm>3`(OFDM PAPR>3dB) | 恒模信号vs OFDM信号PAPR对比 |
| 4.2 | PAPR削峰 | `papr_after<=6+0.5`(削峰后<=目标+余量); `papr_after<papr_before`(PAPR降低) | 硬限幅target=6dB |
| 5.1 | OFDM频谱可视化 | 无显式断言（绘图成功即通过） | 256子载波fs=48kHz频谱图生成 |
| 5.2 | OTFS 5种导频对比 | 无显式断言（绘图成功即通过） | 5种模式DD域热图+频谱效率柱状图 |
| 6.1 | 空输入拒绝 | `caught==9`（9个函数空输入均正确报错） | 覆盖ofdm/scfde/otfs/papr函数空输入 |

## 可视化说明

测试生成以下figure（位于独立try/catch块中，不影响测试计数）：

- **Figure 1 (测试5.1): OFDM频谱** — 四子图：(1) 时域波形实部，(2) 瞬时功率(dB)，(3) 功率谱密度(PSD)，(4) PAPR CCDF分布（256子载波，fs=48kHz）
- **Figure 2 (测试5.2): OTFS 5种导频模式对比** — 六子图：(1-5) 单脉冲/多脉冲/叠加导频/ZC序列/自适应保护区的DD域幅度热图（导频位置青色标注，保护区白点标注），(6) 五种模式数据格点占比柱状图（频谱效率对比），N=16 M=32
