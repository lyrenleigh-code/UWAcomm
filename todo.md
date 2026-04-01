# UWAcomm 水声通信算法开发进度（v5.0框架）

> 框架参考：`framework/framework_v5.html`
> Turbo均衡实现方案：`12_IterativeProc/turbo_equalizer_implementation.md`
> 覆盖6种通信体制：SC-TDE / SC-FDE / DSSS / OFDM / OTFS / FH-MFSK + 阵列增强

---

## 已完成模块（算法层，单模块已验证）

| 模块 | 文件夹 | 函数数 | 状态 |
|------|--------|--------|------|
| 01 信源编解码 | `01_SourceCoding/` | 5 | ✅ |
| 02 信道编解码 | `02_ChannelCoding/` | 11 | ✅ 含SISO(BCJR)/SOVA |
| 03 交织/解交织 | `03_Interleaving/` | 7 | ✅ |
| 04 符号映射/判决 | `04_Modulation/` | 6 | ✅ |
| 05 扩频/解扩 | `05_SpreadSpectrum/` | 15 | ✅ |
| 06 多载波+CP | `06_MultiCarrier/` | 16 | ✅ |
| 07 信道估计与均衡 | `07_ChannelEstEq/` | 25+ | ✅ 含MMSE-IC/MP/Turbo接口 |
| 08 同步+帧组装 | `08_Sync/` | 16 | ✅ |
| 09 脉冲成形/变频 | `09_Waveform/` | 8 | ✅ |
| 10 多普勒处理 | `10_DopplerProc/` | 14 | ✅ 单模块已验证 |
| 11 阵列预处理 | `11_ArrayProc/` | 8 | ✅ |
| 12 Turbo迭代调度 | `12_IterativeProc/` | 8 | ✅ 4体制Turbo收敛 |

## 模块13端到端集成 — 当前状态与待办

### 已完成

- [x] `gen_uwa_channel.m` — 简化水声信道（多径+Jakes衰落+多普勒+AWGN）
- [x] `sys_params.m` — 6体制统一参数配置
- [x] `tx_chain.m` — 通用发射链路（编码→交织→调制→RRC/OTFS成形→上变频）
- [x] `rx_chain.m` — 通用接收链路（下变频→匹配滤波→均衡→译码）
- [x] `main_sim_single.m` — 单SNR点仿真（静态信道6/6通过BER=0%）
- [x] `test_timevarying.m` — 时变信道测试（OTFS/FH-MFSK通过，其他4种退化）

### 核心待办：对齐framework_v5的完整接收链路

当前rx_chain缺失模块10集成（10-1粗多普勒+10-2残余CFO），且信道施加在通带而非基带。需重构为：

```
信道: shaped_baseband(复数) → gen_uwa_channel → rx_baseband(复数)

RX: rx_baseband(复数,过采样)
    → 10-1 粗多普勒估计+重采样补偿
    → RRC匹配滤波 + 下采样
    → 10-2 残余CFO校正
    → [去CP] → 7' 均衡 → [3' 解交织] → 2' 译码 → [Turbo迭代]

通带输出: shaped_baseband → upconvert → 通带实信号(DAC) [仅输出/可视化]
```

---

## 逐体制重构计划

### P1: SC-FDE（频域均衡，最干净的参考实现）

```
TX: info → conv_encode → interleave → QPSK → [加CP] → RRC↑sps
信道: shaped_bb → gen_uwa_channel(复数基带) → rx_bb
RX:
  10-1: 复自相关幅相联合(est_doppler_xcorr) → spline重采样(comp_resample_spline)
  匹配滤波: RRC match → ↓sps
  6': 去CP → FFT
  10-2: 残余CFO旋转(comp_cfo_rotate)
  7': MMSE-IC Turbo均衡(turbo_equalizer_scfde)
  输出: 硬判决比特
```

