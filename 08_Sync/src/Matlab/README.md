# 同步与帧结构模块 (Sync)

发端帧组装和收端同步检测/帧解析的统一入口，支持SC-TDE/SC-FDE/OFDM/OTFS四种体制的帧结构。覆盖三层同步架构：帧同步（粗粒度）-> 符号同步（中粒度）-> 位同步/相位跟踪（精细粒度）。

## 对外接口

其他模块/端到端应调用的函数：

### Layer 1: 帧同步（粗粒度，ms量级）

#### `gen_lfm` -- LFM线性调频信号生成

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `fs` | 输入 | 正实数 | 采样率 (Hz) | 无 |
| `duration` | 输入 | 正实数 | 信号持续时间 (秒) | 无 |
| `f_start` | 输入 | 实数 | 起始频率 (Hz) | 无 |
| `f_end` | 输入 | 实数 | 终止频率 (Hz) | 无 |
| `amplitude` | 输入 | 正实数 | 信号幅度 | 1 |
| `signal` | 输出 | 1xN 实数数组 | LFM时域波形 | -- |
| `t` | 输出 | 1xN 实数数组 | 时间轴 (秒) | -- |

#### `gen_hfm` -- HFM双曲调频信号生成（Doppler不变）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `fs` | 输入 | 正实数 | 采样率 (Hz) | 无 |
| `duration` | 输入 | 正实数 | 信号持续时间 (秒) | 无 |
| `f_start` | 输入 | 正实数 | 起始频率 (Hz) | 无 |
| `f_end` | 输入 | 正实数 | 终止频率 (Hz) | 无 |
| `amplitude` | 输入 | 正实数 | 信号幅度 | 1 |
| `signal` | 输出 | 1xN 实数数组 | HFM时域波形 | -- |
| `t` | 输出 | 1xN 实数数组 | 时间轴 (秒) | -- |

#### `gen_zc_seq` -- Zadoff-Chu序列生成（恒模，理想自相关）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `N` | 输入 | 正整数 | 序列长度（建议奇素数） | 无 |
| `root` | 输入 | 正整数 | 根索引，1 <= root < N，须与N互素 | 1 |
| `seq` | 输出 | 1xN 复数数组 | ZC复数序列（恒模，\|seq(n)\|=1） | -- |
| `N` | 输出 | 正整数 | 实际序列长度 | -- |

#### `gen_barker` -- Barker码生成（低旁瓣，长度2~13）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `N` | 输入 | 正整数 | 码长，支持 2/3/4/5/7/11/13 | 13 |
| `code` | 输出 | 1xN 数组 | Barker码（值为 +1/-1） | -- |
| `N` | 输出 | 正整数 | 实际码长 | -- |

#### `sync_detect` -- 粗同步检测（V2.0: 标准互相关 + 多普勒补偿二维搜索）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `received` | 输入 | 1xM 实/复数组 | 接收信号 | 无 |
| `preamble` | 输入 | 1xL 实/复数组 | 前导码参考信号 | 无 |
| `threshold` | 输入 | 实数 (0~1) | 归一化相关峰值检测门限 | 0.5 |
| `params` | 输入 | struct | 可选参数结构体（V2.0新增） | struct() |
| `params.method` | 输入 | 字符串 | 'correlate'(标准互相关) / 'doppler'(二维搜索) | 'correlate' |
| `params.fs` | 输入 | 正实数 | 采样率 (Hz)，doppler方法必须 | 无 |
| `params.fd_max` | 输入 | 正实数 | 最大多普勒频移 (Hz) | 50 |
| `params.num_fd` | 输入 | 正整数 | 多普勒频率搜索网格数 | 21 |
| `start_idx` | 输出 | 标量 | 前导起始位置索引（0=未检测到） | -- |
| `peak_val` | 输出 | 标量 (0~1) | 归一化相关峰值 | -- |
| `corr_out` | 输出 | 1x(M-L+1) 数组 | 完整归一化相关输出 | -- |

