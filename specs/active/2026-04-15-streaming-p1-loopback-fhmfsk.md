---
project: uwacomm
type: task
status: active
created: 2026-04-15
updated: 2026-04-15
parent: 2026-04-15-streaming-framework-master.md
phase: P1
tags: [流式仿真, 14_Streaming, FH-MFSK, loopback]
---

# Streaming P1 — 单体制串行 loopback (FH-MFSK)

## Spec

### 目标

实现文本 → raw.wav → 信道 → channel.wav → 文本的最小闭环，**单体制（FH-MFSK）**，**串行**（TX 写完 → channel 处理完 → RX 读完），**单帧**（文本长度 ≤ 单帧 payload）。

### 原因

作为 streaming 框架的"hello world"，打通数据流骨架：帧头/CRC/wav I/O/文本编解码/帧检测（简化版，信任 LFM 偏移）。FH-MFSK 最鲁棒，先选它最容易看到端到端效果，后续 phase 扩展。

### 范围

**新增文件**：

```
modules/14_Streaming/
├── src/Matlab/
│   ├── tx/
│   │   ├── tx_stream_p1.m                # 入口：tx_stream_p1(text, session, sys)
│   │   ├── frame_packer.m                # bits + header + crc → frame_bits
│   │   └── modem_encode_fhmfsk.m         # P1 临时：FH-MFSK encode（P3 统一）
│   ├── rx/
│   │   ├── rx_stream_p1.m                # 入口：rx_stream_p1(session, sys) → text
│   │   ├── frame_unpacker.m              # frame_bits → header解析 + crc校验 + payload
│   │   └── modem_decode_fhmfsk.m         # P1 临时：FH-MFSK decode（P3 统一）
│   ├── channel/
│   │   └── channel_simulator_p1.m        # raw_frames/NNNN → channel_frames/NNNN
│   ├── common/
│   │   ├── text_to_bits.m                # UTF-8 string → bit array
│   │   ├── bits_to_text.m                # bit array → UTF-8 string
│   │   ├── crc16.m                       # 标准 CRC-16-CCITT
│   │   ├── frame_header.m                # 构造/解析 16B 帧头
│   │   ├── sys_params_default.m          # 默认参数
│   │   ├── create_session_dir.m          # 创建 session_<timestamp>/ 目录结构
│   │   ├── wav_write_frame.m             # 写 NNNN.wav (int16) + touch NNNN.ready
│   │   ├── wav_read_frame.m              # 等 NNNN.ready 就绪后读 NNNN.wav
│   │   └── assemble_physical_frame.m     # [HFM+|..|LFM2|guard|frame_body] 组装
│   └── tests/
│       └── test_p1_loopback_fhmfsk.m     # 串行 loopback 测试
└── README.md
```

**复用（不改）**：
- FH-MFSK 调制/解调：从 `13_SourceCode/tests/FH-MFSK/test_fhmfsk_e2e.m` 提取 encode/decode 部分，包装为临时函数 `modem_encode_fhmfsk.m` / `modem_decode_fhmfsk.m`（P3 再统一 API）
- HFM/LFM 前导码：`08_Sync/` + `09_Waveform/`
- 信道：`13_SourceCode/src/Matlab/common/gen_uwa_channel.m`

### 非目标

- **不做流式检测**（RX 已知 raw.wav 长度，帧起点用 LFM 一次匹配确定）
- **不做多帧**（payload 必须一帧装下）
- **不做三进程并发**（单脚本串行调用 TX→channel→RX）
- **不做其他体制**（FH-MFSK only）
- **不做 AMC**
- **不优化性能**（优先功能正确）

### 验收标准

- [ ] `test_p1_loopback_fhmfsk.m` 运行成功，输入文本 "Hello 水声通信"（UTF-8）
- [ ] 生成 `raw.wav`（48kHz/mono/int16）
- [ ] 信道模拟器生成 `channel.wav`（静态 3 径 + SNR=15dB）
- [ ] RX 输出文本与输入**完全一致**（无误码）
- [ ] header CRC 校验通过，payload CRC 校验通过
- [ ] 断言：帧头 scheme=6 (FH-MFSK)、frame_idx=0、flags.last=1
- [ ] 可视化：TX/RX 时域波形 + LFM 相关峰 + 帧边界标注

---

## Plan

（spec 确认后填写，大致思路）

### 主流程（伪代码）

采用方案 B 目录结构（P5 无缝扩展），P1 串行：

```matlab
% test_p1_loopback_fhmfsk.m
sys = sys_params_default();               % fs=48k, fc=12k, sps=8, ...
session = create_session_dir();           % session_2026-04-15-1830/
text_in = 'Hello 水声通信';

% --- TX: text → session/raw_frames/0001.wav + 0001.ready ---
tx_stream_p1(text_in, session, sys);

% --- Channel: raw_frames/0001.ready → channel_frames/0001.wav ---
ch_params = struct('fading_type','static', 'snr_db',15, ...);
channel_simulator_p1(session, ch_params, sys);

% --- RX: channel_frames/0001.ready → rx_out/0001.meta.json + text ---
text_out = rx_stream_p1(session, sys);

% --- 核验 ---
assert(strcmp(text_in, text_out), 'loopback 失败');
```

