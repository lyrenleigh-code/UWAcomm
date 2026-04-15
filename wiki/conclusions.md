---
tags: [结论, 技术决策]
updated: 2026-04-14
---

# 关键技术结论

累积记录项目中得出的技术结论，作为后续决策依据。

## 信道估计

1. **散布导频是精度决定性因素**：比算法选择影响大10-20dB
2. **BEM(DCT)+散布导频最优**：高fd下全面优于CE-BEM和DD-BEM
3. **接收端禁用发射端参数**：Oracle只作性能对比基准
4. **模块07 doppler_rate 修正后基线 (2026-04-12)**：fd≤5Hz 下 oracle α 补偿后 5dB+ 基本不变；fd=10Hz 是系统 ICI 极限（oracle 在高 SNR 非单调反弹 0.73%→3.65%，非算法问题）；DD-BEM 在 fd=5Hz@20dB 有 0.26% 判决误差传播地板

## 均衡

5. **FDE在长时延信道下全面优于TDE**：有5dB编码增益优势
6. **两级分离架构有效**：多普勒估计与精确定时解耦
7. **UAMP对BCCB无优势**：LMMSE per-frequency权重已最优，UAMP Turbo不稳定
8. **时变信道需 nv_post 实测噪声兜底 nv_eq (2026-04-14)**：BEM+散布导频有残余模型误差，高 SNR 时名义噪声远小于实际残差；MMSE 公式 (|h0|² + nv_eq) 过度去噪 → LLR 过度自信 → BER 在高 SNR 反弹。对策：从训练段用 h_tv 重构 y_pred，`nv_eq = max(nv_eq, nv_post_meas)`，该策略已在 OFDM V4.3 / SC-TDE V5.2 落地
9. **时变信道应跳过训练/CP 精估 (2026-04-14)**：训练段相位差 R_t1/R_t2 在 Jakes 多普勒扩散下被污染，训练精估 α 误差可达 88%；时变只用 LFM 相位粗估 + BEM 跟踪残余即可

## 信道模型

10. **Jakes ≠ 实际水声信道**：Jakes连续Doppler谱过度悲观，实际水声是Rician混合(离散强径+弱散射)
11. **Jakes连续谱确认为伪瓶颈(2026-04-13)**：6体制×6信道对比，离散Doppler下全部可工作

## 体制对比（2026-04-13 离散Doppler全体制对比）

12. **离散Doppler下全部6体制可工作**：disc-5Hz/Rician混合信道，高速体制5-10dB达0%BER
13. **SC-TDE在离散Doppler下逆袭**：Jakes ~48%@全SNR → disc-5Hz **0%@5dB+**，改善最大
14. **FH-MFSK唯一全信道可工作**：Jakes也在0dB即0%，跳频分集+能量检测天然抗Doppler
15. **OTFS在离散Doppler下完美工作**：含分数频移(max 5Hz)→0% BER@10dB+，BCCB模型精确

## OTFS 专项（2026-04-13~14）

16. **OTFS PAPR无法窗化降低**：PAPR=7.1dB根因IFFT随机叠加，CP-only和数据脉冲成形均无效
17. **Hann脉冲成形降旁瓣有效**：频谱PSL降13.8dB，模糊度多普勒PSL降33dB，分辨力展宽2.3x(水声可接受)
18. **OTFS冲激pilot导致时域尖刺**：pilot_value=sqrt(N_data)能量集中单DD点，产生32×sub_block的周期性峰值，PAPR达20dB
19. **ZC序列pilot显著降PAPR**：sequence模式PAPR降9.2dB(21→12dB)，但边缘延迟阴影落入数据区造成估计偏差

## 流式仿真框架（2026-04-15 P1 + P2 完成）

20. **方案 A passband 原生信道有效**：`gen_uwa_channel_pb` 直接在 passband 做多径（real FIR + 载波相位 tap）+ Jakes 时变 + spline Doppler，避免 channel 内部 down/up convert 的概念混乱；与 baseband 等价模型数学一致
21. **Doppler 漂移随帧长线性累积**：长帧 N_body × α 样本漂移，超过半个符号即解码失败；P1 用 oracle 补偿（chinfo 读 α 反 resample），P5/P6 应改用 LFM1/LFM2 相位差盲估计
22. **MATLAB R2025b 静态分析陷阱**：`uilabel(...).Layout.Row = X` 链式赋值让 MATLAB 把函数名误判为变量，整函数所有该名调用失败；必须 `lbl = uilabel(...); lbl.Layout.Row = X`
23. **流式帧检测 hybrid 优于纯阈值**（P2）：纯阈值检测对 Jakes 衰落首帧不鲁棒（peak 远低于 peak_max 被过滤）；hybrid 模式 = 首帧在预期窗口取绝对最大锚定 + 后续帧用 frame_len 预测 ±5% 窗口取本地最大，深衰落漏检不连锁
24. **FH-MFSK 软判决 LLR 显著改善衰落鲁棒性**（P2）：硬判决 1 位错即 CRC 挂；改用每符号 8 频率能量算 per-bit LLR `(max_e_b1 - max_e_b0) / median(e)` 送 Viterbi，配合 [7,5] 卷积码 dfree=5 能纠多位错
25. **FH-MFSK 无均衡，多径展宽 > 50% 符号时长即崩**：FFT 能量检测对 ISI 无能为力；延时展宽 1.5ms vs 符号 2ms (75%) 时连软 LLR 也救不回；OFDM/SC-FDE 自带均衡器才能扛大延时展宽
26. **downconvert LPF 暖机吃首帧**：64 阶 FIR 前 ~64 样本是瞬态会损伤 frame 1 HFM；流式 RX 必须**预填零给 LPF 暖机**（rx_pb_padded = [zeros(N_warmup), rx_pb]，再 trim 输出）
