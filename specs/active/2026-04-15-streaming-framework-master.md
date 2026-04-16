---
project: uwacomm
type: task-master
status: active
created: 2026-04-15
updated: 2026-04-15
tags: [流式仿真, 14_Streaming, AMC, 自组网, 架构]
---

# Streaming 仿真框架 — 总体架构（Master Spec）

## Spec

### 目标

在现有 01–13 模块基础上新建 `modules/14_Streaming/`，实现**文本输入 → wav 文件 → 信道 → wav 文件 → 文本输出**的全流程流式通信仿真，具备：

1. **双 wav 文件**：`raw.wav`（纯发射信号）+ `channel.wav`（含信道+噪声）
2. **三进程并发**：TX / channel daemon / RX 各自 MATLAB 进程，wav 文件共享
3. **6 体制统一 API**：SC-FDE / OFDM / SC-TDE / DSSS / OTFS / FH-MFSK 包装 `modem_encode/decode`
4. **物理层 AMC**：基于 LFM sync_peak + 信道展宽估计 + 估计 SNR 自主切换体制
5. **自组网接口预留**：帧头含 `node_src/dst`，MAC/路由本次不实现

### 原因

现有 13_SourceCode/tests 为批处理测试（信号为数组、帧起点已知、串行流程），不模拟实际部署场景。实际水声通信需要：
- 用户层有真实信源（文本）
- 物理层有真实传输介质（wav 文件，后续可替换 audio / socket）
- 接收端持续监听（不知道帧起点）
- 链路自适应（不同信道条件选不同体制）

### 范围

**代码仓库**：`D:\Claude\TechReq\UWAcomm`

**新增模块**：`modules/14_Streaming/`
```
14_Streaming/
├── src/Matlab/
│   ├── tx/              # 发射链：text → frame → modem → raw.wav
│   ├── rx/              # 接收链：channel.wav → detect → unpack → modem → text
│   ├── channel/         # 信道模拟 daemon：raw.wav → channel.wav
│   ├── amc/             # 链路质量估计 + 体制选择
│   ├── common/          # text↔bits, crc16, 帧头, modem_dispatch
│   └── tests/
├── README.md
```

**新增 wiki**：`wiki/modules/14_Streaming/`

**复用（不改）**：01–12 算法模块；13_SourceCode 批处理测试继续作为**算法回归基准**

### 非目标

- 不做 audio 设备 I/O（后续扩展）
- 不做 TCP/UDP socket（后续扩展）
- 不实现 MAC 层（CSMA/Aloha/TDMA）
- 不实现路由层（AODV/flooding）
- 不改 01–12 算法实现，仅在 14_Streaming 内做编排包装

### 验收标准（Master 层）

- [ ] 6 个体制均可通过 `modem_encode/decode` 统一 API 收发
- [ ] 文本 "Hello 水声" → raw.wav → channel.wav → "Hello 水声"（任一体制，高 SNR 无误码）
- [ ] 三进程并发启动，各自可独立运行
- [ ] AMC 在 3 种信道（静态 / 低 Doppler / 高 Doppler）下自动选对应推荐体制
- [ ] 6 phase spec 全部关闭

---

## 关键决策（2026-04-15 已确认）

| # | 决策点 | 确认选择 |
|---|--------|---------|
| 1 | wav 格式 | 48kHz / mono / int16 |
| 2 | 文本编码 | UTF-8 |
| 3 | 帧 payload 长度 | 固定 + 末帧补零（长度写在帧头） |
| 4 | 并发方案 | 3 个 MATLAB 进程（手动或脚本分别启动），wav 文件共享 |
| 5 | channel daemon | 独立进程，监控 raw.wav 文件追加，生成 channel.wav |
| 6 | CRC / ARQ | CRC-16 必做；ARQ 帧头留字段，P6 不实现 |
| 7 | AMC 反馈 | 半双工 + 周期性 ACK（留接口，P6 只做决策侧） |
| 8 | 自组网 | 帧头含 `node_src/dst` 字段，MAC/路由本次不做 |
| 9 | 回归测试 | 保留 `13_SourceCode/tests/*` 作为算法基准，14_Streaming 专注编排 |
| 10 | AMC 决策依据 | **物理层指标**：LFM sync_peak + 信道展宽估计 + 估计 SNR |

---

## 系统架构

### 数据流

```
用户输入                                                   用户输出
  "Hello 水声"                                             "Hello 水声"
       ↓                                                       ↑
  [TX Process]                                            [RX Process]
       ↓                                                       ↑
  text→utf8 bits                                          bits→utf8 text
       ↓                                                       ↑
  frame_packer (crc+header)                         frame_unpacker (crc check)
       ↓                                                       ↑
  modem_encode(scheme)                              modem_decode(scheme)
       ↓                                                       ↑
  wav_writer ──── raw.wav ──→ [Channel Daemon] ──→ channel.wav ──── wav_reader
                                     ↓                     ↑
                              gen_uwa_channel        frame_detector
                              + noise               (滑动 HFM 匹配)
```

