# 多载波/多域变换模块 (MultiCarrier)

水声通信系统多载波调制算法库，覆盖OFDM(CP/ZP)、SC-FDE分块CP、OTFS(DFT/Zak两种实现)，含PAPR计算/抑制和可视化工具。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `ofdm_modulate.m` | OFDM调制（IFFT + CP/ZP插入） | OFDM |
| `ofdm_demodulate.m` | OFDM解调（去CP/ZP + FFT） | OFDM |
| `ofdm_pilot_insert.m` | 频域导频插入（梳状/块状/自定义） | OFDM |
| `ofdm_pilot_extract.m` | 频域导频提取 | OFDM |
| `scfde_add_cp.m` | SC-FDE分块CP插入 | SC-FDE |
| `scfde_remove_cp.m` | SC-FDE去CP + 分块FFT | SC-FDE |
| `otfs_modulate.m` | OTFS调制（ISFFT+Heisenberg，DFT/Zak两种） | OTFS |
| `otfs_demodulate.m` | OTFS解调（Wigner+SFFT） | OTFS |
| `otfs_pilot_embed.m` | DD域嵌入导频+保护区 | OTFS |
| `otfs_get_data_indices.m` | DD域数据格点索引提取 | OTFS |
| `papr_calculate.m` | PAPR计算 | PAPR |
| `papr_clip.m` | PAPR抑制（硬限幅/限幅滤波/幅度缩放） | PAPR |
| `plot_ofdm_spectrum.m` | OFDM频谱+时域+PAPR CCDF可视化 | 可视化 |
| `plot_otfs_dd_grid.m` | OTFS DD域格点幅度/相位热图 | 可视化 |
| `test_multicarrier.m` | 单元测试（14项） | 测试 |

## 三种多载波方案对比