#### `cfo_estimate` -- CFO粗估计（互相关/Schmidl-Cox/CP法）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `received` | 输入 | 1xM 复数数组 | 接收信号（须已粗同步对齐） | 无 |
| `preamble` | 输入 | 1xL 复数数组 | 前导码参考信号 | 无 |
| `fs` | 输入 | 正实数 | 采样率 (Hz) | 无 |
| `method` | 输入 | 字符串 | 'correlate'(互相关相位法) / 'schmidl'(Schmidl-Cox) / 'cp'(CP自相关) | 'correlate' |
| `cfo_hz` | 输出 | 实数 | 频偏估计值 (Hz) | -- |
| `cfo_norm` | 输出 | 实数 | 归一化频偏（相对于采样率） | -- |

### Layer 2: 符号同步（中粒度，us量级）

#### `timing_fine` -- 细定时同步（Gardner/Mueller-Muller/超前滞后 TED）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `signal` | 输入 | 1xM 实/复数组 | 匹配滤波后基带信号（每符号sps个采样） | 无 |
| `sps` | 输入 | 正整数 (>=2) | 每符号采样数 | 无 |
| `method` | 输入 | 字符串 | 'gardner' / 'mm' / 'earlylate' | 'gardner' |
| `timing_offset` | 输出 | 实数 | 定时偏移（采样数，范围 [-sps/2, sps/2)） | -- |
| `ted_output` | 输出 | 1xK 数组 | TED逐符号输出 | -- |

### Layer 3: 位同步/相位跟踪（精细粒度，ns量级）

#### `phase_track` -- 相位跟踪（V1.0: PLL/判决反馈/Kalman联合跟踪）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `signal` | 输入 | 1xN 复数数组 | 均衡后符号序列 | 无 |
| `method` | 输入 | 字符串 | 'pll'(二阶PI锁相环) / 'dfpt'(判决反馈) / 'kalman'(Kalman联合) | 'pll' |
| `params` | 输入 | struct | 参数结构体 | struct() |
| --- PLL参数 --- | | | | |
| `params.Bn` | 输入 | 正实数 | 环路噪声带宽（归一化） | 0.01 |
| `params.zeta` | 输入 | 正实数 | 阻尼系数 | 1/sqrt(2) ~ 0.707 |
| `params.mod_order` | 输入 | 正整数 | 调制阶数 (2=BPSK, 4=QPSK) | 4 |
| --- DFPT参数 --- | | | | |
| `params.mu` | 输入 | 正实数 | 步长 | 0.01 |
| `params.mod_order` | 输入 | 正整数 | 调制阶数 | 4 |
| --- Kalman参数 --- | | | | |
| `params.Ts` | 输入 | 正实数 | 符号间隔 (秒) | 1 |
| `params.q_phase` | 输入 | 正实数 | 相位过程噪声方差 | 1e-4 |
| `params.q_freq` | 输入 | 正实数 | 频偏过程噪声方差 | 1e-6 |
| `params.q_frate` | 输入 | 正实数 | 频偏斜率过程噪声方差 | 1e-8 |
| `params.r_obs` | 输入 | 正实数 | 观测噪声方差 | 0.1 |
| `params.mod_order` | 输入 | 正整数 | 调制阶数 | 4 |
| `phase_est` | 输出 | 1xN 实数数组 | 逐符号相位估计 (弧度) | -- |
| `freq_est` | 输出 | 1xN 实数数组 | 逐符号频偏估计 (Hz，仅kalman有效，其余为差分近似) | -- |
| `info` | 输出 | struct | 附加信息 | -- |
| `info.phase_error` | 输出 | 1xN 数组 | 相位误差序列 | -- |
| `info.corrected` | 输出 | 1xN 复数数组 | 相位补偿后符号 | -- |

### 帧组装/解析