### 帧结构（统一，独立于体制）

```
物理帧 (passband signal):
┌──────────┬───────┬──────────┬───────┬──────┬───────┬──────┬───────┬──────────────────┐
│   HFM+   │ guard │   HFM-   │ guard │ LFM1 │ guard │ LFM2 │ guard │ Frame Body (PHY) │
└──────────┴───────┴──────────┴───────┴──────┴───────┴──────┴───────┴──────────────────┘

Frame Body:
┌────────────────────────────────┬─────────────────────────────┐
│  Header (16B, FH-MFSK coded)   │  Payload (scheme coded)     │
└────────────────────────────────┴─────────────────────────────┘

Header (16 Bytes):
┌────┬────┬────┬────┬────┬────┬────┬────┐
│MAGIC(2)│SCH │IDX │ LEN(2)  │MOD │FLG │RSV(2)│
├────┴────┼────┼────┼────────┼────┼────┼──────┤
│ 0xA5C3  │ 1B │ 1B │  2B    │ 1B │ 1B │  2B  │
├─────────┴────┴────┴────────┴────┴────┴──────┤
│           SRC_NODE(2) │ DST_NODE(2)         │
├────────────────────────────────────────────┤
│              HEADER_CRC16(2)                │
└────────────────────────────────────────────┘

字段：
  MAGIC       0xA5C3（帧同步标识，辅助检测）
  SCH (scheme) 1B: 0=CTRL, 1=SC-FDE, 2=OFDM, 3=SC-TDE, 4=DSSS, 5=OTFS, 6=FH-MFSK
  IDX         帧序号 (0~255 循环)
  LEN         payload 比特数 (2B, 最大 65535)
  MOD         调制阶数 (QPSK=2, 8PSK=3, 16QAM=4 等)
  FLG         flags: bit0=last_frame, bit1=ack_req, bit2=is_ack, ...
  SRC/DST     节点 ID (自组网预留，单机设 0)
  CRC16       头部 CRC

Payload trailer:
┌─────────────┬──────────────┐
│ payload bits│ PAYLOAD_CRC16│
└─────────────┴──────────────┘
```

**关键设计**：Header 总是用 FH-MFSK（最鲁棒）调制，Payload 按 SCH 字段指定体制。这保证**控制信息永远可解**，即便 payload 体制在当前信道失效也能读到头部做 AMC 决策。

### 统一 modem API

```matlab
function [tx_pb, meta] = modem_encode(bits, scheme, sys_params)
% bits       : 输入比特流 (1×N logical)
% scheme     : 1~6 (或 0=CTRL)
% sys_params : 系统参数 struct（fs, fc, sps 等）
% tx_pb      : 通带实信号 (1×M double)
% meta       : 元数据 (帧长、CP、pilot 位置等，供 decode 使用)

function [bits, info] = modem_decode(rx_pb, scheme, sys_params, meta)
% rx_pb      : 接收通带信号
% info       : 性能信息 (估计SNR, BER估计, 迭代次数等，供 AMC 使用)
```

每个体制在 `common/modem_dispatch.m` 中注册，TX/RX 通过 `scheme` 字段分发。

### 进程间协作（方案 B：每帧一个 wav 文件）

**会话目录结构**：

```
session_2026-04-15-1830/
├── raw_frames/                # TX 输出
│   ├── 0001.wav               # 每帧独立 wav（写完即 close）
│   ├── 0001.ready             # 空文件，TX close wav 后原子创建
│   ├── 0002.wav
│   ├── 0002.ready
│   └── ...
├── channel_frames/            # Channel daemon 输出
│   ├── 0001.wav               # 对应 raw_frames/0001.wav 的信道版本
│   ├── 0001.ready
│   └── ...
├── rx_out/
│   ├── 0001.meta.json         # RX 每帧解码结果 + 链路指标（AMC 用）
│   └── session_text.log       # 解码文本累积输出
└── session.log                # 三进程公共日志
```

**进程协作**：

```
Terminal 1 (TX):                Terminal 2 (Channel):            Terminal 3 (RX):
tx_stream(text, session)        channel_daemon(session, ch_cfg)   rx_stream(session)
    ↓                               ↓                                  ↓
write 0001.wav                  dir(raw_frames/*.ready) polling    dir(channel_frames/*.ready)
close → touch 0001.ready            ↓                                  ↓
    ↓                           read 0001.wav (已 close)            read 0001.wav (已 close)
write 0002.wav                  gen_uwa_channel → 0001.wav(ch)     detect+decode
close → touch 0002.ready        close → touch 0001.ready           write 0001.meta.json
```

