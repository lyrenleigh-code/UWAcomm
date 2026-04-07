# 同步与帧结构模块 (Sync)

发端帧组装和收端同步检测/帧解析的统一入口，支持SC-TDE/SC-FDE/OFDM/OTFS四种体制的帧结构。
覆盖三层同步架构：帧同步（粗粒度）→ 符号同步（中粒度）→ 位同步/相位跟踪（精细粒度）。

## 对外接口

其他模块/端到端应调用的函数：

### Layer 1: 帧同步（粗粒度，ms量级）

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `gen_lfm` | LFM线性调频信号生成 | fs, duration, f_start, f_end | signal, t |
| `gen_hfm` | HFM双曲调频信号生成（Doppler不变） | fs, duration, f_start, f_end | signal, t |
| `gen_zc_seq` | Zadoff-Chu序列生成（恒模，理想自相关） | N, root | seq, N |
| `gen_barker` | Barker码生成（低旁瓣，长度2~13） | N | code, N |
| `sync_detect` | 粗同步检测（V2.0: 标准互相关 + 多普勒补偿二维搜索） | received, preamble, threshold, params | start_idx, peak_val, corr_out |
| `cfo_estimate` | CFO粗估计（互相关/Schmidl-Cox/CP法） | received, preamble, fs, method | cfo_hz, cfo_norm |

### Layer 2: 符号同步（中粒度，us量级）

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `timing_fine` | 细定时同步（Gardner/Mueller-Muller/超前滞后 TED） | signal, sps, method | timing_offset, ted_output |

### Layer 3: 位同步/相位跟踪（精细粒度，ns量级）

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `phase_track` | 相位跟踪（V1.0: PLL/判决反馈/Kalman联合跟踪） | signal, method, params | phase_est, freq_est, info |

### 帧组装/解析

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `frame_assemble_sctde` | SC-TDE帧组装 | data_symbols, params | frame, info |
| `frame_parse_sctde` | SC-TDE帧解析 | received, info | data_symbols, training_rx, sync_info |
| `frame_assemble_scfde` | SC-FDE帧组装（含前后导码） | data_symbols, params | frame, info |
| `frame_parse_scfde` | SC-FDE帧解析 | received, info | data_symbols, sync_info |
| `frame_assemble_ofdm` | OFDM帧组装（双重复前导,供Schmidl-Cox） | data_symbols, params | frame, info |
| `frame_parse_ofdm` | OFDM帧解析（含CFO估计） | received, info | data_symbols, sync_info |
| `frame_assemble_otfs` | OTFS帧组装（推荐HFM前导） | data_symbols, params | frame, info |
| `frame_parse_otfs` | OTFS帧解析 | received, info | data_symbols, sync_info |

## 使用示例

```matlab
% 生成前导码 + 粗同步（标准方法）
[preamble, ~] = gen_lfm(48000, 0.01, 8000, 16000);
[start_idx, peak, corr] = sync_detect(received, preamble, 0.5);

% 多普勒补偿同步（时变信道，V2.0新增）
dp = struct('method','doppler', 'fs',48000, 'fd_max',50, 'num_fd',21);
[start_idx, peak, corr] = sync_detect(received, preamble, 0.5, dp);

% SC-FDE帧组装/解析回环
[frame, info] = frame_assemble_scfde(data_symbols, params);
[data_rx, sync_info] = frame_parse_scfde(received, info);

% CFO估计（Schmidl-Cox法，OFDM场景）
[cfo_hz, ~] = cfo_estimate(rx_preamble, ref_preamble, fs, 'schmidl');

% 相位跟踪（PLL / 判决反馈 / Kalman）
[ph, freq, info] = phase_track(eq_symbols, 'pll', struct('Bn',0.02,'mod_order',4));
[ph, freq, info] = phase_track(eq_symbols, 'kalman', struct('Ts',1/48000));
corrected_symbols = info.corrected;
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- `plot_sync_spectrogram.m` — 同步信号时频谱图可视化（LFM/HFM调频信号）
- `test_sync.m` — 单元测试（V2.0: 23项，覆盖序列生成/同步检测/CFO/细定时/帧回环/多普勒补偿/相位跟踪/异常输入）

## 依赖关系

- 模块8的 `cfo_estimate` CP法内部调用模块10 (DopplerProc) 的 `est_doppler_cp`
- CP插入/去除统一在模块06 (MultiCarrier) 中处理，本模块不处理CP
