---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-15-streaming-p2-stream-detect.md
master_spec: specs/active/2026-04-15-streaming-framework-master.md
created: 2026-04-15
tags: [14_Streaming, P2, 多帧, 流式检测]
---

# Streaming P2 — 多帧流式检测 实施计划

## 默认决策（写本 plan 时确定，可改）

1. **多帧无 gap**（直接 concat）— HFM 匹配滤波足够分辨帧边界
2. **末帧用 `flags.bit0=last_frame`**（不传总帧数，RX 看到就停止读取）
3. **丢帧**：插入文本 `[missing frame N]` 占位，便于人工识别哪段丢了

## 总体架构

```
长文本 "Hello 水声..."
  ↓
text_chunker (按 UTF-8 字节边界 + 单帧 payload 上限)
  ↓
chunk_1 (256 B), chunk_2 (256 B), ..., chunk_N (≤ 256 B, last)
  ↓
for each chunk_i:
  → tx_stream_p1 内部 reuse: text_to_bits → frame_packer → modem_encode → assemble
  → frame_pb_i (passband)
  ↓
concatenate all frame_pb → multi_frame_pb
  ↓
wav_write_frame(multi_frame_pb, raw_frames/0001.wav)   # 整段当一个"帧"写入

──────────────── 信道 ────────────────
channel_simulator_p1(session, ch_params, sys)   # 完全复用
                                                # 加 wav 长度自动调整
──────────────── RX ─────────────────

wav_read_frame → multi_frame_pb_rx
  ↓
downconvert → bb_raw → Doppler 反 resample (oracle)
  ↓
frame_detector (滑动 HFM+ 匹配 + 双阈值 + debounce)
  ↓
detected_starts = [k_1, k_2, ..., k_N] (HFM+ 头位置)
  ↓
for each k_i:
  → 截取 frame_window = bb_compensated(k_i : k_i + frame_len_samples - 1)
  → detect_lfm_start(frame_window) → LFM2 精确定位
  → modem_decode_fhmfsk → body_bits → frame_header.unpack → payload
  → 校验 CRC
  ↓
text_assembler: 按 hdr.idx 排序，拼接 payload(1:len)，丢帧用占位
  ↓
text_out
```

---

## 文件清单与签名

### tx/ (2 个新)

#### 1. `text_chunker.m`

```matlab
function chunks = text_chunker(text, max_bytes)
% 功能：UTF-8 文本按字节切分（不切断字符）
% 输入：
%   text       - UTF-8 字符串
%   max_bytes  - 单帧最大字节数（来自 sys.frame.payload_bits / 8）
% 输出：
%   chunks - cell 数组，每元素是一个字符串子串，UTF-8 字节数 ≤ max_bytes
%
% 算法：
%   1. 整段 unicode2native('UTF-8') → bytes
%   2. 按 max_bytes 切，**回退到最近的 UTF-8 起始字节**（高位 bit 不是 10xxxxxx）
%      防止 multi-byte 字符被截断
%   3. 各段 native2unicode → 字符串
%
% 注意：
%   - UTF-8 编码：ASCII 单字节、中文 3 字节
%   - 切分点必须在字符边界（首字节高位 != 10）

bytes = unicode2native(text, 'UTF-8');
N = length(bytes);
chunks = {};
start = 1;
while start <= N
    end_byte = min(start + max_bytes - 1, N);
    if end_byte < N
        % 找回退点：end_byte 之后的字节高位若是 10xxxxxx，向前回退
        while end_byte > start && bitand(uint8(bytes(end_byte+1)), uint8(192)) == uint8(128)
            end_byte = end_byte - 1;
        end
    end
    chunks{end+1} = native2unicode(bytes(start:end_byte), 'UTF-8'); %#ok<AGROW>
    start = end_byte + 1;
end
end
```

**验证**：
- ASCII text 应等价 strsplit
- 中文 text 切分后各段都是合法 UTF-8（每段单独可 unicode2native 解码）
- 总拼接（concat 各 chunk）= 原 text

