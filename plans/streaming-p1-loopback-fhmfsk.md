---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-15-streaming-p1-loopback-fhmfsk.md
master_spec: specs/active/2026-04-15-streaming-framework-master.md
created: 2026-04-15
tags: [14_Streaming, P1, FH-MFSK, loopback]
---

# Streaming P1 — FH-MFSK Loopback 实施计划

## 总体架构

```
test_p1_loopback_fhmfsk.m
├── sys = sys_params_default()
├── session = create_session_dir()
├── tx_stream_p1(text, session, sys)
│     ├── text_to_bits → UTF-8 bits
│     ├── frame_packer → [header_bits | payload_bits | payload_crc]
│     ├── modem_encode_fhmfsk(frame_bits, sys) → fsk_bb + meta
│     ├── assemble_physical_frame(fsk_bb, sys) → frame_bb (带 HFM/LFM)
│     ├── upconvert(frame_bb) → frame_pb
│     └── wav_write_frame(frame_pb, session/raw_frames/0001) → 0001.wav + 0001.ready
├── channel_simulator_p1(session, ch_params, sys)
│     ├── wav_read_frame(session/raw_frames/0001) → frame_pb
│     ├── gen_uwa_channel(baseband) + upconvert + 加噪
│     └── wav_write_frame → session/channel_frames/0001.wav + 0001.ready
└── rx_stream_p1(session, sys) → text
      ├── wav_read_frame(session/channel_frames/0001) → rx_pb
      ├── downconvert → bb_raw
      ├── detect_lfm_start(bb_raw, sys) → lfm_pos（P1：单帧用一次匹配）
      ├── extract frame_body
      ├── modem_decode_fhmfsk(frame_body, sys, meta) → frame_bits
      ├── frame_unpacker → header + payload
      ├── 校验 crc
      └── bits_to_text → text_out
```

P1 **meta** 由 TX 生成后通过 session/0001.meta.json 传给 RX（P3/P4 再改为从 header 推导）。

---

## 参数设计（sys_params_default）

基于现有 `13_SourceCode/common/sys_params.m` 中 `FH-MFSK` case，但 P1 的 N_info 由 payload 长度动态算：

```matlab
function sys = sys_params_default()
  % 基本
  sys.fs         = 48000;    % 采样率
  sys.fc         = 12000;    % 载频
  sys.sym_rate   = 6000;     % （FH-MFSK 不使用 sym_rate，预留给其他体制）
  sys.sps        = 8;

  % 编解码
  sys.codec.gen_polys      = [7,5];
  sys.codec.constraint_len = 3;
  sys.codec.interleave_seed= 7;
  sys.codec.decode_mode    = 'max-log';

  % FH-MFSK 子结构
  sys.fhmfsk.M              = 8;         % 8-FSK
  sys.fhmfsk.bits_per_sym   = 3;
  sys.fhmfsk.num_freqs      = 16;
  sys.fhmfsk.freq_spacing   = 500;
  sys.fhmfsk.sym_duration   = 1/500;     % 2 ms
  sys.fhmfsk.samples_per_sym= round(sys.fhmfsk.sym_duration * sys.fs);  % 96
  sys.fhmfsk.fb_base        = ((0:15) - 8) * 500;                        % [-4000..3500]
  sys.fhmfsk.total_bw       = 16 * 500;  % 8000 Hz
  sys.fhmfsk.hop_seed       = 42;

  % 帧协议（P1 固定单帧）
  sys.frame.magic        = uint16(hex2dec('A5C3'));
  sys.frame.header_bytes = 16;
  sys.frame.header_bits  = sys.frame.header_bytes * 8;  % 128
  sys.frame.payload_bits = 512;                          % 固定 payload（含补零）
  sys.frame.payload_crc_bits = 16;
  sys.frame.body_bits    = sys.frame.header_bits + sys.frame.payload_bits + sys.frame.payload_crc_bits;  % 656

  % 前导码
  sys.preamble.dur        = 0.05;
  sys.preamble.guard_samp = round(max([0, 1, 3, 5, 8])/sys.fhmfsk.freq_spacing * sys.fs) + 80;  % 与 FH-MFSK 对应
  % 注：guard 基于信道最大时延；P1 先用 static 时延上限 8 符号
  sys.preamble.bw_lfm     = sys.fhmfsk.total_bw;   % 与数据同带宽

  % wav
  sys.wav.bit_depth = 16;
  sys.wav.channels  = 1;
  sys.wav.scale     = 0.95;   % int16 前归一化上限
end
```

**关键数字**：
- frame_body_bits = 656
- 656 bits → 656/3 ≈ 219 FSK 符号（补零到 3 的倍数 = 219*3 = 657）→ 其实 656 不是 3 的倍数，需补 1 bit
- 取 `N_coded_padded = ceil(body_bits/3)*3 = 657` 实际 FSK 符号数 = 219
- 但这里 body_bits 经过卷积编码后才是实际发射的：656 info-like bits → conv_encode 产出 (656+mem)*2 = 1316 coded bits → FSK 符号 = ceil(1316/3)*3 = 1317 → 439 sym
- **更正**：modem_encode 的输入已经是"需要发射的全部 bits"（包含 header+payload+crc），这些 bits **本身也要经过卷积编码**
- 预估：body_bits=656 → coded=1316 → padded=1317 → FSK_sym=439 → data_samples=439*96=42144 → 数据段时长 ≈ 0.88s

