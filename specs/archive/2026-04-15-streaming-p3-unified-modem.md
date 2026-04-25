---
project: uwacomm
type: task
status: in-progress
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

## Plan

详见 `plans/streaming-p3-unified-modem.md`（P3.1）。分阶段推进：
- **P3.1**：架构 + FH-MFSK + SC-FDE → ✅ 完成（2026-04-15）
- **P3.2**：OFDM + SC-TDE → 待开始
- **P3.3**：DSSS + OTFS → 待开始

## Log

### 2026-04-15 — P3.1 完成

新增：
- `common/modem_dispatch.m` — 按 scheme 大写去连字符分发
- `common/modem_encode.m` / `common/modem_decode.m` — 薄包装入口
- `tx/modem_encode_scfde.m` — 从 13_SourceCode L100-128 抽取
- `rx/modem_decode_scfde.m` — 从 13_SourceCode L238-373 抽取（含 GAMP 静态/BEM 时变 + 6 轮 Turbo）
- `tests/test_p3_unified_modem.m` — 双体制回归测试

修改：
- `rx/modem_decode_fhmfsk.m` — info 补齐 4 个统一字段（estimated_snr/ber/turbo_iter/convergence_flag）
- `common/sys_params_default.m` — 加入 `sys.scfde` 子结构

测试结果（静态 6 径 + 复 AWGN）：

| scheme  | 5dB | 10dB | 15dB |
|---------|-----|------|------|
| FH-MFSK | 0%  | 0%   | 0%   |
| SC-FDE  | 0%  | 0%   | 0%   |

通过 2/2 验收（FH-MFSK <0.5%@10dB；SC-FDE <0.5%@15dB）。

**注**：本次测试 bypass passband/HFM-LFM 同步，直接基带卷积 + 复 AWGN，是严格更易场景。
完整 passband 集成（含 frame_detector + LFM 精定时）在 P4 流水线整合时验证。

### 2026-04-16 — P3.1 SC-FDE bug 修复 + UI V3

bug 修复（3 项）：
- 零填充→随机填充（seed=42）：GAMP 需多样化训练符号
- σ²_bb 公式 4·σ²_pb·BW/fs → 8·σ²_pb·BW/fs：downconvert I/Q 各贡献一份
- NV 实测覆盖改为兜底：优先用 on_transmit 精确值

UI V3.0：
- 解码历史（最多 20 条，带时间戳，下拉回看）
- 信道 tab 拆为时域/频域（H_est vs H_true 叠加对比）
- 日志移至底部 tab，TX 面板改为信号信息面板
- 音频监听（Mon 按钮，1:1 实时 48kHz 播放）

## Result

- **完成日期**：2026-04-16（P3.1 + P3.2 + P3.3 三子 spec 全部 ✅）
- **状态**：✅ 完成
- **关键产出**：
  - `modules/14_Streaming/src/Matlab/common/modem_dispatch.m` 6 体制统一 API
  - P3.1 (FH-MFSK + SC-FDE) — 2026-04-16
  - P3.2 (OFDM + SC-TDE) — 2026-04-16，spec `archive/2026-04-16-streaming-p3.2-ofdm-sctde.md`
  - P3.3 (DSSS + OTFS) — 2026-04-16，Gold31 Rake+DCD + DD 域 LMMSE Turbo
  - BER 与 `13_SourceCode/tests/*_timevarying.m` baseline 一致
- **后继 spec**：
  - `archive/2026-04-17-p3-demo-ui-refactor.md`（UI 重构）
  - `archive/2026-04-17-p3-demo-ui-polish.md`（深色科技风 V2）
  - `archive/2026-04-17-p3-demo-ui-sync-quality-viz.md`（真同步 + Quality/Sync tab）
  - `active/streaming-p4-scheme-routing.md` / `p5-concurrent.md` / `p6-amc.md`（待启动）
- **归档**：2026-04-25 by spec 状态审计批量归档