#### 2. `tx_stream_p2.m`

```matlab
function tx_stream_p2(text, session, sys)
% 多帧 TX：text → 切分 → N 帧 → concat → 单 wav

frame_idx_outer = 1;   % wav 文件名仍 0001.wav（多帧串联在一起）

% 1. 切分文本
max_bytes = floor(sys.frame.payload_bits / 8);
chunks = text_chunker(text, max_bytes);
N_frames = length(chunks);
fprintf('[TX] 文本切为 %d 帧（每帧最多 %d 字节）\n', N_frames, max_bytes);

% 2. 逐帧生成 frame_pb，串联
multi_frame_pb = [];
modem_metas = cell(1, N_frames);
frame_metas = cell(1, N_frames);
for fi = 1:N_frames
    chunk_text = chunks{fi};
    payload_raw = text_to_bits(chunk_text);
    pad = zeros(1, sys.frame.payload_bits - length(payload_raw));
    crc_p = crc16(payload_raw);
    payload_full = [payload_raw, pad, crc_p];

    is_last = (fi == N_frames);
    hdr_input = struct('scheme', sys.frame.scheme_fhmfsk, ...
        'idx', fi, 'len', length(payload_raw), ...
        'mod_level', 1, 'flags', double(is_last), ...
        'src', 0, 'dst', 0);
    hdr_bits = frame_header('pack', hdr_input, sys);

    body_bits = [hdr_bits, payload_full];
    [body_bb, meta_modem] = modem_encode_fhmfsk(body_bits, sys);
    [frame_bb, meta_frame] = assemble_physical_frame(body_bb, sys);
    [frame_pb, ~] = upconvert(frame_bb, sys.fs, sys.fc);

    multi_frame_pb = [multi_frame_pb, frame_pb]; %#ok<AGROW>
    modem_metas{fi} = meta_modem;
    frame_metas{fi} = meta_frame;

    fprintf('[TX] frame %d/%d: "%s" (%d bits, last=%d)\n', ...
        fi, N_frames, chunk_text, length(payload_raw), is_last);
end

% 3. 写单 wav（multi_frame_pb 整段）
subdir = fullfile(session, 'raw_frames');
wav_write_frame(multi_frame_pb, subdir, frame_idx_outer, sys);

% 4. 写 meta（包含所有 N 帧的元数据 + frame_metas[1] 给 RX 推 frame_len）
meta_full = struct();
meta_full.N_frames     = N_frames;
meta_full.modem_metas  = {modem_metas};   % cell wrap 给 mat 存
meta_full.frame_metas  = {frame_metas};
meta_full.input_text   = text;
meta_full.chunks       = {chunks};
% 单帧标称长度（所有帧相同 — payload_bits 固定）
meta_full.single_frame_samples = length(multi_frame_pb) / N_frames;
save(fullfile(subdir, sprintf('%04d.meta.mat', frame_idx_outer)), '-struct', 'meta_full');

fprintf('[TX] 总 wav %d 样本 (%.2f s, %d 帧)\n', ...
    length(multi_frame_pb), length(multi_frame_pb)/sys.fs, N_frames);
end
```

**复用**：text_to_bits, crc16, frame_header, modem_encode_fhmfsk, assemble_physical_frame, upconvert, wav_write_frame（全 P1 函数）

### rx/ (3 个新)

#### 3. `frame_detector.m`

