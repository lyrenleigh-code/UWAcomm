# 同步+帧组装模块 (Sync)

水声通信系统同步与帧结构算法库，覆盖4种同步序列生成、粗同步检测、CFO粗估计、细定时同步，以及SC-TDE/SC-FDE/OFDM/OTFS四种体制的帧组装与解析。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `gen_lfm.m` | LFM线性调频信号生成 | 序列生成 |
| `gen_hfm.m` | HFM双曲调频信号生成（Doppler不变） | 序列生成 |
| `gen_zc_seq.m` | Zadoff-Chu序列生成（恒模，理想自相关） | 序列生成 |
| `gen_barker.m` | Barker码生成（低旁瓣，长度2~13） | 序列生成 |
| `sync_detect.m` | 粗同步检测（滑动窗归一化互相关） | 同步 |
| `cfo_estimate.m` | CFO粗估计（互相关法/Schmidl-Cox/CP法） | 同步 |
| `timing_fine.m` | 细定时同步（Gardner/Mueller-Muller/超前滞后） | 同步 |
| `frame_assemble_sctde.m` | SC-TDE帧组装 | 帧结构 |
| `frame_parse_sctde.m` | SC-TDE帧解析 | 帧结构 |
| `frame_assemble_scfde.m` | SC-FDE帧组装（含前后导码） | 帧结构 |
| `frame_parse_scfde.m` | SC-FDE帧解析 | 帧结构 |
| `frame_assemble_ofdm.m` | OFDM帧组装（双重复前导,供Schmidl-Cox） | 帧结构 |
| `frame_parse_ofdm.m` | OFDM帧解析（含CFO估计） | 帧结构 |
| `frame_assemble_otfs.m` | OTFS帧组装（推荐HFM前导） | 帧结构 |
| `frame_parse_otfs.m` | OTFS帧解析 | 帧结构 |
| `test_sync.m` | 单元测试（16项） | 测试 |

## 模块功能与接口概述

模块8负责同步序列生成、帧结构组装（发端）和同步检测、CFO估计、细定时、帧解析（收端）。发端输入为数据符号+参数配置，输出为完整帧信号（含前导码+导频+数据+保护间隔）。收端输入为接收信号+帧信息，输出为同步位置、CFO估计值、提取的数据段和训练序列。支持SC-TDE/SC-FDE/OFDM/OTFS四种体制的帧结构。

## 四种同步序列对比

| 序列 | 长度 | 自相关 | 特点 | 推荐体制 |
|------|------|--------|------|----------|
| LFM | 可调 | 时宽带宽积TB决定旁瓣 | 通用，处理增益高 | SC-TDE/SC-FDE |
| HFM | 可调 | 类似LFM | Doppler不变性 | OTFS/移动场景 |
| Zadoff-Chu | 素数N | 理想（旁瓣=0） | 恒模,PAPR=0dB | OFDM |
| Barker | 2~13 | 旁瓣≤1 | 短码,简单 | 短帧/辅助同步 |

## 同步处理流程

```
接收信号 → 粗同步(sync_detect) → CFO粗估计(cfo_estimate) → 细定时(timing_fine)
           匹配滤波找前导位置    利用前导结构估计频偏        符号定时精调
```

### 粗同步
```matlab
[preamble, ~] = gen_lfm(fs, 0.01, 8000, 16000);
[start_idx, peak, corr] = sync_detect(received, preamble, 0.5);
```

### CFO估计
```matlab
% 互相关相位法
[cfo_hz, ~] = cfo_estimate(rx_preamble, ref_preamble, fs, 'correlate');
% Schmidl-Cox法（OFDM，需双重复前导）
[cfo_hz, ~] = cfo_estimate(rx_preamble, ref_preamble, fs, 'schmidl');
```

### 细定时
```matlab
[offset, ted] = timing_fine(filtered_signal, sps, 'gardner');
```

## 四种体制帧结构

### SC-TDE
```
| 前导码(LFM) | 保护 | 训练序列 | 数据符号 | 保护 |
```

### SC-FDE
```
| 前导码(LFM) | 保护 | 数据(分块,CP由模块6加) | 保护 | 后导码(LFM) |
```

### OFDM
```
| 前导码(ZC双重复) | 保护 | 数据(OFDM符号,CP由模块6加) |
```

### OTFS
```
| 前导码(HFM) | 保护 | 数据(DD域,整帧CP由模块6加) |
```

**注意：CP插入/去除统一在模块6(MultiCarrier)中处理。**

## 函数接口说明

### gen_lfm.m

**功能**：生成LFM（线性调频）信号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| fs | 正实数 | 采样率 (Hz) |
| duration | 正实数 | 信号持续时间 (秒) |
| f_start | 实数 | 起始频率 (Hz) |
| f_end | 实数 | 终止频率 (Hz)。上扫频：f_start < f_end；下扫频：f_start > f_end |
| amplitude | 实数 | 信号幅度，默认 1 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xN 实数数组 | LFM时域波形 |
| t | 1xN 数组 | 时间轴（秒） |

---

### gen_hfm.m

