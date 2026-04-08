# 端到端仿真模块 (SourceCode)

六种通信体制的端到端仿真统一入口，提供公共函数（参数配置/发射链路/接收链路/信道模型/自适应块长）和逐体制独立测试脚本，采用统一的通带帧结构。

## 对外接口

其他模块/端到端应调用的函数：

### `sys_params`

6体制统一参数配置（SC-TDE/SC-FDE/OFDM/OTFS/DSSS/FH-MFSK）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `scheme` | string | 通信体制: `'SC-TDE'`/`'SC-FDE'`/`'OFDM'`/`'OTFS'`/`'DSSS'`/`'FH-MFSK'` | `'SC-FDE'` |
| `snr_db` | scalar (dB) | 信噪比 | 10 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `params` | struct | 系统参数结构体 |

params主要字段：

| 字段 | 含义 |
|------|------|
| `.scheme` | 体制名称（大写） |
| `.snr_db` | 信噪比 |
| `.fs` | 基带采样率（48000Hz = sym_rate*sps） |
| `.fc` | 载波频率（12000Hz） |
| `.sym_rate` | 符号率（6000 Baud） |
| `.sps` | 每符号采样数（8） |
| `.N_info` | 信息比特数 |
| `.mod` | 调制参数: `.type`('qpsk'), `.M`(4), `.bits_per_sym`(2) |
| `.codec` | 编解码参数: `.gen_polys`([7,5]), `.constraint_len`(3), `.interleave_seed`(7), `.decode_mode`('max-log') |
| `.waveform` | 波形参数: `.sps`(8), `.filter_type`('rrc'), `.rolloff`(0.35), `.span`(6) |
| `.channel` | 信道参数（传给gen_uwa_channel） |
| `.tx` | 发射参数（体制相关，如N_fft, N_cp, train_len等） |
| `.rx` | 接收参数（体制相关） |

---

### `tx_chain`

通用发射链路（编码+交织+调制+帧结构），6种体制统一入口。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `params` | struct | 系统参数（由sys_params生成） | (必需) |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `tx_signal` | 1xN complex | 发射基带信号 |
| `tx_info` | struct | `.info_bits`, `.coded_bits`, `.interleaved`, `.symbols`, `.perm`, `.training`(SC-TDE), `.tx_data_only` |

链路流程：信息比特 -> 信道编码(conv_encode) -> 交织(random_interleave) -> 调制(QPSK) -> [扩频] -> [CP/训练/帧结构] -> 发射

---

### `rx_chain`

通用接收链路（均衡+译码+BER计算），6种体制统一入口。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `rx_signal` | 1xN complex | 接收基带信号 | (必需) |
| `params` | struct | 系统参数（由sys_params生成） | (必需) |
| `tx_info` | struct | 发射端信息（由tx_chain生成） | (必需) |
| `ch_info` | struct | 信道信息（由gen_uwa_channel生成） | (必需) |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `bits_out` | 1xN_info | 译码后信息比特 |
| `rx_info` | struct | `.ber_info`(信息比特BER), `.ber_sym`(符号BER), `.eq_output`(均衡输出), `.scheme` |

链路流程（通带模式）：下变频 -> 同步检测 -> [粗多普勒补偿] -> RRC匹配 -> 下采样 -> [去CP+FFT] -> [残余CFO] -> 均衡 -> [Turbo迭代] -> 解交织 -> 译码

---

### `gen_uwa_channel`

简化水声信道仿真（多径时变+Jakes衰落+宽带多普勒伸缩+AWGN）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `tx` | 1xN_tx complex | 发射基带信号 | (必需) |
| `ch_params` | struct | 信道参数结构体 | 见下方 |

ch_params字段：

| 字段 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `.fs` | scalar (Hz) | 采样率 | 48000 |
| `.num_paths` | integer | 路径数 | 5 |
| `.max_delay_ms` | scalar (ms) | 最大时延 | 10 |
| `.delay_profile` | string | 时延功率谱: `'exponential'`/`'uniform'`/`'custom'` | `'exponential'` |
| `.delays_s` | 1xP (s) | 自定义时延向量（仅custom） | -- |
| `.gains` | 1xP complex | 自定义复增益向量（仅custom） | -- |
| `.doppler_rate` | scalar | 多普勒伸缩率 alpha（正=靠近/压缩） | 0 |
| `.fading_type` | string | 衰落类型: `'static'`/`'slow'`/`'fast'` | `'static'` |
| `.fading_fd_hz` | scalar (Hz) | 最大多普勒频移（仅slow/fast） | 2 |
| `.snr_db` | scalar (dB) | 信噪比（Inf则不加噪） | 15 |
| `.seed` | integer | 随机种子 | 0 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `rx` | 1xN_rx complex | 接收基带信号（长度可能因多普勒伸缩与tx不同） |
| `ch_info` | struct | `.h_time`(num_pathsxN_tx时变信道矩阵), `.delays_s`, `.delays_samp`, `.gains_init`, `.doppler_rate`, `.noise_var` |

