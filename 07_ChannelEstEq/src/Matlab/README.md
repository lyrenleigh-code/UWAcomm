# 信道估计与均衡模块 (ChannelEstEq)

水声通信系统信道估计与均衡算法库，覆盖10种信道估计算法（从LS到WS-Turbo-VAMP）、8种基础均衡器和3种Turbo均衡接口函数，含简化信道模型和可视化工具。

## 文件清单

### 信道估计

| 文件 | 功能 |
|------|------|
| `ch_est_ls.m` | LS最小二乘估计 |
| `ch_est_mmse.m` | MMSE估计（噪声正则化） |
| `ch_est_omp.m` | OMP正交匹配追踪（自适应稀疏度停止） |
| `ch_est_sbl.m` | SBL稀疏贝叶斯学习 |
| `ch_est_amp.m` | AMP近似消息传递 |
| `ch_est_gamp.m` | GAMP广义AMP（伯努利-高斯先验） |
| `ch_est_vamp.m` | VAMP变分AMP（BG去噪+EM自适应） |
| `ch_est_turbo_amp.m` | Turbo-AMP |
| `ch_est_turbo_vamp.m` | Turbo-VAMP（标准VAMP框架+积极EM） |
| `ch_est_ws_turbo_vamp.m` | WS-Turbo-VAMP（热启动，利用前帧先验） |

### 基础均衡器

| 文件 | 功能 | 体制 |
|------|------|------|
| `eq_dfe.m` | DFE判决反馈均衡器(RLS+PLL) | SC-TDE |
| `eq_linear_rls.m` | 线性RLS均衡器（DFE反馈阶=0） | SC-TDE |
| `eq_lms.m` | LMS自适应均衡器 | SC-TDE |
| `eq_rls.m` | RLS自适应均衡器 | SC-TDE |
| `eq_mmse_fde.m` | MMSE频域均衡（非迭代版） | SC-FDE/OFDM |
| `eq_ofdm_zf.m` | ZF迫零均衡 | OFDM |
| `eq_otfs_mp.m` | OTFS MP消息传递均衡（完整高斯BP） | OTFS |
| `eq_otfs_mp_simplified.m` | OTFS MP简化版（MMSE+SIC） | OTFS |

### Turbo均衡接口（v5新增）

| 文件 | 功能 | 说明 |
|------|------|------|
| `eq_mmse_ic_fde.m` | **迭代MMSE-IC频域均衡器** | Tuchler公式，W=H*/(|H|²+σ²w/σ²x)，输出等效增益μ和噪声σ²ñ |
| `soft_demapper.m` | **软解映射器** | 均衡输出→编码比特外信息LLR，含μ校正+先验减除(Le=Lp-La) |
| `soft_mapper.m` | **软映射器** | 后验LLR→软符号x̄+残余方差σ²x，用于MMSE-IC权重自适应 |

### 辅助/旧版接口

| 文件 | 功能 |
|------|------|
| `eq_ptrm.m` | PTR被动时反转（多通道空间聚焦） |
| `eq_bidirectional_dfe.m` | 双向DFE（减少误差传播） |
| `llr_to_symbol.m` | LLR→软符号（tanh映射，向后兼容） |
| `symbol_to_llr.m` | 符号→LLR（基础版，不含μ校正） |
| `interference_cancel.m` | 干扰消除（旧版简单减法） |
| `ch_est_otfs_dd.m` | OTFS DD域嵌入导频信道估计 |
| `gen_test_channel.m` | 简化多径信道模型 |
| `plot_channel_estimate.m` | 信道估计对比四格图 |
| `plot_equalizer_output.m` | 均衡结果星座图+BER对比 |
| `test_channel_est_eq.m` | 单元测试（16项） |

## 模块功能与接口概述

模块7位于接收链路核心位置（RX流程中6'之后、10-2之前）。输入为去CP/逆变换后的频域或时域接收信号+导频/训练序列，输出为均衡后的数据符号估计。

**Turbo均衡模式**（v5框架）：在迭代回环 7'(SISO均衡)→3'→2'(SISO译码)→3→7' 中，本模块提供三个关键接口：
- `eq_mmse_ic_fde` — SISO均衡器（频域MMSE-IC，自适应权重随σ²x迭代更新）
- `soft_demapper` — 均衡输出→编码比特外信息（减先验La，避免信息自我强化）
- `soft_mapper` — 后验LLR→软符号+残余方差（供下一轮MMSE-IC权重计算）

数据流：
- 非迭代：模块6' → 本模块(估计+均衡) → 10-2 → 4' → 3' → 2'
- Turbo迭代：模块6' → 10-2 → **[7'(eq_mmse_ic_fde+soft_demapper) → 3' → 2'(siso_decode_conv) → 3(soft_mapper) → 7']** × 3~6次

## 信道估计算法对比