**功能**：生成HFM（双曲调频）信号，具有Doppler不变性

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| fs | 正实数 | 采样率 (Hz) |
| duration | 正实数 | 信号持续时间 (秒) |
| f_start | 正实数 | 起始频率 (Hz，必须为正数) |
| f_end | 正实数 | 终止频率 (Hz，必须为正数) |
| amplitude | 实数 | 信号幅度，默认 1 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xN 实数数组 | HFM时域波形 |
| t | 1xN 数组 | 时间轴（秒） |

---

### gen_zc_seq.m

**功能**：生成Zadoff-Chu (ZC) 序列

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| N | 正整数 | 序列长度，建议为奇素数以获得最佳相关性 |
| root | 正整数 | 根索引，1 <= root < N，须与N互素，默认 1 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| seq | 1xN 复数数组 | ZC复数序列，恒模 \|seq(n)\|=1 |
| N | 正整数 | 实际序列长度 |

---

### gen_barker.m

**功能**：生成Barker码（低旁瓣二进制同步码）

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| N | 整数 | 码长，支持 2/3/4/5/7/11/13，默认 13 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| code | 1xN 数组 | Barker码，值为 +1/-1 |
| N | 整数 | 实际码长 |

---

### sync_detect.m

**功能**：粗同步检测——匹配滤波寻找前导码起始位置

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| received | 1xM 实数/复数数组 | 接收信号 |
| preamble | 1xL 数组 | 前导码参考信号（由gen_lfm/gen_hfm/gen_zc_seq/gen_barker生成） |
| threshold | 0~1 实数 | 检测门限（归一化相关峰值门限），默认 0.5 |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| start_idx | 标量 | 检测到的前导起始位置索引，0表示未检测到 |
| peak_val | 0~1 标量 | 归一化相关峰值 |
| corr_out | 1x(M-L+1) 数组 | 完整的归一化相关输出 |

---

### cfo_estimate.m

**功能**：载波频偏(CFO)粗估计

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| received | 1xM 复数数组 | 接收信号，须已粗同步对齐 |
| preamble | 1xL 复数数组 | 前导码参考信号 |
| fs | 正实数 | 采样率 (Hz) |
| method | 字符串 | 估计方法：'correlate'(默认，互相关相位法)、'schmidl'(Schmidl-Cox法，需双重复前导)、'cp'(CP相关法，用于OFDM) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| cfo_hz | 标量 | 频偏估计值 (Hz) |
| cfo_norm | 标量 | 归一化频偏（相对于采样率） |

---

### timing_fine.m

**功能**：细定时同步——估计符号采样时刻的分数间隔偏移

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| signal | 1xM 复数/实数数组 | 匹配滤波后的基带信号，每符号sps个采样 |
| sps | 正整数 | 每符号采样数，须>=2 |
| method | 字符串 | 定时误差检测算法：'gardner'(默认，非数据辅助)、'mm'(Mueller-Muller，数据辅助)、'earlylate'(超前-滞后门) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| timing_offset | 标量 | 估计的定时偏移（采样数，分数值），范围 [-sps/2, sps/2) |
| ted_output | 1xK 数组 | 定时误差检测器(TED)的逐符号输出 |

---

### frame_assemble_sctde.m

**功能**：SC-TDE帧组装——前导 + 训练序列 + 数据 + 保护间隔

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xN 复数/实数 | 调制后数据符号序列 |
| params | 结构体 | 帧参数，字段：`.preamble_type`(默认'lfm')、`.preamble_len`(默认512)、`.fs`(默认48000)、`.fc`(默认12000)、`.bw`(默认8000)、`.training_len`(默认64)、`.guard_len`(默认128)、`.training_seed`(默认0) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| frame | 1xM 数组 | 组装后的完整帧 |
| info | 结构体 | 帧信息（供帧解析使用），含 `.preamble`、`.training`、`.data_start`、`.data_len`、`.total_len`、`.params` |

---

### frame_parse_sctde.m

**功能**：SC-TDE帧解析——同步检测 + 提取训练序列和数据

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| received | 1xM 数组 | 接收信号，可能含同步偏移和噪声 |
| info | 结构体 | 帧信息结构体（由 frame_assemble_sctde 生成） |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xN 数组 | 提取的数据符号 |
| training_rx | 1xL 数组 | 提取的训练序列 |
| sync_info | 结构体 | 同步信息，含 `.sync_pos`、`.sync_peak`、`.training_start`、`.data_start` |

---

### frame_assemble_scfde.m

**功能**：SC-FDE帧组装——前导码 + [分块数据+CP] + 后导码

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xN 数组 | 调制后数据符号序列 |
| params | 结构体 | 帧参数，字段：`.preamble_type`(默认'lfm')、`.preamble_len`(默认512)、`.fs`(默认48000)、`.fc/.bw`、`.block_size`(默认256)、`.cp_len`(默认64)、`.guard_len`(默认128)、`.training_seed`(默认0) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| frame | 1xM 数组 | 帧信号 |
| info | 结构体 | 帧信息，含 `.preamble`、`.postamble`、`.num_blocks`、`.block_size`、`.cp_len`、`.pad_len`、`.data_start`、`.data_len`、`.total_len`、`.params` |