#### `frame_assemble_sctde` -- SC-TDE帧组装

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `data_symbols` | 输入 | 1xN 复/实数组 | 调制后数据符号 | 无 |
| `params` | 输入 | struct | 帧参数结构体 | struct() |
| `params.preamble_type` | 输入 | 字符串 | 前导类型 'lfm'/'hfm'/'zc'/'barker' | 'lfm' |
| `params.preamble_len` | 输入 | 正整数 | 前导码长度（采样点数） | 512 |
| `params.fs` | 输入 | 正实数 | 采样率 (Hz) | 48000 |
| `params.fc` | 输入 | 正实数 | 中心频率 (Hz) | 12000 |
| `params.bw` | 输入 | 正实数 | 带宽 (Hz) | 8000 |
| `params.training_len` | 输入 | 正整数 | 训练序列长度（符号数） | 64 |
| `params.guard_len` | 输入 | 正整数 | 保护间隔长度（采样点数） | 128 |
| `params.training_seed` | 输入 | 整数 | 训练序列随机种子 | 0 |
| `frame` | 输出 | 1xM 数组 | 完整帧 [前导+保护+训练+数据+保护] | -- |
| `info` | 输出 | struct | 帧信息（含 preamble, training, data_start, data_len, total_len, params） | -- |

#### `frame_parse_sctde` -- SC-TDE帧解析

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `received` | 输入 | 1xM 数组 | 接收信号 | 无 |
| `info` | 输入 | struct | 帧信息（由 frame_assemble_sctde 生成） | 无 |
| `data_symbols` | 输出 | 1xN 数组 | 提取的数据符号 | -- |
| `training_rx` | 输出 | 1xL 数组 | 提取的训练序列 | -- |
| `sync_info` | 输出 | struct | 同步信息（sync_pos, sync_peak, training_start, data_start） | -- |

#### `frame_assemble_scfde` -- SC-FDE帧组装（含前后导码）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `data_symbols` | 输入 | 1xN 数组 | 调制后数据符号 | 无 |
| `params` | 输入 | struct | 帧参数结构体 | struct() |
| `params.preamble_type` | 输入 | 字符串 | 前导类型 | 'lfm' |
| `params.preamble_len` | 输入 | 正整数 | 前导码长度（采样点数） | 512 |
| `params.fs` | 输入 | 正实数 | 采样率 (Hz) | 48000 |
| `params.fc` | 输入 | 正实数 | 中心频率 (Hz) | 12000 |
| `params.bw` | 输入 | 正实数 | 带宽 (Hz) | 8000 |
| `params.block_size` | 输入 | 正整数 | 数据分块大小（符号数） | 256 |
| `params.cp_len` | 输入 | 正整数 | CP长度（符号数） | 64 |
| `params.guard_len` | 输入 | 正整数 | 保护间隔（采样点数） | 128 |
| `params.training_seed` | 输入 | 整数 | 训练序列种子 | 0 |
| `frame` | 输出 | 1xM 数组 | 帧信号 [前导+保护+数据+保护+后导] | -- |
| `info` | 输出 | struct | 帧信息（含 preamble, postamble, num_blocks, block_size, cp_len, data_start, data_len, total_len, params） | -- |

#### `frame_parse_scfde` -- SC-FDE帧解析

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `received` | 输入 | 1xM 数组 | 接收信号 | 无 |
| `info` | 输入 | struct | 帧信息（由 frame_assemble_scfde 生成） | 无 |
| `data_symbols` | 输出 | 1xN 数组 | 提取的数据符号（不含补零） | -- |
| `sync_info` | 输出 | struct | 同步信息（sync_pos, sync_peak, data_start） | -- |

#### `frame_assemble_ofdm` -- OFDM帧组装（双重复前导，供Schmidl-Cox）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `data_symbols` | 输入 | 1xN 数组 | 频域数据符号 | 无 |
| `params` | 输入 | struct | 帧参数结构体 | struct() |
| `params.preamble_type` | 输入 | 字符串 | 前导类型 | 'zc' |
| `params.preamble_len` | 输入 | 正整数 | 前导码长度 | 256 |
| `params.fs` | 输入 | 正实数 | 采样率 (Hz) | 48000 |
| `params.guard_len` | 输入 | 正整数 | 前导后保护间隔 | 64 |
| `params.num_subcarriers` | 输入 | 正整数 | 子载波数 | 256 |
| `frame` | 输出 | 1xM 数组 | 帧信号 [前导(双重复)+保护+数据] | -- |
| `info` | 输出 | struct | 帧信息（含 preamble, preamble_half, data_start, data_len, total_len, params） | -- |