```matlab
function [starts, peaks_info] = frame_detector(bb_raw, sys, opts)
% 功能：滑动 HFM+ 匹配滤波检测多帧起点
% 输入：
%   bb_raw - 已下变频 + Doppler 补偿的基带复信号
%   sys    - 系统参数
%   opts   - 可选 struct
%       .frame_len_samples  - 单帧标称样本数（从 TX meta 取）
%       .threshold_K        - 噪底倍数阈值（默认 8）
%       .threshold_ratio    - 全局峰比例阈值（默认 0.3）
%       .min_sep_factor     - debounce 最小间隔（默认 0.9 × frame_len）
% 输出：
%   starts - 1×N 检测到的帧起点（HFM+ 头位置，1-based 样本索引）
%   peaks_info - struct
%       .corr_mag      - 完整 |匹配滤波| 序列（debug/可视化用）
%       .threshold     - 实际使用的阈值
%       .raw_peaks     - debounce 前的所有候选峰

if nargin < 3, opts = struct(); end
if ~isfield(opts, 'threshold_K'),    opts.threshold_K = 8; end
if ~isfield(opts, 'threshold_ratio'),opts.threshold_ratio = 0.3; end
if ~isfield(opts, 'min_sep_factor'), opts.min_sep_factor = 0.9; end

% 1. 生成 HFM+ 模板（与 assemble_physical_frame 一致）
fs = sys.fs; fc = sys.fc;
bw = sys.preamble.bw_lfm;
dur = sys.preamble.dur;
f_lo = fc - bw/2; f_hi = fc + bw/2;
t_pre = (0:round(dur*fs)-1) / fs;
k_hfm = f_lo*f_hi*dur/(f_hi-f_lo);
phase_hfm = -2*pi*k_hfm*log(1 - (f_hi-f_lo)/f_hi*t_pre/dur);
HFM_bb = exp(1j*(phase_hfm - 2*pi*fc*t_pre));

% 2. 匹配滤波（HFM+ 是 Doppler 不变的，对 Doppler 残余有鲁棒性）
mf = conj(fliplr(HFM_bb));
corr = filter(mf, 1, bb_raw(:).');
corr_mag = abs(corr);

% 3. 自适应阈值
noise_floor = median(corr_mag);
peak_max = max(corr_mag);
threshold = max(opts.threshold_K * noise_floor, opts.threshold_ratio * peak_max);

% 4. 找所有超阈值的局部最大（debounce）
N_lfm_template = length(HFM_bb);
% 注意：filter 输出的峰对应"当前样本到当前样本-N+1 的相关"，
% 所以 corr_mag(p) 大表示在 bb_raw(p-N+1 : p) 处有 HFM+；
% 因此 HFM+ 头位置 = p - N_lfm_template + 1
min_sep = round(opts.min_sep_factor * opts.frame_len_samples);

% 阈值过滤
above = find(corr_mag > threshold);
% debounce：在 min_sep 窗口内只取最大
starts = [];
i = 1;
while i <= length(above)
    pos = above(i);
    % 滑窗内最大
    win_end = pos + min_sep - 1;
    j = i;
    best = pos;
    while j <= length(above) && above(j) <= win_end
        if corr_mag(above(j)) > corr_mag(best)
            best = above(j);
        end
        j = j + 1;
    end
    % 转换匹配滤波峰位 → HFM+ 头位置
    hfm_head = best - N_lfm_template + 1;
    if hfm_head >= 1
        starts(end+1) = hfm_head; %#ok<AGROW>
    end
    i = j;  % 跳到 win_end 之后
end

peaks_info = struct('corr_mag', corr_mag, 'threshold', threshold, ...
    'noise_floor', noise_floor, 'peak_max', peak_max, ...
    'raw_peaks', above);
end
```

**关键**：
- HFM+ 多普勒不变（双曲调频特性），对 Doppler 残余有鲁棒
- 双阈值确保高/低 SNR 都合理
- debounce 用 `min_sep = 0.9 × frame_len` 防止单帧多次触发
- 输出的 `starts` 是 HFM+ 头部位置（不是匹配滤波峰位）

#### 4. `text_assembler.m`

