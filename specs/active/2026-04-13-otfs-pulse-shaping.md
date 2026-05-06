---
project: uwacomm
type: task
status: active
created: 2026-04-13
updated: 2026-04-13
tags: [模块06, OTFS, 脉冲成形, PAPR, 模糊度函数]
---

# OTFS 通带 2D 脉冲整形

## Spec

### 目标

1. 测量当前 OTFS PAPR baseline，量化问题严重程度
2. 设计 DD 域 2D 发射/接收脉冲（替代矩形脉冲），改善延迟-多普勒模糊度旁瓣
3. 对比 CP-only 窗化方案的 PAPR 效果
4. 模糊度函数分析：量化不同脉冲的延迟/多普勒分辨力与旁瓣权衡

### 原因

当前 `otfs_modulate.m` 使用矩形脉冲（无窗函数），存在两个问题：
- **PAPR**：OTFS 均值 7.1dB（接近 OFDM 的 7.7dB），远高于 SC 的 3.6dB
- **模糊度旁瓣**：矩形脉冲的 sinc 型旁瓣在多普勒维 PSL=-13.4dB，影响信道估计精度

### 范围

**Phase 0: PAPR 测量** ✅ 完成
**Phase 1: 模糊度函数分析** ✅ 完成
**Phase 2: 双路径实现** ✅ 完成
**Phase 3: 时域窗化对比** ✅ 合并到 Phase 2
**Phase 4: 端到端 BER 验证** 🔴 待做

### 主要文件

| 文件 | 动作 | 状态 |
|------|------|------|
| `modules/06_MultiCarrier/src/Matlab/otfs_pulse.m` | 新建：5种脉冲生成 | ✅ V1.1 |
| `modules/06_MultiCarrier/src/Matlab/otfs_ambiguity.m` | 新建：2D模糊度函数 | ✅ V1.1 |
| `modules/06_MultiCarrier/src/Matlab/otfs_modulate.m` | 修改：pulse_type + cp_window双参数 | ✅ V4.0 |
| `modules/06_MultiCarrier/src/Matlab/otfs_demodulate.m` | 修改：RX不做窗补偿(均衡器处理) | ✅ V4.0 |
| `modules/06_MultiCarrier/src/Matlab/test_multicarrier.m` | 修改：新增3.9-3.12 | ✅ 22/22通过 |
| `modules/06_MultiCarrier/src/Matlab/measure_papr_baseline.m` | 新建：PAPR测量脚本 | ✅ |
| `modules/06_MultiCarrier/src/Matlab/analyze_otfs_ambiguity.m` | 新建：模糊度分析脚本 | ✅ |
| `modules/07_ChannelEstEq/src/Matlab/eq_otfs_lmmse.m` | 可能修改：脉冲纳入有效信道 | 🔴 待Phase 4验证 |

### 验收标准

| 指标 | 条件 | 状态 |
|------|------|------|
| PAPR baseline | 测量完成 | ✅ OTFS=7.1dB, OFDM=7.7dB, SC=3.6dB |
| 模糊度函数 | 5种脉冲量化表 | ✅ Hann PSL_nu=-46.9dB (rect:-13.4dB) |
| CP-only回环 | bit-exact | ✅ 误差=9e-16 |
| PAPR改善(CP-only) | ≥1dB | ❌ 仅-0.64dB（PAPR根因非CP边界） |
| 旁瓣改善(Hann) | ≥10dB | ✅ 13.8dB (rect:-17.8dB → hann:-31.6dB) |
| 向后兼容 | bit-exact | ✅ 默认参数与V3.0一致 |
| BER不退化 | 离散Doppler 0%@10dB+ | 🔴 待验证 |

## Log