#### `frame_parse_ofdm` -- OFDM帧解析（含CFO估计）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `received` | 输入 | 1xM 数组 | 接收信号 | 无 |
| `info` | 输入 | struct | 帧信息（由 frame_assemble_ofdm 生成） | 无 |
| `data_symbols` | 输出 | 1xN 数组 | 提取的数据段 | -- |
| `sync_info` | 输出 | struct | 同步信息（sync_pos, sync_peak, cfo_hz, cfo_norm, data_start） | -- |

#### `frame_assemble_otfs` -- OTFS帧组装（推荐HFM前导）

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `data_symbols` | 输入 | 1xN 数组 | DD域数据符号 | 无 |
| `params` | 输入 | struct | 帧参数结构体 | struct() |
| `params.preamble_type` | 输入 | 字符串 | 前导类型（推荐HFM） | 'hfm' |
| `params.preamble_len` | 输入 | 正整数 | 前导码长度（采样点数） | 512 |
| `params.fs` | 输入 | 正实数 | 采样率 (Hz) | 48000 |
| `params.fc` | 输入 | 正实数 | 中心频率 (Hz) | 12000 |
| `params.bw` | 输入 | 正实数 | 带宽 (Hz) | 8000 |
| `params.guard_len` | 输入 | 正整数 | 保护间隔 | 128 |
| `frame` | 输出 | 1xM 数组 | 帧信号 [前导+保护+数据] | -- |
| `info` | 输出 | struct | 帧信息（含 preamble, data_start, data_len, total_len, params） | -- |

#### `frame_parse_otfs` -- OTFS帧解析

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `received` | 输入 | 1xM 数组 | 接收信号 | 无 |
| `info` | 输入 | struct | 帧信息（由 frame_assemble_otfs 生成） | 无 |
| `data_symbols` | 输出 | 1xN 数组 | 提取的数据段 | -- |
| `sync_info` | 输出 | struct | 同步信息（sync_pos, sync_peak, data_start） | -- |

## 内部函数（不建议外部直接调用）

#### `plot_sync_spectrogram` -- 同步信号时频谱图可视化

| 参数 | 方向 | 类型 | 含义 | 默认值 |
|------|------|------|------|--------|
| `signal` | 输入 | 1xN 数组 | 时域信号 | 无 |
| `fs` | 输入 | 正实数 | 采样率 (Hz) | 48000 |
| `title_str` | 输入 | 字符串 | 图标题 | 'Sync Signal' |

绘制三子图：时域波形、频谱（dB）、STFT时频谱图。适用于LFM/HFM等调频信号的观测。

#### `test_sync.m` -- 单元测试（V2.0, 22项）

覆盖：序列生成、同步检测、CFO估计、细定时、帧回环、多普勒补偿、相位跟踪、异常输入 + 可视化。

#### 各函数内部辅助函数（internal）

- `sync_detect` 内部: `sliding_corr` (标准滑动归一化互相关), `doppler_compensated_corr` (多普勒补偿二维搜索)
- `phase_track` 内部: `hard_decision` (硬判决，支持BPSK/QPSK/8PSK/16QAM), `pll_track` (PLL跟踪), `dfpt_track` (DFPT跟踪), `kalman_track` (Kalman跟踪)
- `timing_fine` 内部: `gardner_ted` (Gardner TED), `mm_ted` (Mueller-Muller TED), `earlylate_ted` (超前滞后门TED)
- `cfo_estimate` 内部: 无独立子函数，三种方法在switch-case中直接实现

## 核心算法技术描述

