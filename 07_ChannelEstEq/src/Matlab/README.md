# 信道估计与均衡模块 (ChannelEstEq)

水声通信系统信道估计与均衡算法库，覆盖10种信道估计算法（从LS到WS-Turbo-VAMP）和8种均衡器（按SC-TDE/SC-FDE/OFDM/OTFS四种体制分），含简化信道模型和可视化工具。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `ch_est_ls.m` | LS最小二乘估计 | 信道估计 |
| `ch_est_mmse.m` | MMSE估计（噪声正则化） | 信道估计 |
| `ch_est_omp.m` | OMP正交匹配追踪（自适应稀疏度停止） | 信道估计 |
| `ch_est_sbl.m` | SBL稀疏贝叶斯学习 | 信道估计 |
| `ch_est_amp.m` | AMP近似消息传递 | 信道估计 |
| `ch_est_gamp.m` | GAMP广义AMP（伯努利-高斯先验） | 信道估计 |
| `ch_est_vamp.m` | VAMP变分AMP（BG去噪+EM自适应） | 信道估计 |
| `ch_est_turbo_amp.m` | Turbo-AMP | 信道估计 |
| `ch_est_turbo_vamp.m` | Turbo-VAMP（标准VAMP框架+积极EM） | 信道估计 |
| `ch_est_ws_turbo_vamp.m` | WS-Turbo-VAMP（热启动，利用前帧先验） | 信道估计 |
| `eq_dfe.m` | DFE判决反馈均衡器 | SC-TDE均衡 |
| `eq_lms.m` | LMS自适应均衡器 | SC-TDE均衡 |
| `eq_rls.m` | RLS自适应均衡器 | SC-TDE均衡 |
| `eq_mmse_fde.m` | MMSE频域均衡（SC-FDE/OFDM通用） | 频域均衡 |
| `eq_ofdm_zf.m` | ZF迫零均衡 | OFDM均衡 |
| `ch_est_otfs_dd.m` | OTFS DD域嵌入导频信道估计 | OTFS |
| `eq_otfs_mp.m` | OTFS MP消息传递均衡（完整高斯BP） | OTFS均衡 |
| `eq_otfs_mp_simplified.m` | OTFS MP简化版（MMSE+SIC） | OTFS均衡 |
| `gen_test_channel.m` | 简化多径信道模型（sparse/dense/exponential） | 辅助 |
| `plot_channel_estimate.m` | 信道估计对比四格图 | 可视化 |
| `plot_equalizer_output.m` | 均衡结果星座图+BER对比 | 可视化 |
| `test_channel_est_eq.m` | 单元测试（16项） | 测试 |

## 模块功能与接口概述

模块7位于接收链路核心位置（RX流程中6'之后、10-2之前）。输入为去CP/逆变换后的频域或时域接收信号+导频/训练序列，输出为均衡后的数据符号估计。

发端模块7（导频插入）已在模块8(Sync)的帧组装中实现（时域训练序列），以及模块6(MultiCarrier)中实现（频域导频、DD域导频）。本模块负责收端的导频提取→信道估计→均衡。

数据流：
- 上游：模块6'(去CP+逆变换) → 本模块
- 下游：本模块 → 模块10-2(残余多普勒) → 迭代回环(可选) → 模块4'(符号判决)

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