这个单帧长度可接受。

---

## 文件清单与签名

### common/ (10 个)

#### 1. `text_to_bits.m`

```matlab
function bits = text_to_bits(text)
  % UTF-8 编码 → byte array → bit array (MSB first)
  bytes = unicode2native(text, 'UTF-8');
  bits = zeros(1, length(bytes)*8, 'uint8');
  for i = 1:length(bytes)
    bits((i-1)*8+1 : i*8) = bitget(bytes(i), 8:-1:1);
  end
  bits = double(bits);
end
```

#### 2. `bits_to_text.m`

```matlab
function text = bits_to_text(bits)
  % bit array → byte array → UTF-8 解码
  assert(mod(length(bits), 8) == 0, 'bits 长度必须是 8 的倍数');
  N_bytes = length(bits) / 8;
  bytes = zeros(1, N_bytes, 'uint8');
  for i = 1:N_bytes
    b = bits((i-1)*8+1 : i*8);
    bytes(i) = sum(b .* (2.^(7:-1:0)));
  end
  text = native2unicode(bytes, 'UTF-8');
end
```

**断言**：`bits_to_text(text_to_bits('Hello 水声')) == 'Hello 水声'`（UTF-8 往返）。

#### 3. `crc16.m`

标准 **CRC-16-CCITT**（polynomial 0x1021, init 0xFFFF, no refl）：

```matlab
function crc_bits = crc16(bits)
  % 输入：bits (1×N, 0/1)，不要求 8 对齐（内部按位处理）
  % 输出：crc_bits (1×16, 0/1, MSB first)
  crc = uint16(hex2dec('FFFF'));
  for i = 1:length(bits)
    crc = bitxor(crc, bitshift(uint16(bits(i)), 15));
    if bitand(crc, hex2dec('8000')) ~= 0
      crc = bitxor(bitshift(crc, 1), hex2dec('1021'));
    else
      crc = bitshift(crc, 1);
    end
    crc = bitand(crc, hex2dec('FFFF'));
  end
  crc_bits = bitget(crc, 16:-1:1);
  crc_bits = double(crc_bits);
end
```

**断言**：`crc16([1 0 1 0 ...])` 对已知序列与在线 CRC 计算器一致。

#### 4. `frame_header.m`

```matlab
function out = frame_header(op, input, sys)
  % op = 'pack'   : input=struct{scheme,idx,len,mod_level,flags,src,dst}
  %                 输出：out = bit array (128 bits)
  % op = 'unpack' : input=bit array (128 bits)
  %                 输出：out = struct{..., crc_ok}
  if strcmp(op, 'pack')
    bytes = zeros(1, 16, 'uint8');
    bytes(1:2) = typecast(uint16(sys.frame.magic), 'uint8');   % little-endian? 用 big-endian 更可读
    bytes(3)   = uint8(input.scheme);
    bytes(4)   = uint8(input.idx);
    bytes(5:6) = uint8(bitget(uint16(input.len), 16:-1:1));     % 伪代码，细节看实现
    bytes(7)   = uint8(input.mod_level);
    bytes(8)   = uint8(input.flags);
    bytes(9:10)= 0;                                             % RSVD
    bytes(11:12)= uint8(bitget(uint16(input.src), 16:-1:1));
    bytes(13:14)= uint8(bitget(uint16(input.dst), 16:-1:1));
    % CRC16 over bytes(1:14)
    tmp_bits = bytes_to_bits(bytes(1:14));
    crc_bits = crc16(tmp_bits);
    bytes(15:16) = bits_to_bytes(crc_bits);
    out = bytes_to_bits(bytes);
  else  % unpack
    bits = input;
    assert(length(bits) == 128);
    bytes = bits_to_bytes(bits);
    out = struct();
    out.magic     = typecast(bytes(1:2), 'uint16');
    out.scheme    = bytes(3);
    out.idx       = bytes(4);
    out.len       = bits_to_uint16(bits(33:48));
    out.mod_level = bytes(7);
    out.flags     = bytes(8);
    out.src       = bits_to_uint16(bits(81:96));
    out.dst       = bits_to_uint16(bits(97:112));
    % 校验 CRC
    crc_recv = bits(113:128);
    crc_calc = crc16(bits(1:112));
    out.crc_ok = isequal(crc_recv(:)', crc_calc(:)');
  end
end
```

**辅助**：`bytes_to_bits` / `bits_to_bytes` / `bits_to_uint16` 内联小函数。

#### 5. `sys_params_default.m`

见上"参数设计"。

#### 6. `create_session_dir.m`

