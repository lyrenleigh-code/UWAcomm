# UWAcomm 水声通信算法开发进度（v5.0框架）

> 框架参考：`framework/framework_v5.html`
> Turbo均衡实现方案：`12_IterativeProc/turbo_equalizer_implementation.md`
> 覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

## 已完成模块

### 模块1. 01_SourceCoding — 信源编解码 (5个函数, 14项测试)
### 模块2. 02_ChannelCoding — 信道编解码 (11个函数, 22项测试)
- 含 `siso_decode_conv.m` V3（BCJR/MAP，支持max-log/log-map/sova三模式）
- 含 `sova_decode_conv.m` V1（软输出Viterbi）

### 模块3. 03_Interleaving — 交织/解交织 (7个函数, 19项测试)
### 模块4. 04_Modulation — 符号映射/判决 (6个函数, 25项测试)
### 模块5. 05_SpreadSpectrum — 扩频/解扩 (15个函数, 19项测试)

### 模块7. 07_ChannelEstEq — 信道估计与均衡 (25+个函数, 16项测试)
- 信道估计：LS/MMSE/OMP/SBL/AMP/GAMP/VAMP/Turbo-AMP/Turbo-VAMP/WS-Turbo-VAMP
- 基础均衡：DFE(RLS+PLL)/LMS/RLS/MMSE-FDE/ZF/OTFS-MP
- **Turbo均衡接口（v5新增）**：
  - `eq_mmse_ic_fde.m` V2 — 迭代LMMSE-IC频域均衡器（正确公式: x̃=x̄+IFFT(G·(Y-HX̄))）
  - `soft_demapper.m` V1 — 均衡输出→编码比特外信息LLR（含μ校正+先验减除+QPSK符号修正）
  - `soft_mapper.m` V1 — 后验LLR→软符号+残余方差（含LLR截断防var_x塌缩）
  - `eq_otfs_mp.m` V3 — OTFS MP均衡器（修复：BP先验项+阻尼+软估计输出）

### 模块6. 06_MultiCarrier — 多载波/多域变换+CP (16个函数)
- OFDM: ofdm_modulate/demodulate, ofdm_pilot_insert/extract
- SC-FDE: scfde_add_cp/remove_cp
- OTFS: otfs_modulate/demodulate, otfs_pilot_embed, otfs_get_data_indices
- PAPR: papr_calculate, papr_clip
- 可视化: plot_ofdm_spectrum, plot_otfs_dd_grid

### 模块8. 08_Sync — 同步+帧组装 (16个函数, 16项测试)
### 模块9. 09_Waveform — 脉冲成形/上下变频 (8个函数, 20项测试)

### 模块10. 10_DopplerProc — 多普勒估计与补偿 (14个函数)
- 粗估计：est_doppler_caf/cp/xcorr/zoomfft
- 粗补偿：comp_resample_spline(快速Catmull-Rom/精确Thomas), comp_resample_farrow(Lagrange)
- 残余补偿：comp_cfo_rotate, comp_ici_matrix
- 辅助：doppler_coarse_compensate, doppler_residual_compensate, gen_doppler_channel

### 模块11. 11_ArrayProc — 阵列接收预处理 (8个函数)
- 波束形成：bf_das(DAS), bf_mvdr(MVDR/Capon)
- 阵列处理：bf_delay_calibration, bf_nonuniform_resample
- 辅助：gen_array_config, gen_doppler_channel_array, plot_beampattern

### 模块12. 12_IterativeProc — Turbo均衡迭代调度（4个调度器+测试+文档）
- `turbo_equalizer_scfde.m` V7 — SC-FDE: LMMSE-IC ⇌ BCJR外信息迭代
- `turbo_equalizer_ofdm.m` V7 — OFDM: 同SC-FDE架构
- `turbo_equalizer_sctde.m` V7 — SC-TDE: RLS+单抽头ZF IC ⇌ BCJR+置信度门控
- `turbo_equalizer_otfs.m` V3 — OTFS: MP(BP) ⇌ BCJR双层迭代
- 支持三种译码模式：`decode_mode = 'max-log' / 'log-map' / 'sova'`
- 测试结果（4种体制全部通过不发散）：
  - SC-FDE: symBER 0%稳定 (SNR=3dB)
  - OFDM: symBER 0%稳定 (SNR=3dB)
  - SC-TDE: 49.8%→1.2%收敛 (SNR=8dB, 1000数据)
  - OTFS: 9.8%→0.8%收敛(3dB), 3.3%→0%(6dB)

