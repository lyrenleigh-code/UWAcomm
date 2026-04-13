---
spec: specs/active/2026-04-13-otfs-pulse-shaping.md
created: 2026-04-13
status: phase2-done
---

# OTFS 脉冲成形 — 实现计划

## Phase 0: PAPR Baseline 测量

**目的**：量化当前问题严重程度，决定后续投入力度。

**快速脚本**（不入库，MATLAB 命令行跑）：
- 生成 QPSK DD 域随机数据（N=8, M=32）
- 分别用 `otfs_modulate`、`ofdm_modulate`、`pulse_shape(RRC)` 生成时域信号
- 用 `papr_calculate` 计算 PAPR
- 多次 Monte Carlo（100次）取统计量
- 输出：OTFS / OFDM / SC-FDE 的 PAPR 均值/最大值/CCDF

**判断**：如果 OTFS PAPR < 6dB 且与 SC-FDE 接近，脉冲成形优先级降低，转向 Phase 1 做理论分析。

## Phase 1: 模糊度函数分析

### 1.1 脉冲设计

**新建** `modules/06_MultiCarrier/src/Matlab/otfs_pulse.m`

```
function g = otfs_pulse(M, pulse_type, params)
% 生成 OTFS 发射/接收脉冲
% 输入:
%   M          - 子块长度（采样点）
%   pulse_type - 'rect' | 'rc' | 'rrc' | 'gaussian'
%   params     - 结构体
%     .rolloff   - 滚降系数 (rc/rrc, 默认 0.3)
%     .BT        - 带宽时间积 (gaussian, 默认 0.3)
% 输出:
%   g          - 1×M 脉冲向量（归一化能量=1）
```

候选脉冲：

| 脉冲 | 时域 | 频域 | 延迟分辨力 | 多普勒分辨力 | 旁瓣 |
|------|------|------|-----------|------------|------|
| 矩形 | 门函数 | sinc | 最优（1/M） | 最优（1/NT） | 高（-13dB） |
| 升余弦(RC) | RC 成形 | 带限平滑 | 略降 | 略降 | 低 |
| 根升余弦(RRC) | RRC 成形 | $\sqrt{RC}$ | 略降 | 略降 | TX+RX 匹配后最优 |
| 高斯 | 高斯窗 | 高斯 | 取决于 BT | 取决于 BT | 极低 |

### 1.2 模糊度函数计算

**新建** `modules/06_MultiCarrier/src/Matlab/otfs_ambiguity.m`

```
function [chi, tau_axis, nu_axis] = otfs_ambiguity(g, fs, tau_range, nu_range)
% 计算脉冲的 2D 模糊度函数
% chi(tau, nu) = | integral g(t) * conj(g(t-tau)) * exp(-j*2*pi*nu*t) dt |
% 输入:
%   g         - 1×M 脉冲波形
%   fs        - 采样率
%   tau_range - 延迟搜索范围（秒）[tau_min, tau_max]
%   nu_range  - 多普勒搜索范围（Hz）[nu_min, nu_max]
% 输出:
%   chi       - 2D 模糊度函数矩阵（归一化峰值=1）
%   tau_axis  - 延迟轴（秒）
%   nu_axis   - 多普勒轴（Hz）
```

### 1.3 分析脚本

对 4 种脉冲计算并可视化：
- 2D 等高线图/surface plot
- 零延迟切面 $\chi(0, \nu)$（多普勒分辨力）
- 零多普勒切面 $\chi(\tau, 0)$（延迟分辨力）
- 量化指标：主瓣 -3dB 宽度、最高旁瓣电平（dB）、积分旁瓣比

## Phase 2: DD 域 2D 脉冲实现

### 2.1 调制器修改

**修改** `modules/06_MultiCarrier/src/Matlab/otfs_modulate.m`

当前 Heisenberg 变换：
```matlab
% 逐子块 M-point IFFT（等价于矩形脉冲）
for n = 1:N
    sub_block = ifft(X_tf(n,:), M) * sqrt(M);
end
```

修改为：
```matlab
g_tx = otfs_pulse(M, pulse_type, pulse_params);
for n = 1:N
    sub_block = ifft(X_tf(n,:), M) * sqrt(M);
    sub_block = sub_block .* g_tx;  % 施加发射脉冲
end
```

