# Plan: TX/RX 简化 UI 拆分

**Spec**: `specs/active/2026-05-04-tx-rx-simple-ui-split.md`
**Date**: 2026-05-04
**Owner**: claude (UWAcomm-claude branch)

## 总览

| Phase | 内容 | 工时 | Checkpoint |
|-------|------|------|------------|
| 0 | 复用接口梳理 + 路径注册 helper | 0.5h | spec 中复用清单确认 |
| 1 | TX UI MVP（6 体制 + WAV/JSON 输出） | 1d | 6 体制 smoke test PASS |
| 2 | RX UI MVP（4 信道模式 + 流式 chunk） | 1d | AWGN SC-FDE smoke test PASS |
| 3 | 诊断 plot（sync / channel tab） | 0.5d | 可视化打开无错 |
| 4 | 与 runner 等价性验证 + 6 体制 BER 复现 | 1d | 等价性测试 PASS |
| 5 | 文档 + spec Result + commit | 0.5h | wiki/index.md + log.md 同步 |

**总计：3-4 工日**

## Phase 0: 复用接口梳理（0.5h）

### 0.1 直接调用清单

| 函数 | 路径 | 用途 |
|------|------|------|
| `sys_params_default` | common/ | 默认 sys |
| `p4_apply_scheme_params` | ui/ | 6 体制参数注入 + V4.0 预设 |
| `modem_encode` | tx/ | 6 体制 dispatch 编码 |
| `modem_decode` | rx/ | 6 体制 dispatch 解码 |
| `assemble_physical_frame` | common/ | 加 HFM±/LFM 前导 |
| `upconvert` / `downconvert` | (09_Waveform) | 基带↔通带 |
| `gen_uwa_channel` | (13_SourceCode/common) | jakes + 多径 |
| `detect_frame_stream` | common/ | 真同步 + α 估计 |
| `comp_resample_spline` | (10_DopplerProc) | α 反补偿 |
| `streaming_alpha_gate` | common/ | α 假报拒绝 |
| `p4_downconv_bw` | ui/ | 各体制 baseband bw |

### 0.2 不复用清单

- `start_tx.m` / `rx_daemon_p5.m` / `channel_daemon_p5.m` — daemon polling 架构对单帧 GUI 过重
- `p4_demo_ui.m` 内部 nested function — closure 陷阱根因，不复用

### 0.3 Helper 文件（如果需要）

- `ui/simple_ui_addpaths.m` — 集中路径注册（参考 p4_demo_ui.m L18-37）
- `ui/simple_ui_meta_io.m` — JSON meta 编解码（jsonencode + jsondecode + base64 known_bits）
- 这些都是"如果一个 UI 用了，另一个 UI 也要用"的 shared utility

## Phase 1: TX UI MVP（1d）

### 1.1 文件骨架（~50 行）

```matlab
% modules/14_Streaming/src/Matlab/ui/tx_simple_ui.m
classdef tx_simple_ui < handle
    properties
        fig
        sys
        scheme = 'SC-FDE'
        ui_vals
        widgets   % 控件 handles
    end
    methods
        function this = tx_simple_ui()
            simple_ui_addpaths();
            this.sys = sys_params_default();
            this.ui_vals = struct(...);   % 默认值
            this.createComponents();
        end
        function createComponents(this) ... end
        function on_scheme_change(this, src, ~) ... end
        function on_v40_preset(this, ~, ~) ... end
        function on_source_type_change(this, src, ~) ... end
        function on_generate(this, ~, ~) ... end
        function append_log(this, msg) ... end
    end
end
```

### 1.2 控件布局（~150 行）

- 顶部 row：`Scheme [dropdown]` + `[V4.0 Preset]` 按钮
- 参数 grid（按 scheme 显示不同字段）：
  - SC-FDE: blk_fft / blk_cp / pilot_per_blk / train_period_K / turbo_iter / payload_bytes
  - OFDM: blk_fft / blk_cp / pilot_spacing / payload_bytes
  - SC-TDE: train_len / payload_bytes
  - OTFS: N / M / pilot_mode / payload_bytes
  - DSSS: code_len / payload_bytes
  - FH-MFSK: hops / payload_bytes
- 信源 row：`Source Type [random/text/file]` + content edit/file picker
- 输出 row：`Output Dir [picker]` + `Filename Prefix [edit]`
- 按钮：`[Generate]` + `[Open Output Dir]`
- 底部：log textarea（read-only，不滚动 timer）

### 1.3 on_generate 回调（~150 行）