```matlab
function session = create_session_dir(root)
  if nargin < 1 || isempty(root), root = fullfile(pwd, 'sessions'); end
  ts = datestr(now, 'yyyy-mm-dd-HHMMSS');
  session = fullfile(root, ['session_' ts]);
  for d = {'raw_frames', 'channel_frames', 'rx_out'}
    mkdir(fullfile(session, d{1}));
  end
  % 写 session.log 标头
  fid = fopen(fullfile(session, 'session.log'), 'w');
  fprintf(fid, '[%s] session created: %s\n', datestr(now), session);
  fclose(fid);
end
```

#### 7. `wav_write_frame.m`

```matlab
function wav_write_frame(frame_pb, session_subdir, frame_idx, sys)
  % session_subdir: e.g., fullfile(session, 'raw_frames')
  % frame_idx: 整数（0 或从 1 开始，protocol 内部）
  wav_name = sprintf('%04d.wav', frame_idx);
  ready_name = sprintf('%04d.ready', frame_idx);
  wav_path   = fullfile(session_subdir, wav_name);
  ready_path = fullfile(session_subdir, ready_name);

  % 归一化到 [-scale, scale]
  max_abs = max(abs(frame_pb));
  if max_abs > 0
    frame_pb = frame_pb * (sys.wav.scale / max_abs);
  end
  % 写 wav（audiowrite 自动处理 int16 转换）
  audiowrite(wav_path, frame_pb, sys.fs, 'BitsPerSample', 16);

  % 同时写一个 meta 记录归一化因子（RX 反归一化用）
  meta = struct('scale_factor', sys.wav.scale / max_abs, 'frame_idx', frame_idx);
  meta_path = fullfile(session_subdir, sprintf('%04d.scale.mat', frame_idx));
  save(meta_path, '-struct', 'meta');

  % 原子创建 .ready 标记（fopen+fclose，OS 保证可见性）
  fid = fopen(ready_path, 'w');
  fprintf(fid, '%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'));
  fclose(fid);
end
```

#### 8. `wav_read_frame.m`

```matlab
function [frame_pb, fs] = wav_read_frame(session_subdir, frame_idx, wait_timeout)
  if nargin < 3, wait_timeout = 10; end   % 秒
  wav_name   = sprintf('%04d.wav', frame_idx);
  ready_name = sprintf('%04d.ready', frame_idx);
  ready_path = fullfile(session_subdir, ready_name);
  wav_path   = fullfile(session_subdir, wav_name);

  % 等 .ready 存在（poll 0.1s）
  t_start = tic;
  while ~exist(ready_path, 'file')
    if toc(t_start) > wait_timeout
      error('wav_read_frame: 等待 %s 超时 (%ds)', ready_path, wait_timeout);
    end
    pause(0.1);
  end

  [frame_pb, fs] = audioread(wav_path);
  frame_pb = frame_pb(:).';  % 行向量

  % 反归一化（若存在 .scale.mat）
  scale_path = fullfile(session_subdir, sprintf('%04d.scale.mat', frame_idx));
  if exist(scale_path, 'file')
    s = load(scale_path);
    frame_pb = frame_pb / s.scale_factor;
  end
end
```

#### 9. `assemble_physical_frame.m`

```matlab
function [frame_bb, meta] = assemble_physical_frame(body_bb, sys)
  % body_bb: 基带数据段（FSK 波形）
  % frame_bb: 完整基带帧 [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|body]
  fs = sys.fs; fc = sys.fc;
  bw = sys.preamble.bw_lfm;
  dur = sys.preamble.dur;
  guard = sys.preamble.guard_samp;

  f_lo = fc - bw/2; f_hi = fc + bw/2;
  [HFM_pb, ~] = gen_hfm(fs, dur, f_lo, f_hi);
  N_pre = length(HFM_pb);
  t_pre = (0:N_pre-1)/fs;

  % HFM+ 基带
  k_hfm = f_lo*f_hi*dur/(f_hi-f_lo);
  phase_hfm = -2*pi*k_hfm*log(1 - (f_hi-f_lo)/f_hi*t_pre/dur);
  HFM_bb = exp(1j*(phase_hfm - 2*pi*fc*t_pre));

  % HFM- 基带
  k_neg = f_hi*f_lo*dur/(f_lo-f_hi);
  phase_neg = -2*pi*k_neg*log(1 - (f_lo-f_hi)/f_lo*t_pre/dur);
  HFM_bb_neg = exp(1j*(phase_neg - 2*pi*fc*t_pre));

  % LFM 基带
  chirp_rate = (f_hi - f_lo)/dur;
  phase_lfm = 2*pi*(f_lo*t_pre + 0.5*chirp_rate*t_pre.^2);
  LFM_bb = exp(1j*(phase_lfm - 2*pi*fc*t_pre));
  N_lfm = length(LFM_bb);

  % 功率归一化
  [body_pb_ref, ~] = upconvert(body_bb, fs, fc);
  body_rms = sqrt(mean(body_pb_ref.^2));
  scale = body_rms / sqrt(mean(HFM_pb.^2));

  HFM_bb  = HFM_bb  * scale;
  HFM_bb_neg = HFM_bb_neg * scale;
  LFM_bb  = LFM_bb  * scale;

  frame_bb = [HFM_bb, zeros(1,guard), HFM_bb_neg, zeros(1,guard), ...
              LFM_bb, zeros(1,guard), LFM_bb, zeros(1,guard), body_bb];

  meta = struct('N_pre', N_pre, 'N_lfm', N_lfm, 'guard_samp', guard, ...
                'lfm2_peak_nom', 2*N_pre + 3*guard + 2*N_lfm, ...
                'data_offset_from_lfm_head', N_lfm + guard);
end
```

