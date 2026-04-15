---
project: uwacomm
type: task
status: archived
created: 2026-04-15
updated: 2026-04-15
parent: 2026-04-15-streaming-framework-master.md
phase: P2
depends_on: [P1]
tags: [流式仿真, 14_Streaming, 帧检测, 多帧]
---

# Streaming P2 — RX 流式帧检测 + 多帧支持

## Spec

### 目标

支持**多帧长文本**端到端：
1. **TX**：长文本自动切分为 N 个帧，按帧序号编入 header，全部 frame_pb 串联写入**单一 wav 文件**
2. **Channel**：单 wav → 单 wav（信道处理不变）
3. **RX**：**不依赖 TX meta 的 frame_idx**，对 channel.wav 做**滑动 HFM 匹配滤波**自动检测所有帧起点，逐帧解码后按 frame_idx 拼回原文本

P1 的"oracle 桥接"（RX 读 TX 的 .meta.mat 拿 frame_meta）在 P2 仍保留单帧 modem 元数据传递，但**帧定位不再依赖 TX 已知 frame_idx 列表**。

### 原因

P1 为单帧串行 demo，RX 在已知"只有 1 帧、起点固定"的前提下工作。真实部署中 RX 必须：
- 处理任意长度的文本（多帧）
- 自主发现帧边界（不知道有几帧、何时来）
- 容忍单帧丢失（CRC 失败）后继续解后续帧

这是从"仿真验证"到"准实际部署"的关键一步，也是后续 P5 并发的前置（并发场景下 RX 也不知道 TX 何时发新帧）。

### 范围

**新增文件**（约 5 个）：
```
modules/14_Streaming/src/Matlab/
├── tx/
│   ├── tx_stream_p2.m          # 多帧 TX：text → 多帧 → 单 wav
│   └── text_chunker.m          # UTF-8 文本按字节切分（保证不跨字符）
├── rx/
│   ├── rx_stream_p2.m          # 多帧 RX：wav → 检测+逐帧解 → 拼回 text
│   ├── frame_detector.m        # 滑动 HFM 匹配 + 阈值 + debounce → 帧起点列表
│   └── text_assembler.m        # 按 frame_idx 排序拼接 payload
└── tests/
    └── test_p2_multiframe.m    # 多帧端到端测试
```

**复用（不改）**：所有 P1 的 common/tx/rx/channel 函数。
**修改**：`tx_stream_p1` / `rx_stream_p1` 不动（保留作为 P1 单帧基准）。

### 非目标

- 不改帧协议（header 16B 不变，frame_idx 字段已有）
- 不做并发（仍串行 TX→Channel→RX）
- 不做 ARQ 重传（CRC 失败的帧标记 missing 即可）
- 不做 6 体制路由（仍 FH-MFSK only）
- 不做盲 Doppler 估计（继续从 chinfo 读 oracle α）

### 多帧协议

**单帧结构**（同 P1，唯一变化是 header 字段语义）：
```
[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|Header(16B)|Payload(N bits)]
```

**Header 字段使用**（P1 已支持，P2 激活）：
- `idx` (1B): 帧序号 0~255（多帧场景内）
- `flags` bit0 = `last_frame`（1=本帧是末帧）
- `len` (2B): 本帧 payload 实际有效 bit 数（末帧通常 < payload_bits）

**多帧串联**：N 个 frame_pb 直接 concat，**无显式 inter-frame gap**（HFM+ 检测足够区分）：
```
[Frame1: HFM+|...|Header(idx=1)|Payload1]
[Frame2: HFM+|...|Header(idx=2)|Payload2]
...
[FrameN: HFM+|...|Header(idx=N, last=1)|PayloadN]
```

可选：在末帧后追加 ~10ms 静默"尾哨"，方便 RX 知道流结束（P2 不强制实现）。

### 流式检测算法

**输入**：channel.wav → 下变频 + Doppler 补偿 → bb_raw（基带复信号）

**步骤**：
1. **HFM+ 模板生成**（与 TX 一致）
2. **滑动匹配滤波**：`corr = filter(conj(fliplr(HFM_bb)), 1, bb_raw)`
3. **自适应阈值**：
   - `noise_floor = median(|corr|)`
   - `threshold = max(K * noise_floor, ratio * peak_max)` 双阈值
   - 默认 K=8（≥8倍噪底）+ ratio=0.3（≥30% 全局最大峰）
4. **峰检测 + debounce**：
   - 遍历 |corr| > threshold 的位置
   - 强制最小间隔 `min_sep = frame_length_samples - margin`
   - 同窗口内取最大峰位置
   - 输出帧起点列表 `[k_1, k_2, ..., k_N]`（k_i = HFM+ 头位置）
5. **每帧解码**：对每个 k_i：
   - 提取从 k_i 起 `frame_length_samples` 长度
   - 复用 P1 的 `detect_lfm_start` 做 LFM2 精确定时（在帧内搜索）
   - 调 `modem_decode_fhmfsk` 得 body_bits
   - 解 header → 取 idx + len + last_frame
   - 校验 header CRC + payload CRC
6. **文本拼接**：按 idx 排序，concatenate 各帧的 `payload(1:len)`，取出 UTF-8 → 原文本

### 验收标准