### 1. 滑动归一化互相关同步（sync_detect, correlate方法）

**原理**: 接收信号 r(n) 与已知前导码 s(n) 做滑动归一化互相关，检测相关峰超过门限的位置。

**关键公式**:
$$C(k) = \frac{\left|\sum_{n=0}^{L-1} r(n+k) \cdot s^*(n)\right|}{\sqrt{E_r(k) \cdot E_s}}$$

其中:

$$E_r(k) = \sum_{n=0}^{L-1} |r(n+k)|^2 \quad \text{(接收段能量)}$$

$$E_s = \sum_{n=0}^{L-1} |s(n)|^2 \quad \text{(前导码能量)}$$

**参数选择**: 门限threshold通常取0.3~0.7，高SNR取高值减少误检，低SNR取低值提高检出率。多峰超限时返回最大峰位置。

**适用条件**: 信道静止或慢变时有效。高多普勒频移场景下相关峰衰减，需切换至doppler方法。

### 2. 多普勒补偿二维搜索同步（sync_detect, doppler方法, V2.0新增）

**原理**: 对候选多普勒频移网格逐一补偿后做互相关，取所有频移中的最大相关值。

**关键公式**:
$$C(k) = \frac{\max_f \left|\sum_{n=0}^{L-1} r(n+k) \cdot s^*(n) \cdot e^{-j 2\pi f n T_s}\right|^2}{\sqrt{E_r(k) \cdot E_s}}$$

$$f_d\text{\_grid} = \text{linspace}(-f_{d,\max},\; f_{d,\max},\; N_{fd}), \quad T_s = 1/f_s$$

**参数选择**: fd_max根据运动速度估算（水声典型: v*fc/c），num_fd取奇数（含零频偏），推荐21~51。网格过密增加计算量，过疏漏检。

**适用条件**: 时变水声信道（UWA），运动平台，多普勒频移可达数十Hz。对频率扩展信道效果好，但计算复杂度为标准方法的num_fd倍。

### 3. CFO估计算法

#### 3a. 互相关相位法（correlate）

**原理**: 将前导码分为前后两半，分别互相关后取相位差。

**关键公式**:
$$\text{corr}_1 = \sum_{n=0}^{L/2-1} r(n) \cdot s^*(n), \quad \text{corr}_2 = \sum_{n=L/2}^{L-1} r(n) \cdot s^*(n)$$

$$f_{\text{cfo}} = \frac{\angle(\text{corr}_2 \cdot \text{corr}_1^*)}{2\pi \cdot (L/2) / f_s}$$

**适用条件**: 需要已知前导码，估计范围受限于 |cfo| < fs/(2*L)。简单高效，适合粗估。

#### 3b. Schmidl-Cox法（schmidl）

**原理**: 利用前导码的双重复结构 [A, A]，前后半段自相关提取频偏信息。

**关键公式**:
$$P = \sum_{n=0}^{L/2-1} r(n + L/2) \cdot r^*(n)$$

$$f_{\text{cfo}} = \frac{\angle(P) \cdot f_s}{2\pi \cdot L/2}$$

**参数选择**: 前导码须为严格重复结构。估计范围 |cfo| < fs/L。

**适用条件**: OFDM系统常用，盲估计（不需要已知前导码内容，仅需重复结构）。

#### 3c. CP自相关法（cp）

调用模块10 (DopplerProc) 的 `est_doppler_cp`，利用OFDM的CP与数据重复结构估计多普勒因子alpha，再转换为频偏。

### 4. 细定时同步（timing_fine）

#### 4a. Gardner TED（非数据辅助）

**原理**: 利用相邻采样点和中间点的关系估计定时误差，不需要数据判决。

**关键公式**:
$$e(k) = \mathrm{Re}\!\left\{y(kT + T/2) \cdot \left[y^*(kT) - y^*((k+1)T)\right]\right\}$$

**适用条件**: 需sps>=2，适合突发传输。收敛速度中等。

#### 4b. Mueller-Muller TED（数据辅助）

