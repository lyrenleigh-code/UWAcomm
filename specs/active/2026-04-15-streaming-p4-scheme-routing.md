---
project: uwacomm
type: task
status: placeholder
created: 2026-04-15
updated: 2026-04-15
parent: 2026-04-15-streaming-framework-master.md
phase: P4
depends_on: [P3]
tags: [流式仿真, 14_Streaming, scheme路由, 异构帧]
---

# Streaming P4 — 帧头 FH-MFSK + payload 异构体制路由

## Spec

### 目标

帧头（16B）永远用 FH-MFSK 调制（最鲁棒），payload 按帧头 `scheme` 字段指定体制调制。RX 先用 FH-MFSK 解头，读到 scheme 后再调用对应体制 decode payload。

### 验收标准

- [ ] 同一 channel.wav 中包含 6 种不同 scheme 的 payload（混合帧序列）
- [ ] RX 正确分发到 6 个 modem_decode 路径
- [ ] 头部可解但 payload CRC 失败时，记录 miss 而非崩溃
- [ ] 头部不可解（FH-MFSK 也失败）时，跳到下一 HFM 峰继续搜

### 依赖

- P3 完成（6 体制统一 API 可用）

### 关键点（细化待 P3 完成后）

- 物理帧结构：[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|Hdr(FH-MFSK)|Payload(scheme)]
- 两段不同体制需要明确的时间边界（在帧头后加一个小 guard）
- RX 分两次解调：先用 FH-MFSK 解帧头那段 → 按 scheme 分发解 payload
- scheme=0 (CTRL) 特殊处理：空 payload 或轻量控制信息

---

## Plan / Log / Result

（P3 完成后补）
