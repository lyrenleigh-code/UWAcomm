---
project: uwacomm
type: plan
status: done
created: 2026-04-15
parent_spec: specs/active/2026-04-15-streaming-p3-unified-modem.md
phase: P3
tags: [流式仿真, 14_Streaming, 统一API]
---

# Streaming P3 — 统一 modem API 实施计划

## 背景

P1/P2 完成后，`modem_encode_fhmfsk` / `modem_decode_fhmfsk` 已在 `14_Streaming/tx,rx/` 落地。P3 目标是将 6 体制统一成
`modem_encode(bits, scheme, sys)` / `modem_decode(body_bb, scheme, sys, meta)` 接口。

P3 采用**分阶段**策略（2026-04-15 与用户确认）：
- **P3.1（本计划）**：搭架构 + 接入 FH-MFSK（已有）+ SC-FDE（最常用、文档最全）
- **P3.2**：OFDM + SC-TDE
- **P3.3**：DSSS + OTFS

本 plan 仅覆盖 **P3.1**。

## 架构边界

```
┌── modem_encode(bits, scheme, sys) → body_bb, meta
│     · 输入：纯信息比特（含 header+payload+crc，已由 frame_header + crc16 组装）
│     · 输出：基带 body（复信号，不含 HFM/LFM/guard）
│     · meta：TX 侧已知参数（符号数、CP、导频位置、交织 perm 等）
│
├── assemble_physical_frame(body_bb, sys) → frame_bb
│     （共享，已在 common/，P3 不动）
│
├── upconvert(frame_bb, fs, fc) → frame_pb → wav
│
├── [信道]
│
├── downconvert → bb_raw
├── frame_detector(bb_raw, sys, opts) → starts（HFM+ 帧头）
├── detect_lfm_start(frame_win, sys, fm) → lfm_pos
├── （可选）doppler 补偿（oracle / dual-LFM 两种路径）
│
└── modem_decode(body_bb, scheme, sys, meta) → bits, info
      · 输入：LFM 对齐 + doppler 补偿后的基带 body
      · 输出：bits + 诊断 info（estimated_snr, turbo_iter, convergence_flag …）
```

**关键约定**：
- body 只含 scheme 相关波形（RRC/OFDM/FSK/ZC-OTFS 等），**不含前导码**。
- Doppler 补偿仍由外层 RX stream 做（P2 用 oracle α；SC-FDE 时变下后续 P3.2+ 考虑 dual-LFM 内置）。
- 符号定时 hint 通过 `meta.pilot_sym`（TX 已知首 N 符号）传入，避免盲搜索（oracle 辅助，streaming 场景合理，因为 meta 随 wav 写入）。

## 文件清单

### 新建

| 文件 | 作用 |
|------|------|
| `common/modem_dispatch.m` | 按 scheme 字段分发到具体 encode/decode |
| `common/modem_encode.m` | 薄包装，调用 dispatch |
| `common/modem_decode.m` | 薄包装，调用 dispatch |
| `tx/modem_encode_scfde.m` | SC-FDE TX（从 `test_scfde_timevarying.m` L100-128 抽取） |
| `rx/modem_decode_scfde.m` | SC-FDE RX（从 L238-373 抽取；sync/doppler 已在外层剥离） |
| `tests/test_p3_unified_modem.m` | FH-MFSK + SC-FDE 双体制统一 API 回归测试 |

### 重命名（保留原文件作过渡）

- `tx/modem_encode_fhmfsk.m` → 保留（内部实现）；新增 dispatch 引用
- `rx/modem_decode_fhmfsk.m` → 保留

### 不动

- `common/assemble_physical_frame.m`
- `rx/frame_detector.m`, `rx/detect_lfm_start.m`
- `tx/tx_stream_p2.m`, `rx/rx_stream_p2.m`（P4 再改用 dispatch 路由）
- 01–13 所有算法模块

## 统一 API 签名

```matlab
function [body_bb, meta] = modem_encode(bits, scheme, sys)
% scheme: 'FH-MFSK' | 'SC-FDE' | 'OFDM' | 'SC-TDE' | 'DSSS' | 'OTFS' (P3.1 前两个)
% sys   : 结构体，至少含
%         .fs .fc .sps .scheme 特定子结构（sys.fhmfsk / sys.scfde / ...）
%         .codec (gen_polys, constraint_len, interleave_seed)
% body_bb: 1×N 基带复信号
% meta   : struct 含 scheme 解调所需的 TX 侧元数据

function [bits, info] = modem_decode(body_bb, scheme, sys, meta)
% info 至少包含：
%   .estimated_snr     dB
%   .estimated_ber     软/硬判决 BER 估计
%   .turbo_iter        实际迭代数
%   .convergence_flag  0=未收敛 / 1=CRC 通过收敛 / 2=LLR 稳定
```

