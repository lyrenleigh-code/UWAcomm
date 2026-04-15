# 14_Streaming — 流式通信仿真框架

> **状态**：骨架阶段（2026-04-15），Phase 1 实施中
> **Master Spec**：`specs/active/2026-04-15-streaming-framework-master.md`

## 目的

在 01–13 算法模块基础上构建**文本 → wav 文件 → 信道 → wav 文件 → 文本**的流式通信仿真框架，模拟真实水声部署场景：

- 用户输入文本字符串（UTF-8）
- TX 生成 passband wav 文件（48kHz / mono / int16）
- Channel daemon 独立进程，输入 raw wav，输出含信道+噪声的 channel wav
- RX 持续监听 channel wav，解码后输出文本
- 支持 6 体制（SC-FDE / OFDM / SC-TDE / DSSS / OTFS / FH-MFSK）统一接口
- 基于物理层指标的 AMC 自适应体制切换
- 为自组网扩展预留节点地址字段

## 目录

```
14_Streaming/
├── src/Matlab/
│   ├── tx/          # 发射链：text → frame → modem → raw_frames/NNNN.wav
│   ├── rx/          # 接收链：channel_frames/NNNN.wav → detect → decode → text
│   ├── channel/     # 信道模拟 daemon
│   ├── amc/         # 链路质量估计 + 体制选择（P6）
│   ├── common/      # 文本↔比特 / 帧头 / CRC / session 管理 / wav I/O
│   └── tests/
├── README.md
```

## 会话目录结构（方案 B：每帧一个 wav）

```
session_<timestamp>/
├── raw_frames/       NNNN.wav + NNNN.ready   (TX 产出)
├── channel_frames/   NNNN.wav + NNNN.ready   (Channel daemon 产出)
├── rx_out/           NNNN.meta.json + session_text.log   (RX 产出)
└── session.log
```

帧级 wav 写完 close 后原子创建 `.ready` 标记，下游只读 `.ready` 存在的 wav，避免 Windows 文件锁冲突。

## Phase 进度

| Phase | 目标 | 状态 |
|-------|------|------|
| P1 | 单体制串行 loopback (FH-MFSK) + GUI demo | ✅ 完成 (2026-04-15) |
| P2 | RX 流式帧检测 | 待开始 |
| P3 | 6 体制统一 modem API | 待 P2 |
| P4 | 帧头 FH-MFSK + payload 异构体制路由 | 待 P3 |
| P5 | 三进程并发 | 待 P4 |
| P6 | 物理层 AMC | 待 P5 |

## P1 用法

```matlab
% 命令行测试
clear functions; clear all;
cd modules/14_Streaming/src/Matlab/tests
run('test_p1_loopback_fhmfsk.m');

% 交互式 GUI demo
cd modules/14_Streaming/src/Matlab/ui
p1_demo_ui
```

GUI 含：TX 文本输入 + 信道参数（SNR / Doppler / 衰落类型 / Jakes fd / 预设 / 帧长度）+ RX 解码显示 + 7 个可视化 tab。

## 统一 modem API（P3 目标）

```matlab
[tx_pb, meta] = modem_encode(bits, scheme, sys_params)
[bits, info]  = modem_decode(rx_pb, scheme, sys_params, meta)

% scheme: 0=CTRL, 1=SC-FDE, 2=OFDM, 3=SC-TDE, 4=DSSS, 5=OTFS, 6=FH-MFSK
```

## 帧协议

```
物理帧：[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|Header(FH-MFSK)|Payload(scheme)]
帧头 16B：MAGIC(2) | SCH | IDX | LEN(2) | MOD | FLG | RSVD(2) | SRC(2) | DST(2) | CRC16(2)
Payload：payload_bits | CRC16(2)
```

**关键设计**：Header 永远用 FH-MFSK 调制（最鲁棒），保证控制信息在恶劣信道也可解，支撑 AMC 决策。

## 复用关系

- **不改** 01–12 算法模块
- **不改** 13_SourceCode/tests（保留为算法回归基准）
- 本模块仅做编排、I/O、流式检测、AMC 决策

## 参考

- Master spec: `specs/active/2026-04-15-streaming-framework-master.md`
- P1 spec: `specs/active/2026-04-15-streaming-p1-loopback-fhmfsk.md`
- 项目 CLAUDE.md / wiki/architecture/system-framework.md