- 新增可选参数 `pulse_type`（默认 `'rect'`，向后兼容）
- `'rect'` 时 `g_tx = ones(1,M)`，行为 bit-exact

### 2.2 解调器修改

**修改** `modules/06_MultiCarrier/src/Matlab/otfs_demodulate.m`

Wigner 变换中嵌入匹配接收脉冲：
```matlab
g_rx = otfs_pulse(M, pulse_type, pulse_params);
for n = 1:N
    sub_block = sub_block .* conj(g_rx);  % 匹配接收脉冲
    X_tf(n,:) = fft(sub_block, M) / sqrt(M);
end
```

### 2.3 均衡器适配

**可能修改** `modules/07_ChannelEstEq/src/Matlab/eq_otfs_lmmse.m`

脉冲成形后有效信道变为：
$$H_{\text{eff}}[k,l] = G_{rx}[k] \cdot H[k,l] \cdot G_{tx}[l]$$

其中 $G_{tx}$, $G_{rx}$ 是脉冲的频域表示。BCCB 对角化仍成立，但特征值需乘以脉冲频谱：
```matlab
D_eff = D .* (G_rx(:) * G_tx(:).');  % 脉冲加权
W = conj(D_eff) ./ (abs(D_eff).^2 + nv);
```

**注**：如果 $g_{tx} = g_{rx}$ 且能量归一化，且脉冲频谱平坦（如 RRC），影响可能很小。需实测验证是否必须修改均衡器。

## Phase 3: 时域窗化对比

### 3.1 CP-only 方案

仅对 CP 段施加 ramp-up，M 个 data 样本不动：
- 优点：零风险，不影响均衡器
- 缺点：只平滑 CP→data 过渡，data→下一 CP 跳变仍存在

### 3.2 Overlap-add 方案

子块间重叠相加：
- 每子块施加完整窗（含两端 ramp）
- 相邻子块 ramp-down + ramp-up 重叠相加
- 信号长度变化：`N*(M+cp_len) - (N-1)*ramp_len`
- 优点：彻底消除所有跳变
- 缺点：信号长度变化，端到端需适配

### 3.3 对比测试

- PAPR 降低量
- 频谱旁瓣抑制
- BER 影响（如有）

## Phase 4: 综合测试

### 单元测试（test_multicarrier.m 新增）

| 编号 | 名称 | 断言 |
|------|------|------|
| 3.9 | 模糊度函数矩形脉冲 | 峰值=1, sinc 旁瓣 ≈ -13dB |
| 3.10 | 模糊度函数 RRC 脉冲 | 旁瓣 < 矩形旁瓣 |
| 3.11 | 脉冲成形回环(RC) | `max(abs(dd_rx - dd_tx)) < 1e-6` |
| 3.12 | 脉冲成形回环(RRC) | 同上 |
| 3.13 | PAPR 对比 | 最佳脉冲 vs rect 改善 > 1dB |
| 3.14 | 向后兼容 | 默认参数 bit-exact |

### 端到端验证（test_otfs_papr_window.m）

- 脉冲类型 × rolloff sweep
- 静态 + 离散 Doppler 信道
- BER + PAPR + 模糊度函数可视化

## 执行顺序

```
Phase 0 (PAPR测量, ~10min)
  ↓ 决策点：是否继续
Phase 1.1-1.2 (otfs_pulse + otfs_ambiguity, 新建)
  ↓
Phase 1.3 (模糊度分析, 跑脚本出图)
  ↓ 选定最佳脉冲
Phase 2.1-2.2 (modulate/demodulate 修改)
  ↓
Phase 2.3 (均衡器适配, 实测决定)
  ↓
Phase 3 (时域窗化对比)
  ↓
Phase 4 (综合测试 + 文档)
```

## 风险

| 风险 | 概率 | 缓解 |
|------|------|------|
| PAPR baseline 本就很低 | 中 | Phase 0 先测，不盲目投入 |
| 非矩形脉冲破坏 BCCB | 中 | 脉冲加权纳入有效信道，BCCB 结构本身不变 |
| 均衡器需要大改 | 低 | RRC 频谱接近平坦，影响可能很小 |
| overlap-add 端到端适配复杂 | 中 | 与 CP-only 做 A/B 对比，择优 |
