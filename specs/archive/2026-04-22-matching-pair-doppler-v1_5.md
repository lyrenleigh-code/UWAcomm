---
project: uwacomm
type: task
status: completed
created: 2026-04-22
updated: 2026-04-22
tags: [多普勒, 真实Doppler, poly_resample, matching_pair, 10_DopplerProc, 架构修复, V1.5]
---

# Doppler 仿真-补偿架构修复（Option 1 匹配对，V1.5）

## 背景

原 `gen_doppler_channel` V1.1 真实 Doppler 仿真与接收端通带 resample 补偿不能
精确互逆，|α|≥1e-2 时出现非单调 BER 跳变（α=+1.5e-2 BER 10%，+1.7e-2 0%，
+2e-2 20%）。用户指出关键物理直觉：**若每径共享 α，就应该等价于对整个信号
统一压缩/扩展**，应该完全可由单次 resample 逆反。

## 根因：Doppler 与多径的顺序错了（Option 2 vs Option 1）

### V1.4 采用 Option 2（Doppler 先、多径后）

```matlab
s_doppler = poly_resample(s, q, p);       % ← 先对 s 加 Doppler
for p: r[m-δ_p] += gain_p · s_doppler[m]  % ← 再加多径延迟
```

物理模型：
$$rx(t) = \sum_p \text{gain}_p \cdot s_{pb}((1+\alpha)(t - \tau_p))$$

接收端通带 resample with (1+α) 补偿后：
$$rx_{comp}(t) = \sum_p \text{gain}_p \cdot s_{pb}\big(t - (1+\alpha)\tau_p\big)$$

**多径延迟被缩放为 (1+α)·τ_p**，BEM 用 nominal `sym_delays` 估计时有 α% 位置
偏差 → 信道估计失配 → BER 跳变。

### V1.5 修正为 Option 1（多径先、Doppler 后）

```matlab
for p: y_mpath[m-δ_p] += gain_p · s[m]    % ← 先多径叠加（nominal 延迟）
y_dop = poly_resample(y_mpath, q, p);     % ← 再对整个信号做 Doppler
r = y_dop .* exp(j·2π·fc·α·n/fs);
```

物理模型：
$$rx(t) = y_{mpath}((1+\alpha)t), \quad y_{mpath}(t) = \sum_p \text{gain}_p \cdot s_{pb}(t-\tau_p)$$

接收端 resample 反转：
$$rx_{comp}(t) = y_{mpath}(t) = \sum_p \text{gain}_p \cdot s_{pb}(t - \tau_p)$$

**多径延迟完美恢复到 nominal τ_p**，BEM 用固定 `sym_delays` 正确估计 → BER = 0。

### 两种顺序对应的物理场景

- **Option 1（V1.5）**：RX 向 TX 移动 + 多径散射体静态 → Doppler 统一作用在总信号
- **Option 2（V1.4 错）**：TX 向 RX 移动 + 散射体静态 → 散射后 Doppler 独立（不物理常见）

`gen_uwa_channel`（老的"假 Doppler"）就是 Option 1 顺序，接收端 pipeline
按此设计；V1.4 的 Option 2 与接收端假设不匹配才是根因。

## 新增工具：poly_resample.m

`modules/10_DopplerProc/src/Matlab/poly_resample.m`（60 行）
- Kaiser 加窗 sinc polyphase FIR（和 MATLAB `resample` 同架构）
- 自逆性质：在同 L/β 参数下，`poly_resample(poly_resample(x,p,q), q,p) ≈ x`
- 与 MATLAB `resample` 数值等价验证：**NMSE -302~-309 dB**（机器精度）
- 带限信号自逆精度：NMSE -55 dB（sym_rate/fs ≪ 1 时）

## 验证结果

### 单元级（`test_poly_resample.m`）

| 测试 | NMSE | 判定 |
|------|:----:|:----:|
| p=q=1 identity | 0 | PASS |
| vs MATLAB resample | -302~-309 dB | PASS（机器精度匹配）|
| 带限信号 self-inverse | -55 dB | PASS |
| 宽带随机 self-inverse | -17 dB | 预期（Nyquist 附近 LPF 损失）|

### 集成级（50 节工况 α=±1.7e-2）

| α | v (kn) | oracle_passband BER |
|:---:|:---:|:---:|
| +1.2e-2 | +35 | **0** |
| +1.5e-2 | +43.7 | **0** |
| **+1.7e-2** | **+49.6** | **0** |
| +2.0e-2 | +58.3 | **0** |
| +3.0e-2 | +87.4 | **0** |
| 所有 −α 对称点 | | **0** |

**全 10 α 点（±5e-4 到 ±3e-2）BER = 0**，无需 force_zero band-aid。

### 架构演进

| 版本 | 关键改动 | oracle_passband 最差 BER |
|:----:|:--------:|:------------------------:|
| V1.1 | 原 dt 方向反 | ~50% 全崩 |
| V1.2 | dt=(1+α)/fs 方向修正 | -3e-2: 9.6%, +3e-2: 1.0% |
| V1.3 | α<0 输出长度扩展 | 同 V1.2 |
| V1.4 | poly_resample matching pair（Option 2）| -3e-2: 0.6%, +3e-2: 4.5% |
| **V1.5** | **Option 1：多径先 Doppler 后** | **全 0** ✓ |

## 交付物

1. `modules/10_DopplerProc/src/Matlab/poly_resample.m`（V1.0，新）
2. `modules/10_DopplerProc/src/Matlab/test_poly_resample.m`（新，单元测试）
3. `modules/10_DopplerProc/src/Matlab/gen_doppler_channel.m`（V1.1 → V1.5）
4. `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m`
   - 添加 `bench_use_real_doppler` 开关（切换 gen_uwa_channel vs gen_doppler_channel）
   - 添加 `bench_oracle_passband_resample` 开关（通带 oracle resample 路径）
   - 添加 `bench_alpha_override` 开关（灵敏度扫描用）
5. diag 脚本集（`tests/SC-FDE/diag_*.m`）：
   - `diag_passband_vs_baseband_oracle.m`
   - `diag_passband_real_doppler.m`
   - `diag_passband_real_big_alpha.m`
   - `diag_alpha_estimator_error_vs_oracle.m`
   - `diag_alpha_sensitivity.m`
   - `diag_50knots.m` / `diag_50knots_multi_seed.m`
6. 用户的 `tests/test_resample_roundtrip_nodoppler.m`（resample 自逆验证）

## 遗留

**baseline 和 oracle_baseband 在真实 Doppler 下仍 ~50% 崩**：rx_pb 载波在 fc·(1+α)
而接收端下变频用固定 fc → 基带有 fc·α 的 CFO 未补偿。下一步 C 方向：
- 让 baseline estimator 支持真实 Doppler（先通带 resample 再下变频），
  或给基带加 CFO 估计/旋转模块

## Log

- 2026-04-22 创建 spec + 实施 V1.2/1.3/1.4/1.5 多版本迭代
- 2026-04-22 验证：50 节 ±1.7e-2 BER = 0，±3e-2 BER = 0