- 2026-04-13: Spec 创建
- 2026-04-13: 讨论更新——加入DD域2D脉冲+模糊度函数+双路径
- 2026-04-13: Phase 0完成——OTFS PAPR=7.1dB (200次MC, QPSK, N=8 M=32)
- 2026-04-13: Phase 1完成——5种脉冲模糊度分析，Hann推荐(PSL降33dB, 分辨力2.3x可接受)
- 2026-04-13: Phase 2完成——双路径实现:
  - 路径A(CP-only): 实现完成, 回环bit-exact, 但PAPR改善不显著(-0.64dB)
  - 路径B(Hann数据脉冲): 频谱旁瓣降13.8dB, RX不做窗补偿(均衡器吸收)
- 2026-04-13: 关键发现:
  - **PAPR根因是IFFT随机叠加**，非CP边界跳变，窗化无法解决
  - **数据脉冲成形增加PAPR**(+4dB)因能量集中
  - **Hann窗真正价值是降旁瓣/ICI**，帮助信道估计和均衡
  - PAPR降低需要SLM/PTS/削峰等专用技术

## Result

### Phase 0-2 结论

**PAPR方面**：
- 当前OTFS PAPR均值7.1dB，与OFDM(7.7dB)接近
- CP-only窗化和数据脉冲成形均不能有效降低PAPR
- PAPR降低需要专用技术(已有papr_clip.m可用)

**旁瓣/ICI方面**（路径B核心价值）：
- Hann窗频谱PSL: -17.8dB → -31.6dB（改善13.8dB）
- 模糊度函数多普勒PSL: -13.4dB → -46.9dB（改善33dB）
- 多普勒分辨力展宽2.3x，对水声5Hz max Doppler完全可接受
- RX不做窗补偿，窗效应由均衡器自然吸收

**待验证**：Hann脉冲成形在离散Doppler信道下BER是否退化（Phase 4）

### Phase 4 实测（2026-05-04）

诊断脚本：`modules/13_SourceCode/src/Matlab/tests/OTFS/diag_phase4_hann_ber.m`
（rect / hann × {static, disc-5Hz, hyb-K5} × SNR={10,15} dB, seed=42）。

**BER 矩阵（%）**：

| Fading | rect@10dB | hann@10dB | rect@15dB | hann@15dB |
|--------|----------:|----------:|----------:|----------:|
| static | 0.000 | **11.147** | 0.000 | 1.885 |
| disc-5Hz | 0.000 | **14.755** | 0.000 | 3.554 |
| hyb-K5 | 0.269 | **12.924** | 0.000 | 2.262 |

**Acceptance criterion #4（BER 不退化 / 离散 Doppler 0%@10dB+）：0/6 PASS** 🔴

**根因证据**：hann 路径 loopback 验证误差 **2.78e+01**（rect 路径 1.26e-15 量级），
说明 TX 加 hann 时域窗后 mod→demod 已不闭环 → spec Phase 0-2 假设
"RX 不做窗补偿，窗效应由均衡器自然吸收"在端到端实测下不成立。
`eq_otfs_lmmse` 未将 pulse_type 纳入有效信道；`otfs_demodulate` 未传 pulse_type
反向加窗。

**决议（2026-05-04）：维持 rect 默认部署**

- Phase 0-2 PSL 改善 13.8 dB（频谱旁瓣维度）+ 模糊度多普勒 PSL 改善 33 dB
  保留作脉冲设计层面的理论参考；
- production 路径 OTFS 仍用 rect 脉冲（`bench_otfs_pulse_type='rect'` 默认）；
- Phase 4 BER 未达成 → 不部署 hann；
- 重启路径（如未来需要）：先修 RX 链路（`otfs_demodulate` + `eq_otfs_lmmse`
  传 `pulse_type` 实现反向加窗或纳入有效信道矩阵），再重跑 Phase 4。
- 解耦说明：PAPR 路径 ≠ Phase 4 路径。PAPR 通过 SLM/clip16/superimposed pilot
  达成（commit `c9c0601`，PAPR 16.8→8.9 dB），与 Hann 脉冲端到端 BER 失败独立。

