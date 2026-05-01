# 14_Streaming — 流式通信仿真框架

> **状态**：P1-P4 完成（2026-05-01），P5 三进程并发 + P6 AMC 待启动
> **Master Spec**：`specs/active/2026-04-15-streaming-framework-master.md`
> **里程碑**：P1 (FH-MFSK loopback) → P2 (流式帧检测) → P3 (统一 modem API + 6 体制 + 深色 UI + 真同步) → P4 (scheme routing + 真多普勒 + Jakes + α refinement + bypass=ON 路径修复)

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
│   ├── amc/         # [P6 占位，待实现] 链路质量估计 + 体制选择，见 specs/active/2026-04-15-streaming-p6-amc.md
│   ├── common/      # 文本↔比特 / 帧头 / CRC / session 管理 / wav I/O
│   ├── ui/          # P1/P2/P3 交互 demo + 样式/动效 helper
│   └── tests/
├── README.md
```

## UI helper 模块（2026-04-17 视觉升级引入）

位于 `src/Matlab/ui/`，供 `p3_demo_ui.m` 统一深色科技风 + 通信声纳主题：

| 文件 | 职责 |
|------|------|
| `p3_style.m` | 色板 / 字体 / 尺寸 / 发光参数的**单一事实源**，返回 struct(PALETTE,FONTS,SIZES,GLOW) |
| `p3_pick_font.m` | 按优先级探测可用字体，缺失时 fallback `'monospaced'` |
| `p3_semantic_color.m` | 关键词（收敛/未收敛/进行中/失败/空闲）→ 前景/背景 RGB |
| `p3_metric_card.m` | 指标卡（label + value + unit 三层），返回 handles 供 UI 更新 |
| `p3_sonar_badge.m` | 顶栏声纳波纹装饰（3 道同心弧 + 扫描线 patch）|
| `p3_animate_tick.m` | on_tick 动效：呼吸灯 / 检测闪烁 / 解码 flash / FIFO 进度 |
| `p3_plot_channel_stem.m` | 彩色 stem 绘信道抽头，\|h\| 梯度 cyan→amber |
| `p3_style_axes.m` | 深色 axes 统一样式（grid / 字体 / 颜色） |
| `p3_channel_tap.m` | 按 scheme + preset 构造信道抽头（refactor 抽出） |
| `p3_downconv_bw.m` | scheme → 接收端下变频带宽（refactor 抽出） |
| `p3_text_capacity.m` | scheme → 最大文本字节数单一事实源（refactor 抽出） |
| `p3_render_quality.m` | 质量历史 tab（BER + SNR + iter 演进，scheme 分色） |
| `p3_render_sync.m` | 同步/多普勒 tab（HFM+/- 匹配滤波 + 符号级 scheme 分支 + 偏差轨迹） |

`common/detect_frame_stream.m`（2026-04-17 引入）：流式帧检测器，P3 demo UI 真同步核心。
替代旧 `frame_start_write` 共享捷径，对 passband FIFO 尾部做 downconvert + HFM+ 匹配滤波定位帧起点。
单元测试 `tests/test_detect_frame_stream.m`：AWGN -5~15dB / 多径场景 6/6 PASS，位置偏差 ≤ 1 样本。

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
| P2 | RX 流式帧检测 + 多帧 + 软判决 LLR + GUI | ✅ 完成 (2026-04-15) |
| P3.1 | 统一 modem API + FH-MFSK + SC-FDE + GUI | ✅ 完成 (2026-04-15) |
| P3.2 | OFDM + SC-TDE 接入统一 API | 待 P3.1 |
| P3.3 | DSSS + OTFS 接入统一 API | 待 P3.2 |
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

## P2 用法

```matlab
% 命令行测试
clear functions; clear all;
cd modules/14_Streaming/src/Matlab/tests
run('test_p2_multiframe.m');

% 交互式 GUI demo（多帧）
cd modules/14_Streaming/src/Matlab/ui
p2_demo_ui
```

GUI 含：长文本输入 + 容量提示自动算帧数 + RX 解码文本 + 帧明细 uitable + 7 个可视化 tab（含"帧检测"匹配滤波 panel）。

P2 vs P1 关键差异：
- 文本任意长度自动按 UTF-8 字节边界切多帧
- 多帧串联在单 wav 文件内
- RX 用滑动 HFM+ 匹配滤波自动检测帧边界（hybrid 模式：首帧锚定 + 后续帧预测窗口）
- FH-MFSK 解码改软判决 LLR（对 Jakes 衰落更鲁棒）
- 缺帧用 `[missing frame N]` 占位，CRC 失败的帧不影响其他帧

## P3.1 用法

```matlab
% 命令行测试（FH-MFSK + SC-FDE 双体制基带回归）
clear functions; clear all;
cd modules/14_Streaming/src/Matlab/tests
run('test_p3_unified_modem.m');

% 交互式 GUI demo（流式 — RX 持续监听 + TX 触发）
cd modules/14_Streaming/src/Matlab/ui
p3_demo_ui
```

GUI（V2 流式版）：
- 顶部：scheme 下拉（FH-MFSK / SC-FDE）+ **RX 监听开关** + status + Transmit 按钮
- 工作流：先打开 RX 开关 → 配置参数 → 点 Transmit → TX 切片入 FIFO → 实时通带示波器更新 → 累积满帧自动解调显示 BER/info
- TX 参数（沿用 P1/P2 风格）：文本（默认值可改）+ SNR + Doppler + 衰落类型 + Jakes fd + 信道预设；scheme 切换动态显示参数（SC-FDE: blk_fft / Turbo iter；FH-MFSK: payload bits）
- RX 面板：解码文本 + BER 大字 + info 6 字段（estimated_snr/ber, turbo_iter, convergence, noise_var, 解码次数）+ TX/RX bits 对比 + FIFO/队列状态
- 5 tab：**实时通带示波器**（最近 0.4s 真实 passband real 信号，timer 100ms 刷新）、通带频谱、均衡前星座/能量矩阵、均衡后星座/LLR、CIR + Hest 频响
- 单进程 timer 模拟流（chunk_ms=50, tick=100ms → 2× 加速）；跳过 wav/session，便于即点即看

## 统一 modem API

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
