# 迭代调度器模块 (IterativeProc)

Turbo均衡迭代调度器，调度模块07(SISO均衡)、模块03(交织)和模块02(SISO译码)之间的外信息迭代循环，覆盖SC-FDE/OFDM/SC-TDE/OTFS四种体制，共7个文件。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `turbo_equalizer_scfde` | SC-FDE Turbo均衡（LMMSE-IC+BCJR外信息迭代，V7） | Y_freq, H_est, num_iter, snr_or_nv, codec_params | bits_out, iter_info |
| `turbo_equalizer_ofdm` | OFDM Turbo均衡（同SC-FDE架构） | Y_freq, H_est, num_iter, snr_or_nv, codec_params | bits_out, iter_info |
| `turbo_equalizer_sctde` | SC-TDE Turbo均衡（V8: DFE iter1 + 软ISI消除iter2+ + BCJR） | rx, h_est, training, num_iter, snr_or_nv, eq_params, codec_params | bits_out, iter_info |
| `turbo_equalizer_scfde_crossblock` | SC-FDE/OFDM跨块Turbo均衡（多块LMMSE-IC+跨块BCJR+DD信道更新） | Y_freq_blocks, H_est_blocks, num_iter, noise_var, codec_params | bits_out, iter_info |
| `turbo_equalizer_otfs` | OTFS Turbo均衡（MP-BP+译码） | Y_dd, H_dd, num_iter, noise_var, codec_params | bits_out, iter_info |

## 使用示例

```matlab
% SC-FDE Turbo均衡（频域，6次迭代）
codec = struct('gen_polys', [7,5], 'constraint_len', 3, 'interleave_seed', 7);
[bits, info] = turbo_equalizer_scfde(Y_freq, H_est, 6, 10, codec);

% SC-TDE Turbo均衡（时域，V8 DFE首次迭代）
eq_p = struct('num_ff', 21, 'num_fb', 10, 'lambda', 0.998);
[bits, info] = turbo_equalizer_sctde(rx, h_est, training, 5, 10, eq_p, codec);

% 跨块Turbo均衡（多块编码跨块BCJR）
[bits, info] = turbo_equalizer_scfde_crossblock(Y_blocks, H_blocks, 6, nv, codec);
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- `plot_turbo_convergence.m` — 收敛可视化（BER/MSE曲线+星座图对比）
- `test_iterative.m` — 单元测试（SC-FDE+OFDM，含BER收敛验证+可视化）

## 依赖关系

- 依赖模块07 (ChannelEstEq) 的 `eq_mmse_ic_fde`、`soft_demapper`、`soft_mapper`（LMMSE-IC均衡核心）
- 依赖模块07 (ChannelEstEq) 的 `eq_dfe`、`eq_linear_rls`（SC-TDE时域均衡）
- 依赖模块02 (ChannelCoding) 的 `siso_decode_conv`、`conv_encode`（BCJR译码+编码）
- 依赖模块03 (Interleaving) 的 `random_interleave`、`random_deinterleave`（迭代环内交织/解交织）
