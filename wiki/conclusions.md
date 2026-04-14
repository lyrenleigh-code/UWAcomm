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

## 均衡

4. **FDE在长时延信道下全面优于TDE**：有5dB编码增益优势
5. **两级分离架构有效**：多普勒估计与精确定时解耦
6. **UAMP对BCCB无优势**：LMMSE per-frequency权重已最优，UAMP Turbo不稳定

## 信道模型

7. **Jakes ≠ 实际水声信道**：Jakes连续Doppler谱过度悲观，实际水声是Rician混合(离散强径+弱散射)
8. **Jakes连续谱确认为伪瓶颈(2026-04-13)**：6体制×6信道对比，离散Doppler下全部可工作

## 体制对比（2026-04-13 离散Doppler全体制对比）

9. **离散Doppler下全部6体制可工作**：disc-5Hz/Rician混合信道，高速体制5-10dB达0%BER
10. **SC-TDE在离散Doppler下逆袭**：Jakes ~48%@全SNR → disc-5Hz **0%@5dB+**，改善最大
11. **FH-MFSK唯一全信道可工作**：Jakes也在0dB即0%，跳频分集+能量检测天然抗Doppler
12. **OTFS在离散Doppler下完美工作**：含分数频移(max 5Hz)→0% BER@10dB+，BCCB模型精确

## OTFS 专项（2026-04-13~14）

13. **OTFS PAPR无法窗化降低**：PAPR=7.1dB根因IFFT随机叠加，CP-only和数据脉冲成形均无效
14. **Hann脉冲成形降旁瓣有效**：频谱PSL降13.8dB，模糊度多普勒PSL降33dB，分辨力展宽2.3x(水声可接受)
15. **OTFS冲激pilot导致时域尖刺**：pilot_value=sqrt(N_data)能量集中单DD点，产生32×sub_block的周期性峰值，PAPR达20dB
16. **ZC序列pilot显著降PAPR**：sequence模式PAPR降9.2dB(21→12dB)，但边缘延迟阴影落入数据区造成估计偏差
