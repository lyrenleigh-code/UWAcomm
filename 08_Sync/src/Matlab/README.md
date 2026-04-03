# 同步与帧结构模块 (Sync)

发端帧组装和收端同步检测/帧解析的统一入口，支持SC-TDE/SC-FDE/OFDM/OTFS四种体制的帧结构。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `gen_lfm` | LFM线性调频信号生成 | fs, duration, f_start, f_end | signal, t |
| `gen_hfm` | HFM双曲调频信号生成（Doppler不变） | fs, duration, f_start, f_end | signal, t |
| `gen_zc_seq` | Zadoff-Chu序列生成（恒模，理想自相关） | N, root | seq, N |
| `gen_barker` | Barker码生成（低旁瓣，长度2~13） | N | code, N |
| `sync_detect` | 粗同步检测（滑动窗归一化互相关） | received, preamble, threshold | start_idx, peak_val, corr_out |
| `cfo_estimate` | CFO粗估计（互相关/Schmidl-Cox/CP法） | received, preamble, fs, method | cfo_hz, cfo_norm |
| `timing_fine` | 细定时同步（Gardner/Mueller-Muller/超前滞后） | signal, sps, method | timing_offset, ted_output |
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
% 生成前导码 + 粗同步
[preamble, ~] = gen_lfm(48000, 0.01, 8000, 16000);
[start_idx, peak, corr] = sync_detect(received, preamble, 0.5);

% SC-FDE帧组装/解析回环
[frame, info] = frame_assemble_scfde(data_symbols, params);
[data_rx, sync_info] = frame_parse_scfde(received, info);

% CFO估计（Schmidl-Cox法，OFDM场景）
[cfo_hz, ~] = cfo_estimate(rx_preamble, ref_preamble, fs, 'schmidl');
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- `plot_sync_spectrogram.m` — 同步信号时频谱图可视化（LFM/HFM调频信号）
- `test_sync.m` — 单元测试（16项，覆盖序列生成/同步检测/CFO/细定时/帧回环/异常输入）

## 依赖关系

- 模块8的 `cfo_estimate` CP法内部调用模块10 (DopplerProc) 的 `est_doppler_cp`
- CP插入/去除统一在模块06 (MultiCarrier) 中处理，本模块不处理CP
