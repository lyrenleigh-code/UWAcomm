# UWAcomm 水声通信算法开发进度（v2.0框架）

> 框架参考：`framework/framework_v2.html`
> 覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

## 已完成模块

### 模块1. SourceCoding — 信源编解码
- [x] huffman_encode.m / huffman_decode.m（Huffman无损编码）
- [x] uniform_quantize.m / uniform_dequantize.m（均匀量化/反量化）
- [x] test_source_coding.m（14项测试）
- [x] README.md

### 模块2. ChannelCoding — 信道编解码
- [x] hamming_encode.m / hamming_decode.m（Hamming分组码）
- [x] conv_encode.m / viterbi_decode.m（卷积码 + Viterbi译码，硬/软判决）
- [x] turbo_encode.m / turbo_decode.m（Turbo码，Max-Log-MAP迭代）
- [x] ldpc_encode.m / ldpc_decode.m（LDPC码，Min-Sum BP）
- [x] test_channel_coding.m（22项测试）
- [x] README.md

### 模块3. Interleaving — 交织/解交织
- [x] block_interleave.m / block_deinterleave.m（块交织）
- [x] random_interleave.m / random_deinterleave.m（随机交织）
- [x] conv_interleave.m / conv_deinterleave.m（卷积交织）
- [x] turbo_encode.m 已更新调用 random_interleave
- [x] test_interleaving.m（19项测试，含Turbo集成验证）
- [x] README.md

### 模块4. Modulation — 符号映射/判决
- [x] qam_modulate.m / qam_demodulate.m（BPSK/QPSK/8QAM/16QAM/64QAM，Gray/自然映射，硬/软判决LLR）
- [x] mfsk_modulate.m / mfsk_demodulate.m（M-FSK比特↔频率索引）
- [x] plot_constellation.m（星座图绘制）
- [x] test_modulation.m（25项测试）
- [x] README.md

### 模块5. SpreadSpectrum — 扩频/解扩
- [x] gen_msequence.m / gen_gold_code.m / gen_walsh_hadamard.m / gen_kasami_code.m（4种扩频码）
- [x] dsss_spread.m / dsss_despread.m（DSSS直扩）
- [x] csk_spread.m / csk_despread.m（CSK循环移位键控）
- [x] mary_spread.m / mary_despread.m（M-ary组合扩频）
- [x] gen_hop_pattern.m / fh_spread.m / fh_despread.m（FH跳频）
- [x] det_dcd.m / det_ded.m（差分相关/能量检测器）
- [x] test_spread_spectrum.m（19项测试）
- [x] README.md

### 模块8. Sync — 同步+帧组装
- [x] gen_lfm.m / gen_hfm.m / gen_zc_seq.m / gen_barker.m（4种同步序列）
- [x] sync_detect.m（粗同步，滑动窗归一化互相关）
- [x] cfo_estimate.m（CFO粗估计，互相关法/Schmidl-Cox/CP法）
- [x] timing_fine.m（细定时，Gardner/Mueller-Muller/超前滞后门TED）
- [x] frame_assemble/parse_sctde.m（SC-TDE帧：前导+训练+数据+保护）
- [x] frame_assemble/parse_scfde.m（SC-FDE帧：前导+数据+后导）
- [x] frame_assemble/parse_ofdm.m（OFDM帧：ZC双重复前导+数据）
- [x] frame_assemble/parse_otfs.m（OTFS帧：HFM前导+数据）
- [x] test_sync.m（16项测试）
- [x] README.md

### 模块9. Waveform — 脉冲成形/上下变频
- [x] pulse_shape.m（RC/RRC/矩形/高斯四种脉冲成形）
- [x] match_filter.m（匹配滤波）
- [x] upconvert.m / downconvert.m（数字上下变频）
- [x] gen_fsk_waveform.m（FSK波形生成，CPFSK）
- [x] da_convert.m / ad_convert.m（DA/AD转换仿真）
- [x] test_waveform.m（20项测试，含Modulation联合测试和全链路验证）
- [x] README.md

## 待开发模块

### 阶段一（续）：打通单载波端到端链路

#### 模块7. ChannelEstEq — 导频 + 信道估计与均衡
- [ ] 导频插入/提取
  - 频域梳状/块状导频（OFDM）
  - DD域嵌入单脉冲导频+保护区（OTFS）
  - （时域训练序列已在模块8 SC-TDE帧中实现）