- [ ] 修改main_sim/rx_chain: 信道施加在基带
- [ ] 集成10-1: doppler_coarse_compensate(xcorr) — 调试接口适配
- [ ] 集成10-2: doppler_residual_compensate(cfo_rotate)
- [ ] 单独调试: static + slow + fast 三种衰落
- [ ] 验证: BER vs SNR曲线

### P2: OFDM（和SC-FDE类似，多普勒估计用CP自相关）

```
RX:
  10-1: CP自相关(est_doppler_cp) → spline重采样
  6': 去CP → FFT
  10-2: 残余CFO旋转
  7': MMSE-IC Turbo均衡(turbo_equalizer_ofdm)
```

- [ ] 集成10-1: doppler_coarse_compensate(cp)
- [ ] 单独调试: static + slow + fast

### P3: SC-TDE（时域均衡，PLL嵌入=10-2）

```
RX:
  10-1: xcorr(训练序列) → spline重采样
  匹配滤波 + 下采样
  [PTR空间聚焦(可选)]
  7': RLS-DFE+PLL Turbo均衡(turbo_equalizer_sctde)
       ↑ PLL = 10-2残余CFO补偿（嵌入均衡器内部）
```

- [ ] 集成10-1: doppler_coarse_compensate(xcorr)
- [ ] 验证PLL跟踪效果（10-2已嵌入eq_dfe）
- [ ] 单独调试: static + slow + fast

### P4: OTFS（DD域处理，10-1可弱化）

```
RX:
  10-1: 可弱化（DD域天然处理多普勒）
  6': Wigner+SFFT → DD域
  7': MP均衡 + BCJR Turbo(turbo_equalizer_otfs)
```

- [ ] 当前DD域基带处理已通过，保持不变
- [ ] 后续专项: OTFS通带实现（复数增益×实信号物理建模）
- [ ] 后续专项: 分数多普勒处理

### P5: DSSS（扩频增益+Rake接收）

```
RX:
  10-1: xcorr → spline重采样
  匹配滤波 + 下采样
  10-2: 残余相位校正
  5': 相关解扩
  7': 均衡(可选)
  4' → 3' → 2' 译码
```

- [ ] 集成10-1
- [ ] 集成10-2
- [ ] 单独调试

### P6: FH-MFSK（跳频抗衰落）

```
RX:
  10-1: xcorr → spline重采样
  10-2: 残余相位校正
  5': 解跳频
  4': 能量检测
  3' → 2' 译码
```

- [ ] 集成10-1
- [ ] 集成10-2
- [ ] 单独调试

---

## 集成验证

- [ ] 单SNR点测试: 6体制 × (static/slow/fast) 全部通过
- [ ] BER vs SNR曲线: main_sim_ber_curve.m（多SNR点，含编码增益对比）
- [ ] 时变信道基准: OTFS作为参照（最抗多普勒）
- [ ] 阵列增强叠加测试（可选）

---

## 已知问题

| 问题 | 状态 | 说明 |
|------|------|------|
| gen_uwa_channel复数增益×实信号 | 待解决 | 信道必须施加在复数基带，通带仅做上/下变频 |
| OTFS通带实现 | 搁置 | DD域基带处理已通过，通带需专项攻关 |
| doppler_coarse_compensate接口 | 待调试 | 矩阵维度错误，需适配当前信号格式 |
| 8'同步检测未集成 | 待开发 | 帧同步+细定时，当前用已知偏移替代 |
| 模块11阵列未集成 | 待开发 | 波束形成叠加，对下游透明 |

---

## 统计

| 指标 | 数值 |
|------|------|
| 已完成算法模块 | 12 / 13 |
| 模块13状态 | 静态信道6/6通过，时变信道待重构 |
| 已完成 .m 文件 | ~125 个 |
| 总提交数 | ~70 次 |

---

## 框架图演进

| 版本 | 文件 | 主要变更 |
|------|------|----------|
| v1-v4 | framework_v1~v4.html | 模块递增+PTR+Turbo参考 |
| **v5.0** | **framework_v5.html** | Turbo外信息迭代，交织纳入迭代环，10-2移出迭代环 |
