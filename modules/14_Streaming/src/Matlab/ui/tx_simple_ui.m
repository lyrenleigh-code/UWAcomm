classdef tx_simple_ui < handle
% 功能：水声通信 TX 简化 UI —— 一键生成 passband WAV + JSON meta
% 版本：V1.0.0（2026-05-04）
% 用法：
%   t = tx_simple_ui();              % 启动 GUI
%   t = tx_simple_ui('headless', true);  % headless（测试用，不开 figure）
%   t.on_generate();                 % headless 下手动触发生成
%
% 架构：
%   - classdef + uifigure，所有处理在按钮回调里同步执行
%   - 无 timer / FIFO ring / 持续 app 状态 → 无 closure 缓存陷阱
%   - 复用 P5 / P4 底层函数（modem_encode / assemble_physical_frame / upconvert）
%   - 体制覆盖全 6 体制（SC-FDE / OFDM / SC-TDE / OTFS / DSSS / FH-MFSK）
%
% Spec: specs/active/2026-05-04-tx-rx-simple-ui-split.md

    properties
        % --- core state ---
        sys
        scheme = 'SC-FDE'
        ui_vals
        output_dir
        headless = false

        % --- widgets ---
        fig
        scheme_dd
        v40_btn
        blk_fft_edit
        blk_cp_edit
        pilot_edit
        train_K_edit
        turbo_iter_edit
        payload_edit
        otfs_pilot_dd
        source_type_dd
        source_text_edit
        source_file_edit
        source_file_btn
        out_dir_edit
        out_dir_btn
        prefix_edit
        gen_btn
        log_area
        last_wav_path = ''
        last_json_path = ''
    end

    methods
        function this = tx_simple_ui(varargin)
            % 解析 'headless' name-value
            p = inputParser;
            addParameter(p, 'headless', false);
            parse(p, varargin{:});
            this.headless = p.Results.headless;

            simple_ui_addpaths();
            this.sys = sys_params_default();
            this.output_dir = pwd;

            % 默认 ui_vals（SC-FDE V4.0 预设）
            this.ui_vals = struct( ...
                'blk_fft',        256, ...
                'blk_cp',         128, ...
                'pilot_per_blk',  128, ...
                'train_period_K', 31, ...
                'turbo_iter',     3, ...
                'payload',        128, ...
                'otfs_pilot_mode','impulse', ...
                'fading_type',    'static (恒定)', ...
                'fd_hz',          0);

            if ~this.headless
                this.createComponents();
            end
        end

        % =================================================================
        function createComponents(this)
            this.fig = uifigure('Name', '通信 TX 简化 UI', ...
                'Position', [200 200 720 600], 'Resize', 'on');

            grid = uigridlayout(this.fig, [11, 4]);
            grid.RowHeight   = {30, 30, 30, 30, 30, 30, 30, 30, 30, '1x', 30};
            grid.ColumnWidth = {130, '1x', 130, '1x'};

            % --- Row 1: scheme ---
            uilabel(grid, 'Text', '体制:');
            this.scheme_dd = uidropdown(grid, ...
                'Items', {'SC-FDE','OFDM','SC-TDE','OTFS','DSSS','FH-MFSK'}, ...
                'Value', this.scheme, ...
                'ValueChangedFcn', @(s,e) this.on_scheme_change(s,e));
            this.scheme_dd.Layout.Column = [2 4];

            % --- Row 2: V4.0 preset button ---
            this.v40_btn = uibutton(grid, 'Text', 'V4.0 Jakes 预设 (SC-FDE)', ...
                'ButtonPushedFcn', @(s,e) this.on_v40_preset());
            this.v40_btn.Layout.Column = [1 4];

            % --- Row 3-5: scheme params ---
            uilabel(grid, 'Text', 'blk_fft:');
            this.blk_fft_edit = uieditfield(grid, 'numeric', 'Value', this.ui_vals.blk_fft);
            uilabel(grid, 'Text', 'blk_cp:');
            this.blk_cp_edit = uieditfield(grid, 'numeric', 'Value', this.ui_vals.blk_cp);

            uilabel(grid, 'Text', 'pilot_per_blk:');
            this.pilot_edit = uieditfield(grid, 'numeric', 'Value', this.ui_vals.pilot_per_blk);
            uilabel(grid, 'Text', 'train_period_K:');
            this.train_K_edit = uieditfield(grid, 'numeric', 'Value', this.ui_vals.train_period_K);

            uilabel(grid, 'Text', 'turbo_iter:');
            this.turbo_iter_edit = uieditfield(grid, 'numeric', 'Value', this.ui_vals.turbo_iter);
            uilabel(grid, 'Text', 'payload bytes (DSSS/FHMFSK):');
            this.payload_edit = uieditfield(grid, 'numeric', 'Value', this.ui_vals.payload);

            % --- Row 6: OTFS pilot mode ---
            uilabel(grid, 'Text', 'OTFS pilot:');
            this.otfs_pilot_dd = uidropdown(grid, ...
                'Items', {'impulse','zc','superimposed'}, 'Value', 'impulse');

            % --- Row 7: source type ---
            uilabel(grid, 'Text', '信源:');
            this.source_type_dd = uidropdown(grid, ...
                'Items', {'random','text','file'}, 'Value', 'random', ...
                'ValueChangedFcn', @(s,e) this.on_source_type_change(s,e));
            this.source_type_dd.Layout.Column = [2 2];

            this.source_text_edit = uieditfield(grid, 'text', ...
                'Value', 'hello underwater', 'Enable', 'off');
            this.source_text_edit.Layout.Column = [3 4];

            % --- Row 8: source file ---
            uilabel(grid, 'Text', '源文件:');
            this.source_file_edit = uieditfield(grid, 'text', 'Value', '', 'Enable', 'off');
            this.source_file_edit.Layout.Column = [2 3];
            this.source_file_btn = uibutton(grid, 'Text', '...', ...
                'ButtonPushedFcn', @(s,e) this.on_pick_source_file(), 'Enable', 'off');

            % --- Row 9: output dir + prefix ---
            uilabel(grid, 'Text', '输出目录:');
            this.out_dir_edit = uieditfield(grid, 'text', 'Value', this.output_dir);
            this.out_dir_edit.Layout.Column = [2 3];
            this.out_dir_btn = uibutton(grid, 'Text', '...', ...
                'ButtonPushedFcn', @(s,e) this.on_pick_output_dir());

            % --- Row 10 (large): log area ---
            this.log_area = uitextarea(grid, 'Editable', 'off', ...
                'Value', {'[UI] tx_simple_ui 启动'});
            this.log_area.Layout.Row = 10;
            this.log_area.Layout.Column = [1 4];

            % --- Row 11: generate button ---
            this.gen_btn = uibutton(grid, 'Text', '🚀 生成 WAV + JSON', ...
                'FontSize', 14, 'BackgroundColor', [0.2 0.6 0.3], ...
                'FontColor', [1 1 1], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(s,e) this.on_generate());
            this.gen_btn.Layout.Column = [1 4];

            this.append_log(sprintf('[UI] fs=%dHz fc=%dHz, 默认体制=%s', ...
                this.sys.fs, this.sys.fc, this.scheme));
        end

        % =================================================================
        function on_scheme_change(this, src, ~)
            this.scheme = src.Value;
            this.append_log(sprintf('[UI] scheme -> %s', this.scheme));
        end

        function on_v40_preset(this, ~, ~)
            % SC-FDE V4.0 协议层突破预设
            this.scheme_dd.Value = 'SC-FDE';
            this.scheme = 'SC-FDE';
            this.blk_fft_edit.Value     = 256;
            this.blk_cp_edit.Value      = 128;
            this.pilot_edit.Value       = 128;
            this.train_K_edit.Value     = 31;
            this.turbo_iter_edit.Value  = 3;
            this.append_log('[预设] V4.0 Jakes：blk_fft=256, blk_cp=128, pilot_per_blk=128, train_period_K=31');
            this.append_log('       直接链路实测 jakes fd=1Hz BER 0.68% (吞吐损失 50%)');
        end

        function on_source_type_change(this, src, ~)
            t = src.Value;
            if strcmp(t, 'text')
                this.source_text_edit.Enable = 'on';
                this.source_file_edit.Enable = 'off';
                this.source_file_btn.Enable  = 'off';
            elseif strcmp(t, 'file')
                this.source_text_edit.Enable = 'off';
                this.source_file_edit.Enable = 'on';
                this.source_file_btn.Enable  = 'on';
            else
                this.source_text_edit.Enable = 'off';
                this.source_file_edit.Enable = 'off';
                this.source_file_btn.Enable  = 'off';
            end
        end

        function on_pick_source_file(this)
            [f, p] = uigetfile({'*.*','所有文件'}, '选源文件');
            if isequal(f, 0), return; end
            this.source_file_edit.Value = fullfile(p, f);
        end

        function on_pick_output_dir(this)
            d = uigetdir(this.output_dir, '选输出目录');
            if isequal(d, 0), return; end
            this.output_dir = d;
            this.out_dir_edit.Value = d;
        end

        % =================================================================
        function on_generate(this, ~, ~)
            try
                % --- 1. 同步 UI 值到 ui_vals（headless 模式直接用属性默认值）---
                if ~this.headless
                    this.ui_vals.blk_fft        = this.blk_fft_edit.Value;
                    this.ui_vals.blk_cp         = this.blk_cp_edit.Value;
                    this.ui_vals.pilot_per_blk  = this.pilot_edit.Value;
                    this.ui_vals.train_period_K = this.train_K_edit.Value;
                    this.ui_vals.turbo_iter     = this.turbo_iter_edit.Value;
                    this.ui_vals.payload        = this.payload_edit.Value;
                    this.ui_vals.otfs_pilot_mode = this.otfs_pilot_dd.Value;
                    this.output_dir              = this.out_dir_edit.Value;
                end

                % --- 2. apply scheme params（V3.0 解耦 blk_cp/blk_fft）---
                [N_info, sys_use] = p4_apply_scheme_params(this.scheme, this.sys, this.ui_vals);

                % OTFS pilot mode 单独透传
                if strcmp(this.scheme, 'OTFS') && isfield(sys_use, 'otfs')
                    sys_use.otfs.pilot_mode = this.ui_vals.otfs_pilot_mode;
                end

                % --- 3. 信源 → bits ---
                info_bits = this.read_info_bits(N_info);

                % --- 4. encode + assemble ---
                [body_bb, meta_tx] = modem_encode(info_bits, this.scheme, sys_use);
                [frame_bb, ~] = assemble_physical_frame(body_bb, sys_use);
                body_offset = length(frame_bb) - length(body_bb);

                % --- 5. upconvert (passband) ---
                [tx_pb, ~] = upconvert(frame_bb, sys_use.fs, sys_use.fc);
                tx_pb = real(tx_pb);

                % --- 6. 归一化到 [-0.95, 0.95] ---
                peak = max(abs(tx_pb));
                if peak < 1e-12
                    error('TX signal peak ≈ 0，疑似 encoding 失败');
                end
                scale_factor = 0.95 / peak;
                tx_pb_norm = tx_pb * scale_factor;

                % --- 7. 构造文件名 ---
                ts = datestr(now, 'yyyymmdd_HHMMSS');
                if ~exist(this.output_dir, 'dir'), mkdir(this.output_dir); end
                wav_name  = sprintf('tx_%s_%s.wav', this.scheme, ts);
                json_name = sprintf('tx_%s_%s.json', this.scheme, ts);
                wav_path  = fullfile(this.output_dir, wav_name);
                json_path = fullfile(this.output_dir, json_name);

                % --- 8. 写 WAV（单声道）---
                audiowrite(wav_path, tx_pb_norm(:), sys_use.fs);

                % --- 9. 写 JSON meta ---
                meta = struct();
                meta.scheme = this.scheme;
                meta.created_at = ts;
                meta.sys   = local_extract_sys_essential(sys_use, this.scheme);
                meta.frame = struct( ...
                    'N_info', N_info, ...
                    'body_offset', body_offset, ...
                    'frame_pb_samples', length(tx_pb_norm), ...
                    'scale_factor', scale_factor);
                meta.known_bits = info_bits;
                % encode_meta：CLAUDE.md §2 帧结构白名单（blk_fft/blk_cp/N_blocks/sym_per_block/N_shaped/perm_all 等）
                meta.encode_meta = local_strip_oracle_fields(meta_tx);
                json_str = simple_ui_meta_io('encode', meta);
                fid = fopen(json_path, 'w');
                if fid < 0, error('无法打开 JSON 写入: %s', json_path); end
                fwrite(fid, json_str);
                fclose(fid);

                this.last_wav_path  = wav_path;
                this.last_json_path = json_path;

                this.append_log(sprintf('[OK] %s (%d samples, %.2fs)', wav_name, ...
                    length(tx_pb_norm), length(tx_pb_norm)/sys_use.fs));
                this.append_log(sprintf('     scheme=%s N_info=%d body_offset=%d', ...
                    this.scheme, N_info, body_offset));
                this.append_log(sprintf('     scale=%.3e peak_pre=%.3e', scale_factor, peak));

            catch ME
                this.append_log(sprintf('[ERR] %s', ME.message));
                if ~isempty(ME.stack)
                    for si = 1:min(3, length(ME.stack))
                        this.append_log(sprintf('  @ %s L%d', ME.stack(si).name, ME.stack(si).line));
                    end
                end
                rethrow(ME);  % 让单测能捕获
            end
        end

        % =================================================================
        function bits = read_info_bits(this, N_info)
            switch lower(this.source_type_dd_value())
                case 'random'
                    rng('shuffle');
                    bits = randi([0 1], 1, N_info);
                case 'text'
                    txt = this.source_text_edit_value();
                    bits = local_text_to_bits(txt, N_info);
                case 'file'
                    fpath = this.source_file_edit_value();
                    if isempty(fpath) || ~exist(fpath, 'file')
                        error('源文件不存在: %s', fpath);
                    end
                    fid = fopen(fpath, 'r');
                    raw = fread(fid, '*uint8');
                    fclose(fid);
                    bits = local_bytes_to_bits(raw, N_info);
                otherwise
                    error('未知信源类型');
            end
        end

        function v = source_type_dd_value(this)
            if this.headless, v = 'random'; else, v = this.source_type_dd.Value; end
        end
        function v = source_text_edit_value(this)
            if this.headless, v = 'hello'; else, v = this.source_text_edit.Value; end
        end
        function v = source_file_edit_value(this)
            if this.headless, v = ''; else, v = this.source_file_edit.Value; end
        end

        % =================================================================
        function append_log(this, msg)
            if this.headless
                fprintf('%s\n', msg);
                return;
            end
            curr = this.log_area.Value;
            if ischar(curr), curr = {curr}; end
            curr{end+1} = msg;
            % 限 200 行
            if length(curr) > 200
                curr = curr(end-199:end);
            end
            this.log_area.Value = curr;
            scroll(this.log_area, 'bottom');
        end
    end