**关键公式**:
$$e(k) = \mathrm{Re}\!\left\{d^*(k-1) \cdot y(k) - d^*(k) \cdot y(k-1)\right\}$$
其中 d(k) 为硬判决符号。收敛后精度高于Gardner。

#### 4c. 超前滞后门TED

**关键公式**:
$$e(k) = |y(kT + \delta)|^2 - |y(kT - \delta)|^2, \quad \delta = 1 \text{ sample}$$

简单实现，但需较高过采样率。

**定时偏移估计**: 取TED输出均值乘以sps/(2*pi)，限制在 [-sps/2, sps/2) 范围。

### 5. 相位跟踪（phase_track, V1.0）

#### 5a. 二阶PI锁相环（PLL）

**原理**: 经典二阶反馈环路，通过PI控制器跟踪慢变相位偏移。

**关键公式**:
$$e_\varphi(n) = \mathrm{Im}\!\left\{y(n) \cdot \hat{a}^*(n) \cdot e^{-j\hat{\varphi}(n)}\right\} \quad \text{(鉴相器)}$$

$$\hat{\varphi}(n+1) = \hat{\varphi}(n) + \alpha_1 e + \alpha_2 \sum e \quad \text{(环路滤波)}$$

环路系数从 $B_n$ 和 $\zeta$ 推导:

$$\theta_n = \frac{B_n}{\zeta + 1/(4\zeta)}, \quad \alpha_1 = \frac{4\zeta \theta_n}{1 + 2\zeta \theta_n + \theta_n^2}, \quad \alpha_2 = \frac{4\theta_n^2}{1 + 2\zeta \theta_n + \theta_n^2}$$

**参数选择**: Bn越大跟踪越快但噪声越大。慢时变推荐 Bn=0.01~0.02，快变可增大至0.05。zeta=1/sqrt(2)为临界阻尼。

**适用条件**: 恒定或慢变频偏最优。快速时变场景跟踪滞后。

#### 5b. 判决反馈相位跟踪（DFPT）

**原理**: 一阶LMS式更新，利用判决符号和接收符号的相位差。

**关键公式**:
$$\hat{\varphi}(n) = \hat{\varphi}(n-1) + \mu \cdot \mathrm{Im}\!\left\{y(n) \cdot \hat{a}^*(n)\right\}$$

**参数选择**: mu为步长，典型0.01~0.05。mu越大收敛越快但稳态抖动越大。

**适用条件**: 中速时变、高SNR场景。结构简单，计算量最小。

#### 5c. Kalman联合跟踪（相位+频偏+频偏斜率）

**原理**: 三阶状态空间模型，同时估计相位、频偏和频偏变化率，对加速度型相位变化最优。

**关键公式**:
**状态向量:** $\mathbf{x} = [\varphi,\; \Delta f,\; \Delta\dot{f}]^T$

$$\mathbf{A} = \begin{bmatrix} 1 & 2\pi T_s & 2\pi T_s^2/2 \\ 0 & 1 & T_s \\ 0 & 0 & 1 \end{bmatrix}, \quad \mathbf{C} = [1,\; 0,\; 0]$$

$$\mathbf{Q} = \text{diag}(q_\varphi,\; q_f,\; q_{\dot{f}}), \quad R = r_{\text{obs}}$$

**预测:**

$$\mathbf{x}_{\text{pred}} = \mathbf{A} \mathbf{x}, \quad \mathbf{P}_{\text{pred}} = \mathbf{A} \mathbf{P} \mathbf{A}^T + \mathbf{Q}$$

**观测:** $z = \angle(y(n) \cdot \hat{d}^*(n))$ （硬判决后提取相位）

**更新:**

$$\mathbf{K} = \frac{\mathbf{P}_{\text{pred}} \mathbf{C}^T}{\mathbf{C} \mathbf{P}_{\text{pred}} \mathbf{C}^T + R}, \quad \mathbf{x} = \mathbf{x}_{\text{pred}} + \mathbf{K} (z - \mathbf{C} \mathbf{x}_{\text{pred}})$$

