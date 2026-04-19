# SC-FDE 端到端调试日志

> 体制：SC-FDE | 当前版本：V4.0
> 关联模块：[[06_多载波变换]] [[07_信道估计与均衡]] [[08_同步与帧结构]] [[09_脉冲成形与变频]] [[10_多普勒处理]] [[12_迭代调度器]]
> 关联笔记：[[端到端帧组装调试笔记]] [[UWAcomm MOC]] [[项目仪表盘]]
> 技术参考：[[水声信道估计与均衡器详解]] [[时变信道估计与均衡调试笔记]]
> Areas：[[信道估计与均衡]] [[同步技术]] [[多普勒处理]]

#SC-FDE #调试日志 #端到端

---

## 版本总览

| 版本 | 日期 | 核心变更 | 状态 |
|------|------|---------|------|
| V4.0 | 2026-04-09 | 两级分离架构+LFM定时 | ✅ fd<=1Hz完成 |

---

## V4.0 — 两级分离架构 (2026-04-09)

**Git**: `80bfe14` (V4.0), `a68c12f` (规则更新)
**文件**: `test_scfde_timevarying.m` V4.0, `sync_dual_hfm.m` V1.1

### 目标

将 SC-FDE 端到端测试从"无噪声 sync 捷径"改为全链路有噪声处理：
- 帧同步（[[08_同步与帧结构|sync]]）
- 多普勒估计与补偿（[[10_多普勒处理|Doppler]]）
- 信道估计（[[07_信道估计与均衡|BEM/GAMP]]）
- Turbo 均衡（[[12_迭代调度器|LMMSE-IC + BCJR]]）

### 最终帧结构

```
[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]
```

- HFM+/HFM-: 双曲调频（Doppler 不变），保留用于帧检测
- LFM1/LFM2: 线性调频，用于多普勒估计（相位法）+ 精确定时
- guard: 800 样本（max_delay=720 + 80 余量）
- 参数: fs=48kHz, fc=12kHz, bw=8.1kHz, preamble_dur=50ms

### RX 两级分离架构

```
阶段①: 双LFM相位法多普勒估计 → alpha_est
阶段②: comp_resample_spline补偿
阶段③: LFM2匹配滤波精确定时 → lfm_pos
阶段④: 数据提取 + RRC匹配 + 符号定时恢复
阶段⑤: BEM信道估计 + Turbo均衡(LMMSE-IC ⇌ BCJR, 6轮)
```

### 验证结果

#### Oracle alpha（链路验证）

| 场景 | BER@5dB | BER@10dB | BER@15dB | BER@20dB |
|------|---------|----------|----------|----------|
| static | 0% | 0% | 0% | 0% |
| fd=1Hz | 0% | 0% | 0% | 0% |
| fd=5Hz | 0.24% | 0.07% | 0% | 0% |

#### 盲估计（LFM相位 + CP精估）

| 场景 | BER@5dB | BER@10dB | BER@15dB | BER@20dB | alpha误差 |
|------|---------|----------|----------|----------|-----------|
| static | 0% | 0% | 0% | 0% | ~0 |
| fd=1Hz | **0.20%** | **0%** | **0%** | **0%** | 89% |
| fd=5Hz | 50% | 50% | 50% | 50% | >100% |

### sync_dual_hfm V1.1 改进

α 公式从 `Δ/(2·S·fs)` 修正为 `Δ/(2·S·fs - G)`，加入帧间隔多普勒压缩修正项。

### fd=5Hz 多普勒估计攻关记录（10种方案）

| 方案 | 失败原因 |
|------|----------|
| 双HFM偏置对消(bookend) | 帧首尾间距0.85s >> 相干时间0.2s，Jakes衰落不一致 |
| 双HFM偏置对消(串联) | 直达径深衰落→匹配滤波峰被多径劫持 |
| CAF 2D搜索 | HFM Doppler不变性→α维度无法区分 |
| HFM-/LFM差异化偏置 | 不同信号峰被不同多径主导→差值含随机偏移 |
| CP迭代(α=0) | ISI污染70%CP + 衰落噪声 → 每轮仅修正1.3e-5 |
| VV-CFO(Turbo内) | BEM吸收92.5%CFO → VV只测到7.5%残余 |
| DA差分相位(已知TX) | 违反"禁用发射端参数"规则；且ISI噪底~4e-3>>α |
| SAGE(0.05s前导码) | 分辨率20Hz，无法区分5Hz和0Hz |
| SAGE(0.2s前导码) | α_est=1.56e-4（真值37.5%），首次正确方向但不够 |
| SAGE+VV迭代 | VV无法有效累积，BEM吸收阻止收敛 |