```matlab
function text = text_assembler(decoded_chunks)
% 功能：按 frame_idx 排序 + 拼接，缺帧插入占位
% 输入：
%   decoded_chunks - cell 数组，每元素 struct：
%       .idx        帧序号
%       .text       该帧解出的文本（CRC 失败则 '[missing]'）
%       .ok         CRC 是否通过
% 输出：
%   text - 拼接后的完整文本

if isempty(decoded_chunks)
    text = '';
    return;
end

% 提取 idx 排序
all_idx = cellfun(@(c) c.idx, decoded_chunks);
[~, sort_perm] = sort(all_idx);
sorted = decoded_chunks(sort_perm);

% 找 idx 范围（从 1 到 max）
max_idx = max(all_idx);
parts = cell(1, max_idx);

for j = 1:length(sorted)
    c = sorted{j};
    if c.ok
        parts{c.idx} = c.text;
    else
        parts{c.idx} = sprintf('[missing frame %d]', c.idx);
    end
end

% 检测整帧丢失（idx 跳号）
for k = 1:max_idx
    if isempty(parts{k})
        parts{k} = sprintf('[missing frame %d]', k);
    end
end

text = strjoin(parts, '');
end
```

#### 5. `rx_stream_p2.m`

```matlab
function [text, info] = rx_stream_p2(session, sys)
% 多帧流式 RX：channel.wav → 滑动检测 → 逐帧解 → text_assembler

frame_idx_outer = 1;

% 1. 读 channel.wav
chan_subdir = fullfile(session, 'channel_frames');
[rx_pb, fs] = wav_read_frame(chan_subdir, frame_idx_outer);
assert(fs == sys.fs);

% 2. 读 TX meta（拿 single_frame_samples）
meta_tx_path = fullfile(session, 'raw_frames', sprintf('%04d.meta.mat', frame_idx_outer));
assert(exist(meta_tx_path, 'file') == 2, '缺少 TX meta');
meta_tx = load(meta_tx_path);

% 3. 下变频 + Doppler 补偿（沿用 P1 逻辑）
[bb_raw, ~] = downconvert(rx_pb, sys.fs, sys.fc, sys.fhmfsk.total_bw);
chinfo_path = fullfile(session, 'channel_frames', sprintf('%04d.chinfo.mat', frame_idx_outer));
if exist(chinfo_path, 'file')
    ci = load(chinfo_path);
    if isfield(ci, 'doppler_rate') && abs(ci.doppler_rate) > 1e-10
        alpha = ci.doppler_rate;
        N_rx = length(bb_raw);
        t_orig = (0:N_rx-1) / sys.fs;
        t_query = t_orig / (1 + alpha);
        bb_raw = interp1(t_orig, bb_raw, t_query, 'spline', 0);
    end
end

% 4. 流式帧检测
det_opts = struct('frame_len_samples', meta_tx.single_frame_samples);
[starts, peaks_info] = frame_detector(bb_raw, sys, det_opts);
fprintf('[RX] 检测到 %d 帧（TX 实际 %d 帧）\n', length(starts), meta_tx.N_frames);

% 5. 逐帧解码
modem_metas = meta_tx.modem_metas{1};
frame_metas = meta_tx.frame_metas{1};
decoded = {};

for ki = 1:length(starts)
    k = starts(ki);
    % 截取本帧窗口（多取一些防边界）
    win_end = min(k + meta_tx.single_frame_samples + 200, length(bb_raw));
    frame_win = bb_raw(k:win_end);

    % 用第一帧 frame_meta 做 LFM 定位（所有帧结构相同）
    fm = frame_metas{1};
    [lfm_pos_local, ~, ~] = detect_lfm_start(frame_win, sys, fm);
    ds = lfm_pos_local + fm.data_offset_from_lfm_head;

    mm = modem_metas{1};
    N_body = mm.N_sym * mm.samples_per_sym;
    de = ds + N_body - 1;
    if de > length(frame_win)
        body_bb = [frame_win(ds:end), zeros(1, de - length(frame_win))];
    else
        body_bb = frame_win(ds:de);
    end

    [body_bits, ~] = modem_decode_fhmfsk(body_bb, sys, mm);
    if length(body_bits) ~= sys.frame.body_bits
        fprintf('[RX] 帧 %d 长度异常，跳过\n', ki);
        continue;
    end

    % 解 header
    hdr_bits = body_bits(1:sys.frame.header_bits);
    hdr = frame_header('unpack', hdr_bits, sys);
    if ~hdr.crc_ok || ~hdr.magic_ok
        decoded{end+1} = struct('idx', ki, 'text', '', 'ok', false); %#ok<AGROW>
        fprintf('[RX] 帧 %d header CRC/MAGIC 失败\n', ki);
        continue;
    end

    % payload
    p_start = sys.frame.header_bits + 1;
    p_end   = p_start + sys.frame.payload_bits - 1;
    c_start = p_end + 1;
    c_end   = p_end + sys.frame.payload_crc_bits;
    payload_all = body_bits(p_start:p_end);
    payload_crc_recv = body_bits(c_start:c_end);

    payload_real = payload_all(1:hdr.len);
    crc_calc = crc16(payload_real);
    pl_crc_ok = isequal(payload_crc_recv(:).', crc_calc(:).');

    if pl_crc_ok && mod(length(payload_real), 8) == 0
        try
            chunk_text = bits_to_text(payload_real);
        catch
            chunk_text = '';
            pl_crc_ok = false;
        end
    else
        chunk_text = '';
        pl_crc_ok = false;
    end

    decoded{end+1} = struct('idx', hdr.idx, 'text', chunk_text, ...
        'ok', pl_crc_ok, 'last', bitand(hdr.flags, 1) == 1); %#ok<AGROW>

    fprintf('[RX] 检测帧 %d → idx=%d "%s" (crc=%d, last=%d)\n', ...
        ki, hdr.idx, chunk_text, pl_crc_ok, bitand(hdr.flags, 1));
end

% 6. 拼接文本
text = text_assembler(decoded);

% 7. 返回 info
info = struct();
info.detected_starts = starts;
info.peaks_info      = peaks_info;
info.decoded         = {decoded};
info.N_detected      = length(starts);
info.N_expected      = meta_tx.N_frames;

% 写 rx_out
rx_out_dir = fullfile(session, 'rx_out');
rx_meta = struct('text_out', text, 'info', info);
save(fullfile(rx_out_dir, sprintf('%04d.meta.mat', frame_idx_outer)), '-struct', 'rx_meta');

fprintf('[RX] 输出: "%s"\n', text);
end
```

