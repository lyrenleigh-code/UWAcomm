classdef rx_simple_ui < handle
% 功能：水声通信 RX 简化 UI —— 读 wav + 选信道 → 流式 chunk-by-chunk 解码 + BER
% 版本：V1.0.0（2026-05-04）
% 用法：
%   r = rx_simple_ui();                      % 启动 GUI
%   r = rx_simple_ui('headless', true);      % headless 测试用
%   r.wav_path = 'tx_xxx.wav';
%   r.channel_mode = 'awgn';                 % pass/awgn/jakes/multipath
%   r.channel_params.snr_db = 20;
%   r.on_run();
%   disp(r.last_result)
%
% 架构：
%   - classdef + uifigure，按钮回调同步执行
%   - 流式 = chunk-by-chunk 推 ring buffer + 调 detect_frame_stream
%   - jakes/multipath 一次过加信道再流式读（避免 stateful）；awgn/pass 流式 chunk 加
%   - 复用 detect_frame_stream / streaming_alpha_gate / comp_resample_spline / modem_decode
%
% Spec: specs/active/2026-05-04-tx-rx-simple-ui-split.md

    properties
        % --- core state ---
        sys
        meta
        wav_path = ''
        json_path = ''
        channel_mode = 'pass'        % pass | awgn | jakes | multipath
        channel_params               % struct（按 mode 不同字段）
        chunk_ms = 50
        headless = false
        last_result                  % struct: ber / decoded_count / details

        % --- streaming state（每次 on_run 重置） ---
        ring
        ring_write
        ring_capacity
        last_decode_at

        % --- widgets ---
        fig
        wav_path_label
        load_btn
        scheme_label
        mode_pass_btn
        mode_awgn_btn
        mode_jakes_btn
        mode_mp_btn
        snr_edit
        jakes_fd_edit
        jakes_alpha_edit
        jakes_type_dd
        mp_delays_edit
        mp_gains_edit
        mp_seed_edit
        chunk_ms_edit
        run_btn
        status_label
        log_area
    end

    methods
        function this = rx_simple_ui(varargin)
            p = inputParser;
            addParameter(p, 'headless', false);
            parse(p, varargin{:});
            this.headless = p.Results.headless;

            simple_ui_addpaths();
            this.sys = sys_params_default();
            this.channel_params = struct( ...
                'snr_db',         20, ...
                'fading_type',    'slow', ...
                'fading_fd_hz',   1, ...
                'doppler_rate',   0, ...
                'mp_delays_ms',   '0 0.167 0.5 0.833 1.333', ...
                'mp_gains',       '1 0.5 0.3 0.2 0.1', ...
                'mp_seed',        4242);
            this.last_result = struct();

            if ~this.headless
                this.createComponents();
            end
        end

        % =================================================================
        function createComponents(this)
            this.fig = uifigure('Name', '通信 RX 简化 UI', ...
                'Position', [200 200 760 640], 'Resize', 'on');

            grid = uigridlayout(this.fig, [12, 4]);
            grid.RowHeight = {30, 30, 30, 30, 30, 30, 30, 30, 30, 30, '1x', 40};
            grid.ColumnWidth = {130, '1x', 130, '1x'};

            % --- Row 1: load wav ---
            this.load_btn = uibutton(grid, 'Text', '📂 选 WAV 文件', ...
                'ButtonPushedFcn', @(s,e) this.on_load_wav());
            this.wav_path_label = uilabel(grid, 'Text', '(未加载)');
            this.wav_path_label.Layout.Column = [2 4];

            % --- Row 2: scheme info ---
            uilabel(grid, 'Text', '体制 (from JSON):');
            this.scheme_label = uilabel(grid, 'Text', '—');
            this.scheme_label.Layout.Column = [2 4];

            % --- Row 3: 信道模式 4 按键（手动 group 实现 radio）---
            uilabel(grid, 'Text', '信道模式:');
            this.mode_pass_btn = uibutton(grid, 'state', 'Text', '纯接收', ...
                'Value', true, 'ValueChangedFcn', @(s,e) this.on_mode_change('pass'));
            this.mode_awgn_btn = uibutton(grid, 'state', 'Text', 'AWGN', ...
                'Value', false, 'ValueChangedFcn', @(s,e) this.on_mode_change('awgn'));
            this.mode_jakes_btn = uibutton(grid, 'state', 'Text', 'Jakes', ...
                'Value', false, 'ValueChangedFcn', @(s,e) this.on_mode_change('jakes'));
            this.mode_pass_btn.Layout.Column = 2;
            this.mode_awgn_btn.Layout.Column = 3;
            this.mode_jakes_btn.Layout.Column = 4;

            uilabel(grid, 'Text', ''); % spacer
            this.mode_mp_btn = uibutton(grid, 'state', 'Text', 'Multipath', ...
                'Value', false, 'ValueChangedFcn', @(s,e) this.on_mode_change('multipath'));
            this.mode_mp_btn.Layout.Column = 2;

            % --- Row 5-7: AWGN / Jakes / Multipath 参数 ---
            uilabel(grid, 'Text', 'SNR (dB):');
            this.snr_edit = uieditfield(grid, 'numeric', 'Value', this.channel_params.snr_db);
            uilabel(grid, 'Text', 'Jakes fd (Hz):');
            this.jakes_fd_edit = uieditfield(grid, 'numeric', 'Value', this.channel_params.fading_fd_hz);

            uilabel(grid, 'Text', 'Jakes type:');
            this.jakes_type_dd = uidropdown(grid, 'Items', {'slow','fast'}, ...
                'Value', this.channel_params.fading_type);
            uilabel(grid, 'Text', 'α (doppler_rate):');
            this.jakes_alpha_edit = uieditfield(grid, 'numeric', 'Value', this.channel_params.doppler_rate);

            uilabel(grid, 'Text', 'MP delays (ms):');
            this.mp_delays_edit = uieditfield(grid, 'text', 'Value', this.channel_params.mp_delays_ms);
            this.mp_delays_edit.Layout.Column = [2 4];

            uilabel(grid, 'Text', 'MP gains (mag):');
            this.mp_gains_edit = uieditfield(grid, 'text', 'Value', this.channel_params.mp_gains);
            this.mp_gains_edit.Layout.Column = [2 3];
            uilabel(grid, 'Text', 'MP seed:');
            this.mp_seed_edit = uieditfield(grid, 'numeric', 'Value', this.channel_params.mp_seed);

            % --- Row 9: chunk + status ---
            uilabel(grid, 'Text', 'chunk (ms):');
            this.chunk_ms_edit = uieditfield(grid, 'numeric', 'Value', this.chunk_ms);
            uilabel(grid, 'Text', '状态:');
            this.status_label = uilabel(grid, 'Text', '就绪');

            % --- Row 11: log ---
            this.log_area = uitextarea(grid, 'Editable', 'off', ...
                'Value', {'[UI] rx_simple_ui 启动'});
            this.log_area.Layout.Row = 11;
            this.log_area.Layout.Column = [1 4];

            % --- Row 12: run ---
            this.run_btn = uibutton(grid, 'Text', '▶ 流式解码运行', ...
                'FontSize', 14, 'BackgroundColor', [0.2 0.5 0.8], ...
                'FontColor', [1 1 1], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(s,e) this.on_run());
            this.run_btn.Layout.Column = [1 4];
        end

        % =================================================================
        function on_load_wav(this)
            [f, p] = uigetfile({'*.wav','WAV 文件'}, '选 wav');
            if isequal(f, 0), return; end
            this.wav_path = fullfile(p, f);
            this.wav_path_label.Text = f;

            % 找同名 JSON
            [~, base, ~] = fileparts(this.wav_path);
            json_candidate = fullfile(p, [base '.json']);
            if exist(json_candidate, 'file')
                this.json_path = json_candidate;
                this.load_meta();
            else
                this.json_path = '';
                this.scheme_label.Text = '(无 JSON, 需手动)';
                this.append_log('[WARN] 同名 JSON 未找到，meta 缺失，无法 BER 评估');
            end
        end

        function load_meta(this)
            fid = fopen(this.json_path, 'r');
            json_str = fread(fid, '*char').';
            fclose(fid);
            this.meta = simple_ui_meta_io('decode', json_str);
            this.scheme_label.Text = sprintf('%s (N_info=%d, body=%d)', ...
                this.meta.scheme, this.meta.frame.N_info, this.meta.frame.body_offset);
            this.append_log(sprintf('[META] %s scheme=%s frame_pb_samples=%d', ...
                this.meta.created_at, this.meta.scheme, this.meta.frame.frame_pb_samples));
        end

        function on_mode_change(this, mode)
            this.channel_mode = mode;
            % 互斥（手动 radio）
            this.mode_pass_btn.Value  = strcmp(mode, 'pass');
            this.mode_awgn_btn.Value  = strcmp(mode, 'awgn');
            this.mode_jakes_btn.Value = strcmp(mode, 'jakes');
            this.mode_mp_btn.Value    = strcmp(mode, 'multipath');
            this.append_log(sprintf('[MODE] %s', mode));
        end

        % =================================================================
        function on_run(this, ~, ~)
            try
                if isempty(this.wav_path) || ~exist(this.wav_path, 'file')
                    error('未加载 wav');
                end
                if isempty(this.meta)
                    error('未加载 JSON meta');
                end

                % --- 同步 UI 值 ---
                if ~this.headless
                    this.channel_params.snr_db        = this.snr_edit.Value;
                    this.channel_params.fading_type   = this.jakes_type_dd.Value;
                    this.channel_params.fading_fd_hz  = this.jakes_fd_edit.Value;
                    this.channel_params.doppler_rate  = this.jakes_alpha_edit.Value;
                    this.channel_params.mp_delays_ms  = this.mp_delays_edit.Value;
                    this.channel_params.mp_gains      = this.mp_gains_edit.Value;
                    this.channel_params.mp_seed       = this.mp_seed_edit.Value;
                    this.chunk_ms                     = this.chunk_ms_edit.Value;
                end

                this.set_status('运行中...', [0.9 0.6 0.2]);

                % --- 1. 读 wav ---
                [audio_full, fs_read] = audioread(this.wav_path);
                audio_full = audio_full(:, 1).';
                if abs(fs_read - this.meta.sys.fs) > 1
                    error('fs mismatch: wav=%d meta=%d', fs_read, this.meta.sys.fs);
                end
                % undo TX scale_factor
                if isfield(this.meta.frame, 'scale_factor') && this.meta.frame.scale_factor > 0
                    audio_full = audio_full / this.meta.frame.scale_factor;
                end
                this.append_log(sprintf('[LOAD] wav=%d samples (%.2fs) fs=%d', ...
                    length(audio_full), length(audio_full)/fs_read, fs_read));

                % --- 2. 加 stateful 信道（jakes/multipath 一次过）---
                audio_in = audio_full;
                switch this.channel_mode
                    case 'jakes'
                        audio_in = this.apply_jakes_full(audio_full);
                    case 'multipath'
                        audio_in = this.apply_multipath_full(audio_full);
                end
                this.append_log(sprintf('[CHAN] mode=%s', this.channel_mode));

                % --- 3. ring buffer init ---
                fn_hint = this.meta.frame.frame_pb_samples;
                this.ring_capacity = max(8 * fn_hint, length(audio_in) + 16000);
                this.ring = zeros(1, this.ring_capacity);
                this.ring_write = 0;
                this.last_decode_at = 0;

                % --- 4. 重建解码用 sys ---
                sys_dec = this.rebuild_sys_for_decode();

                % --- 5. chunk-by-chunk 推 + 试解码 ---
                chunk_n = round(this.chunk_ms * 1e-3 * sys_dec.fs);
                n_chunks = ceil(length(audio_in) / chunk_n);
                decoded_count = 0;
                ber_sum = 0;
                details = {};

                for k = 1:n_chunks
                    idx_lo = (k-1)*chunk_n + 1;
                    idx_hi = min(k*chunk_n, length(audio_in));
                    chunk = audio_in(idx_lo:idx_hi);

                    % 流式信道（awgn 流式加噪；其他模式加 dither 防 modem_decode 零噪奇点）
                    sig_pwr_chunk = mean(chunk.^2);
                    if strcmp(this.channel_mode, 'awgn')
                        nv = sig_pwr_chunk * 10^(-this.channel_params.snr_db/10);
                    else
                        % pass/jakes/multipath: -80 dB dither，远低于实用 SNR，不影响算法
                        nv = sig_pwr_chunk * 10^(-80/10);
                    end
                    if sig_pwr_chunk > 0
                        chunk = chunk + sqrt(nv) * randn(size(chunk));
                    end

                    % push to ring
                    L = length(chunk);
                    this.ring(this.ring_write + (1:L)) = chunk;
                    this.ring_write = this.ring_write + L;

                    % try decode（条件：ring 有完整一帧 + 上次未解过此位置）
                    if this.ring_write >= this.last_decode_at + fn_hint + 1000
                        decoded = this.try_decode_one_frame(sys_dec, fn_hint);
                        if decoded.found
                            decoded_count = decoded_count + 1;
                            ber_sum = ber_sum + decoded.ber;
                            details{end+1} = decoded; %#ok<AGROW>
                            this.append_log(sprintf('[DEC #%d] %s BER=%.3f%% (%d/%d) iter=%d α=%+.2e gate=%s', ...
                                decoded_count, this.meta.scheme, decoded.ber*100, ...
                                decoded.n_err, decoded.n, decoded.iter, ...
                                decoded.alpha_used, decoded.alpha_gate_reason));
                        end
                    end
                end

                % 最后再试一次（防止刚好结尾差一点）
                if this.ring_write >= this.last_decode_at + fn_hint
                    decoded = this.try_decode_one_frame(sys_dec, fn_hint);
                    if decoded.found
                        decoded_count = decoded_count + 1;
                        ber_sum = ber_sum + decoded.ber;
                        details{end+1} = decoded; %#ok<AGROW>
                        this.append_log(sprintf('[DEC #%d FINAL] BER=%.3f%%', decoded_count, decoded.ber*100));
                    end
                end

                mean_ber = ber_sum / max(1, decoded_count);
                this.last_result = struct( ...
                    'mode', this.channel_mode, ...
                    'decoded_count', decoded_count, ...
                    'mean_ber', mean_ber, ...
                    'details', {details});

                this.append_log(sprintf('[DONE] mode=%s, frames=%d, mean_BER=%.3f%%', ...
                    this.channel_mode, decoded_count, mean_ber*100));
                this.set_status(sprintf('完成 BER=%.3f%%', mean_ber*100), [0.2 0.7 0.3]);

            catch ME
                this.append_log(sprintf('[ERR] %s', ME.message));
                if ~isempty(ME.stack)
                    for si = 1:min(3, length(ME.stack))
                        this.append_log(sprintf('  @ %s L%d', ME.stack(si).name, ME.stack(si).line));
                    end
                end
                this.set_status('错误', [0.8 0.2 0.2]);
                rethrow(ME);
            end
        end

        % =================================================================
        function decoded = try_decode_one_frame(this, sys_dec, fn_hint)
            decoded = struct('found', false);

            % detect_frame_stream
            sync_det = detect_frame_stream(this.ring, this.ring_write, ...
                this.last_decode_at, sys_dec, struct('frame_len_hint', fn_hint));
            if ~sync_det.found, return; end

            fs_pos = sync_det.fs_pos;
            if this.ring_write < fs_pos + fn_hint - 1, return; end
            if this.last_decode_at >= fs_pos, return; end

            alpha_est = 0; alpha_conf = 0;
            if isfield(sync_det, 'alpha_est'),        alpha_est  = sync_det.alpha_est; end
            if isfield(sync_det, 'alpha_confidence'), alpha_conf = sync_det.alpha_confidence; end

            this.append_log(sprintf('[SYNC] fs=%d peak=%.1f ratio=%.1f conf=%.2f α=%+.3e', ...
                fs_pos, sync_det.peak_val, sync_det.peak_ratio, sync_det.confidence, alpha_est));

            rx_seg = this.ring(fs_pos : fs_pos + fn_hint - 1);

            % α gate
            gate = streaming_alpha_gate(alpha_est, alpha_conf, sys_dec);
            alpha_used = 0;
            if gate.accepted
                alpha_used = gate.alpha;
                this.append_log(sprintf('[α-COMP] α=%+.3e (gate=%s)', gate.alpha, gate.reason));
            else
                this.append_log(sprintf('[α-GATE] α=%+.3e conf=%.2f 拒绝（%s），α 视为 0', ...
                    alpha_est, alpha_conf, gate.reason));
            end
            % 总是调 comp_resample（α=0 时 no-op），保持下游路径一致
            % 避免 GATE / COMP 两路径走不同代码导致 sub-sample 处理差异
            rx_seg = comp_resample_spline(rx_seg, alpha_used, sys_dec.fs, 'fast');
            if length(rx_seg) >= fn_hint
                rx_seg = rx_seg(1:fn_hint);
            else
                rx_seg = [rx_seg, zeros(1, fn_hint - length(rx_seg))];
            end

            % downconvert + body 切片
            bw_use = p4_downconv_bw(this.meta.scheme, sys_dec);
            [full_bb_rx, ~] = downconvert(rx_seg, sys_dec.fs, sys_dec.fc, bw_use);
            body_offset = this.meta.frame.body_offset;
            % N_shaped 取 frame_pb 对应 body 长度
            body_bb_rx = full_bb_rx(body_offset+1 : end);

            % decode：用 TX encode_meta（白名单字段，复数已 strip → 恢复）
            if isfield(this.meta, 'encode_meta') && ~isempty(this.meta.encode_meta)
                meta_dec = local_restore_complex(this.meta.encode_meta);
            else
                meta_dec = struct();
            end
            meta_dec.scheme = this.meta.scheme;
            try
                [bits_out, info] = modem_decode(body_bb_rx, this.meta.scheme, sys_dec, meta_dec);
            catch ME
                this.append_log(sprintf('[DEC-ERR] %s', ME.message));
                this.last_decode_at = fs_pos;  % skip 这帧
                return;
            end

            % BER
            n = min(length(bits_out), length(this.meta.known_bits));
            n_err = sum(bits_out(1:n) ~= this.meta.known_bits(1:n));
            ber = n_err / max(1, n);

            decoded.found = true;
            decoded.fs_pos = fs_pos;
            decoded.alpha_est = alpha_est;
            decoded.alpha_used = alpha_used;
            decoded.alpha_gate_reason = gate.reason;
            decoded.bits_out = bits_out;
            decoded.bits_in = this.meta.known_bits(1:n);
            decoded.n = n;
            decoded.n_err = n_err;
            decoded.ber = ber;
            if isfield(info, 'turbo_iter'), decoded.iter = info.turbo_iter; else, decoded.iter = 0; end
            decoded.info = info;

            this.last_decode_at = fs_pos;
        end

        % =================================================================
        function audio_out = apply_jakes_full(this, audio_in)
            % 用 gen_uwa_channel 一次过加 jakes（基带），但 audio_in 是 passband
            % → 简化：在 passband 上 conv 一个 jakes-tap-only 滤波器（大约等价 narrowband 假设）
            % → 或更精确：downconvert 到 baseband → gen_uwa_channel → upconvert 回
            % 简化版用后者（更精确）
            sys_use = this.meta.sys;
            % 1. downconvert
            [bb, ~] = downconvert(audio_in, sys_use.fs, sys_use.fc, sys_use.fs);
            % 2. gen_uwa_channel
            ch_params = struct( ...
                'fs',            sys_use.fs, ...
                'num_paths',     5, ...
                'delay_profile', 'custom', ...
                'delays_s',      [0, 0.167, 0.5, 0.833, 1.333] * 1e-3, ...
                'gains',         [1, 0.5, 0.3, 0.2, 0.1], ...
                'doppler_rate',  this.channel_params.doppler_rate, ...
                'fading_type',   this.channel_params.fading_type, ...
                'fading_fd_hz',  this.channel_params.fading_fd_hz, ...
                'snr_db',        this.channel_params.snr_db, ...
                'seed',          12345 );
            [bb_ch, ~] = gen_uwa_channel(bb, ch_params);
            if length(bb_ch) > length(bb)
                bb_ch = bb_ch(1:length(bb));
            elseif length(bb_ch) < length(bb)
                bb_ch = [bb_ch, zeros(1, length(bb) - length(bb_ch))];
            end
            % 3. upconvert
            [audio_out, ~] = upconvert(bb_ch, sys_use.fs, sys_use.fc);
            audio_out = real(audio_out);
        end

        function audio_out = apply_multipath_full(this, audio_in)
            % 用 conv 在 passband 加 multipath（FIR tap）
            delays_ms = sscanf(this.channel_params.mp_delays_ms, '%f');
            gains_str = this.channel_params.mp_gains;
            gains = sscanf(gains_str, '%f');
            if length(gains) ~= length(delays_ms)
                error('multipath: delays 与 gains 长度不一致');
            end
            sys_use = this.meta.sys;
            tap_idx = round(delays_ms * 1e-3 * sys_use.fs) + 1;
            tap_len = max(tap_idx);
            h_tap = zeros(1, tap_len);
            for k = 1:length(tap_idx)
                h_tap(tap_idx(k)) = gains(k);
            end
            % 加噪声
            audio_filt = conv(audio_in, h_tap);
            audio_filt = audio_filt(1:length(audio_in));
            sig_pwr = mean(audio_filt.^2);
            nv = sig_pwr * 10^(-this.channel_params.snr_db/10);
            rng(this.channel_params.mp_seed);
            audio_out = audio_filt + sqrt(nv) * randn(size(audio_filt));
        end

        % =================================================================
        function sys_dec = rebuild_sys_for_decode(this)
            % 从 meta.sys 重建解码用 sys（恢复复数字段、补全默认）
            sys_dec = sys_params_default();
            ms = this.meta.sys;
            sys_dec.fs   = ms.fs;
            sys_dec.fc   = ms.fc;
            sys_dec.sps  = ms.sps;
            sys_dec.sym_rate = ms.sym_rate;
            sys_dec.codec = ms.codec;
            sch_field = lower(strrep(this.meta.scheme, '-', ''));
            if strcmp(sch_field, 'fhmfsk'), sch_field = 'fhmfsk'; end
            if strcmp(sch_field, 'sctde'),  sch_field = 'sctde'; end
            % SC-FDE → scfde, SC-TDE → sctde, FH-MFSK → fhmfsk
            map = struct('scfde','scfde','ofdm','ofdm','sctde','sctde', ...
                         'otfs','otfs','dsss','dsss','fhmfsk','fhmfsk');
            if isfield(map, sch_field)
                fname = map.(sch_field);
                if isfield(ms, fname)
                    sys_dec.(fname) = local_restore_complex(ms.(fname));
                end
            end
            if isfield(ms, 'frame'),    sys_dec.frame = ms.frame; end
            if isfield(ms, 'preamble'), sys_dec.preamble = ms.preamble; end
        end

        % =================================================================
        function set_status(this, msg, color)
            if this.headless, return; end
            this.status_label.Text = msg;
            if nargin >= 3, this.status_label.FontColor = color; end
        end

        function append_log(this, msg)
            if this.headless
                fprintf('%s\n', msg);
                return;
            end
            curr = this.log_area.Value;
            if ischar(curr), curr = {curr}; end
            curr{end+1} = msg;
            if length(curr) > 200, curr = curr(end-199:end); end
            this.log_area.Value = curr;
            scroll(this.log_area, 'bottom');
        end
    end
end

%% =========================================================================
function s_out = local_restore_complex(s)
% 递归恢复 strip_complex 编出的 .re/.im struct → 复数
if ~isstruct(s)
    s_out = s;
    return;
end
fns = fieldnames(s);
s_out = struct();
for k = 1:length(fns)
    fn = fns{k};
    val = s.(fn);
    if isstruct(val) && isfield(val, 're') && isfield(val, 'im') && numel(fieldnames(val)) == 2
        s_out.(fn) = val.re(:).' + 1j * val.im(:).';
    elseif isstruct(val)
        s_out.(fn) = local_restore_complex(val);
    else
        s_out.(fn) = val;
    end
end
end