**复用**：`gen_hfm` (08_Sync), `upconvert` (09_Waveform)。

#### 10. `gen_uwa_channel_pb.m` (passband 原生信道，方案 A)

```matlab
function [rx_pb, ch_info] = gen_uwa_channel_pb(tx_pb, ch_params, fc)
  % 功能：passband 原生水声信道 — 多径卷积 + 多普勒 resample + passband AWGN
  % 版本：V1.0.0 (P1 仅支持 static，P5/P6 扩展 Jakes 时变)
  % 输入：
  %   tx_pb     - 发射 passband 实信号 (1×N)
  %   ch_params - .fs, .delays_s, .gains (complex bb), .doppler_rate,
  %               .fading_type ('static' only for P1), .snr_db, .seed
  %   fc        - 载波频率 (Hz)
  % 输出：
  %   rx_pb     - 接收 passband 实信号
  %   ch_info   - .delays_samp, .gains_pb (real), .noise_var
  assert(strcmpi(ch_params.fading_type, 'static'), ...
    'P1 gen_uwa_channel_pb 仅支持 static (Jakes 时变 P5/P6 补)');

  fs = ch_params.fs;
  delays_samp = round(ch_params.delays_s * fs);
  % 基带复增益 → passband 实增益：考虑载波相位延迟
  gains_pb = real(ch_params.gains .* exp(1j * 2*pi*fc * ch_params.delays_s));

  rng(ch_params.seed);

  % 多径卷积（passband real FIR）
  N_tx = length(tx_pb);
  max_d = max(delays_samp);
  rx_pb = zeros(1, N_tx + max_d);
  for p = 1:length(delays_samp)
    d = delays_samp(p);
    rx_pb(d+1:d+N_tx) = rx_pb(d+1:d+N_tx) + gains_pb(p) * tx_pb(:).';
  end
  rx_pb = rx_pb(1:N_tx);

  % Doppler：resample_spline（passband 直接 resample 即可）
  if abs(ch_params.doppler_rate) > 1e-10
    % alpha > 0: 靠近（压缩）; alpha < 0: 远离（拉伸）
    t_orig = (0:N_tx-1)/fs;
    t_new = t_orig * (1 + ch_params.doppler_rate);
    rx_pb = interp1(t_orig, rx_pb, t_new, 'spline', 0);
  end

  % passband AWGN
  sig_pwr = mean(rx_pb.^2);
  noise_var = sig_pwr * 10^(-ch_params.snr_db/10);
  if isfinite(ch_params.snr_db)
    rx_pb = rx_pb + sqrt(noise_var) * randn(size(rx_pb));
  end

  ch_info = struct('delays_samp', delays_samp, 'gains_pb', gains_pb, ...
                   'noise_var', noise_var, 'mode', 'passband');
end
```

**设计说明**：
- 物理信道 `h_pb(τ) = Re{h_bb(τ) · exp(j·2π·fc·τ)}`，所以实增益由复基带增益 + 载波延迟相位换算
- Doppler 直接在 passband 做 resample（不改频谱内容，只时间压缩/拉伸），与 baseband 版本等价
- AWGN 在 passband（real），σ² 按功率算
- **不做 I/Q 分离，不做下变频**，接口就是 pb→pb

**与 `gen_uwa_channel` (baseband) 的一致性验证**（P1 实施时做）：
- 同一 ch_params 下，`gen_uwa_channel_pb(upconvert(x_bb))` ≈ `upconvert(gen_uwa_channel(x_bb))`
- 误差来自：载波相位离散 + resample 方法差异，高 SNR 下应该 <-40dB

### tx/ (2 个)

#### 10. `tx_stream_p1.m`