---

### `adaptive_block_len`

自适应块长选择（从接收信号估计多普勒扩展fd，计算最优FFT块长）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `rx_signal` | 1xN complex | 接收信号（含前后导频） | (必需) |
| `pilot` | 1xL complex | 导频序列 | (必需) |
| `fs` | scalar (Hz) | 采样率 | (必需) |
| `fc` | scalar (Hz) | 载波频率 | (必需) |
| `blk_range` | 1x2 | 允许块长范围 [min, max] | [32, 1024] |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `blk_fft` | integer | 推荐FFT块长（2的幂） |
| `fd_est` | scalar (Hz) | 估计的最大多普勒频移 |
| `T_coherence` | scalar (s) | 估计的信道相干时间 |

### `main_sim_single`

单SNR点6体制仿真脚本（直接运行，输出BER柱状图+表格）。

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| (无输入参数，直接run) | -- | -- | SNR=10dB |
| **输出** | figure + console | BER柱状图 + 体制对比表格 | -- |

## 内部函数

辅助函数（不建议外部直接调用）：
- 各体制 `tests/` 下的 `*.txt` -- 仿真结果记录文件

## 核心算法技术描述

### 1. 简化水声信道模型（gen_uwa_channel）

**多径建模：**
- exponential：时延均匀分布在 [0, max_delay]，功率指数衰减
- custom：用户指定时延和增益

**时变衰落（Jakes模型）：**

```
h_p(t) = g_p · Σ_{k=1}^{K} cos(2π·fd·cos(φ_k)·t + θ_k) / sqrt(K)
```

其中fd为最大多普勒频移，phi_k为均匀分布的到达角。static模式下增益不随时间变化。

**宽带多普勒伸缩：**

对整个信号做重采样（时间压缩/扩展），模拟收发相对运动。正alpha表示靠近（信号压缩），负alpha表示远离。

**简化假设：** 各路径独立衰落，无海面/海底反射几何建模。

### 2. 自适应块长选择（adaptive_block_len）

**原理：**
1. 用导频互相关找到前后两个导频位置
2. 提取两处信道估计，计算信道变化率 -> fd
3. 相干时间 `T_c ≈ 1/(4·fd)`
4. 块长 = T_c * sym_rate / 4（块时长约25%相干时间，保守选择）
5. 取2的幂次对齐

**参数选择规则：**
- 静态信道(fd=0)：取blk_range上限（最大块长=最高频谱分辨率）
- 快衰落(fd>5Hz)：小块长（128或更小）以保证块内信道近似不变
- 慢衰落(fd=1~2Hz)：中等块长（256~512）

## 统一通带帧结构

所有体制的端到端测试采用统一的通带实数帧结构：

```
TX: info_bits -> 02编码 -> 03交织 -> 04调制 -> [06加CP] -> 09 RRC成形 -> 09上变频 -> 通带实信号
信道: 等效基带 -> gen_uwa_channel(多径+Jakes+多普勒+AWGN) -> 09上变频 -> +实噪声
RX: 09下变频 -> 08同步检测 -> [10粗多普勒] -> 09 RRC匹配 -> 下采样
    -> [06去CP+FFT] -> [10残余CFO] -> 07均衡 -> [12 Turbo迭代] -> 03解交织 -> 02译码
```

帧格式: `[LFM前导 | guard | 数据(通带) | guard | LFM后导]`，LFM前导由模块08的gen_lfm生成。

## 测试结构

逐体制独立测试位于 `tests/` 目录下：

### SC-FDE (tests/SC-FDE/)

**test_scfde_static.m (V2.0)** -- 静态信道 SNR vs BER

| 编号 | 测试名称 | 验证内容 | 说明 |
|------|---------|---------|------|
| 1 | SC-FDE静态信道SNR扫描 | SNR=[5,10,15,20,25,30]dB下BER曲线 | 通带实数帧+同步+跨块BCJR，6径信道(max_delay=15ms=90符号)，4块x1024FFT，CP=128 |

**test_scfde_timevarying.m (V2.1)** -- 时变信道测试

| 编号 | 测试名称 | 验证内容 | 说明 |
|------|---------|---------|------|
| 1 | SC-FDE时变信道多衰落配置 | 4种衰落(static/fd=1/fd=5/fd=10Hz) x 4个SNR点 | Jakes+多普勒伸缩+重采样补偿+Turbo+DD信道更新。同步在无噪声信号上做一次(per fading config) |

### OFDM (tests/OFDM/)

**test_ofdm_e2e.m (V8.0)** -- 静态信道 SNR vs BER

| 编号 | 测试名称 | 验证内容 | 说明 |
|------|---------|---------|------|
| 1 | OFDM静态信道SNR扫描 | SNR=[5,10,15,20,25,30]dB下BER曲线 | 对齐SC-FDE V2通带帧结构，同参数(1024FFT, 4块, 6径) |

