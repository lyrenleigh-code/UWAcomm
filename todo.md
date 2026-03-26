# UWAcomm 水声通信算法开发进度（v2.0框架）

> 框架参考：`framework/framework_v2.html`
> 覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

## 已完成模块

### 1. SourceCoding — 信源编解码
- [x] huffman_encode.m / huffman_decode.m（Huffman无损编码）
- [x] uniform_quantize.m / uniform_dequantize.m（均匀量化/反量化）
- [x] test_source_coding.m（14项测试）
- [x] README.md

### 2. ChannelCoding — 信道编解码
- [x] hamming_encode.m / hamming_decode.m（Hamming分组码）
- [x] conv_encode.m / viterbi_decode.m（卷积码 + Viterbi译码，硬/软判决）
- [x] turbo_encode.m / turbo_decode.m（Turbo码，Max-Log-MAP迭代）
- [x] ldpc_encode.m / ldpc_decode.m（LDPC码，Min-Sum BP）
- [x] test_channel_coding.m（22项测试）
- [x] README.md

### 3. Interleaving — 交织/解交织
- [x] block_interleave.m / block_deinterleave.m（块交织）
- [x] random_interleave.m / random_deinterleave.m（随机交织）
- [x] conv_interleave.m / conv_deinterleave.m（卷积交织）
- [x] turbo_encode.m 已更新调用 random_interleave
- [x] test_interleaving.m（19项测试，含Turbo集成验证）
- [x] README.md

### 4. Modulation — 符号映射/判决
- [x] qam_modulate.m / qam_demodulate.m（BPSK/QPSK/8QAM/16QAM/64QAM，Gray/自然映射，硬/软判决LLR）
- [x] mfsk_modulate.m / mfsk_demodulate.m（M-FSK比特↔频率索引）
- [x] plot_constellation.m（星座图绘制）
- [x] test_modulation.m（25项测试）
- [x] README.md

### 5. SpreadSpectrum — 扩频/解扩
- [x] gen_msequence.m / gen_gold_code.m / gen_walsh_hadamard.m / gen_kasami_code.m（4种扩频码）
- [x] dsss_spread.m / dsss_despread.m（DSSS直扩）
- [x] csk_spread.m / csk_despread.m（CSK循环移位键控）
- [x] mary_spread.m / mary_despread.m（M-ary组合扩频）
- [x] gen_hop_pattern.m / fh_spread.m / fh_despread.m（FH跳频）
- [x] det_dcd.m / det_ded.m（差分相关/能量检测器）
- [x] test_spread_spectrum.m（19项测试）
- [x] README.md

## 待开发模块

### 6. MultiCarrier — 多载波/多域变换
- [ ] OFDM调制：IFFT + CP插入
- [ ] OFDM解调：去CP + FFT
- [ ] OTFS调制：ISFFT + Heisenberg变换（N×M格点）
- [ ] OTFS解调：Wigner变换 + SFFT
- [ ] 测试 + 文档

### 7. ChannelEstEq — 导频 + 信道估计与均衡
- [ ] 导频插入/提取（时域训练序列 / 频域导频 / DD域嵌入导频）
- [ ] LS / OMP 信道估计
- [ ] SBL 稀疏贝叶斯学习估计
- [ ] SC-TDE均衡：PTR被动时反转 + DFE判决反馈均衡 + LMS/RLS
- [ ] SC-FDE均衡：分块FFT → MMSE → IFFT
- [ ] OFDM均衡：LS+插值 → 频域单抽头均衡
- [ ] OTFS均衡：DD域稀疏路径估计 {h_i, l_i, k_i}
- [ ] 测试 + 文档

### 8. Sync — 同步 + 帧组装/解析
- [ ] LFM/HFM同步序列生成
- [ ] 帧同步检测（匹配滤波）
- [ ] 定时同步
- [ ] 帧结构组装/解析
  - SC-TDE/DSSS/FH：前导 + 导频 + 数据 + 保护间隔
  - SC-FDE：前导码 + 分块CP + 数据 + 后导码
  - OFDM：前导码 + 每符号CP + 数据
  - OTFS：前导码 + 整帧CP + DD域数据
- [ ] 测试 + 文档

### 9. Waveform — 脉冲成形/上下变频
- [ ] 脉冲成形滤波（升余弦/根升余弦）
- [ ] 上变频（基带→通带）
- [ ] 下变频（通带→基带）
- [ ] 匹配滤波
- [ ] FSK波形生成（配合MFSK/FH模块）
- [ ] 测试 + 文档

### 10. DopplerProc — 多普勒估计与补偿（接收端特有）
- [ ] SC-TDE/SC-FDE：复自相关幅相联合（前后导码），两步补偿（幅度粗估→相位精估）
- [ ] OFDM：CP自相关 + 两步补偿（重采样→残余CFO旋转）
- [ ] OTFS：可弱化（DD域天然分辨路径多普勒）
- [ ] 通用：HFM粗估计 + ARD/FFCI精跟踪 + PLL载波相位锁定
- [ ] 压缩/扩展法宽带多普勒补偿
- [ ] 测试 + 文档

### 11. ArrayProc — 阵列接收预处理（v2.0新增，接收端特有）
- [ ] 阵元时延标定（bf_delay_calibration）
- [ ] 模式A：空时变采样重建（非均匀重采样，等效采样率M·fs）
- [ ] 模式B：DAS波束形成（时延对齐+相位补偿，SNR提升10log10(M) dB）
- [ ] 矢量水听器处理（声压+振速联合）
- [ ] 测试 + 文档

### 12. IterativeProc — 迭代处理（v2.0新增，接收端特有）
- [ ] SC-FDE Turbo均衡：SISO-MMSE均衡器 ⇌ SISO信道译码器(BCJR)，软干扰消除
- [ ] OTFS MP均衡器：DD域稀疏因子图，高斯近似消息传递(BP)，10~30次迭代
- [ ] 测试 + 文档

### 13. SourceCode — 端到端仿真
- [ ] 水声信道仿真器（多径 + 时变 + Doppler + 噪声）
- [ ] 端到端链路仿真脚本（tx_chain → channel → rx_chain）
- [ ] BER/FER性能评估与绘图
- [ ] 6种体制场景配置：
  - SC-TDE（浅海短延时）
  - SC-FDE（长延时，Turbo迭代可选）
  - DSSS（低SNR抗干扰）
  - OFDM（高速率宽带）
  - OTFS（快时变高移动）
  - FH-MFSK（抗窄带干扰）
- [ ] 阵列增强叠加测试
- [ ] 测试 + 文档

## 其他待办

- [x] framework_v2.html 模块编号更新（* → 10, ** → 11, † → 12）
- [ ] CLAUDE.md 更新（反映v2.0目录结构和12个模块）
- [ ] 各模块间跨模块依赖的路径管理统一方案（addpath / startup.m）
- [ ] 全模块集成测试

## 统计

| 指标 | 数值 |
|------|------|
| 已完成模块 | 5 / 13 |
| 待开发模块 | 8（含v2.0新增的模块11、12） |
| 已完成算法函数 | 48 个 .m 文件 |
| 已完成测试项 | 99 项 |
| 覆盖通信体制 | 6种 + 阵列增强 |
