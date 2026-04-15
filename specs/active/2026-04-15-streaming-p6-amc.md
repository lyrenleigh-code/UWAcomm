---
project: uwacomm
type: task
status: placeholder
created: 2026-04-15
updated: 2026-04-15
parent: 2026-04-15-streaming-framework-master.md
phase: P6
depends_on: [P5]
tags: [流式仿真, 14_Streaming, AMC, 自适应]
---

# Streaming P6 — 物理层 AMC（自适应体制切换）

## Spec

### 目标

RX 基于**物理层指标**估计链路质量，决策推荐体制，通过 ACK 帧（反向半双工链路）告诉 TX 下一帧用哪个体制。TX 按推荐切换。

### 决策输入（物理层）

- **sync_peak**：LFM 匹配滤波归一化峰值
- **SNR_est**：LFM 峰附近噪声基线估计
- **delay_spread**：OMP/BEM 估计的最大时延
- **doppler_est**：LFM 相位法 α × fc

### 决策规则（Master spec 里的决策表，P6 细化）

### 验收标准

- [ ] 3 种测试信道（静态 / 低 Doppler 1Hz / 高 Doppler 5Hz），AMC 在 10 帧内收敛到正确体制
- [ ] 切换冷却 ≥ 3 帧，避免抖动
- [ ] 切换滞后（hysteresis）：质量恶化 2dB 才升体制，改善 5dB 才降体制
- [ ] 盲模式（无 ACK 链路）下仍能工作（依赖 TX 固定规则）
- [ ] 可视化：链路质量时序图 + 体制切换点标注

### 依赖

- P5 完成（并发框架可用）
- 反向 ACK 帧定义（scheme=0 CTRL 帧）

### 关键点（细化待 P5 完成后）

- link_quality_est.m：实时计算上述 4 个指标
- mode_selector.m：决策表 + hysteresis + 冷却
- ACK 帧格式（CTRL scheme，payload 含推荐 scheme ID）
- TX 侧模式队列：收到 ACK 后更新下一帧 scheme
- 自组网预留：ACK 帧含 `recommend_scheme` + `link_quality_metric` 字段

---

## Plan / Log / Result

（P5 完成后补）