**为什么无锁冲突**：
1. 每帧 wav 写完 **close** 后才创建 `.ready` 标记，OS 级保证这两步原子序列
2. 下游进程只读 `.ready` 存在的 wav — 对应 wav 必然已关闭
3. 多个帧并发处理时各自独立文件，无共享文件句柄

**会话汇总（可选）**：会话结束或手动触发时，用 `session_wavconcat.m` 把 `raw_frames/*.wav` 合并成 `raw_session.wav` 归档（与"一个 raw.wav"心智一致），channel 同理。实时处理链路仍用每帧小文件。

**崩溃恢复**：任一进程重启后，扫描上游 `.ready` 文件，跳过下游已产出的（根据 ready 对应关系），继续处理未完成帧。

**清理策略**：session 目录可配置保留（默认保留最近 N 帧用于 debug/回放，其他移至 `archive/`）。

---

## Phase 规划

| Phase | 目标 | 状态 | spec |
|-------|------|------|------|
| **P1** | 单体制串行 loopback (FH-MFSK) | ✅ 完成 (2026-04-15) | `archive/2026-04-15-streaming-p1-loopback-fhmfsk.md` |
| **P2** | RX 流式帧检测 + 多帧 + 软判决 LLR | ✅ 完成 (2026-04-15) | `archive/2026-04-15-streaming-p2-stream-detect.md` |
| **P3.1** | 统一 API + FH-MFSK + SC-FDE | ✅ 完成 (2026-04-15) | `2026-04-15-streaming-p3-unified-modem.md` |
| **P3.2** | OFDM + SC-TDE | ⬜ 待开始 | 待写 |
| **P3.3** | DSSS + OTFS | ⬜ 待开始 | 待写 |
| **P4** | scheme 路由 | ⬜ 待 P3 | `2026-04-15-streaming-p4-scheme-routing.md` |
| **P5** | 三进程并发 | ⬜ 待 P4 | `2026-04-15-streaming-p5-concurrent.md` |
| **P6** | 物理层 AMC | ⬜ 待 P5 | `2026-04-15-streaming-p6-amc.md` |

---

## AMC 决策逻辑（物理层指标）

决策输入：
- **sync_peak**：LFM 匹配滤波归一化峰值（反映同步质量）
- **SNR_est**：从 LFM 峰附近噪声基线估计
- **delay_spread**：OMP/BEM 估计的信道最大时延（反映频选程度）
- **doppler_est**：LFM 相位法 α × fc（反映时变程度）

决策表（初版，P6 细化）：

| 条件 | 推荐体制 | 备选 |
|------|---------|------|
| SNR < 0 dB | FH-MFSK | DSSS |
| 0 ≤ SNR < 5 dB, 低 Doppler (<1Hz) | DSSS | OFDM |
| 5 ≤ SNR, 低 Doppler, 小 delay_spread | OFDM | SC-FDE |
| 5 ≤ SNR, 低 Doppler, 大 delay_spread | OFDM | SC-FDE |
| 5 ≤ SNR, 高 Doppler (>3Hz) | OTFS | FH-MFSK |
| 信道剧烈非平稳 | OTFS | SC-TDE |

---

## 风险

| 风险 | 概率 | 应对 |
|------|------|------|
| wav 文件并发读写冲突 | 中 | 用 `.lock` 文件 + 帧边界追加写，RX 只读已写完的帧 |
| MATLAB 进程间通信慢 | 低 | 用文件轮询 + 帧完整性标记（CRC 兜底） |
| 6 体制 API 参数差异大 | 高 | 每体制一个 `sys_params` 子结构，`modem_dispatch` 统一入口 |
| AMC 抖动（体制频繁切换） | 中 | 加滞后（hysteresis）+ 切换冷却（最少保持 N 帧） |
| 自组网接口过设计 | 低 | 本次只留字段，逻辑空实现 |

---

## Log

- **2026-04-15 P3.1 完成**：搭建 `modem_dispatch / modem_encode / modem_decode` 统一 API；
  FH-MFSK 现有实现适配 4 字段 info；SC-FDE 从 `13_SourceCode/tests/SC-FDE/test_scfde_timevarying.m`
  抽取 encode/decode 到 `14_Streaming/{tx,rx}/modem_{encode,decode}_scfde.m`。
  `test_p3_unified_modem.m` 静态 6 径 + AWGN 两体制 0%@5dB+ 通过。
  剩余 4 体制（OFDM/SC-TDE/DSSS/OTFS）拆分到 P3.2/P3.3。

---

## Result

（6 phase 完成后汇总）
