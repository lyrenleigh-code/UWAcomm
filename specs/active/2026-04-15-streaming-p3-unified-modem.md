---
project: uwacomm
type: task
status: placeholder
created: 2026-04-15
updated: 2026-04-15
parent: 2026-04-15-streaming-framework-master.md
phase: P3
depends_on: [P1, P2]
tags: [流式仿真, 14_Streaming, 统一API, 6体制]
---

# Streaming P3 — 6 体制统一 modem API

## Spec

### 目标

将 SC-FDE / OFDM / SC-TDE / DSSS / OTFS / FH-MFSK 6 个体制的 encode/decode 从 `13_SourceCode/tests/*` 提取为统一接口：

```matlab
[tx_pb, meta] = modem_encode(bits, scheme, sys_params)
[bits, info]  = modem_decode(rx_pb, scheme, sys_params, meta)
```

实现 `common/modem_dispatch.m` 按 scheme 字段分发。

### 验收标准

- [ ] 6 个体制均可通过统一 API 收发
- [ ] 每个体制的 BER 与 `13_SourceCode/tests/*_timevarying.m` 基线一致（±0.5%）
- [ ] 统一 API 可在 `test_p3_all_schemes.m` 中批量测 6 体制
- [ ] `info` 结构包含：estimated_snr, estimated_ber, turbo_iter, convergence_flag

### 依赖

- P2 完成（流式检测可用，避免提取时耦合帧对齐逻辑）
- 01–12 算法模块稳定

### 关键点（细化待 P2 完成后）

- 每体制一个 `sys_params` 子结构（`sys.sc_fde` / `sys.ofdm` / ...）
- encode 端：TX 链路提取，信道前的部分（bits → 通带数组）
- decode 端：RX 链路提取，LFM 精确定时后 → bits
- meta 携带 TX 侧已知参数（帧长、CP、pilot 位置等）给 RX 使用

---

## Plan / Log / Result

（P2 完成后补）