```matlab
function tx_stream_p1(text, session, sys)
  % --- 文本 → bits ---
  payload_raw = text_to_bits(text);
  max_payload_bits = sys.frame.payload_bits;
  assert(length(payload_raw) <= max_payload_bits, ...
    'P1 单帧 payload 限制 %d bits，输入 %d bits', max_payload_bits, length(payload_raw));

  % --- 构 payload：[payload_raw | 补零 | CRC16(payload_raw)] ---
  pad = zeros(1, max_payload_bits - length(payload_raw));
  crc_p = crc16(payload_raw);
  payload_with_crc = [payload_raw, pad, crc_p];   % 512 + 16 = 528

  % --- 构 header ---
  hdr_input = struct('scheme', 6, 'idx', 1, 'len', length(payload_raw), ...
                     'mod_level', 1, 'flags', 1, 'src', 0, 'dst', 0);
  hdr_bits = frame_header('pack', hdr_input, sys);   % 128

  frame_bits = [hdr_bits, payload_with_crc];   % 656

  % --- FH-MFSK 编码（含 conv_encode + interleave + 跳频） ---
  [body_bb, meta_modem] = modem_encode_fhmfsk(frame_bits, sys);

  % --- 组装物理帧 ---
  [frame_bb, meta_frame] = assemble_physical_frame(body_bb, sys);

  % --- 上变频 ---
  [frame_pb, ~] = upconvert(frame_bb, sys.fs, sys.fc);

  % --- 写 wav + ready + meta json ---
  frame_idx = 1;
  subdir = fullfile(session, 'raw_frames');
  wav_write_frame(frame_pb, subdir, frame_idx, sys);

  % 附加保存 meta（P1 临时，P3/P4 从 header 推导）
  meta_full = struct('modem', meta_modem, 'frame', meta_frame, ...
                     'input_text', text, 'payload_len_bits', length(payload_raw));
  save(fullfile(subdir, sprintf('%04d.meta.mat', frame_idx)), '-struct', 'meta_full');

  fprintf('[TX] frame %04d written: %d text chars, %d bits payload, %d samples wav\n', ...
    frame_idx, length(text), length(payload_raw), length(frame_pb));
end
```

#### 11. `modem_encode_fhmfsk.m`

从 `test_fhmfsk_timevarying.m` lines 113–143 提炼（TX 段）：

```matlab
function [body_bb, meta] = modem_encode_fhmfsk(bits, sys)
  % bits: 要发射的全部比特（已含 header+payload+crc）
  % body_bb: 基带复信号
  cfg = sys.fhmfsk;
  codec = sys.codec;
  mem = codec.constraint_len - 1;

  % 1. 卷积编码
  coded = conv_encode(bits, codec.gen_polys, codec.constraint_len);
  M_coded = length(coded);

  % 2. 交织
  [interleaved, ~] = random_interleave(coded, codec.interleave_seed);

  % 3. 补齐到 bits_per_sym 倍数
  N_sym = ceil(M_coded / cfg.bits_per_sym);
  N_pad = N_sym * cfg.bits_per_sym - M_coded;
  coded_padded = [interleaved, zeros(1, N_pad)];

  % 4. FSK 映射: 3 bits → freq_index [0, M-1]
  freq_indices = zeros(1, N_sym);
  for k = 1:N_sym
    b3 = coded_padded((k-1)*cfg.bits_per_sym+1 : k*cfg.bits_per_sym);
    freq_indices(k) = bi2de(b3, 'left-msb');
  end

  % 5. 跳频
  hop_pattern = gen_hop_pattern(N_sym, cfg.num_freqs, cfg.hop_seed);
  hopped = fh_spread(freq_indices, hop_pattern, cfg.num_freqs);   % 0-based [0, num_freqs-1]

  % 6. 基带 FSK 波形生成（复指数）
  N_samples = N_sym * cfg.samples_per_sym;
  body_bb = zeros(1, N_samples);
  t_sym = (0:cfg.samples_per_sym-1)/sys.fs;
  phase_acc = 0;
  for k = 1:N_sym
    f_k = cfg.fb_base(hopped(k)+1);
    seg = exp(1j*(2*pi*f_k*t_sym + phase_acc));
    body_bb((k-1)*cfg.samples_per_sym+1 : k*cfg.samples_per_sym) = seg;
    phase_acc = phase_acc + 2*pi*f_k*cfg.samples_per_sym/sys.fs;
  end

  meta = struct('M_coded', M_coded, 'N_sym', N_sym, 'N_pad', N_pad, ...
                'hop_pattern', hop_pattern, 'samples_per_sym', cfg.samples_per_sym);
end
```

**依赖**：`conv_encode` (02), `random_interleave` (03), `gen_hop_pattern` / `fh_spread` (05_SpreadSpectrum)。

### rx/ (2 个)

#### 12. `modem_decode_fhmfsk.m`

从 `test_fhmfsk_timevarying.m` lines 185–234 提炼（RX 段）：