| 算法 | 复杂度 | 需要稀疏度K | 需要噪声方差 | 适用场景 |
|------|--------|------------|-------------|----------|
| LS | O(N) | 否 | 否 | 基准，全频带导频 |
| MMSE | O(N) | 否 | 是 | 低SNR改善 |
| OMP | O(K·M·N) | 可选(自适应停止) | 可选 | 稀疏度已知/可估 |
| SBL | O(iter·N²·M) | 否(自动学习) | 自动估计 | 稀疏度未知 |
| AMP | O(iter·M·N) | 否 | 否 | iid高斯测量矩阵 |
| GAMP | O(iter·M·N) | 否 | 是 | 非高斯先验 |
| VAMP | O(iter·N³) | 可选 | 是 | 一般测量矩阵 |
| Turbo-AMP | O(iter·M·N) | 可选 | 否 | AMP+BG先验 |
| Turbo-VAMP | O(iter·N³) | 是 | 是 | 当前最优(大N) |
| WS-Turbo-VAMP | O(iter·N³) | 是 | 是 | 慢时变信道追踪 |

## Turbo均衡接口说明（v5新增）

### eq_mmse_ic_fde.m

**功能**：迭代MMSE-IC频域均衡器（Tuchler公式），供Turbo均衡调度器调用

```matlab
[x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var)
```

| 参数 | 方向 | 说明 |
|------|------|------|
| Y_freq | 输入 | 频域接收信号 (1×N) |
| H_est | 输入 | 频域信道估计 (1×N) |
| x_bar | 输入 | 时域软符号先验 (1×N，首次迭代全0) |
| var_x | 输入 | 残余符号方差 (标量，首次迭代=1) |
| noise_var | 输入 | 噪声方差 σ²w |
| x_tilde | 输出 | 时域均衡输出 (1×N) |
| mu | 输出 | 等效增益 μ = mean(W·H) |
| nv_tilde | 输出 | 等效噪声方差 |

核心公式：`W[k] = H*/(|H|²+σ²w/σ²x)`, `Ỹ = Y-(1-WH)·X̄`, `x̃ = IFFT(W·Ỹ)`

### soft_demapper.m

**功能**：均衡输出→编码比特外信息LLR（含等效增益μ校正和先验减除）

```matlab
Le_eq = soft_demapper(x_tilde, mu, nv_tilde, La_eq, 'qpsk')
```

| 参数 | 方向 | 说明 |
|------|------|------|
| x_tilde | 输入 | 均衡后时域符号 (1×N) |
| mu, nv_tilde | 输入 | 来自eq_mmse_ic_fde的等效增益和噪声 |
| La_eq | 输入 | 编码比特先验LLR (1×2N, 首次=0) |
| Le_eq | 输出 | 编码比特**外信息**LLR (1×2N) |

核心公式：`Le = 2μ√2·Re(x̃)/σ²ñ - La`（关键：减先验，输出纯外信息）

### soft_mapper.m

**功能**：编码比特后验LLR→软符号估计+残余方差

```matlab
[x_bar, var_x] = soft_mapper(L_posterior, 'qpsk')
```

| 参数 | 方向 | 说明 |
|------|------|------|
| L_posterior | 输入 | 编码比特后验LLR (1×2N)，内部截断到±8防止var_x→0 |
| x_bar | 输出 | 软符号 E[x|Lpost] (1×N 复数) |
| var_x | 输出 | 残余方差 1-mean(|x̄|²)，下限0.01 |

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\ChannelEstEq\src\Matlab');
run('test_channel_est_eq.m');
```

### 测试用例说明

**1. 频域信道估计（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 LS | NMSE < 0 dB | 全频带导频LS估计基本正确 |
| 1.2 MMSE vs LS | MMSE NMSE ≤ LS+1dB | MMSE不差于LS |

**2. 稀疏信道估计（7项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1 OMP | NMSE < -5 dB | 稀疏度K=5正确检测 |
| 2.2 SBL | 打印NMSE | 自动学习稀疏度 |
| 2.3 AMP | 打印NMSE | 近似消息传递 |
| 2.4 GAMP | 打印NMSE | 伯努利-高斯先验 |
| 2.5 VAMP | NMSE < 0 dB | 标量精度VAMP+BG去噪 |
| 2.6 Turbo-VAMP vs WS | 打印对比 | VAMP框架+积极EM |
| 2.7 可视化 | 绘图无报错 | OMP/SBL/Turbo-VAMP对比四格图 |

**3. SC-TDE均衡（2项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 LMS | BER < 15% | 训练+判决引导自适应均衡 |
| 3.2 RLS | 打印BER | 收敛快于LMS |

**4. 频域均衡（3项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 MMSE-FDE | BER < 10% | 频域MMSE均衡 |
| 4.2 OFDM ZF | 打印频域NMSE | 迫零均衡 |
| 4.3 可视化 | 绘图无报错 | 星座图+BER对比 |

**5. 异常输入（1项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 5.1 空输入 | 3个函数均报错 | LS/MMSE/OMP空输入拒绝 |