### tests/ (1 个新)

#### 6. `test_p2_multiframe.m`

```matlab
%% test_p2_multiframe.m — Streaming P2 多帧端到端测试
clear functions; clear all; clc;
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))));
addpath(genpath(fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab')));
addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '09_Waveform', 'src', 'Matlab'));

diary('test_p2_multiframe_results.txt');
fprintf('========================================\n');
fprintf(' Streaming P2 — 多帧流式检测端到端测试\n');
fprintf('========================================\n');

sys = sys_params_default();
% 减小 payload 让短文本也能切多帧（便于测试）
sys.frame.payload_bits = 256;   % = 32 字节，~1 个汉字 10 字节 = 3 字符
sys.frame.body_bits = sys.frame.header_bits + sys.frame.payload_bits + sys.frame.payload_crc_bits;
session_root = fullfile(proj_root, 'modules', '14_Streaming', 'sessions');

% --- 测试组 ---
test_cases = { ...
    'short',  '短文本',                                            'static', 15;
    'medium', '这是一段中等长度的水声通信测试文本，包含中英文 ABC 123 混合内容', 'static', 15;
    'long',   ['第一段：' repmat('水声', 1, 20) ' 第二段：' repmat('Hello ', 1, 30) ' 第三段：' repmat('测试', 1, 25)], 'static', 15;
    'medium_lowSNR', '这是一段中等长度的水声通信测试文本', 'static', 5; ...
};

results = {};
for ti = 1:size(test_cases, 1)
    name = test_cases{ti, 1};
    text_in = test_cases{ti, 2};
    fading = test_cases{ti, 3};
    snr = test_cases{ti, 4};

    fprintf('\n--- 测试 %s: SNR=%ddB, fading=%s ---\n', name, snr, fading);
    fprintf('输入文本 (%d 字符): %s\n', length(text_in), text_in);

    session = create_session_dir(session_root);
    tx_stream_p2(text_in, session, sys);

    ch_params = struct('fs', sys.fs, ...
        'delays_s', [0, 0.167, 0.5, 0.833, 1.333] * 1e-3, ...
        'gains', [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)], ...
        'num_paths', 5, 'doppler_rate', 0, 'fading_type', fading, ...
        'fading_fd_hz', 0, 'snr_db', snr, 'seed', 42);
    channel_simulator_p1(session, ch_params, sys);

    [text_out, info] = rx_stream_p2(session, sys);

    ok = strcmp(text_in, text_out);
    fprintf('输出文本: %s\n', text_out);
    fprintf('一致: %d, 检测/预期帧数: %d/%d\n', ok, info.N_detected, info.N_expected);
    results{end+1} = struct('name', name, 'in', text_in, 'out', text_out, ...
        'ok', ok, 'N_det', info.N_detected, 'N_exp', info.N_expected); %#ok<SAGROW>
end

% --- 汇总 ---
fprintf('\n=== 汇总 ===\n');
n_pass = 0;
for ri = 1:length(results)
    r = results{ri};
    fprintf('%-15s: %s (det=%d/exp=%d)\n', r.name, ...
        tern(r.ok, 'PASS', 'FAIL'), r.N_det, r.N_exp);
    if r.ok, n_pass = n_pass + 1; end
end
fprintf('\n%d/%d 通过\n', n_pass, length(results));
diary off;

function s = tern(cond, a, b)
    if cond, s = a; else, s = b; end
end
```