```matlab
function [bits, info] = modem_decode_fhmfsk(body_bb, sys, meta)
  % body_bb: 基带复信号（已下变频+对齐）
  % meta: modem_encode 产出的元数据（N_sym, hop_pattern, M_coded）
  cfg = sys.fhmfsk;
  codec = sys.codec;
  N_sym = meta.N_sym;
  N_samples_needed = N_sym * cfg.samples_per_sym;

  % 长度对齐
  if length(body_bb) < N_samples_needed
    body_bb = [body_bb, zeros(1, N_samples_needed - length(body_bb))];
  else
    body_bb = body_bb(1:N_samples_needed);
  end

  % 1. FFT 能量检测
  fft_bin_idx = mod(round(cfg.fb_base * cfg.samples_per_sym / sys.fs), cfg.samples_per_sym) + 1;
  energy_matrix = zeros(N_sym, cfg.num_freqs);
  for k = 1:N_sym
    seg = body_bb((k-1)*cfg.samples_per_sym+1 : k*cfg.samples_per_sym);
    psd = abs(fft(seg, cfg.samples_per_sym)).^2;
    energy_matrix(k, :) = psd(fft_bin_idx);
  end

  % 2. 去跳频
  detected_indices = zeros(1, N_sym);
  for k = 1:N_sym
    shift = meta.hop_pattern(k);
    e_shifted = circshift(energy_matrix(k, :), -shift);
    [~, detected_indices(k)] = max(e_shifted(1:cfg.M));
    detected_indices(k) = detected_indices(k) - 1;
  end

  % 3. 解映射 → 比特
  detected_bits = zeros(1, N_sym * cfg.bits_per_sym);
  for k = 1:N_sym
    b3 = de2bi(detected_indices(k), cfg.bits_per_sym, 'left-msb');
    detected_bits((k-1)*cfg.bits_per_sym+1 : k*cfg.bits_per_sym) = b3;
  end

  M_coded = meta.M_coded;
  detected_bits = detected_bits(1:M_coded);

  % 4. 解交织
  [~, perm] = random_interleave(zeros(1, M_coded), codec.interleave_seed);
  deint_bits = random_deinterleave(detected_bits, perm);

  % 5. 硬判决 Viterbi
  hard_llr = (2*deint_bits - 1) * 10;
  [~, Lp_info, ~] = siso_decode_conv(hard_llr, [], codec.gen_polys, ...
    codec.constraint_len, codec.decode_mode);
  bits = double(Lp_info > 0);

  % trim 到 原始 N_info 长度
  mem = codec.constraint_len - 1;
  N_info = M_coded / 2 - mem;
  bits = bits(1:N_info);

  info = struct('energy_matrix', energy_matrix, 'detected_indices', detected_indices);
end
```

**依赖**：`random_interleave` / `random_deinterleave` (03), `siso_decode_conv` (02)。

#### 13. `rx_stream_p1.m`

```matlab
function [text, info] = rx_stream_p1(session, sys)
  frame_idx = 1;

  % --- 读 wav ---
  subdir = fullfile(session, 'channel_frames');
  [rx_pb, fs] = wav_read_frame(subdir, frame_idx);
  assert(fs == sys.fs, 'fs 不匹配');

  % --- 读 TX 侧 meta（P1 临时，P4 后改 header 推导） ---
  meta_tx_path = fullfile(session, 'raw_frames', sprintf('%04d.meta.mat', frame_idx));
  meta_tx = load(meta_tx_path);

  % --- 下变频 ---
  [bb_raw, ~] = downconvert(rx_pb, sys.fs, sys.fc, sys.fhmfsk.total_bw);

  % --- LFM 匹配滤波找起点 ---
  lfm_pos = detect_lfm_start(bb_raw, sys, meta_tx.frame);

  % --- 提取数据段 ---
  ds = lfm_pos + meta_tx.frame.data_offset_from_lfm_head;
  N_body_samples = meta_tx.modem.N_sym * meta_tx.modem.samples_per_sym;
  de = ds + N_body_samples - 1;
  if de > length(bb_raw)
    body_bb = [bb_raw(ds:end), zeros(1, de - length(bb_raw))];
  else
    body_bb = bb_raw(ds:de);
  end

  % --- FH-MFSK 解 ---
  [frame_bits, decode_info] = modem_decode_fhmfsk(body_bb, sys, meta_tx.modem);
  % 注：modem_decode_fhmfsk 返回 info bits（已 Viterbi 解），长度 = N_info
  % 这里 N_info = frame_body_bits = 656

  % --- 解帧 ---
  hdr_bits = frame_bits(1:sys.frame.header_bits);
  hdr = frame_header('unpack', hdr_bits, sys);
  assert(hdr.crc_ok, 'header CRC 失败');
  assert(hdr.scheme == 6, 'scheme ≠ FH-MFSK');

  payload_seg_len = sys.frame.payload_bits;
  payload_bits = frame_bits(sys.frame.header_bits+1 : sys.frame.header_bits + payload_seg_len);
  payload_crc_recv = frame_bits(sys.frame.header_bits+payload_seg_len+1 : sys.frame.header_bits+payload_seg_len+16);

  payload_real = payload_bits(1:hdr.len);   % 取前 len bits 有效
  crc_calc = crc16(payload_real);
  payload_crc_ok = isequal(payload_crc_recv(:)', crc_calc(:)');

  % --- bits → text ---
  text = bits_to_text(payload_real);

  info = struct('hdr', hdr, 'payload_crc_ok', payload_crc_ok, ...
                'lfm_pos', lfm_pos, 'decode_info', decode_info);

  % 写 RX meta
  rx_meta = struct('text_out', text, 'info', info);
  save(fullfile(session, 'rx_out', sprintf('%04d.meta.mat', frame_idx)), '-struct', 'rx_meta');

  fprintf('[RX] frame %04d decoded: "%s" | crc_ok=%d\n', frame_idx, text, payload_crc_ok);
end
```