---

### frame_parse_scfde.m

**功能**：SC-FDE帧解析——前后导码同步 + 数据段提取

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| received | 1xM 数组 | 接收信号 |
| info | 结构体 | 帧信息结构体（由 frame_assemble_scfde 生成） |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xN 数组 | 提取的数据符号（不含补零） |
| sync_info | 结构体 | 同步信息，含 `.sync_pos`、`.sync_peak`、`.data_start` |

---

### frame_assemble_ofdm.m

**功能**：OFDM帧组装——前导码(双重复结构,供Schmidl-Cox) + 数据符号

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xN 数组 | 频域数据符号 |
| params | 结构体 | 帧参数，字段：`.preamble_type`(默认'zc')、`.preamble_len`(默认256)、`.fs`(默认48000)、`.guard_len`(默认64)、`.num_subcarriers`(默认256) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| frame | 1xM 数组 | 帧信号 |
| info | 结构体 | 帧信息，含 `.preamble`、`.preamble_half`、`.data_start`、`.data_len`、`.total_len`、`.params` |

---

### frame_parse_ofdm.m

**功能**：OFDM帧解析——同步+CFO估计+数据提取

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| received | 1xM 数组 | 接收信号 |
| info | 结构体 | 帧信息结构体（由 frame_assemble_ofdm 生成） |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xN 数组 | 提取的数据段 |
| sync_info | 结构体 | 同步信息，含 `.sync_pos`、`.sync_peak`、`.cfo_hz`、`.cfo_norm`、`.data_start` |

---

### frame_assemble_otfs.m

**功能**：OTFS帧组装——前导码 + 数据（整帧CP由模块6处理）

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xN 数组 | DD域数据符号 |
| params | 结构体 | 帧参数，字段：`.preamble_type`(默认'hfm'，Doppler不变)、`.preamble_len`(默认512)、`.fs`(默认48000)、`.fc`(默认12000)、`.bw`(默认8000)、`.guard_len`(默认128) |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| frame | 1xM 数组 | 帧信号 |
| info | 结构体 | 帧信息，含 `.preamble`、`.data_start`、`.data_len`、`.total_len`、`.params` |

---

### frame_parse_otfs.m

**功能**：OTFS帧解析——同步检测 + 数据段提取

**输入参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| received | 1xM 数组 | 接收信号 |
| info | 结构体 | 帧信息结构体（由 frame_assemble_otfs 生成） |

**输出参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| data_symbols | 1xN 数组 | 提取的数据段 |
| sync_info | 结构体 | 同步信息，含 `.sync_pos`、`.sync_peak`、`.data_start` |

---

### plot_sync_spectrogram.m

同步信号时频谱图可视化（适合LFM/HFM等调频信号），绘制时域波形、频谱和STFT时频谱图。输入：`signal`(时域信号)、`fs`(采样率，默认48000)、`title_str`(标题)。

---

### test_sync.m

单元测试脚本（16项），覆盖同步序列生成、粗同步检测、CFO粗估计、细定时同步、四种体制帧回环和异常输入。

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\Sync\src\Matlab');
run('test_sync.m');
```

### 测试用例说明

**1. 同步序列生成（4项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 LFM | 长度正确，实信号 | 线性调频基本参数验证 |
| 1.2 HFM | 长度正确 | 双曲调频信号生成验证 |
| 1.3 ZC | 恒模，周期自相关旁瓣/峰值<1% | ZC序列的理想自相关特性 |
| 1.4 Barker | 长度=13，非周期自相关旁瓣≤1 | Barker码的低旁瓣特性 |

**2. 粗同步检测（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1 LFM无噪声 | 位置偏差≤1，峰值>0.9 | 已知偏移下精确检测 |
| 2.2 ZC有噪声 | 位置偏差≤2 | SNR≈6dB下的鲁棒同步 |

**3. CFO粗估计（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 互相关法 | 50Hz频偏估计误差<20Hz | 利用前导码两半相位差 |
| 3.2 Schmidl-Cox | 30Hz频偏估计误差<20Hz | 利用双重复前导结构 |

**4. 细定时同步（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 Gardner TED | 输出非空 | Gardner定时误差检测基本功能 |
| 4.2 三种TED | 三种方法均输出非空 | gardner/mm/earlylate全覆盖 |

**5. 帧组装/解析回环（4项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 5.1 SC-TDE | 同步成功，数据误差<1e-10 | LFM前导+训练+数据的完整回环 |
| 5.2 SC-FDE | 同步成功，数据长度一致 | 含前后导码的帧结构回环 |
| 5.3 OFDM | 同步成功，含CFO估计输出 | ZC双重复前导+Schmidl-Cox CFO |
| 5.4 OTFS | 同步成功，数据长度一致 | HFM前导（Doppler不变）帧回环 |

**6. 异常输入（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 6.1 异常输入 | 5项空输入/非法参数均报错 | 覆盖同步检测/CFO/定时/Barker/ZC |
