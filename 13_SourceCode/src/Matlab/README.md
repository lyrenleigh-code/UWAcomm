# 端到端仿真模块 (SourceCode)

六种通信体制的端到端仿真统一入口，提供公共函数（参数配置/发射链路/接收链路/信道模型）和逐体制独立测试脚本，采用统一的通带帧结构。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `sys_params` | 6体制统一参数配置（SC-TDE/SC-FDE/OFDM/OTFS/DSSS/FH-MFSK） | scheme, snr_db | params |
| `tx_chain` | 通用发射链路（编码+交织+调制+帧结构） | params | tx_signal, tx_info |
| `rx_chain` | 通用接收链路（均衡+译码+BER计算） | rx_signal, params, tx_info, ch_info | bits_out, rx_info |
| `gen_uwa_channel` | 简化水声信道仿真（多径时变+Jakes+多普勒伸缩+AWGN） | tx, ch_params | rx, ch_info |
| `adaptive_block_len` | 自适应块长选择（估计fd，计算最优FFT块长） | rx_signal, pilot, fs, fc, blk_range | blk_fft, fd_est, T_coherence |
| `main_sim_single` | 单SNR点6体制仿真脚本 | (直接运行) | 柱状图+BER表格 |

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
```

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

**SC-FDE** (V2.1):
- `test_scfde_static.m` — 静态信道SNR vs BER，通带实数帧+同步+跨块BCJR
- `test_scfde_timevarying.m` — 时变信道测试，含Jakes衰落+多普勒伸缩+重采样补偿+Turbo+DD信道更新

**OFDM** (V8/V2):
- `test_ofdm_e2e.m` — 静态信道SNR vs BER（V8，对齐SC-FDE V2通带帧结构）
- `test_ofdm_timevarying.m` — 时变信道测试（V2，含Turbo+DD信道更新）

**SC-TDE** (V3.1):
- `test_sctde_static.m` — 静态信道均衡方法对比（LE/DFE/BiDFE/Turbo）
- `test_sctde_timevarying.m` — 时变信道测试，RLS+PLL+BCJR Turbo均衡

**OTFS/DSSS/FH-MFSK**: 待开发。

## 内部函数

辅助函数（不建议外部直接调用）：
- 各体制 `tests/` 下的 `*.txt` — 仿真结果记录文件

## 依赖关系

- 依赖模块02 (ChannelCoding) 的 `conv_encode`、`viterbi_decode`、`siso_decode_conv`
- 依赖模块03 (Interleaving) 的 `random_interleave`、`random_deinterleave`
- 依赖模块07 (ChannelEstEq) 的 `eq_mmse_fde`、`eq_mmse_ic_fde`、`eq_dfe`、`soft_demapper`、`soft_mapper`、`ch_est_*` 等
- 依赖模块08 (Sync) 的 `gen_lfm`、`sync_detect`、`frame_assemble_*`、`frame_parse_*`
- 依赖模块09 (Waveform) 的 `pulse_shape`、`match_filter`、`upconvert`、`downconvert`
- 依赖模块10 (DopplerProc) 的 `doppler_coarse_compensate`、`comp_resample_spline`（时变信道测试）
- 依赖模块12 (IterativeProc) 的 `turbo_equalizer_scfde`、`turbo_equalizer_sctde`、`turbo_equalizer_scfde_crossblock`