## 待开发模块

#### 模块13. 13_SourceCode — 端到端仿真
- [ ] 水声信道仿真器（单路/阵列）
- [ ] 参数配置（sys_params_ofdm/scfde/otfs）
- [ ] 端到端链路（main_sim, tx_chain, rx_chain）
- [ ] 性能评估（BER/FER曲线, 多普勒RMSE, 信道估计NMSE）

## 框架图演进

| 版本 | 文件 | 主要变更 |
|------|------|----------|
| v1.0 | `framework_diagram.html` | 10个成对模块，4种体制 |
| v2.0 | `framework_v2.html` | 新增SC-FDE/OTFS，阵列/迭代模块 |
| v3.0 | `framework_v3.html` | 10拆分10-1/10-2，迭代回环 |
| v4.0 | `framework_v4.html` | PTR被动时反转，RLS-DFE(+PLL)，LLR↔符号接口 |
| **v5.0** | **`framework_v5.html`** | **Turbo外信息迭代重构：SISO-EQ↔3'/3↔SISO-DEC，交织纳入迭代环，10-2移出迭代环** |

## Turbo均衡开发中修复的关键问题

| 问题 | 根因 | 修复 |
|------|------|------|
| 迭代发散（V1-V5） | Viterbi硬输出无外信息，正反馈环 | 改用SISO(BCJR)，外信息交换 |
| MMSE-IC信号衰减 | 公式错：IFFT(W·Ỹ)丢失x̄项 | 正确LMMSE: x̃=x̄+IFFT(G·(Y-HX̄)) |
| BCJR译码全错 | QPSK映射bit=0→Re>0，LLR符号反 | soft_demapper/soft_mapper取负 |
| var_x→0致MMSE塌缩 | BCJR后验过大→tanh饱和→var_x≈0 | soft_mapper LLR截断±8，var_x≥noise_var |
| La过大→Le反号振荡 | 后验-Le远大于观测→外信息反向 | IC-only模式（La_eq=0） |
| SC-TDE RLS错误传播 | 每次迭代重训练RLS，坏样本污染全局权重 | 迭代2+改用单抽头ZF（IC后信道≈h(0)） |
| OTFS MP输出≈随机 | BP信念缺先验项+用硬判决算LLR | 加先验+阻尼+软估计输出 |

## 其他待办

- [ ] CLAUDE.md 更新
- [ ] 跨模块路径管理统一方案（startup.m）
- [ ] 全模块集成测试
- [ ] Turbo均衡EXIT图分析（收敛域可视化）

## 统计

| 指标 | 数值 |
|------|------|
| 已完成模块 | 12 / 13（仅模块13待开发） |
| 待开发模块 | 13(端到端集成) |
| 已完成 .m 文件 | ~120 个 |
| 已完成测试项 | ~170 项 |
| 总提交数 | ~65 次 |

## 模块与文件夹对照

| 编号 | 模块名 | 文件夹 | 状态 |
|------|--------|--------|------|
| 1 | 信源编解码 | `01_SourceCoding/` | 已完成 |
| 2 | 信道编解码 | `02_ChannelCoding/` | 已完成（含SISO/SOVA） |
| 3 | 交织/解交织 | `03_Interleaving/` | 已完成 |
| 4 | 符号映射/判决 | `04_Modulation/` | 已完成 |
| 5 | 扩频/解扩 | `05_SpreadSpectrum/` | 已完成 |
| 6 | 多载波变换+CP | `06_MultiCarrier/` | 已完成（16个函数） |
| 7 | 信道估计与均衡 | `07_ChannelEstEq/` | 已完成（含Turbo接口） |
| 8 | 同步+帧组装 | `08_Sync/` | 已完成 |
| 9 | 脉冲成形/变频 | `09_Waveform/` | 已完成 |
| 10 | 多普勒处理 | `10_DopplerProc/` | 已完成（14个函数） |
| 11 | 阵列预处理 | `11_ArrayProc/` | 已完成（8个函数） |
| 12 | Turbo迭代调度 | `12_IterativeProc/` | **已完成（4体制Turbo均衡）** |
| 13 | 端到端仿真 | `13_SourceCode/` | 待开发 |