## modem_dispatch 设计

```matlab
function varargout = modem_dispatch(op, scheme, varargin)
%   op     : 'encode' | 'decode'
%   scheme : string，大小写不敏感，规范化后分发
scheme = upper(strrep(scheme, '-', ''));   % 'FHMFSK' 'SCFDE' ...
switch scheme
  case 'FHMFSK'
    switch op
      case 'encode', [varargout{1:2}] = modem_encode_fhmfsk(varargin{:});
      case 'decode', [varargout{1:2}] = modem_decode_fhmfsk(varargin{:});
    end
  case 'SCFDE'
    switch op
      case 'encode', [varargout{1:2}] = modem_encode_scfde(varargin{:});
      case 'decode', [varargout{1:2}] = modem_decode_scfde(varargin{:});
    end
  otherwise
    error('modem_dispatch: 未知 scheme %s', scheme);
end
end
```

## SC-FDE 抽取要点

从 `test_scfde_timevarying.m` 抽出的 TX/RX 边界：

### encode（L100-128）

```
bits → conv_encode → interleave → QPSK → 分块+CP → pulse_shape(RRC) → body_bb
```

meta 字段：`{perm_all, all_cp_data, N_info, blk_fft, blk_cp, N_blocks, sym_per_block, M_total, M_per_blk}`

### decode（L238-373，外层先剥离 sync/doppler）

```
body_bb → match_filter(RRC) → 符号定时(pilot_sym=all_cp_data(1:10)) →
  信道估计(static:GAMP / tv:BEM) → 分块去CP+FFT → LMMSE-IC Turbo 6 轮 → bits
```

**参数化点**：
- `sys.scfde.fading_type`：static / slow，决定 GAMP vs BEM 路径
- `sys.scfde.fd_hz`：传给 `ch_est_bem`
- `sys.scfde.sym_delays`、`sys.scfde.gains_raw`：BEM 需要的信道结构先验
- `sys.scfde.turbo_iter`（默认 6）

**noise_var 估计**：外层 rx stream 已有 SNR 估计（来自 frame_detector），传入 meta；或 decoder 内部用 median 估噪。P3.1 先从 meta.noise_var 读取，后续改为自估。

## 验收标准（P3.1）

- [ ] `test_p3_unified_modem.m` 通过：
  - FH-MFSK 与 `13_SourceCode/tests/FH-MFSK/test_fhmfsk_timevarying.m` BER 对齐 ±0.5%
  - SC-FDE 与 `13_SourceCode/tests/SC-FDE/test_scfde_timevarying.m` BER 对齐 ±0.5%
- [ ] `modem_dispatch('encode', 'FH-MFSK', bits, sys)` 与 `modem_dispatch('encode', 'SC-FDE', bits, sys)` 均工作
- [ ] `info` 结构 4 个字段齐全
- [ ] 现有 `tx_stream_p2 / rx_stream_p2` 仍可运行（不破坏 P2）

## 实施步骤

1. **架构搭建**（任务 #2）
   - `common/modem_dispatch.m` + `common/modem_encode.m` + `common/modem_decode.m`

2. **FH-MFSK 适配**（任务 #3）
   - 确认现有 `modem_encode_fhmfsk / decode_fhmfsk` 签名与统一 API 兼容
   - 若不兼容，薄包装层补齐 `info` 字段
   - dispatch 入口联通

3. **SC-FDE 抽取**（任务 #4）
   - 新建 `tx/modem_encode_scfde.m`（约 60 行）
   - 新建 `rx/modem_decode_scfde.m`（约 200 行，含 Turbo 循环）
   - `sys.scfde` 子结构加入 `sys_params_default.m`

4. **回归测试**（任务 #5）
   - `tests/test_p3_unified_modem.m`
   - 两体制 × static/fd=1Hz/fd=5Hz × SNR 列表
   - 与 13_SourceCode 基线对比

5. **收尾**（任务 #6）
   - 更新 `todo.md`：P3 标记为"P3.1 完成"
   - 更新 `wiki/modules/14_Streaming/14_流式仿真框架.md`
   - master spec log 追加
   - 归档不需要（P3 未完全完成）

## 风险

| 风险 | 应对 |
|------|------|
| SC-FDE 外层 sync/doppler 剥离后 BER 差 | 先在 test 里用 oracle α 跑通，再接 dual-LFM |
| modem_metas 结构在 P2 已固化，P3 改签名破坏 P2 | dispatch 薄包装保留旧签名，P2 入口不改 |
| BEM 信道估计依赖 all_cp_data（oracle 发射符号） | streaming 场景允许（TX meta 随 wav 下发），本次不改 |
| Turbo 迭代数写死 6 | 做成 sys.scfde.turbo_iter 可配 |

## Log

（实施过程追加）
