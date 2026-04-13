---
tags: [自动生成, 函数索引, UWAcomm]
last-sync: 2026-04-11
---

# UWAcomm 全模块函数索引

> 自动生成，勿手动编辑。共 13 个模块，151 个函数。

## 模块概览

| 模块 | 函数数 | 说明 |
|------|--------|------|
| [[01_SourceCoding\|01_SourceCoding]] | 4 | 水声通信发射链路最前端，负责原始数据的无损压缩（Huffman编码）和有损压缩（均匀量化），输出压缩 |
| [[02_ChannelCoding\|02_ChannelCoding]] | 10 | 为比特流添加冗余保护，覆盖分组码（Hamming）、卷积码（Viterbi）、迭代码（Turbo/L |
| [[03_Interleaving\|03_Interleaving]] | 6 | 打散突发错误以提升信道编码纠错效果，覆盖块交织、随机交织和卷积交织三种方案，广泛用于Turbo迭代回 |
| [[04_Modulation\|04_Modulation]] | 4 | 将比特流映射为复数调制符号（QAM/PSK）或频率索引（MFSK），接收端支持硬判决和软判决LLR输 |
| [[05_SpreadSpectrum\|05_SpreadSpectrum]] | 17 | 提供扩频处理能力，覆盖DSSS直接序列扩频、CSK循环移位键控、M-ary组合扩频、FH跳频四种方案 |
| [[06_MultiCarrier\|06_MultiCarrier]] | 15 | 将频域/DD域符号变换为时域发射信号，覆盖OFDM(CP/ZP)、SC-FDE和OTFS(DFT/Z |
| [[07_ChannelEstEq\|07_ChannelEstEq]] | 37 | 接收链路核心模块，覆盖静态/时变/OTFS信道估计、信道跟踪、时域/频域/OTFS均衡器、Turbo |
| [[08_Sync\|08_Sync]] | 20 | 发端帧组装和收端同步检测/帧解析的统一入口，支持SC-TDE/SC-FDE/OFDM/OTFS四种体 |
| [[09_Waveform\|09_Waveform]] | 8 | 发射链路末端和接收链路前端的物理层波形处理，负责脉冲成形/匹配滤波、数字上下变频、FSK波形生成和D |
| [[10_DopplerProc\|10_DopplerProc]] | 12 | 接收链路中的多普勒处理模块，分为10-1粗多普勒估计+重采样补偿（去CP前）和10-2残余CFO/I |
| [[11_ArrayProc\|11_ArrayProc]] | 6 | 可选的接收链路前端预处理模块，对多通道阵列信号进行波束形成或非均匀变采样重建，输出单路高质量信号供下 |
| [[12_IterativeProc\|12_IterativeProc]] | 5 | Turbo均衡迭代调度器，调度模块07(SISO均衡)、模块03(交织)和模块02(SISO译码)之 |
| [[13_SourceCode\|13_SourceCode]] | 7 | 六种通信体制的端到端仿真统一入口，提供公共函数（参数配置/发射链路/接收链路/信道模型/自适应块长） |

## 全部函数

| 函数 | 模块 | 说明 |
|------|------|------|
| `huffman_encode` | 01_SourceCoding | 对输入符号序列进行Huffman编码，输出比特流和码本 |
| `huffman_decode` | 01_SourceCoding | 根据码本对Huffman比特流进行解码，还原符号序列 |
| `uniform_quantize` | 01_SourceCoding | 对连续信号进行均匀量化，输出量化索引、量化电平和量化后信号 |
| `uniform_dequantize` | 01_SourceCoding | 根据量化索引和量化参数，反量化重建连续信号 |
| `conv_encode` | 02_ChannelCoding | 卷积编码器，支持任意码率1/n和约束长度 |
| `viterbi_decode` | 02_ChannelCoding | Viterbi译码器，支持硬判决和软判决 |
| `siso_decode_conv` | 02_ChannelCoding | BCJR(MAP) SISO卷积码译码器，输出外信息供Turbo均衡 |
| `sova_decode_conv` | 02_ChannelCoding | SOVA软输出Viterbi译码器，Turbo均衡对比用 |
| `hamming_encode` | 02_ChannelCoding | Hamming(2^r-1, 2^r-1-r)分组码编码 |
| `hamming_decode` | 02_ChannelCoding | Hamming伴随式译码，纠正单比特错误 |
| `turbo_encode` | 02_ChannelCoding | Turbo编码器（双RSC并行级联，码率1/3） |
| `turbo_decode` | 02_ChannelCoding | Turbo迭代译码器（Max-Log-MAP） |
| `ldpc_encode` | 02_ChannelCoding | LDPC编码器（Gallager正则构造） |
| `ldpc_decode` | 02_ChannelCoding | LDPC码置信传播(BP)迭代译码（Min-Sum近似） |
| `random_interleave` | 03_Interleaving | 基于伪随机置换对数据序列进行交织（Turbo均衡中最常用） |
| `random_deinterleave` | 03_Interleaving | 随机交织的逆操作 |
| `block_interleave` | 03_Interleaving | 块交织器——按行写入矩阵、按列读出，将突发错误打散 |
| `block_deinterleave` | 03_Interleaving | 块解交织器——按列写入矩阵、按行读出 |
| `conv_interleave` | 03_Interleaving | 卷积交织器——基于延迟递增的移位寄存器组，适合流式处理 |
| `conv_deinterleave` | 03_Interleaving | 卷积解交织器——延迟互补 |
| `qam_modulate` | 04_Modulation | QAM/PSK符号映射，支持BPSK/QPSK/8QAM/16QAM/64QAM |
| `qam_demodulate` | 04_Modulation | QAM/PSK硬判决 + 软判决LLR |
| `mfsk_modulate` | 04_Modulation | MFSK符号映射，比特序列转频率索引 |
| `mfsk_demodulate` | 04_Modulation | MFSK符号判决，频率索引转比特序列 |
| `gen_msequence` | 05_SpreadSpectrum | m序列生成 |
| `gen_gold_code` | 05_SpreadSpectrum | Gold码生成 |
| `gen_walsh_hadamard` | 05_SpreadSpectrum | Walsh-Hadamard正交码矩阵 |
| `gen_kasami_code` | 05_SpreadSpectrum | Kasami码小集合 |
| `dsss_spread` | 05_SpreadSpectrum | DSSS直接序列扩频 |
| `dsss_despread` | 05_SpreadSpectrum | DSSS相关解扩 |
| `csk_spread` | 05_SpreadSpectrum | CSK循环移位键控扩频 |
| `csk_despread` | 05_SpreadSpectrum | CSK解扩 |
| `mary_spread` | 05_SpreadSpectrum | M-ary组合扩频 |
| `mary_despread` | 05_SpreadSpectrum | M-ary解扩 |
| `gen_hop_pattern` | 05_SpreadSpectrum | 伪随机跳频图案生成 |
| `fh_spread` | 05_SpreadSpectrum | 跳频扩频 |
| `fh_despread` | 05_SpreadSpectrum | 去跳频 |
| `det_dcd` | 05_SpreadSpectrum | 差分相关检测器 |
| `det_ded` | 05_SpreadSpectrum | 差分能量检测器 |
| `plot_code_correlation` | 05_SpreadSpectrum | 扩频码相关性可视化 |
| `test_spread_spectrum` | 05_SpreadSpectrum | 单元测试 |
| `ofdm_modulate` | 06_MultiCarrier | OFDM调制 |
| `ofdm_demodulate` | 06_MultiCarrier | OFDM解调 |
| `ofdm_pilot_insert` | 06_MultiCarrier | 频域导频插入 |
| `ofdm_pilot_extract` | 06_MultiCarrier | 频域导频提取 |
| `scfde_add_cp` | 06_MultiCarrier | SC-FDE分块CP插入 |
| `scfde_remove_cp` | 06_MultiCarrier | SC-FDE去CP + 分块FFT |
| `otfs_modulate` | 06_MultiCarrier | OTFS调制 |
| `otfs_demodulate` | 06_MultiCarrier | OTFS解调 |
| `otfs_pilot_embed` | 06_MultiCarrier | DD域导频嵌入 |
| `otfs_get_data_indices` | 06_MultiCarrier | DD域数据格点索引 |
| `papr_calculate` | 06_MultiCarrier | 峰均功率比计算 |
| `papr_clip` | 06_MultiCarrier | PAPR抑制 |
| `plot_ofdm_spectrum` | 06_MultiCarrier | OFDM信号可视化 |
| `plot_otfs_dd_grid` | 06_MultiCarrier | OTFS DD域格点可视化 |
| `test_multicarrier` | 06_MultiCarrier | 单元测试 |
| `ch_est_ls` | 07_ChannelEstEq | LS最小二乘，频域导频处直接相除 |
| `ch_est_mmse` | 07_ChannelEstEq | MMSE正则化，利用噪声方差抑制噪声增强 |
| `ch_est_omp` | 07_ChannelEstEq | OMP正交匹配追踪，稀疏恢复 |
| `ch_est_sbl` | 07_ChannelEstEq | SBL稀疏贝叶斯学习 |
| `ch_est_gamp` | 07_ChannelEstEq | GAMP广义近似消息传递 |
| `ch_est_amp` | 07_ChannelEstEq | AMP近似消息传递 |
| `ch_est_vamp` | 07_ChannelEstEq | VAMP变分近似消息传递 |
| `ch_est_turbo_vamp` | 07_ChannelEstEq | Turbo-VAMP + BG先验 + EM自适应 |
| `ch_est_turbo_amp` | 07_ChannelEstEq | Turbo-AMP，伯努利-高斯先验 |
| `ch_est_ws_turbo_vamp` | 07_ChannelEstEq | 热启动Turbo-VAMP，利用前帧支撑概率 |
| `ch_est_bem` | 07_ChannelEstEq | BEM基扩展时变估计，支持CE/DCT基，V2向量化 |
| `ch_est_bem_dd` | 07_ChannelEstEq | 判决辅助迭代BEM(DD-BEM)，FDE均衡→硬判决→扩展导频→重估 |
| `ch_est_tsbl` | 07_ChannelEstEq | T-SBL时序稀疏贝叶斯，多快照联合稀疏+AR(1)时间相关 |
| `ch_est_sage` | 07_ChannelEstEq | SAGE/EM高分辨率参数估计，输出时延/增益/多普勒 |
| `ch_est_otfs_dd` | 07_ChannelEstEq | DD域嵌入导频信道估计，提取稀疏路径参数 |
| `ch_track_kalman` | 07_ChannelEstEq | 稀疏Kalman AR(1)逐符号跟踪 |
| `eq_rls` | 07_ChannelEstEq | RLS居中延迟自适应均衡，抽头甜点=4xL_h |
| `eq_lms` | 07_ChannelEstEq | LMS自适应均衡 |
| `eq_linear_rls` | 07_ChannelEstEq | RLS线性均衡+PLL，Turbo iter1用，输出LLR |
| `eq_dfe` | 07_ChannelEstEq | RLS-DFE+PLL+LLR输出，V3.1 |
| `eq_bidirectional_dfe` | 07_ChannelEstEq | 双向DFE，前向+后向联合判决抑制错误传播 |
| `eq_ofdm_zf` | 07_ChannelEstEq | OFDM ZF迫零，信道零点处噪声放大 |
| `eq_mmse_fde` | 07_ChannelEstEq | MMSE频域均衡，SC-FDE/OFDM通用 |
| `eq_mmse_ic_fde` | 07_ChannelEstEq | 迭代MMSE-IC频域均衡，Turbo核心 |
| `eq_mmse_tv_fde` | 07_ChannelEstEq | 时变MMSE-FDE，构建ICI矩阵求逆 |
| `eq_bem_turbo_fde` | 07_ChannelEstEq | BEM-Turbo迭代ICI消除FDE |
| `eq_otfs_mp` | 07_ChannelEstEq | OTFS消息传递(MP)均衡，高斯近似BP，V3 |
| `eq_otfs_mp_simplified` | 07_ChannelEstEq | OTFS简化MP，MMSE低复杂度近似 |
| `eq_ptrm` | 07_ChannelEstEq | PTR被动时反转，多通道匹配滤波空间聚焦 |
| `build_scattered_obs` | 07_ChannelEstEq | 从帧结构（训练+散布导频）构建BEM观测矩阵 |
| `soft_demapper` | 07_ChannelEstEq | 均衡输出 -> 编码比特外信息LLR |
| `soft_mapper` | 07_ChannelEstEq | 后验LLR -> 软符号估计+残余方差 |
| `llr_to_symbol` | 07_ChannelEstEq | LLR -> 软符号（译码器->均衡器接口） |
| `symbol_to_llr` | 07_ChannelEstEq | 均衡后符号 -> LLR（均衡器->译码器接口） |
| `interference_cancel` | 07_ChannelEstEq | 干扰消除，从接收信号减去已知干扰重构分量 |
| `MMSE` | 07_ChannelEstEq | IC（最小均方误差干扰消除） |
| `OTFS` | 07_ChannelEstEq | MP（OTFS消息传递均衡） |
| `gen_lfm` | 08_Sync | LFM线性调频信号生成 |
| `gen_hfm` | 08_Sync | HFM双曲调频信号生成（Doppler不变） |
| `gen_zc_seq` | 08_Sync | Zadoff-Chu序列生成（恒模，理想自相关） |
| `gen_barker` | 08_Sync | Barker码生成（低旁瓣，长度2~13） |
| `sync_detect` | 08_Sync | 粗同步检测（V2.0: 标准互相关 + 多普勒补偿二维搜索） |
| `cfo_estimate` | 08_Sync | CFO粗估计（互相关/Schmidl-Cox/CP法） |
| `sync_dual_hfm` | 08_Sync | 双HFM帧同步（偏置对消+多普勒联合估计, V1.0） |
| `velocity_spectrum` | 08_Sync | 速度谱扫描法多普勒估计（V1.0） |
| `timing_fine` | 08_Sync | 细定时同步（Gardner/Mueller-Muller/超前滞后 TED） |
| `phase_track` | 08_Sync | 相位跟踪（V1.0: PLL/判决反馈/Kalman联合跟踪） |
| `pll_carrier_sync` | 08_Sync | DD-PLL载波同步（V1.0） |
| `frame_assemble_sctde` | 08_Sync | SC-TDE帧组装 |
| `frame_parse_sctde` | 08_Sync | SC-TDE帧解析 |
| `frame_assemble_scfde` | 08_Sync | SC-FDE帧组装（含前后导码） |
| `frame_parse_scfde` | 08_Sync | SC-FDE帧解析 |
| `frame_assemble_ofdm` | 08_Sync | OFDM帧组装（双重复前导，供Schmidl-Cox） |
| `frame_parse_ofdm` | 08_Sync | OFDM帧解析（含CFO估计） |
| `frame_assemble_otfs` | 08_Sync | OTFS帧组装（推荐HFM前导） |
| `frame_parse_otfs` | 08_Sync | OTFS帧解析 |
| `plot_sync_spectrogram` | 08_Sync | 同步信号时频谱图可视化 |
| `pulse_shape` | 09_Waveform | 脉冲成形（上采样+RC/RRC/矩形/高斯滤波） |
| `match_filter` | 09_Waveform | 匹配滤波（成形滤波器时间反转共轭） |
| `upconvert` | 09_Waveform | 数字上变频（复基带转通带实信号） |
| `downconvert` | 09_Waveform | 数字下变频（通带转复基带，含LPF） |
| `gen_fsk_waveform` | 09_Waveform | FSK波形生成（频率索引转正弦波形，CPFSK） |
| `da_convert` | 09_Waveform | DA转换仿真（量化/理想模式） |
| `ad_convert` | 09_Waveform | AD转换仿真（量化/理想模式，含截断） |
| `plot_eye_diagram` | 09_Waveform | 眼图绘制 |
| `doppler_coarse_compensate` | 10_DopplerProc | 10-1粗多普勒补偿统一入口（估计+重采样一步完成）。 |
| `doppler_residual_compensate` | 10_DopplerProc | 10-2残余多普勒补偿统一入口（CFO旋转/ICI矩阵）。 |
| `est_doppler_caf` | 10_DopplerProc | 二维CAF搜索法多普勒估计（通用高精度离线方法）。 |
| `est_doppler_xcorr` | 10_DopplerProc | 复自相关幅相联合法多普勒估计（SC-FDE/SC-TDE推荐）。 |
| `est_doppler_cp` | 10_DopplerProc | CP自相关法多普勒估计（OFDM专用）。 |
| `est_doppler_zoomfft` | 10_DopplerProc | Zoom-FFT频谱细化法多普勒估计。 |
| `comp_resample_spline` | 10_DopplerProc | 三次样条重采样多普勒补偿。 |
| `comp_resample_farrow` | 10_DopplerProc | Farrow滤波器重采样多普勒补偿。 |
| `comp_cfo_rotate` | 10_DopplerProc | 残余CFO相位旋转补偿（10-2）。 |
| `comp_ici_matrix` | 10_DopplerProc | ICI矩阵补偿（10-2，OFDM高速场景）。 |
| `gen_doppler_channel` | 10_DopplerProc | 时变多普勒水声信道模型（alpha随时间波动）。 |
| `gen_uwa_channel_array` | 10_DopplerProc | 阵列水声信道仿真（M阵元ULA，精确空间时延）。 |
| `gen_array_config` | 11_ArrayProc | 阵列配置生成（ULA/UCA/自定义）。 |
| `gen_doppler_channel_array` | 11_ArrayProc | 多通道阵列信道仿真（每个阵元独立经历信道+精确空间时延）。 |
| `bf_das` | 11_ArrayProc | DAS（Delay-And-Sum）常规波束形成（时延对齐+相干叠加）。 |
| `bf_mvdr` | 11_ArrayProc | MVDR/Capon自适应波束形成（最小方差无失真响应）。 |
| `bf_delay_calibration` | 11_ArrayProc | 阵元时延标定（互相关法）。 |
| `bf_nonuniform_resample` | 11_ArrayProc | 空时联合非均匀变采样重建（等效采样率提升至M*fs）。 |
| `turbo_equalizer_scfde` | 12_IterativeProc | SC-FDE Turbo均衡（LMMSE-IC + BCJR外信息迭代）。 |
| `turbo_equalizer_ofdm` | 12_IterativeProc | OFDM Turbo均衡（与SC-FDE共用频域MMSE-IC架构）。 |
| `turbo_equalizer_sctde` | 12_IterativeProc | SC-TDE Turbo均衡（V8: DFE首次迭代 + 软ISI消除后续迭代 + BCJR）。 |
| `turbo_equalizer_scfde_crossblock` | 12_IterativeProc | SC-FDE/OFDM跨块Turbo均衡（多块LMMSE-IC + 跨块BCJR + DD信道更新）。 |
| `turbo_equalizer_otfs` | 12_IterativeProc | OTFS Turbo均衡（DD域MP-BP均衡 + BCJR译码）。 |
| `SC` | 13_SourceCode | FDE (tests/SC-FDE/) |
| `sys_params` | 13_SourceCode | 6体制统一参数配置（SC-TDE/SC-FDE/OFDM/OTFS/DSSS/FH-MFSK）。 |
| `tx_chain` | 13_SourceCode | 通用发射链路（编码+交织+调制+帧结构），6种体制统一入口。 |
| `rx_chain` | 13_SourceCode | 通用接收链路（均衡+译码+BER计算），6种体制统一入口。 |
| `gen_uwa_channel` | 13_SourceCode | 简化水声信道仿真（多径时变+Jakes衰落+宽带多普勒伸缩+AWGN）。 |
| `adaptive_block_len` | 13_SourceCode | 自适应块长选择（从接收信号估计多普勒扩展fd，计算最优FFT块长）。 |
| `main_sim_single` | 13_SourceCode | 单SNR点6体制仿真脚本（直接运行，输出BER柱状图+表格）。 |