**会话目录（P1 只产出 1 帧，结构与 P5 一致）**：
```
session_2026-04-15-1830/
├── raw_frames/     0001.wav + 0001.ready
├── channel_frames/ 0001.wav + 0001.ready
├── rx_out/         0001.meta.json + session_text.log
└── session.log
```

### tx_stream_p1 内部

```matlab
function tx_stream_p1(text, out_wav, sys)
  bits_payload = text_to_bits(text);            % UTF-8
  payload_len  = length(bits_payload);
  assert(payload_len <= sys.max_payload_bits, 'payload 超单帧上限');
  
  % 构 payload (补零到固定长度 + crc)
  crc_p = crc16(bits_payload);
  bits_payload_padded = [bits_payload, zeros(1, sys.payload_bits - payload_len), crc_p];
  
  % 构 header (16B)
  hdr = frame_header('pack', struct('scheme',6, 'idx',0, 'len',payload_len, ...
                                     'mod_level',1, 'flags',1, ...
                                     'src',0, 'dst',0));
  % 拼 frame_bits = [header | payload]
  frame_bits = [hdr, bits_payload_padded];
  
  % FH-MFSK 调制 (header + payload 合并一起编，P1 简化)
  [tx_pb, meta] = modem_encode_fhmfsk(frame_bits, sys);
  
  % 拼 HFM/LFM 前导 + frame_body
  frame_wav = assemble_physical_frame(tx_pb, sys);   % 复用现有 HFM/LFM 帧组装
  
  wav_writer_int16(frame_wav, out_wav, sys.fs);
end
```

### rx_stream_p1 内部

```matlab
function text = rx_stream_p1(in_wav, sys)
  [rx_pb, fs] = wav_reader_int16(in_wav);
  assert(fs == sys.fs);
  
  % 一次匹配滤波找 LFM → 定帧起点
  lfm_pos = detect_lfm_start(rx_pb, sys);    % 复用现有 LFM 匹配滤波
  
  % 提取 frame_body
  body_start = lfm_pos + sys.lfm_data_offset;
  body_len   = sys.frame_body_len;
  rx_body_pb = rx_pb(body_start : body_start + body_len - 1);
  
  % FH-MFSK 解调
  frame_bits = modem_decode_fhmfsk(rx_body_pb, sys);
  
  % 解帧头
  hdr_bits = frame_bits(1:sys.header_bits);
  hdr = frame_header('unpack', hdr_bits);
  assert(hdr.crc_ok, 'header CRC 失败');
  assert(hdr.scheme == 6, 'scheme 不是 FH-MFSK');
  
  % 解 payload
  payload_bits = frame_bits(sys.header_bits+1 : sys.header_bits + sys.payload_bits);
  payload_crc  = frame_bits(sys.header_bits + sys.payload_bits + 1 : sys.header_bits + sys.payload_bits + 16);
  assert(isequal(crc16(payload_bits(1:hdr.len)), payload_crc), 'payload CRC 失败');
  
  text = bits_to_text(payload_bits(1:hdr.len));
end
```

### 关键参数（sys_params_default）

| 参数 | 值 | 说明 |
|------|-----|------|
| fs | 48000 | 采样率 |
| fc | 12000 | 载频 |
| sps | 8 | 每符号采样数 |
| sym_rate | 6000 | 符号率 |
| rolloff | 0.35 | RRC |
| preamble_dur | 0.05 | HFM/LFM 时长 (s) |
| guard_samp | 800 | 前导码 guard |
| header_bits | 128 | 16B 帧头比特数 |
| payload_bits | 512 | payload 负载（固定，P1 够装 "Hello 水声通信" UTF-8 ~30B=240bits） |
| max_payload_bits | 512 | P1 单帧上限（同 payload_bits） |

### 影响文件

| 文件 | 变更 | 说明 |
|------|------|------|
| 全部 P1 新文件 | 新建 | 见上 |
| 13_SourceCode | **不改** | 保留为算法回归 |
| 01–12 模块 | **不改** | |

### 测试策略

1. **单元测试**：`text_to_bits`/`bits_to_text` 往返一致，`crc16` 标准向量，`frame_header` pack/unpack 往返一致
2. **loopback 无信道**：gain=1，SNR=Inf，验证编解码路径
3. **loopback 含信道**：static 3 径 + SNR=15dB，验证 FH-MFSK 能解
4. **可视化**：TX/RX 波形、LFM 相关峰、解调星座（FH-MFSK 能量）、比特误差定位

### 风险

| 风险 | 概率 | 应对 |
|------|------|------|
| FH-MFSK 的 encode/decode 在 test 脚本里内嵌，提取麻烦 | 中 | 直接 copy test 代码段进临时函数，P3 再重构 |
| UTF-8 中文字符 byte 序列需正确处理 | 中 | 用 MATLAB `unicode2native('text','UTF-8')` / `native2unicode` |
| wav int16 归一化丢失动态范围 | 低 | 信号先归一到 [-0.95, 0.95]，scale 系数可选记录 |
| 帧长不满足 HFM+LFM+body 累加 | 低 | 先计算总长度，doc 里标注 |

---

## Log

（执行时追加）

---

## Result

（完成后填写）
