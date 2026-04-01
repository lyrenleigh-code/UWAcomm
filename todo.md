# UWAcomm 水声通信算法开发进度（v5.0框架）

> 框架参考：`framework/framework_v5.html`（需升级v6，见下方）
> Turbo均衡方案：`12_IterativeProc/turbo_equalizer_implementation.md`
> 覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 已完成算法模块（单模块已验证）

| 模块 | 文件夹 | 函数数 | 状态 |
|------|--------|--------|------|
| 01 信源编解码 | `01_SourceCoding/` | 5 | ✅ |
| 02 信道编解码 | `02_ChannelCoding/` | 11 | ✅ 含SISO(BCJR max-log/log-map/sova) |
| 03 交织/解交织 | `03_Interleaving/` | 7 | ✅ |
| 04 符号映射/判决 | `04_Modulation/` | 6 | ✅ |
| 05 扩频/解扩 | `05_SpreadSpectrum/` | 15 | ✅ |
| 06 多载波+CP | `06_MultiCarrier/` | 16 | ✅ |
| 07 信道估计与均衡 | `07_ChannelEstEq/` | 28+ | ✅ 含MMSE-IC/MP/BEM-Turbo/时变MMSE |
| 08 同步+帧组装 | `08_Sync/` | 16 | ✅ |
| 09 脉冲成形/变频 | `09_Waveform/` | 8 | ✅ |
| 10 多普勒处理 | `10_DopplerProc/` | 14 | ✅ |
| 11 阵列预处理 | `11_ArrayProc/` | 8 | ✅ |
| 12 Turbo迭代调度 | `12_IterativeProc/` | 8 | ✅ 4体制Turbo收敛 |

## 模块13 端到端集成 — 进度

### 已完成

- [x] 公共函数：gen_uwa_channel, sys_params, tx_chain, rx_chain, main_sim_single
- [x] 静态信道：6/6体制 BER=0% (SNR=10dB)
- [x] **P1 SC-FDE 完整framework_v5链路**
  - [x] 信道施加在基带复数信号
  - [x] 10-1粗多普勒：xcorr估计+spline重采样
  - [x] 10-2残余CFO：旋转校正
  - [x] 前后双导频帧结构
  - [x] 自适应块长+块中点H_est
  - [x] 跨块编码（编码和均衡解耦）
  - [x] BEM-Turbo ICI均衡（eq_bem_turbo_fde）
  - [x] 时变MMSE ICI矩阵均衡（eq_mmse_tv_fde）
  - [x] BER vs SNR曲线测试脚本

### SC-FDE时变信道性能（SNR=15dB）

| 衰落 | 无补偿 | 最终（跨块编码+自适应块长） | 最优块长 |
|------|--------|--------------------------|---------|
| static | 0% | **0%** | 1024 |
| slow(fd=1Hz) | 47.6% | **5.0%** | 512 |
| fast(fd=5Hz) | 49.2% | **0.1%** | 64 |

### 待完成

| 任务 | 优先级 | 说明 |
|------|--------|------|
| P2 OFDM | 高 | 类似SC-FDE，10-1用CP自相关替换 |
| P3 SC-TDE | 高 | RLS+PLL跟踪，时变信道自适应 |
| P4 OTFS | 中 | DD域已通过，通带实现待专项 |
| P5 DSSS | 中 | 扩频+Rake |
| P6 FH-MFSK | 中 | 跳频+能量检测 |
| SC-FDE slow进一步优化 | 低 | slow 5%仍有改善空间 |
| OTFS通带实现 | 低 | 复数增益×实信号物理建模 |
| BER vs SNR完整曲线 | 中 | 6体制×3衰落完整对比 |
| main_sim集成 | 低 | 合并各体制到统一入口 |

---

## 已知问题

| 问题 | 状态 | 说明 |
|------|------|------|
| gen_uwa_channel复数增益×实信号 | 已绕过 | 信道施加在基带复数信号，通带仅做上/下变频 |
| OTFS通带实现 | 搁置 | DD域基带处理已通过，通带需专项（二维脉冲成形） |
| SC-FDE slow衰落5% | 保留 | 跨块编码已是当前最优，进一步需BEM迭代或更强码 |
| doppler_coarse_compensate接口 | 保留 | 矩阵维度错误，当前用已知α直接补偿替代 |
| 8'同步检测未集成 | 待开发 | 帧同步+细定时 |
| 11阵列未集成 | 待开发 | 波束形成叠加 |

---

## 新增均衡器（本轮开发）

| 函数 | 模块 | 功能 |
|------|------|------|
| `eq_mmse_tv_fde.m` | 07 | 时变信道N×N ICI矩阵MMSE均衡 |
| `eq_bem_turbo_fde.m` | 07 | BEM基展开+迭代ICI消除+BCJR联合均衡 |

---

## 框架图需升级 v5→v6

framework_v5.html尚未反映以下新内容，需升级为v6：

| 新增内容 | 说明 |
|---------|------|
| 信道施加在基带 | 复数增益×复数信号，通带仅DAC/ADC |
| 跨块编码 | 编码和均衡解耦，一次编码→分块均衡→拼接LLR→一次译码 |
| 自适应块长 | static大块/slow中块/fast短块，匹配信道相干时间 |
| BEM-Turbo ICI均衡 | 时变信道下的高级均衡器选项 |
| 前后双导频帧结构 | 供xcorr多普勒估计 |
| 模块13目录结构 | common/ + tests/per-scheme/ |

---

## 统计

| 指标 | 数值 |
|------|------|
| 已完成算法模块 | 12 / 13 |
| 模块13状态 | P1(SC-FDE)完成，P2-P6待开发 |
| 已完成 .m 文件 | ~130 个 |
| 总提交数 | ~80 次 |

---

## 模块与文件夹对照

| 编号 | 模块名 | 文件夹 | 状态 |
|------|--------|--------|------|
| 1 | 信源编解码 | `01_SourceCoding/` | ✅ |
| 2 | 信道编解码 | `02_ChannelCoding/` | ✅ |
| 3 | 交织/解交织 | `03_Interleaving/` | ✅ |
| 4 | 符号映射/判决 | `04_Modulation/` | ✅ |
| 5 | 扩频/解扩 | `05_SpreadSpectrum/` | ✅ |
| 6 | 多载波变换+CP | `06_MultiCarrier/` | ✅ |
| 7 | 信道估计与均衡 | `07_ChannelEstEq/` | ✅ |
| 8 | 同步+帧组装 | `08_Sync/` | ✅ |
| 9 | 脉冲成形/变频 | `09_Waveform/` | ✅ |
| 10 | 多普勒处理 | `10_DopplerProc/` | ✅ |
| 11 | 阵列预处理 | `11_ArrayProc/` | ✅ |
| 12 | Turbo迭代调度 | `12_IterativeProc/` | ✅ |
| 13 | 端到端仿真 | `13_SourceCode/` | P1完成,P2-P6进行中 |