**辅助函数** `detect_lfm_start`：

```matlab
function lfm_pos = detect_lfm_start(bb_raw, sys, frame_meta)
  fs = sys.fs; fc = sys.fc;
  bw = sys.preamble.bw_lfm; dur = sys.preamble.dur;
  f_lo = fc - bw/2; f_hi = fc + bw/2;
  t_pre = (0:round(dur*fs)-1)/fs;
  chirp_rate = (f_hi - f_lo)/dur;
  phase_lfm = 2*pi*(f_lo*t_pre + 0.5*chirp_rate*t_pre.^2);
  LFM_bb = exp(1j*(phase_lfm - 2*pi*fc*t_pre));
  mf = conj(fliplr(LFM_bb));

  corr = abs(filter(mf, 1, bb_raw));
  lfm2_nom = frame_meta.lfm2_peak_nom;
  margin = frame_meta.guard_samp + 200;
  lo = max(1, lfm2_nom - margin);
  hi = min(lfm2_nom + margin, length(corr));
  [~, rel] = max(corr(lo:hi));
  lfm2_peak = lo + rel - 1;
  lfm_pos = lfm2_peak - frame_meta.N_lfm + 1;
end
```

### channel/ (1 个)

#### 15. `channel_simulator_p1.m`

```matlab
function channel_simulator_p1(session, ch_params, sys)
  % 方案 A：TX→Channel→RX 全程 passband，channel 内部不做下变频
  frame_idx = 1;
  in_subdir  = fullfile(session, 'raw_frames');
  out_subdir = fullfile(session, 'channel_frames');

  [frame_pb, fs] = wav_read_frame(in_subdir, frame_idx);
  assert(fs == sys.fs);

  % passband 原生信道：pb → pb，一次完成多径 + 多普勒 + AWGN
  ch_in = ch_params;
  ch_in.fs = sys.fs;
  [rx_pb, ch_info] = gen_uwa_channel_pb(frame_pb, ch_in, sys.fc);

  wav_write_frame(rx_pb, out_subdir, frame_idx, sys);

  fprintf('[Channel] frame %04d: SNR=%ddB, delay_spread=%.1fms, fading=%s, mode=%s\n', ...
    frame_idx, ch_params.snr_db, max(ch_params.delays_s)*1000, ...
    ch_params.fading_type, ch_info.mode);
end
```

**依赖**：`gen_uwa_channel_pb` (14_Streaming/common)。**不再调用** `gen_uwa_channel` / `downconvert` / `upconvert`（都在 RX 端或 TX 端）。

### tests/ (1 个)

#### 15. `test_p1_loopback_fhmfsk.m`

```matlab
%% test_p1_loopback_fhmfsk.m — Streaming P1 闭环测试
clear functions; clear all; clc;
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))));
addpath(genpath(fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab')));
% 复用旧模块
addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '13_SourceCode', 'src', 'Matlab', 'common'));

diary('test_p1_loopback_fhmfsk_results.txt');

sys = sys_params_default();
session = create_session_dir(fullfile(proj_root, 'modules', '14_Streaming', 'sessions'));

text_in = 'Hello 水声通信测试帧 001';

% --- TX ---
fprintf('=== TX ===\n');
tx_stream_p1(text_in, session, sys);

% --- Channel ---
fprintf('\n=== Channel ===\n');
ch_params = struct('fading_type','static', 'snr_db',15, ...
  'delays_s', [0, 1, 3, 5, 8]/sys.fhmfsk.freq_spacing, ...
  'gains', [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)], ...
  'num_paths', 5, 'doppler_rate', 0, 'fading_fd_hz', 0, ...
  'bw', sys.fhmfsk.total_bw, 'delay_profile', 'custom', 'seed', 42);
channel_simulator_p1(session, ch_params, sys);

% --- RX ---
fprintf('\n=== RX ===\n');
[text_out, info] = rx_stream_p1(session, sys);

% --- 核验 ---
fprintf('\n=== 结果 ===\n');
fprintf('输入: "%s"\n', text_in);
fprintf('输出: "%s"\n', text_out);
fprintf('相等: %d\n', strcmp(text_in, text_out));
fprintf('header CRC ok: %d\n', info.hdr.crc_ok);
fprintf('payload CRC ok: %d\n', info.payload_crc_ok);

assert(strcmp(text_in, text_out), 'loopback 失败');
assert(info.hdr.crc_ok, 'header CRC 失败');
assert(info.payload_crc_ok, 'payload CRC 失败');

fprintf('\n[PASS] P1 loopback 测试通过\n');

% --- 可视化 ---
figure('Position',[100 100 900 600]);
% 子图略（TX 波形 / RX 波形 / LFM 相关峰 / 能量矩阵）

diary off;
```

---

## 实施顺序