| 方案 | 域变换 | CP类型 | 导频方式 | 适用场景 |
|------|--------|--------|----------|----------|
| CP-OFDM | IFFT/FFT | 每符号CP | 频域梳状/块状 | 宽带高速率 |
| ZP-OFDM | IFFT/FFT+OLA | 每符号ZP | 同CP-OFDM | 频选衰落信道 |
| SC-FDE | 分块FFT/IFFT | 每块CP | 时域前导码 | 低PAPR，长延时 |
| OTFS-DFT | ISFFT+Heisenberg | 整帧CP | DD域嵌入脉冲 | 快时变高移动 |
| OTFS-Zak | 2D-IFFT(等价) | 整帧CP | 同DFT方法 | 同上，另一种实现 |

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\MultiCarrier\src\Matlab');
run('test_multicarrier.m');
```

### 测试用例说明

**1. OFDM（3项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 CP-OFDM回环 | 误差<1e-10 | 10个OFDM符号IFFT+CP→去CP+FFT完全还原 |
| 1.2 ZP-OFDM回环 | 误差<1e-10 | ZP模式+overlap-add解调完全还原 |
| 1.3 导频插入/提取 | 导频值和数据值均一致 | comb_4导频模式回环 |

**2. SC-FDE（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1 SC-FDE CP回环 | 时域块和FFT块均与原始一致 | 分块CP插入→去CP→FFT验证 |

**3. OTFS（4项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 DFT方法回环 | 误差<1e-8 | ISFFT+Heisenberg→Wigner+SFFT |
| 3.2 Zak方法回环 | 误差<1e-8 | 2D-IFFT→2D-FFT |
| 3.3 DFT/Zak一致性 | 两种方法输出差异<1e-8 | 验证两种实现数学等价 |
| 3.4 DD域导频嵌入 | 导频值/数据值/保护区均正确 | 单脉冲导频+保护区+数据格点 |

**4. PAPR（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 PAPR计算 | 恒模≈0dB，OFDM>3dB | 不同信号的PAPR差异验证 |
| 4.2 PAPR削峰 | 削峰后PAPR≤目标+余量 | 硬限幅有效降低PAPR |

**5. 可视化（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 5.1 OFDM频谱 | 绘图无报错 | 时域/功率/PSD/CCDF四格图 |
| 5.2 OTFS DD域 | 绘图无报错 | 幅度/相位热图+导频标注 |

**6. 异常输入（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 6.1 空输入 | 9个函数均报错 | 覆盖全部核心函数 |

## 函数接口说明

### ofdm_modulate.m

**功能**：OFDM调制——频域符号经IFFT变换+CP/ZP插入生成时域信号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| freq_symbols | 1xM 数组 | 频域数据符号，M须为N的整数倍，每N个符号组成一个OFDM符号 |
| N | 正整数 | FFT/IFFT点数（子载波数），建议2的幂，默认 256 |
| cp_len | 非负整数 | CP/ZP长度（采样点数），默认 N/4 |
| cp_type | 字符串 | 前缀类型：'cp'(循环前缀，默认) 或 'zp'(补零) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xL 数组 | 时域OFDM信号 |
| params_out | 结构体 | 参数（供解调使用），含 `.N`、`.cp_len`、`.cp_type`、`.num_symbols`、`.symbol_len`(=N+cp_len) |

---

### ofdm_demodulate.m

**功能**：OFDM解调——去CP/ZP + FFT恢复频域符号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xL 数组 | 时域OFDM信号 |
| N | 正整数 | FFT点数，须与调制端一致 |
| cp_len | 非负整数 | CP/ZP长度，须与调制端一致 |
| cp_type | 字符串 | 前缀类型，须与调制端一致，默认 'cp' |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| freq_symbols | 1xM 数组 | 恢复的频域符号 |

---

### ofdm_pilot_insert.m

**功能**：OFDM频域导频插入（梳状、块状、离散、自定义）

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xM 数组 | 数据符号 |
| N | 正整数 | 子载波总数（FFT点数） |
| pilot_pattern | 字符串或数组 | 导频模式：'comb_4'(默认，每4个子载波插1个)、'comb_8'、'scattered_4'(离散，间隔4每符号偏移1)、'scattered_8'(离散，间隔8每符号偏移2)、'block'(首符号全导频)、或自定义 1xK索引数组 |
| pilot_values | 标量或1xK数组 | 导频符号值，默认 +1 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| symbols_with_pilot | 1xL 数组 | 含导频的频域符号，L为N的整数倍 |
| pilot_indices | 1xK 数组 | 导频子载波索引（1-based） |
| data_indices | 1xJ 数组 | 数据子载波索引 |

---

### ofdm_pilot_extract.m

**功能**：OFDM频域导频提取——分离导频和数据子载波

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| freq_symbols | 1xL 数组 | 含导频的频域符号，L为N的整数倍 |
| N | 正整数 | 子载波总数 |
| pilot_pattern | 字符串或数组 | 导频模式，须与插入端一致 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xM 数组 | 数据子载波符号 |
| pilot_rx | num_symbols x num_pilots 矩阵 | 接收到的导频值 |
| pilot_indices | 1xK 数组 | 导频子载波索引 |
| data_indices | 1xJ 数组 | 数据子载波索引 |

---

### scfde_add_cp.m

**功能**：SC-FDE分块CP插入——将数据分块，每块添加循环前缀

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xN 数组 | 数据符号序列 |
| block_size | 正整数 | 每块数据长度，默认 256 |
| cp_len | 正整数 | CP长度，默认 block_size/4 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xL 数组 | 加CP后的时域信号 |
| params_out | 结构体 | 参数，含 `.block_size`、`.cp_len`、`.num_blocks`、`.pad_len` |

---

### scfde_remove_cp.m

**功能**：SC-FDE去CP + 分块FFT——接收端前处理

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xL 数组 | 接收信号 |
| block_size | 正整数 | 每块数据长度，须与发端一致 |
| cp_len | 正整数 | CP长度，须与发端一致 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| freq_blocks | num_blocks x block_size 复数矩阵 | 频域块矩阵，每行为一个块的FFT结果，供MMSE均衡使用 |
| time_blocks | num_blocks x block_size 矩阵 | 时域块矩阵，去CP后的原始时域块 |

---

### otfs_modulate.m

**功能**：OTFS调制——DD域符号经ISFFT+Heisenberg变换生成时域信号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| dd_symbols | NxM 矩阵 或 1x(N*M) 向量 | DD域数据符号，N=多普勒维度(行)，M=时延维度(列) |
| N | 正整数 | 多普勒格点数（OFDM符号数），默认 8 |
| M | 正整数 | 时延格点数（子载波数），默认 32 |
| cp_len | 非负整数 | 整帧CP长度（采样点数），默认 M/4 |
| method | 字符串 | 实现方式：'dft'(默认，标准DFT) 或 'zak'(Zak域实现) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xL 数组 | 时域OTFS帧信号（含整帧CP） |
| params_out | 结构体 | 参数，含 `.N`、`.M`、`.cp_len`、`.method`、`.X_tf`(NxM时频域信号)、`.total_len` |

---

### otfs_demodulate.m

**功能**：OTFS解调——去整帧CP + Wigner变换 + SFFT恢复DD域符号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xL 数组 | 接收时域信号（含整帧CP） |
| N | 正整数 | 多普勒格点数，须与调制端一致 |
| M | 正整数 | 时延格点数，须与调制端一致 |
| cp_len | 非负整数 | 整帧CP长度，须与调制端一致 |
| method | 字符串 | 实现方式，须与调制端一致，默认 'dft' |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| dd_symbols | NxM 复数矩阵 | DD域符号 |
| Y_tf | NxM 矩阵 | 时频域信号（Wigner变换输出） |

---

### otfs_pilot_embed.m

**功能**：OTFS DD域导频嵌入——支持5种导频方案

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xK 向量 | 数据符号 |
| N | 正整数 | 多普勒格点数 |
| M | 正整数 | 时延格点数 |
| pilot_config | 结构体 | 导频配置。核心字段：`.mode`('impulse'(默认)/'multi_pulse'/'superimposed'/'sequence'/'adaptive')、`.pilot_value`(默认1)、`.guard_k`(多普勒保护格点数，默认2)、`.guard_l`(时延保护格点数，默认2)、`.pilot_k`(导频多普勒索引)、`.pilot_l`(导频时延索引)。模式特定字段：multi_pulse用`.pilot_positions`(Px2矩阵)；superimposed用`.pilot_power`(默认0.2)；sequence用`.seq_type`('zc'/'random')、`.seq_root`；adaptive用`.max_delay_spread`(默认3)、`.max_doppler_spread`(默认2) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| dd_frame | NxM 矩阵 | DD域帧 |
| pilot_info | 结构体 | 导频信息（供信道估计使用），含 `.mode`、`.positions`、`.values`、`.guard_mask` 等 |
| guard_mask | NxM 逻辑矩阵 | 保护/导频区掩模（1=保护/导频区，0=数据区） |
| data_indices | 1xK 数组 | 数据格点线性索引 |

---

### otfs_get_data_indices.m

**功能**：获取OTFS DD域数据格点索引（去除导频和保护区）

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| N | 正整数 | 多普勒格点数 |
| M | 正整数 | 时延格点数 |
| pilot_config | 结构体 | 导频配置（须与otfs_pilot_embed一致） |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_indices | 1xK 数组 | 数据格点线性索引 |
| guard_mask | NxM 逻辑矩阵 | 保护区掩模 |
| num_data | 整数 | 可用数据格点总数 |

---

### papr_calculate.m

**功能**：计算信号的峰均功率比(PAPR)

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xN 复数/实数数组 | 时域信号 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| papr_db | 标量 | PAPR值 (dB) |
| peak_power | 标量 | 峰值功率 |
| avg_power | 标量 | 平均功率 |

---

### papr_clip.m

**功能**：PAPR抑制——限幅或幅度缩放降低峰均功率比

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xN 复数数组 | 时域OFDM/OTFS信号 |
| target_papr_db | 正实数 | 目标PAPR上限 (dB)，默认 6 |
| method | 字符串 | 抑制方法：'clip'(默认，硬限幅)、'clip_filter'(限幅+滤波)、'scale'(幅度缩放/软限幅) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| clipped | 1xN 数组 | 限幅后信号 |
| clip_ratio | 0~1 标量 | 被限幅样本比例 |

---

### plot_ofdm_spectrum.m

OFDM信号频谱和时域波形可视化，绘制时域波形、瞬时功率、功率谱密度和PAPR CCDF四格图。输入：`signal`(时域信号)、`fs`(采样率，默认1)、`title_str`(标题)。

---

### plot_otfs_dd_grid.m

OTFS DD域格点可视化——显示数据/导频/保护区分布的幅度和相位热图。输入：`dd_frame`(NxM DD域帧)、`title_str`(标题)、`pilot_pos`([k,l]导频位置，可选)。

---

### test_multicarrier.m

单元测试脚本（14项），覆盖OFDM(CP/ZP)、导频插入提取、SC-FDE CP、OTFS(DFT/Zak)、DD域导频嵌入、PAPR计算/削峰、可视化和异常输入。