$$\mathbf{P} = (\mathbf{I} - \mathbf{K} \mathbf{C}) \mathbf{P}_{\text{pred}}$$

（innovation相位回卷到$[-\pi, \pi]$）

**参数选择**: q_phase/q_freq/q_frate反映相位变化的激烈程度，越大跟踪越快但越不平滑。r_obs反映观测信噪比。高SNR时 r_obs取小值（如0.01），低SNR取大值（如1.0）。

**适用条件**: 高速时变信道（如UWA移动平台），有线性频偏斜率的场景。三种方法中跟踪能力最强，但计算量最大。

### 6. 同步序列设计原则

| 序列类型 | 自相关特性 | PAPR | Doppler鲁棒 | 典型用途 |
|----------|----------|------|------------|---------|
| LFM | 主瓣窄，旁瓣可控 | 0 dB（恒包络） | 较差 | 静态/慢变信道帧同步 |
| HFM | 主瓣窄，旁瓣可控 | 0 dB | 优秀 | 移动水声通信帧同步 |
| ZC | 理想（周期旁瓣=0） | 0 dB | 较差 | OFDM参考信号，CFO估计 |
| Barker | 非周期旁瓣<=1 | 0 dB | 较差 | 短帧同步（长度<=13） |

## 使用示例

```matlab
% 生成前导码 + 粗同步（标准方法）
[preamble, ~] = gen_lfm(48000, 0.01, 8000, 16000);
[start_idx, peak, corr] = sync_detect(received, preamble, 0.5);

% 多普勒补偿同步（时变信道，V2.0新增）
dp = struct('method','doppler', 'fs',48000, 'fd_max',50, 'num_fd',21);
[start_idx, peak, corr] = sync_detect(received, preamble, 0.5, dp);

% SC-TDE帧组装/解析回环
params = struct('preamble_type','lfm','fs',48000,'fc',12000,'bw',8000);
[frame, info] = frame_assemble_sctde(data_symbols, params);
[data_rx, train_rx, sync_info] = frame_parse_sctde(received, info);

% SC-FDE帧组装/解析
[frame, info] = frame_assemble_scfde(data_symbols, params);
[data_rx, sync_info] = frame_parse_scfde(received, info);

% CFO估计（Schmidl-Cox法，OFDM场景）
[cfo_hz, ~] = cfo_estimate(rx_preamble, ref_preamble, fs, 'schmidl');

% 细定时同步（Gardner TED）
[timing_off, ted_out] = timing_fine(filtered_signal, 8, 'gardner');

% 相位跟踪（PLL / 判决反馈 / Kalman）
[ph, freq, info] = phase_track(eq_symbols, 'pll', struct('Bn',0.02,'mod_order',4));
[ph, freq, info] = phase_track(eq_symbols, 'dfpt', struct('mu',0.05,'mod_order',4));
[ph, freq, info] = phase_track(eq_symbols, 'kalman', struct('Ts',1/48000));
corrected_symbols = info.corrected;
```

## 依赖关系

- 模块08的 `cfo_estimate` CP法内部调用模块10 (DopplerProc) 的 `est_doppler_cp`
- 模块08的 `timing_fine` 测试依赖模块09 (Waveform) 的 `pulse_shape`/`match_filter`
- CP插入/去除统一在模块06 (MultiCarrier) 中处理，本模块不处理CP

