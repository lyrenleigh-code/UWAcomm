# 多载波/多域变换模块 (MultiCarrier)

将频域/DD域符号变换为时域发射信号，覆盖OFDM(CP/ZP)、SC-FDE和OTFS(DFT/Zak)三种方案，含导频插入提取和PAPR计算/抑制。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| ofdm_modulate | OFDM调制（IFFT + CP/ZP插入） | freq_symbols, N, cp_len, cp_type | signal, params_out |
| ofdm_demodulate | OFDM解调（去CP/ZP + FFT） | signal, N, cp_len, cp_type | freq_symbols |
| ofdm_pilot_insert | 频域导频插入（梳状/块状/自定义） | data_symbols, N, pilot_pattern, pilot_values | symbols_with_pilot, pilot_indices, data_indices |
| ofdm_pilot_extract | 频域导频提取 | freq_symbols, N, pilot_pattern | data_symbols, pilot_rx, pilot_indices, data_indices |
| scfde_add_cp | SC-FDE分块CP插入 | data_symbols, block_size, cp_len | signal, params_out |
| scfde_remove_cp | SC-FDE去CP + 分块FFT | signal, block_size, cp_len | freq_blocks, time_blocks |
| otfs_modulate | OTFS调制（ISFFT+Heisenberg，DFT/Zak） | dd_symbols, N, M, cp_len, method | signal, params_out |
| otfs_demodulate | OTFS解调（Wigner+SFFT） | signal, N, M, cp_len, method | dd_symbols, Y_tf |
| otfs_pilot_embed | DD域嵌入导频+保护区 | data_symbols, N, M, pilot_config | dd_frame, pilot_info, guard_mask, data_indices |
| otfs_get_data_indices | DD域数据格点索引提取 | N, M, pilot_config | data_indices, guard_mask, num_data |
| papr_calculate | 计算峰均功率比(PAPR) | signal | papr_db, peak_power, avg_power |
| papr_clip | PAPR抑制（硬限幅/限幅滤波/幅度缩放） | signal, target_papr_db, method | clipped, clip_ratio |

## 使用示例

```matlab
%% CP-OFDM调制/解调
symbols = qam_modulate(bits, 16, 'gray');
[signal, params] = ofdm_modulate(symbols, 256, 64, 'cp');
freq_out = ofdm_demodulate(signal, 256, 64, 'cp');

%% OTFS调制/解调（DFT方法）
[signal, params] = otfs_modulate(dd_symbols, 8, 32, 8, 'dft');
[dd_out, Y_tf] = otfs_demodulate(signal, 8, 32, 8, 'dft');

%% PAPR计算与抑制
[papr_db, ~, ~] = papr_calculate(signal);
[clipped, ratio] = papr_clip(signal, 6, 'clip');
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- plot_ofdm_spectrum.m -- OFDM频谱+时域+PAPR CCDF可视化
- plot_otfs_dd_grid.m -- OTFS DD域格点幅度/相位热图
- test_multicarrier.m -- 单元测试（14项），覆盖OFDM(CP/ZP)、导频、SC-FDE、OTFS(DFT/Zak)、PAPR和异常输入

## 依赖关系

- 无外部模块依赖
- 上游：模块04（调制）或模块05（扩频）输出的符号
- 下游：模块07（信道/导频插入）或直接输出时域信号供信道传输
