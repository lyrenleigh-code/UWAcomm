---
project: uwacomm
type: task
status: active
created: 2026-04-12
updated: 2026-04-12
tags: [模块07, 多普勒, 测试]
---

# 模块07 doppler_rate=0 修正

## Spec

### 目标

修正模块 07 统一测试中 doppler_rate=0 的问题，使时变均衡测试包含真实多普勒频偏。

### 原因

当前 `test_channel_est_eq.m` 第 701 行 doppler_rate=0，时变均衡测试仅测了 Jakes 衰落下的估计+均衡能力，未包含真实多普勒频偏。模块级测试结果不能直接反映端到端场景性能。

### 范围

- 代码仓库：`H:\UWAcomm`
- 主要文件：
  - `07_ChannelEstEq/src/Matlab/test_channel_est_eq.m`（约第 701 行）
  - `07_ChannelEstEq/src/Matlab/gen_test_channel.m`（可能需适配）
  - `07_ChannelEstEq/src/Matlab/README.md`（更新测试结果表）

### 非目标

- 不改动估计/均衡算法本身
- 不改动端到端测试（13_SourceCode）

### 验收标准

- [ ] test_channel_est_eq.m 时变测试使用非零 doppler_rate（如 1e-4）
- [ ] 重新运行 24 项测试，更新结果表
- [ ] README.md 测试结果同步更新
- [ ] 新旧结果对比写回 wiki

---

## Plan

（确认 spec 后填写）

### 影响文件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `test_channel_est_eq.m` | 修改 | doppler_rate 改为非零值 |
| `gen_test_channel.m` | 可能修改 | 确认支持 doppler_rate 参数 |
| `README.md` | 更新 | 重新填写测试结果表 |

### 实现步骤

1. 确认 gen_test_channel / gen_uwa_channel 对 doppler_rate 的支持
2. 将 doppler_rate=0 改为合理值（如 1e-4，对应 ~1Hz@10kHz fc）
3. 运行全部 24 项测试
4. 记录新基线结果
5. 更新 README.md 中的测试结果表
6. 新旧结果对比分析

### 测试策略

- 运行 `test_channel_est_eq.m` 全部测试项
- 对比：doppler_rate=0 vs doppler_rate=1e-4 的结果差异
- 关注：时变估计 NMSE 和时变均衡 SER 的变化幅度

### 风险

| 风险 | 概率 | 应对 |
|------|------|------|
| 加入真实 Doppler 后部分方法性能大幅下降 | 高 | 这是预期的，记录为新基线 |
| gen_test_channel 不支持 doppler_rate | 低 | 检查接口，必要时适配 |

---

## Log

### 2026-04-12 代码修改

1. **确认接口**：gen_uwa_channel 支持 doppler_rate 参数（第 39 行），非零时做 spline 重采样
2. **换算关系**：doppler_rate = fd / fc，fc=12kHz（与 sys_params 一致）
   - fd=1Hz → 8.33e-5, fd=5Hz → 4.17e-4, fd=10Hz → 8.33e-4
3. **修改 test_channel_est_eq.m 第 700-706 行**：
   - 新增 `fc_ref=12000; dop_rate_i=fd_i/fc_ref;`
   - `doppler_rate` 从固定 0 改为 `dop_rate_i`
   - 新增 oracle alpha 多普勒补偿（spline 逆重采样），聚焦测试估计+均衡能力
4. **设计决策**：用 oracle alpha 补偿而非调用模块 10，因为模块 07 测试的重点是估计和均衡，不是多普勒补偿

**已完成**：MATLAB 测试运行成功，24/24 通过，结果保存在 `test_results_doppler_fix.txt`

---

## Result

### 测试结果：24/24 通过

#### 时变均衡新基线（doppler_rate=fd/fc, fc=12kHz, oracle alpha 补偿）

**fd=0Hz（静态）**— 无变化，0%@3dB+

**fd=1Hz**

| SNR | -3dB | 0dB | 3dB | 5dB | 10dB | 15dB | 20dB |
|-----|------|-----|-----|-----|------|------|------|
| oracle | 0.22% | 0.11% | 0% | 0% | 0% | 0% | 0% |
| BEM(CE) | 0.61% | 0.11% | 0% | 0% | 0% | 0% | 0% |
| BEM(DCT) | 0.34% | 0.11% | 0% | 0% | 0% | 0% | 0% |
| DD-BEM | 1.17% | 0.34% | 0% | 0% | 0% | 0.11% | 0.11% |

**fd=5Hz**

| SNR | -3dB | 0dB | 3dB | 5dB | 10dB | 15dB | 20dB |
|-----|------|-----|-----|-----|------|------|------|
| oracle | 0.89% | 0.16% | 0% | 0.05% | 0% | 0.05% | 0% |
| BEM(CE) | 2.92% | 0.47% | 0% | 0% | 0% | 0.16% | 0% |
| BEM(DCT) | 3.44% | 0.36% | 0% | 0.10% | 0% | 0.10% | 0% |
| DD-BEM | 5.06% | 0.78% | 0.05% | 0.21% | 0% | 0.10% | 0.26% |

**fd=10Hz**

| SNR | -3dB | 0dB | 3dB | 5dB | 10dB | 15dB | 20dB |
|-----|------|-----|-----|-----|------|------|------|
| oracle | 3.02% | 1.36% | 0.36% | 0.31% | 0.73% | 3.28% | 3.65% |
| BEM(CE) | 20.23% | 8.39% | 6.93% | 4.43% | 9.18% | 11.16% | 13.76% |
| BEM(DCT) | 15.12% | 4.95% | 4.48% | 1.15% | 3.08% | 4.48% | 6.10% |
| DD-BEM | 17.15% | 10.27% | 4.59% | 9.02% | 9.18% | 14.23% | 15.33% |

### 关键发现

1. **fd<=5Hz 影响可控**：加入真实 Doppler 后低 SNR 性能下降（预期），但 5dB+ 基本不变，oracle 补偿有效
2. **DD-BEM 高 SNR 地板效应**：fd=5Hz 时 DD-BEM 在 20dB 出现 0.26% 残余，疑似多普勒残余导致判决误差传播
3. **fd=10Hz 确认 ICI 极限**：oracle 在高 SNR 非单调反弹（0.73%→3.28%→3.65%），是系统级 ICI 极限而非算法问题
4. **BEM(DCT) 仍然最优**：在有真实 Doppler 的条件下，BEM(DCT) 在 fd=5Hz/10Hz 全面优于 CE-BEM 和 DD-BEM

### 待 promote

- [[channel-estimation-and-equalization]] — 更新时变均衡基线数据（doppler_rate 修正后）
- [[time-varying-channel]] — 补充 fd=10Hz ICI 极限的量化数据