```matlab
function on_generate(this, ~, ~)
    try
        % 1. apply scheme params
        [N_info, sys] = p4_apply_scheme_params(this.scheme, this.sys, this.ui_vals);

        % 2. info bits
        info_bits = this.read_info_bits(N_info);

        % 3. encode + assemble
        [body_bb, meta_tx] = modem_encode(info_bits, this.scheme, sys);
        [frame_bb, ~] = assemble_physical_frame(body_bb, sys);
        body_offset = length(frame_bb) - length(body_bb);

        % 4. upconvert (passband)
        [tx_pb, ~] = upconvert(frame_bb, sys.fs, sys.fc);
        tx_pb = real(tx_pb);

        % 5. normalize to [-1, 1]
        tx_pb = tx_pb / max(abs(tx_pb)) * 0.95;

        % 6. write wav + JSON meta
        ts = datestr(now, 'yyyymmdd_HHMMSS');
        wav_name = sprintf('tx_%s_%s.wav', this.scheme, ts);
        json_name = sprintf('tx_%s_%s.json', this.scheme, ts);
        wav_path = fullfile(this.output_dir, wav_name);
        audiowrite(wav_path, tx_pb, sys.fs);

        meta = simple_ui_meta_io('encode', struct( ...
            'scheme', this.scheme, ...
            'sys_essential', extract_sys_essential(sys), ...
            'N_info', N_info, ...
            'body_offset', body_offset, ...
            'frame_pb_samples', length(tx_pb), ...
            'known_bits', info_bits, ...
            'created_at', ts));
        json_path = fullfile(this.output_dir, json_name);
        fid = fopen(json_path, 'w'); fwrite(fid, meta); fclose(fid);

        this.append_log(sprintf('[OK] %s + %s 已生成', wav_name, json_name));
    catch ME
        this.append_log(sprintf('[ERR] %s', ME.message));
    end
end
```

### 1.4 单元测试

`tests/test_tx_simple_ui_smoke.m`：
- 不打开 GUI（headless），直接构造 tx_simple_ui 实例 + 调 on_generate
- 6 体制循环（SC-FDE, OFDM, SC-TDE, OTFS, DSSS, FH-MFSK）
- 检查：wav 文件存在 + audioread 长度匹配 + JSON 可解析 + meta 字段完整
- PASS/FAIL 累计 + diary 输出

## Phase 2: RX UI MVP（1d）

### 2.1 文件骨架（~80 行）

```matlab
% modules/14_Streaming/src/Matlab/ui/rx_simple_ui.m
classdef rx_simple_ui < handle
    properties
        fig
        sys
        meta            % 从 JSON 读
        wav_path
        audio_full      % audioread 整段
        channel_mode = 'pass'   % pass / awgn / jakes / multipath
        channel_params
        chunk_n         % chunk 大小（samples）
        ring            % ring buffer
        ring_write      % 写指针
        last_decode_at  % 上次解码位置
        widgets
    end
    methods
        function this = rx_simple_ui() ... end
        function createComponents(this) ... end
        function on_load_wav(this, ~, ~) ... end
        function on_mode_change(this, src, ~) ... end
        function on_run(this, ~, ~) ... end
        function process_chunk(this, chunk) ... end
        function decoded = try_decode(this) ... end
        function update_plots(this, decoded) ... end
        function append_log(this, msg) ... end
    end
end
```

### 2.2 控件布局（~150 行）

- 顶部：`[Load WAV]` 按钮 + 文件路径 label + 体制 label（auto from JSON / manual dropdown）
- 信道模式 row（4 个 radio button group）：纯接收 / AWGN / Jakes / Multipath
- 信道参数 panel（动态：按 mode 显示不同字段）：
  - awgn: `SNR_dB [edit]`
  - jakes: `fading_type [slow/fast]` + `fading_fd_hz [edit]` + `α (doppler_rate) [edit]`
  - multipath: `delays_ms [edit]` + `gains [edit]` + `seed [edit]`
- chunk 设置：`Chunk ms [edit]`（默认 50）
- 按钮：`[Run]`
- 状态显示：`Frames: N | BER: X.XX% | Sync: OK | α_est: ±X.XXe-X`
- 右侧 tabs：`Sync` / `Channel`
- 底部：log textarea

### 2.3 on_run 流式处理（~150 行）

