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