| 步 | 动作 | 依赖 | 验证 |
|---|------|------|------|
| 1 | `sys_params_default.m` | 无 | 脚本返回正确结构 |
| 2 | `text_to_bits.m` + `bits_to_text.m` + 往返单元测试 | 无 | 中英文字符串 UTF-8 往返 |
| 3 | `crc16.m` + 已知向量单元测试 | 无 | 标准测试向量匹配 |
| 4 | `frame_header.m` pack/unpack 往返 | crc16 | 128 bits 往返 + crc_ok |
| 5 | `create_session_dir.m` | 无 | 目录 + session.log 创建 |
| 6 | `wav_write_frame.m` + `wav_read_frame.m` 往返 | create_session_dir | 随机信号 int16 往返 SNR > 70 dB |
| 7 | `assemble_physical_frame.m` + LFM 相关峰检查 | sys_params | 峰位 = lfm2_peak_nom ±1 |
| 8 | `modem_encode_fhmfsk.m` | sys_params, conv_encode, fh_spread | N_sym / N_samples 一致 |
| 9 | `modem_decode_fhmfsk.m` + 无信道 loopback | modem_encode | BER=0（完美信道） |
| 10 | `gen_uwa_channel_pb.m` + bb/pb 一致性验证 | 无 | vs upconvert(gen_uwa_channel(x_bb)) 相对误差 <-40dB |
| 11 | `detect_lfm_start.m` | assemble | 给已知偏移信号能定位 |
| 12 | `channel_simulator_p1.m` | gen_uwa_channel_pb, wav I/O | static + 5 径处理后输出长度 = 输入长度 |
| 13 | `tx_stream_p1.m` | 以上全部 | 生成完整 raw.wav |
| 14 | `rx_stream_p1.m` | 以上全部 | loopback 无噪声 BER=0 |
| 15 | `test_p1_loopback_fhmfsk.m` | 全部 | "Hello 水声..." 完美复原 |

**测试门**：
- 步 2/3/4/6 是单元门（小测试各自独立）
- 步 9 是"无信道 modem"闭环门（BER=0）
- 步 13 是"静态信道 5 径 SNR=15dB"闭环门（BER=0，CRC 全过）
- 步 14 是整体门

---

## 风险 & 应对

| 风险 | 概率 | 应对 |
|------|------|------|
| `unicode2native('UTF-8')` 在某些 MATLAB 版本行为不同 | 低 | 加显式检查 `feature('DefaultCharacterSet')`，必要时 fallback `unicode2native(...,'UTF-8')`  |
| `audiowrite` int16 归一化导致低幅度信号量化噪声大 | 中 | wav.scale=0.95 留余量；SNR=15dB 场景下 16 bit 量化噪声（~96dB）远低于通信噪声 |
| FH-MFSK 硬判决 Viterbi 在 5 径+SNR=15dB 静态信道下是否 BER=0？ | 中 | 先跑 13_SourceCode 的 test_fhmfsk_timevarying 确认基线；必要时调参（增 N_info 或延长 sym_duration） |
| `gen_uwa_channel_pb` 与 bb 版本一致性 | 中 | 步 10 做 passband vs baseband 对拍，误差 <-40dB 才通过 |
| `gen_uwa_channel_pb` P1 只支持 static，Jakes 要 P5/P6 补 | 低 | 注释明确；P1 验证目标本就是高 SNR static 复原 |
| session 目录路径带空格/中文 | 低 | 用 `fullfile` 拼接，文件名避免中文 |
| `detect_lfm_start` 因信道时延导致峰位漂移 | 低 | search window margin 已含多径时延余量 |
| Windows 下 `.ready` 文件创建/删除的 flush 延迟 | 低 | `fopen+fclose` 已是同步，OS 保证可见性 |
| 帧 body_bits 不是 bits_per_sym 倍数的补 0 处理 | 中 | modem_encode 里明确补齐，RX 解时 trim 到 M_coded |

---

## 不做（留给后续 phase）

- 多帧长文本（P2）
- 流式帧检测（P2）
- 6 体制统一 API（P3）— P1 用 `modem_encode_fhmfsk` 临时命名
- 帧头与 payload 异构调制（P4）— P1 整帧用 FH-MFSK
- 并发（P5）
- AMC（P6）
- session_wavconcat 归档工具
- 崩溃恢复
- 可视化美化

---

## 输出产物

| 产物 | 路径 |
|------|------|
| 15 个源码文件 | `modules/14_Streaming/src/Matlab/{tx,rx,channel,common,tests}/`（common 含方案 A 的 `gen_uwa_channel_pb.m`）|
| 测试报告 | `modules/14_Streaming/src/Matlab/tests/test_p1_loopback_fhmfsk_results.txt` |
| 示例 session | `modules/14_Streaming/sessions/session_<ts>/`（txt 到图） |
| wiki 更新 | `wiki/modules/14_Streaming/14_流式仿真框架.md` 补 P1 段 |
| README 更新 | `modules/14_Streaming/README.md` 标 P1 完成 |
| spec 归档 | `specs/active/2026-04-15-streaming-p1-loopback-fhmfsk.md` → `archive/` |

---

## Log

（实施时追加）
