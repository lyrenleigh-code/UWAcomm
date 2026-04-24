# Spec: 通带 resample 往返（无多普勒）诊断测试

- **日期**：2026-04-22
- **模块**：13_SourceCode / tests
- **相关**：`2026-04-20-alpha-compensation-pipeline-debug.md`、`2026-04-22-resample-negative-alpha-asymmetry.md`、上游讨论「为什么只是简单的压缩扩展会有这么大的误差」

## 背景

上次会话中用户追问通带/基带补偿的差异，以及「简单的压缩扩展」在无真实多普勒下的固有损耗。当前端到端测试均假设 `resample` 本身无损，但尚未有独立诊断证明该假设在 fs=48kHz、fc=12kHz、QPSK/RRC 的具体参数下成立。

若纯 resample 往返 (ratio 1530/1500 → 1500/1530，净比例 1.000) 在无多普勒条件下就引入可观 BER，则说明后续任何多普勒补偿链路在基带操作都会继承这一损耗下限，应改用通带补偿或细化 resample 选择（polyphase vs Farrow vs spline）。

## 目标

**隔离 MATLAB 原生 `resample` 函数的往返损耗，排除多普勒、均衡、同步等所有其他因素。**

不涉及估计器、补偿器、α 参数——**只有一次往返 resample，其它链路与 baseline 完全一致**。

## 设计

### 1. 测试脚本（新建）

路径：`modules/13_SourceCode/src/Matlab/tests/test_resample_roundtrip_nodoppler.m`

骨架复用 `main_sim_single.m`，改两处：

```matlab
% 1) 信道后、接收前插入往返 resample（仅对通带/非 OTFS 体制）
[rx_signal, ch_info] = gen_uwa_channel(tx_signal, params.channel);

% === 往返 resample：时间拉伸 ≈1.0333x → 压缩 ≈0.9677x，净比例 1.000 ===
rx_rs = resample(rx_signal, 1550, 1500);        % up by 1550/1500 ≈ 1.0333
rx_signal = resample(rx_rs, 1500, 1550);        % down by 1500/1550 ≈ 0.9677
% 长度对齐到原 rx_signal（MATLAB resample 舍入可能差 1-2 samples）
N_orig = length(tx_signal);  % 用 tx_signal 长度作为锚
if length(rx_signal) > N_orig
    rx_signal = rx_signal(1:N_orig);
elseif length(rx_signal) < N_orig
    rx_signal = [rx_signal, zeros(1, N_orig - length(rx_signal))];
end

% 2) 继续原流程
[bits_out, rx_info] = rx_chain(rx_signal, params, tx_info, ch_info);
```

### 2. 覆盖体制

**跳过 OTFS**（per `feedback_uwacomm_skip_otfs`；OTFS 走 DD-oracle 占位路径，无通带往返意义）。

测试 5 体制：SC-FDE、OFDM、SC-TDE、DSSS、FH-MFSK

### 3. 输出

| 列 | 含义 |
|------|------|
| scheme | 体制 |
| ber_baseline | `main_sim_single` 无 resample 的 BER（参考） |
| ber_roundtrip | 本测试插入 resample 对后的 BER |
| delta_pct | `(ber_roundtrip - ber_baseline) × 100` |
| status | `通过`/`退化`/`崩坏` |

判据：
- `delta < 0.5%`：通过（resample 损耗可忽略）
- `0.5% ≤ delta < 5%`：退化（resample 引入可观损耗，需对比不同 resample 方案）
- `delta ≥ 5%`：崩坏（MATLAB polyphase resample 在此参数下不可忽略，后续多普勒基带补偿需重选方案）

### 4. 可视化

- Fig 1：baseline vs roundtrip BER 柱状图对比（2 组 × 5 体制）
- Fig 2：某一体制（SC-FDE）的 rx_signal 原始 vs 往返后 的时域/频域对比（看是否出现边带能量泄漏、群延迟、幅度衰减）

### 5. 固定参数

- SNR = 10 dB
- 信道：默认 5 径静态，`doppler_rate = 0`，`fading_type = 'static'`
- `fs_passband = 48 kHz`，`fc = 12 kHz`
- rng(100+si) 保持与 `main_sim_single` 相同 seed

## 非目标

- 不做多 SNR 扫描
- 不测 Farrow/spline 替代 resample（另起 spec）
- 不改动任何模块函数

## 成功标准

1. 脚本运行后输出 5 行 baseline/roundtrip BER 对比表
2. 判据色块清晰
3. Fig 2 展示 resample 前后的信号差异（为后续分析留原始数据）

## 风险

- `resample` 默认 `cutoff=1/max(p,q)`、`n=10`；可能在 fc=12kHz 的通带成分上有可观滚降。若 baseline 本身 0%，roundtrip >5%，需进一步测试不同 `n` 参数。
- 信号长度漂移：MATLAB `resample(x,p,q)` 长度为 `ceil(length(x)*p/q)`；往返后可能差 1-2 samples，需与 `tx_signal` 长度对齐（见代码）。

## 后续工作

- 若损耗可观（>5%），开独立 spec 评估 resample 替代（Farrow/spline 在 comp_resample 中）+ 通带直接补偿路径
- 回写 `wiki/conclusions.md`：resample 在 UWAcomm 参数下的固有损耗基线