**test_ofdm_timevarying.m (V2.0)** -- 时变信道测试

| 编号 | 测试名称 | 验证内容 | 说明 |
|------|---------|---------|------|
| 1 | OFDM时变信道多衰落配置 | 4种衰落 x 4个SNR点 | 对齐SC-FDE V2.1架构（无噪声sync+Turbo+DD信道更新） |

### SC-TDE (tests/SC-TDE/)

**test_sctde_static.m (V3.1)** -- 静态信道均衡方法对比

| 编号 | 测试名称 | 验证内容 | 说明 |
|------|---------|---------|------|
| 1 | SC-TDE均衡方法对比 | SNR=[-10..20]dB下多种方法BER曲线 | 对比方法: oracle/MMSE/OMP/SBL/GAMP等信道估计 + turbo_dfe(31FF,90FB,6迭代)，500训练+2000数据 |

**test_sctde_timevarying.m (V4.0)** -- 时变信道测试

| 编号 | 测试名称 | 验证内容 | 说明 |
|------|---------|---------|------|
| 1 | SC-TDE时变信道测试 | 多衰落配置 x SNR扫描 | V4: 静态径用GAMP+turbo_sctde，时变径用BEM(DCT)+散布导频+ISI消除 |

**OTFS/DSSS/FH-MFSK**: 待开发。

## 使用示例

```matlab
% 6体制快速对比（单SNR点）
cd('13_SourceCode/src/Matlab/common');
run('main_sim_single.m');

% 单体制端到端
params = sys_params('SC-FDE', 10);
[tx_signal, tx_info] = tx_chain(params);
[rx, ch_info] = gen_uwa_channel(tx_signal, params.channel);
[bits_out, rx_info] = rx_chain(rx, params, tx_info, ch_info);
fprintf('BER = %.4f%%\n', rx_info.ber_info * 100);

% 逐体制独立测试
cd('13_SourceCode/src/Matlab/tests/SC-FDE');
run('test_scfde_static.m');
```

## 依赖关系

- 依赖模块02 (ChannelCoding) 的 `conv_encode`、`viterbi_decode`、`siso_decode_conv`
- 依赖模块03 (Interleaving) 的 `random_interleave`、`random_deinterleave`
- 依赖模块07 (ChannelEstEq) 的 `eq_mmse_fde`、`eq_mmse_ic_fde`、`eq_dfe`、`soft_demapper`、`soft_mapper`、`ch_est_*`(GAMP/OMP/SBL等)
- 依赖模块08 (Sync) 的 `gen_lfm`、`sync_detect`、`frame_assemble_*`、`frame_parse_*`
- 依赖模块09 (Waveform) 的 `pulse_shape`、`match_filter`、`upconvert`、`downconvert`
- 依赖模块10 (DopplerProc) 的 `doppler_coarse_compensate`、`comp_resample_spline`（时变信道测试）
- 依赖模块12 (IterativeProc) 的 `turbo_equalizer_scfde`、`turbo_equalizer_sctde`、`turbo_equalizer_scfde_crossblock`

## 测试覆盖

注：端到端测试为性能基准测试（SNR vs BER曲线），不含assert断言，通过BER曲线是否合理、是否随SNR单调下降来验证系统正确性。

| 编号 | 测试文件 | 版本 | 测试内容 | 验证标准 |
|------|---------|------|---------|---------|
| 1 | test_scfde_static.m | V2.0 | SC-FDE静态信道SNR vs BER | BER随SNR单调下降，高SNR趋近0 |
| 2 | test_scfde_timevarying.m | V2.1 | SC-FDE时变信道(4种衰落xSNR) | 各衰落配置BER合理，多普勒补偿有效 |
| 3 | test_ofdm_e2e.m | V8.0 | OFDM静态信道SNR vs BER | 与SC-FDE性能可比 |
| 4 | test_ofdm_timevarying.m | V2.0 | OFDM时变信道(4种衰落xSNR) | Turbo+DD改善BER |
| 5 | test_sctde_static.m | V3.1 | SC-TDE均衡方法对比(多种信道估计) | oracle最优，估计方法性能差异合理 |
| 6 | test_sctde_timevarying.m | V4.0 | SC-TDE时变信道(BEM+散布导频) | 时变信道下BER可接受 |

## 可视化说明

各测试脚本均生成性能对比figure：

- **test_scfde_static / test_ofdm_e2e：** SNR vs BER对数曲线（semilogy），含跨块BCJR对比
- **test_scfde_timevarying / test_ofdm_timevarying：** 多衰落配置的SNR vs BER对比曲线，不同衰落速率用不同标记/颜色区分
- **test_sctde_static：** 多种均衡方法（oracle/MMSE/OMP/SBL/GAMP等）的SNR vs BER对比曲线
- **test_sctde_timevarying：** 时变信道下的BER vs SNR曲线，含静态和时变路径的对比
- **main_sim_single：** 6体制BER柱状图 + 信道可视化