end

%% =========================================================================
function essential = local_extract_sys_essential(sys, scheme)
% 抽取 RX 解码必需的 sys 字段（避免 JSON 巨大）
essential = struct();
essential.fs       = sys.fs;
essential.fc       = sys.fc;
essential.sps      = sys.sps;
essential.sym_rate = sys.sym_rate;
essential.codec    = sys.codec;

key = lower(scheme);
switch key
    case 'sc-fde', essential.scfde = sys.scfde;
    case 'ofdm',   essential.ofdm  = sys.ofdm;
    case 'sc-tde', essential.sctde = sys.sctde;
    case 'otfs',   essential.otfs  = sys.otfs;
    case 'dsss',   essential.dsss  = sys.dsss;
    case 'fh-mfsk',essential.fhmfsk= sys.fhmfsk;
end
% 帧前导固定（HFM/LFM）
if isfield(sys, 'frame'),    essential.frame    = sys.frame;    end
if isfield(sys, 'preamble'), essential.preamble = sys.preamble; end
end

%% =========================================================================
function meta_clean = local_strip_oracle_fields(meta_tx)
% CLAUDE.md §2 严禁 oracle 字段：all_cp_data / all_sym / noise_var / pilot_sym
% 按白名单移除（modem_encode 输出本不应有这些，但 belt-and-suspenders）
oracle_fields = {'all_cp_data', 'all_sym', 'noise_var', 'pilot_sym', ...
                 'h_time', 'h_time_block', 'sym_delays_oracle'};
meta_clean = meta_tx;
fns = fieldnames(meta_clean);
for k = 1:length(fns)
    if any(strcmp(fns{k}, oracle_fields))
        meta_clean = rmfield(meta_clean, fns{k});
    end
end
end

%% =========================================================================
function bits = local_text_to_bits(txt, N_info)
raw = uint8(char(txt));
bits = local_bytes_to_bits(raw, N_info);
end

%% =========================================================================
function bits = local_bytes_to_bits(raw, N_info)
b = de2bi(raw, 8, 'left-msb');     % nx8
bits = reshape(b.', 1, []);
% 截或 zero-pad 到 N_info
if length(bits) > N_info
    bits = bits(1:N_info);
else
    bits = [bits, zeros(1, N_info-length(bits))];
end
end