```matlab
function on_run(this, ~, ~)
    % 1. 读 wav
    [audio_full, fs] = audioread(this.wav_path);
    audio_full = audio_full(:, 1).';   % 单声道
    if abs(fs - this.sys.fs) > 1, error('fs mismatch'); end

    % 2. 加信道（jakes/multipath 一次过；awgn 流式 chunk 加；pass 直通）
    audio_in = audio_full;
    switch this.channel_mode
        case 'jakes'
            audio_in = apply_jakes_full(audio_full, this.channel_params, this.sys);
        case 'multipath'
            audio_in = apply_multipath_full(audio_full, this.channel_params, this.sys);
    end

    % 3. ring buffer init
    fn_hint = this.meta.frame_pb_samples;
    this.ring = zeros(1, max(4*fn_hint, length(audio_in) + 8000));
    this.ring_write = 0;
    this.last_decode_at = 0;

    % 4. chunk-by-chunk 推 ring + 试解码
    n_chunks = ceil(length(audio_in) / this.chunk_n);
    decoded_count = 0;
    ber_sum = 0;
    for k = 1:n_chunks
        idx_lo = (k-1)*this.chunk_n + 1;
        idx_hi = min(k*this.chunk_n, length(audio_in));
        chunk = audio_in(idx_lo:idx_hi);

        % AWGN: chunk 加噪
        if strcmp(this.channel_mode, 'awgn')
            sig_pwr = mean(chunk.^2);
            nv = sig_pwr * 10^(-this.channel_params.snr_db/10);
            chunk = chunk + sqrt(nv) * randn(size(chunk));
        end

        % push
        this.ring(this.ring_write + (1:length(chunk))) = chunk;
        this.ring_write = this.ring_write + length(chunk);

        % try decode
        if this.ring_write >= this.last_decode_at + fn_hint
            decoded = this.try_decode();
            if decoded.found
                decoded_count = decoded_count + 1;
                ber_sum = ber_sum + decoded.ber;
                this.update_plots(decoded);
            end
        end
    end

    this.append_log(sprintf('[DONE] frames=%d, mean_BER=%.3f%%', ...
        decoded_count, 100 * ber_sum / max(1, decoded_count)));
end
```

### 2.4 try_decode 内部（~80 行）

直接复用 try_decode_frame 主流程：detect_frame_stream → streaming_alpha_gate → comp_resample_spline → downconvert → body 切片 → modem_decode → BER。日志前缀同 P4 UI（`[SYNC]` / `[α-COMP]` / `[α-GATE]` / `[DEC #N]`）以保持调试连贯。

### 2.5 单元测试

`tests/test_rx_simple_ui_smoke.m`：
- 用 TX UI 生成的 wav + meta（先调 tx_simple_ui 生成）
- 4 种信道模式各跑 1 次
- AWGN 模式 SC-FDE V4.0 SNR=20：BER < 5%
- 纯接收模式 SC-FDE V4.0：BER < 1%
- PASS/FAIL 累计

## Phase 3: 诊断 plot（0.5d）

### 3.1 Sync tab

- HFM+ 匹配滤波曲线
- LFM2 匹配滤波曲线
- α 估计 + ground truth 对比（如有 meta.known_alpha）
- detect_frame_stream peak_ratio + confidence

### 3.2 Channel tab

- h_est tap 值（stem 图）
- |H(f)| 频域响应

复用 P4 UI 的 `p4_render_tabs.m` 中相关函数（如能直接用）。

## Phase 4: 等价性验证（1d）

`tests/test_simple_ui_runner_equivalence.m`：
- 固定 seed = 20260504
- TX UI 生成 wav（SC-FDE V4.0）
- RX UI AWGN SNR=20，5 seed 跑 → mean BER
- 与 `test_p4_ui_runner_equivalence.m` Path R 5-seed mean (2.28%) 比对：差异 ≤ 1pp
- Jakes fd=1Hz 5 seed mean BER 与 runner 0.68% 同数量级（≤ 5%）
- 6 体制 AWGN 各跑 1 次，BER reproduce dashboard 表

## Phase 5: 文档 + commit（0.5h）

- 更新 `wiki/modules/14_Streaming/README.md` 加 `simple UI` 段
- 更新 `wiki/index.md` + `wiki/log.md`
- spec 追加 Result 段（实测 BER + 单测 PASS 数）
- commit + push

## 风险

| 风险 | 缓解 |
|------|------|
| classdef 也有 closure 类问题（property 引用） | 严格用 method 调用，不用 nested closure；每次按钮点击都用 fresh local var |
| audioread 浮点归一化破坏信号细节 | 写入前归一化到 [-0.95, 0.95]，读取后 *系数 还原（meta 中存 scale_factor） |
| Jakes 一次过加信道 + 流式读 vs UI 真实 chunk-stateful 差异 | 加 toggle："stateful 流式 jakes（实验）" / "一次过 jakes（默认）"；后者作 baseline |
| 6 体制 BER 复现 dashboard 表，可能有 SNR 边界差异 | 接受 ≤ 1pp 差异，关注 0%@SNR 阈值 reproducible |
| 单文件 < 500 行可能超出（控件布局 + 6 体制参数 panel 复杂） | 把控件创建外化到 `simple_ui_widgets_tx.m` / `simple_ui_widgets_rx.m` |