- [ ] 信道估计算法
  - LS 最小二乘
  - OMP 正交匹配追踪（稀疏信道）
  - SBL 稀疏贝叶斯学习
- [ ] 均衡算法
  - SC-TDE：DFE判决反馈 + LMS/RLS自适应
  - SC-FDE：MMSE频域均衡（接收去CP后的频域数据）
  - OFDM：频域单抽头均衡
  - OTFS：DD域稀疏路径估计
- [ ] 测试 + README

### 阶段二：多载波支持

#### 模块6. MultiCarrier — 多载波/多域变换 + CP
- [ ] OFDM调制：IFFT + CP插入
- [ ] OFDM解调：去CP + FFT
- [ ] SC-FDE：分块CP插入/去除
- [ ] OTFS调制：ISFFT + Heisenberg变换 + 整帧CP
- [ ] OTFS解调：去整帧CP + Wigner变换 + SFFT
- [ ] 测试 + README

### 阶段三：接收端增强

#### 模块10. DopplerProc — 多普勒估计与补偿
- [ ] SC-TDE/SC-FDE：复自相关幅相联合，两步补偿
- [ ] OFDM：CP自相关 + 两步补偿（重采样→残余CFO旋转）
- [ ] OTFS：可弱化（DD域天然分辨）
- [ ] 通用：HFM粗估计 + ARD/FFCI精跟踪 + PLL
- [ ] 压缩/扩展法宽带多普勒补偿
- [ ] 测试 + README

#### 模块11. ArrayProc — 阵列接收预处理
- [ ] 阵元时延标定
- [ ] 模式A：空时变采样重建（等效M·fs）
- [ ] 模式B：DAS波束形成（SNR提升10log10(M) dB）
- [ ] 矢量水听器处理（声压+振速联合）
- [ ] 测试 + README

#### 模块12. IterativeProc — 迭代处理
- [ ] SC-FDE Turbo均衡：SISO-MMSE ⇌ BCJR
- [ ] OTFS MP均衡器：DD域稀疏因子图BP
- [ ] 测试 + README

### 阶段四：集成

#### 模块13. SourceCode — 端到端仿真
- [ ] 水声信道仿真器
- [ ] 端到端链路仿真脚本
- [ ] BER/FER性能评估
- [ ] 6种体制场景配置 + 阵列增强
- [ ] 测试 + README

## 其他待办

- [x] framework_v2.html 模块编号更新
- [x] 配置卡RX流程与通用框架对齐
- [x] CP归属调整（从模块8移到模块6）
- [ ] CLAUDE.md 更新
- [ ] 跨模块路径管理统一方案（startup.m）
- [ ] 全模块集成测试

## 统计

| 指标 | 数值 |
|------|------|
| 已完成模块 | 7 / 13 |
| 待开发模块 | 6 |
| 已完成 .m 文件 | 67 个 |
| 已完成测试项 | 135 项 |
| 总代码行数 | ~7200 行 |
| 总提交数 | 32 次 |
| 覆盖通信体制 | 6种 + 阵列增强 |

## 模块与文件夹对照

| 编号 | 模块名 | 文件夹 | 状态 | .m文件数 |
|------|--------|--------|------|----------|
| 1 | 信源编解码 | `SourceCoding/` | 已完成 | 5 |
| 2 | 信道编解码 | `ChannelCoding/` | 已完成 | 10 |
| 3 | 交织/解交织 | `Interleaving/` | 已完成 | 7 |
| 4 | 符号映射/判决 | `Modulation/` | 已完成 | 6 |
| 5 | 扩频/解扩 | `SpreadSpectrum/` | 已完成 | 15 |
| 6 | 多载波变换+CP | `MultiCarrier/` | 待开发 | 0 |
| 7 | 信道估计与均衡 | `ChannelEstEq/` | **下一个** | 0 |
| 8 | 同步+帧组装 | `Sync/` | 已完成 | 16 |
| 9 | 脉冲成形/变频 | `Waveform/` | 已完成 | 8 |
| 10 | 多普勒处理 | `DopplerProc/` | 待开发 | 0 |
| 11 | 阵列预处理 | `ArrayProc/` | 待开发 | 0 |
| 12 | 迭代处理 | `IterativeProc/` | 待开发 | 0 |
| 13 | 端到端仿真 | `SourceCode/` | 待开发 | 0 |