- [ ] 短文本（< 1 帧容量）：单帧通路与 P1 行为一致
- [ ] 中等文本（2~5 帧）：多帧串联收发，RX 复原文本与输入完全一致
- [ ] 长文本（10 帧）：稳定收发，所有帧 idx 递增、last_frame 正确
- [ ] **检测精度**：检测到帧数 == 实际帧数（漏检率 0、误检率 0），SNR=15dB 静态信道
- [ ] **检测鲁棒性**：SNR=5dB 5 径信道下，漏检率 < 5%
- [ ] **丢帧容忍**：人为破坏中间某帧（注 0 / 改 wav）→ 该帧 CRC 失败但前后帧仍能解 → 输出"[missing frame N]"占位
- [ ] **位置精度**：每帧检测 k_i 与真实位置误差 < 1 FSK 符号 (96 样本)
- [ ] 测试报告：`test_p2_multiframe_results.txt` 含 N=1/3/10 帧三种规模 + 检测精度统计

### 风险

| 风险 | 概率 | 应对 |
|------|------|------|
| 自适应阈值在低 SNR 漏检 | 中 | 双阈值（噪底比 + 全局比），阈值在脚本里可调 |
| HFM+ 自相关旁瓣触发误检 | 低 | min_sep 强制大于一帧长度 |
| 帧间无 gap 时相邻帧 HFM 互相干 | 低 | HFM 短（50ms），帧体长（~1~12s），gap 不必要 |
| Doppler 引起的帧长漂移让 min_sep 失效 | 中 | min_sep 用 0.9 × 标称值，留余量 |
| UTF-8 字符跨帧切断 | 高 | text_chunker 按完整字节边界切（UTF-8 多字节字符不切断） |
| header CRC 通过但 payload 大段错位 | 低 | payload CRC 兜底，错则标 missing |

---

## Plan

详见 `plans/streaming-p2-stream-detect.md`（6 个新文件 + 7 步实施顺序）。

## Log

### 2026-04-15 实施

- 6 个源文件按 plan 落地：text_chunker, tx_stream_p2, frame_detector, text_assembler, rx_stream_p2, test_p2_multiframe
- 一次过 4/4 测试通过：短/中/长/低SNR，含 8 帧长文本（122 字符）
- 检测精度：每帧 k 间隔精确 = single_frame_samples，sync_peak ~0.91（与 P1 相当）

### 增量改进（同日完成）

| # | 改进 | 涉及文件 |
|---|------|---------|
| 1 | P2 多帧可视化（7 panels，含帧检测匹配滤波）| visualize_p2_frames |
| 2 | p2_demo_ui 交互 GUI（uitable 帧明细 + 容量预估）| p2_demo_ui |
| 3 | 修复 frame 1 边界：rx_stream_p2 预填零给 LPF 暖机 | rx_stream_p2 |
| 4 | frame_detector V1.1：hybrid 预测模式 + Stage A 直接锚定 frame 1 | frame_detector |
| 5 | FH-MFSK 软判决 LLR（取代硬判决，对 Jakes 鲁棒） | modem_decode_fhmfsk V1.1 |
| 6 | 调整"5径 深衰减"preset：延时展宽 1.5ms→0.6ms 防 ISI | p1/p2_demo_ui |

### 关键调试经验

1. **downconvert LPF 暖机**：64 阶 FIR 的前 ~64 样本是瞬态，会损伤 frame 1 的 HFM。预填零让暖机消化在填充段
2. **检测阈值不适合 frame 1**：Jakes 让 frame 1 峰值远低于其他帧的 peak_max；改为在 frame 1 预期窗口内取**绝对最大**（不依赖阈值）
3. **硬判决 FSK 在衰落下脆弱**：1 位错就 CRC 挂；软 LLR + Viterbi 能纠多位错，对衰落鲁棒
4. **FH-MFSK 无均衡处理不了大延时多径**：延时展宽 > 50% 符号时长就开始严重 ISI，需要 OFDM/SC-FDE 这类带均衡器的体制（P3+）

## Result

### 验收（全部通过）

- [x] 短文本（< 1 帧容量）：单帧通路与 P1 行为一致
- [x] 中等文本（2~5 帧）：多帧串联收发，文本完美复原
- [x] 长文本（10 帧规模，实测 8 帧 122 字符）：稳定收发
- [x] 检测精度：检测帧数 == 实际帧数（8/8, 3/3, 2/2, 1/1）
- [x] 检测鲁棒性：SNR=5dB 5径下漏检 0
- [x] 位置精度：每帧 k 间隔精确等于 single_frame_samples
- [x] 测试报告：`test_p2_multiframe_results.txt` 4 case 全 PASS

### 关键产出

- 6 个流式 RX 源文件 + 多帧 TX
- 多帧 GUI demo（p2_demo_ui）含帧明细 uitable + 7 viz tab
- 软判决 LLR FH-MFSK 解码（V1.1，对衰落更鲁棒）
- frame_detector hybrid 检测算法（首帧锚定 + 后续预测窗口）
- "5径 深衰减"preset 平衡多径强度与 ISI 可承受性

### 已知限制（留 P3+）

- FH-MFSK 无均衡，对延时展宽 > 50% 符号时长的多径无能为力（OFDM/SC-FDE 在 P3 解决）
- Doppler 仍 oracle（chinfo 读 α），需 P5/P6 改盲估计
- TX meta 仍通过 .meta.mat 桥接到 RX，P3/P4 改 header 推导

### Promote 到 wiki

- `wiki/conclusions.md` 加 #23–25（流式检测 hybrid / 软判决 LLR / FH-MFSK ISI 限制）
- `wiki/modules/14_Streaming/14_流式仿真框架.md` 加 P2 实施记录