## 测试覆盖 (test_sync.m V2.0, 22项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|---------|---------|------|
| 1.1 | LFM信号生成 | `length(sig) == round(fs*dur)`, `isreal(sig)` | 长度精确匹配采样率*时长，输出为实信号 |
| 1.2 | HFM信号生成 | `length(sig) == round(fs*dur)` | Doppler不变性调频信号，长度正确 |
| 1.3 | ZC序列生成 | `length(seq) == 127`, `all(abs(abs(seq)-1) < 1e-10)`, `sidelobe/peak < 0.01` | 恒模特性，周期自相关旁瓣/峰值<1% |
| 1.4 | Barker码生成 | `length(code13) == 13`, `max(abs(sidelobes)) <= 1+1e-6` | 非周期自相关旁瓣绝对值<=1 |
| 2.1 | LFM无噪声同步 | `abs(pos - offset - 1) <= 1`, `peak > 0.9` | 位置偏差<=1样本，峰值接近1.0 |
| 2.2 | ZC有噪声同步 | `abs(pos - offset - 1) <= 2` | SNR约6dB，位置偏差<=2样本 |
| 3.1 | 互相关CFO估计 | `abs(cfo_est - true_cfo) < 20` Hz | 50Hz真实频偏，估计误差<20Hz |
| 3.2 | Schmidl-Cox CFO估计 | `abs(cfo_est - true_cfo) < 20` Hz | 30Hz真实频偏，双重复前导，误差<20Hz |
| 4.1 | Gardner TED | `~isempty(ted_out)` | RRC成形信号，TED输出非空 |
| 4.2 | 三种TED方法 | `all_ok == true`（三种方法输出均非空） | gardner/mm/earlylate全部可运行 |
| 5.1 | SC-TDE帧回环 | `sync_pos > 0`, `length(data_rx) == length(data)`, `max(abs(data_rx-data)) < 1e-10` | 无噪声回环数据精确恢复 |
| 5.2 | SC-FDE帧回环 | `sync_pos > 0`, `length(data_rx) == length(data)` | 含前后导码，数据长度一致 |
| 5.3 | OFDM帧回环 | `sync_pos > 0`, `length(data_rx) == length(data)`, `isfield(sync_info,'cfo_hz')` | ZC前导，含CFO估计字段 |
| 5.4 | OTFS帧回环 | `sync_pos > 0`, `length(data_rx) == length(data)` | HFM前导（Doppler不变） |
| 6.1 | 多普勒补偿LFM同步 | `abs(pos_dp - offset - 1) <= 2`, `peak_dp >= peak_std - 1e-10` | fd=30Hz，补偿峰值不低于标准方法 |
| 6.2 | 多普勒补偿ZC同步 | `abs(pos - offset - 1) <= 2` | fd=40Hz+噪声，位置偏差<=2样本 |
| 7.1 | PLL相位跟踪 | `sqrt(mean(phase_error(tail).^2)) < 0.3` | QPSK+恒定频偏0.005，收敛后RMS<0.3rad |
| 7.2 | DFPT判决反馈 | `mean(abs(corrected-qpsk).^2) < 0.1` | 正弦相位漂移，补偿后MSE<0.1 |
| 7.3 | Kalman联合跟踪 | `~isempty(freq_est)`, `phase_err_rms < 0.5` | 线性频偏斜率5Hz/s，收敛后RMS<0.5rad |
| 7.4 | 三种相位跟踪方法 | `all_ok == true`（三种方法输出均非空） | pll/dfpt/kalman全部可运行 |
| 7.5 | BPSK PLL | `abs(est_phase_tail - phase_offset) < 0.15` | BPSK恒定相偏pi/6，估计偏差<0.15rad |
| 8.1 | 异常输入拒绝 | `caught == 7`（7项异常全部报错） | 空信号/非法Barker/非法ZC/缺参数等 |

## 可视化说明

测试生成以下figure（在独立try/catch中，不影响测试计数）：

| Figure | 名称 | 内容 |
|--------|------|------|
| Figure 1 | 多普勒补偿同步对比 | 左: LFM同步 (fd=30Hz)，标准互相关 vs 多普勒补偿，标注真实位置；右: ZC同步 (fd=40Hz)，同样对比 |
| Figure 2 | 相位跟踪结果 | 3x3子图: (1)PLL相位跟踪曲线 (2)PLL误差 (3)PLL星座图(补偿前/后)；(4)DFPT相位跟踪 (5)DFPT误差 (6)DFPT星座图；(7)Kalman相位跟踪 (8)Kalman频偏估计 (9)Kalman星座图 |
