---
project: uwacomm
type: task
status: placeholder
created: 2026-04-15
updated: 2026-04-15
parent: 2026-04-15-streaming-framework-master.md
phase: P2
depends_on: [P1]
tags: [流式仿真, 14_Streaming, 帧检测]
---

# Streaming P2 — 流式帧检测

## Spec

### 目标

RX 不依赖已知帧起点，通过**滑动 HFM 匹配滤波 + 阈值触发 + debounce**在 channel.wav 中发现帧起点，支持多帧长文本。

### 验收标准

- [ ] 长文本（>单帧 payload）拆分为多帧发送，RX 按顺序复原
- [ ] 流式检测器正确识别 2~10 个连续帧的起点（误差 <1 符号）
- [ ] 漏检率 <1%（SNR=10dB 静态信道）
- [ ] 误检率 <0.1%（纯噪声输入无虚警）
- [ ] 帧间隔乱序（模拟丢帧）时能继续解码后续帧

### 依赖

- P1 完成（单帧闭环已通）
- `sync_detect` / `sync_dual_hfm` (08_Sync) 的滑动窗口包装

### 关键点（细化待 P1 完成后）

- 阈值自适应（噪声基线 + K·σ）
- 峰保持窗口长度（覆盖多径）
- 连续峰 debounce（防止单帧被多次触发）
- 帧长由帧头 `payload_len` 决定，需先解 header 再读 payload

---

## Plan / Log / Result

（P1 完成后补）