---

## 实施顺序（7 步）

| 步 | 动作 | 验证门 |
|---|------|--------|
| 1 | `text_chunker.m` + 单元测试 | ASCII / 中英混合 切分后拼接 == 原文，每段都是合法 UTF-8 |
| 2 | `tx_stream_p2.m` | 单帧文本退化为 P1 行为；3 帧文本生成 wav 时长 ≈ 3 × 单帧 |
| 3 | `frame_detector.m` | 3 帧 wav 检测 == 3 个 starts，starts[i+1] - starts[i] ≈ frame_len_samples |
| 4 | `text_assembler.m` 单元 | idx 乱序输入返回正确顺序；缺 idx 返回 `[missing frame N]` |
| 5 | `rx_stream_p2.m` | 串联以上，static 信道下完美复原 |
| 6 | `test_p2_multiframe.m` | 4 个 case 全 PASS |
| 7 | （可选）丢帧测试：手动破坏中间 wav 段 | 占位文本正确插入 |

## 风险与应对

| 风险 | 应对 |
|------|------|
| TX `multi_frame_pb = [multi_frame_pb, frame_pb]` 大文本时内存 / 慢 | 预分配 `multi_frame_pb = zeros(1, N_frames * single_frame_samples)` |
| 多帧 wav 归一化丢失各帧相对幅度 | 整段一次性归一化（wav_write_frame 行为不变即可） |
| 帧间无 gap 导致 HFM+ 自相关旁瓣触发误检 | min_sep_factor = 0.9，强制只在窗外找下一峰 |
| Doppler 残余使 frame_len 漂移导致 min_sep 偏 | min_sep = 0.9 × 标称，留 10% 余量足够 fd=20Hz |
| 末帧解 ok 但 last_frame=0 → RX 不知道结束 | RX 不依赖 last_frame 决定停止（处理所有检测到的帧） |
| 中文 UTF-8 在 256 bits payload 内仅能装 ~10 个汉字 | 测试用例选择合适长度 + 默认 payload_bits 仍是 2048 |

## 不做（留 P3+）

- 6 体制路由（仍 FH-MFSK only）
- 帧头独立 FH-MFSK 调制 + payload 异构（P4）
- ARQ 重传（P6 之后）
- 真正盲 Doppler 估计（仍 oracle）

## 输出产物

- 6 个新文件（5 src + 1 test）
- `test_p2_multiframe_results.txt` 含 4 个 case 通过率
- spec Result 段填写
- wiki 14_Streaming 加 P2 实施记录
- todo.md P2 改完成