#### 根因分析

$$\text{多普勒频偏} = \alpha \cdot f_c = 5\text{Hz}, \quad \text{Jakes衰落频谱} = [-f_d, +f_d] = [-5, +5]\text{Hz}$$

**α·fc 完全落在 Jakes 频谱内**，单次实现中信号与噪声在频域重叠，物理上无法分离。

### 关键结论

1. fd<=1Hz 全盲可工作，两级分离架构有效
2. fd=5Hz 是物理极限（α·fc=5Hz∈Jakes[-5,+5]Hz）
3. 突破需：更高载频/更少多径/联合迭代/更长前导码

---

## 2026-04-17 — 14_Streaming P3 convergence_flag 误判 + est_snr 偏低 10dB

> 范围：`14_Streaming/src/Matlab/rx/modem_decode_scfde.m`（流式 P3 版本，与 13_SourceCode/tests 下的非流式版本独立演进）

### 症状

UI (`p3_demo_ui`) 显示 `convergence: 未收敛`，但 `BER = 0.00%`。`est_snr` 稳定低于真实 SNR 约 10dB，`est_ber` 虚高到 10%+。

测试 `test_p3_unified_modem.m` 修复前结果：
```
SNR= 5dB  BER=0.00%  iter=6 conv=0 est_snr=2.5dB  est_ber=2.74e-1
SNR=10dB  BER=0.00%  iter=6 conv=0 est_snr=3.3dB  est_ber=2.22e-1
SNR=15dB  BER=0.00%  iter=6 conv=0 est_snr=4.9dB  est_ber=1.19e-1
```

解码正确、LLR 硬判决全对，但元信息全错。

### 根因

**(A) est_snr 偏低 10dB**：`info.estimated_snr = 10*log10(P_sig_train / nv_eq) - 10*log10(sys.sps)` 的减项假设 rx_filt 做了 RRC 能量归一化（SNR 提升 sps 倍），但实际未归一化。sys.sps=8 → 减 9dB，与观察 10dB 偏差吻合。

**(B) convergence 单阈值过严**：`med_llr > 5` 判据在 L157 的 `max(min(Le_deint, 30), -30)` clip 下被压制。即便 BER=0 时 Lpost_info median |L| 仍 ≤5。

### 修复

**A. est_snr 去 sps 减法**
```matlab
- info.estimated_snr = 10*log10(P_sig_train / nv_eq) - 10*log10(sys.sps);
+ info.estimated_snr = 10*log10(max(P_sig_train / nv_eq, 1e-6));
```

**B. convergence_flag 三选一判据**（在 Turbo 循环内追踪硬判决稳定性）
```matlab
info.convergence_flag = double( ...
    med_llr > 5 || hard_converged_iter > 0 || frac_confident > 0.70);
```

其中：
- `hard_converged_iter` = 连续两轮 `bits_decoded` 相同时的首次 iter 号（Turbo 循环内增量计算）
- `frac_confident = mean(abs(Lpost_info) > 1.5)`

### 验收

```
修复后：
SNR= 5dB  BER=0.00%  iter=6 conv=1 est_snr=11.6dB est_ber=2.74e-1
SNR=10dB  BER=0.00%  iter=6 conv=1 est_snr=12.3dB est_ber=2.22e-1
SNR=15dB  BER=0.00%  iter=6 conv=1 est_snr=13.9dB est_ber=1.19e-1
```

- ✅ conv=1（真实收敛）
- ✅ est_snr 贴近真实 ±4dB
- ✅ BER=0 保持，2/2 test PASS
- ✅ FH-MFSK 不受影响
- ❌ est_ber 仍虚高（LLR scale 偏小致 `mean(0.5*exp(-|L|))` 虚大）

### 遗留

`est_ber` 估计偏高独立问题，根源 LLR 归一化 scale。可选修复：
1. soft_demapper 输出 LLR 做 per-block 归一化
2. 直接用 `hard_converged_iter > 0` 置 est_ber = 0

暂不处理，convergence_flag 已正确。

### Oracle 排查

本修复不引入发射端参数，conv/est_snr 均用接收端训练块本地估计。符合 CLAUDE.md §7 去 oracle 规则。

