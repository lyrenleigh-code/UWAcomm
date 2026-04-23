function fading_cfgs = bench_build_fading_cfgs(stage, scheme, combo_spec)
% 功能：按 stage/scheme 构造单行 fading_cfgs（对齐各 runner 列数约定）
% 版本：V1.0.0（2026-04-19）
% 输入：
%   stage       - 'A1' | 'A2' | 'A3' | 'B'
%   scheme      - 'SC-FDE' | 'OFDM' | 'SC-TDE' | 'OTFS' | 'DSSS' | 'FH-MFSK'
%   combo_spec  - struct：
%     .fd_hz         （A1/A3 必填）
%     .doppler_rate  （A2/A3 必填）
%     .channel_tag   （B 必填，'disc-5Hz' | 'hyb-K20' | 'hyb-K10' | 'hyb-K5'）
% 输出：
%   fading_cfgs - 1×N cell（仅一行），格式：
%     SC-FDE/OFDM timevarying : 7 列 {tag, dop_type, fd_hz, alpha, fft, cp, nblk}
%     SC-TDE/DSSS/FH-MFSK     : 4 列 {tag, dop_type, fd_hz, alpha}
%     OTFS                    : 3 列 {tag, dop_type, fd_hz|vec|struct}
%     SC-FDE/OFDM discrete(B) : 7 列 {tag, dop_type, vec|struct, fft, cp, nblk, fd_scatter}
%     SC-TDE/DSSS/FH-MFSK(B)  : 4 列 {tag, dop_type, vec|struct, fd_scatter}
%
% 备注：
%   - A2 × OTFS 抛错（调用方应在外层跳过）
%   - B × OTFS 走 timevarying runner + discrete/hybrid 单元

switch upper(stage)
    case 'A1'
        fd_hz = combo_spec.fd_hz;
        alpha = 0;
        tag = ternary(fd_hz == 0, 'static', sprintf('fd=%gHz', fd_hz));
        dop = ternary(fd_hz == 0, 'static', 'slow');
        fading_cfgs = pack_timevarying(scheme, tag, dop, fd_hz, alpha);

    case {'A2', 'D'}
        fd_hz = 0;
        alpha = combo_spec.doppler_rate;
        tag = ternary(alpha == 0, 'static', sprintf('a=%g', alpha));
        dop = 'static';  % 固定 α，不走 Jakes 时变
        if strcmpi(scheme, 'OTFS')
            error('bench_build_fading_cfgs:OTFSAlphaNotSupported', ...
                  '%s × OTFS 不支持（DD 框架不适配固定 α），调用方应跳过', stage);
        end
        fading_cfgs = pack_timevarying(scheme, tag, dop, fd_hz, alpha);

    case 'A3'
        fd_hz = combo_spec.fd_hz;
        alpha = combo_spec.doppler_rate;
        tag = sprintf('fd=%g_a=%g', fd_hz, alpha);
        dop = ternary(fd_hz == 0, 'static', 'slow');
        fading_cfgs = pack_timevarying(scheme, tag, dop, fd_hz, alpha);

    case 'B'
        fading_cfgs = pack_discrete(scheme, combo_spec.channel_tag);

    case 'C'
        % 多 seed 帧检测率（2026-04-23 启用）：doppler_rate=0 固定
        fd_hz = combo_spec.fd_hz;
        alpha = 0;
        tag = ternary(fd_hz == 0, 'static', sprintf('fd=%gHz', fd_hz));
        dop = ternary(fd_hz == 0, 'static', 'slow');
        fading_cfgs = pack_timevarying(scheme, tag, dop, fd_hz, alpha);

    otherwise
        error('bench_build_fading_cfgs:UnknownStage', '未知 stage: %s', stage);
end

end

% ============ 子函数 ============

function cfg = pack_timevarying(scheme, tag, dop, fd_hz, alpha)
% 构造 A1/A2/A3 的 fading_cfgs 单行
[fft_size, cp_len, num_blocks] = bench_get_fft_params(max(fd_hz, 0));
switch upper(scheme)
    case {'SC-FDE','OFDM'}
        cfg = { tag, dop, fd_hz, alpha, fft_size, cp_len, num_blocks };
    case {'SC-TDE','DSSS','FH-MFSK'}
        cfg = { tag, dop, fd_hz, alpha };
    case 'OTFS'
        % OTFS 3 列：第 3 列承载 fd 数值 / vector / struct
        if strcmp(dop, 'static')
            cfg = { tag, 'static', zeros(1,5) };
        else
            cfg = { tag, 'jakes', fd_hz };
        end
    otherwise
        error('bench_build_fading_cfgs:UnknownScheme', '未知体制: %s', scheme);
end
end

function cfg = pack_discrete(scheme, channel_tag)
% 构造 B 阶段的 fading_cfgs 单行（discrete/hybrid/jakes）
switch upper(scheme)
    case {'SC-FDE','OFDM'}
        % 7 列（用快变 FFT 配置 128/96/32，与 test_*_discrete_doppler 默认一致）
        num_paths = 6;
        [type_s, dop_or_struct, fd_scatter] = build_disc_params(channel_tag, num_paths);
        if strcmpi(scheme,'SC-FDE')
            cp = 128;
        else
            cp = 96;  % OFDM
        end
        cfg = { channel_tag, type_s, dop_or_struct, 128, cp, 32, fd_scatter };

    case 'SC-TDE'
        num_paths = 6;
        [type_s, dop_or_struct, fd_scatter] = build_disc_params(channel_tag, num_paths);
        cfg = { channel_tag, type_s, dop_or_struct, fd_scatter };

    case {'DSSS','FH-MFSK'}
        num_paths = 5;
        [type_s, dop_or_struct, fd_scatter] = build_disc_params(channel_tag, num_paths);
        cfg = { channel_tag, type_s, dop_or_struct, fd_scatter };

    case 'OTFS'
        % OTFS 用 test_otfs_timevarying，3 列
        doppler_hz = [0, 3, -4, 5, -2];
        switch lower(channel_tag)
            case 'disc-5hz'
                cfg = { channel_tag, 'discrete', doppler_hz };
            case 'hyb-k20'
                cfg = { channel_tag, 'hybrid', ...
                        struct('doppler_hz', doppler_hz, 'fd_scatter', 0.5, 'K_rice', 20) };
            case 'hyb-k10'
                cfg = { channel_tag, 'hybrid', ...
                        struct('doppler_hz', doppler_hz, 'fd_scatter', 0.5, 'K_rice', 10) };
            case 'hyb-k5'
                cfg = { channel_tag, 'hybrid', ...
                        struct('doppler_hz', doppler_hz, 'fd_scatter', 1.0, 'K_rice', 5) };
            otherwise
                error('bench_build_fading_cfgs:UnknownChannelTag', ...
                      'OTFS 未知 channel_tag: %s', channel_tag);
        end
    otherwise
        error('bench_build_fading_cfgs:UnknownScheme', '未知体制: %s', scheme);
end
end

function [type_s, dop_or_struct, fd_scatter] = build_disc_params(channel_tag, num_paths)
% 按 num_paths 生成 per-path doppler 向量并按 channel_tag 选择类型
if num_paths == 6
    doppler_per_path = [0, 2, -3, 5, -1, 4];
elseif num_paths == 5
    doppler_per_path = [0, 3, -4, 5, -2];
else
    doppler_per_path = linspace(-5, 5, num_paths);
end
switch lower(channel_tag)
    case 'disc-5hz'
        type_s = 'discrete';
        dop_or_struct = doppler_per_path;
        fd_scatter = 5;
    case 'hyb-k20'
        type_s = 'hybrid';
        dop_or_struct = struct('doppler_hz', doppler_per_path, ...
                               'fd_scatter', 0.5, 'K_rice', 20);
        fd_scatter = 5;
    case 'hyb-k10'
        type_s = 'hybrid';
        dop_or_struct = struct('doppler_hz', doppler_per_path, ...
                               'fd_scatter', 0.5, 'K_rice', 10);
        fd_scatter = 5;
    case 'hyb-k5'
        type_s = 'hybrid';
        dop_or_struct = struct('doppler_hz', doppler_per_path, ...
                               'fd_scatter', 1.0, 'K_rice', 5);
        fd_scatter = 5;
    otherwise
        error('bench_build_fading_cfgs:UnknownChannelTag', ...
              '未知 channel_tag: %s', channel_tag);
end
end

function v = ternary(cond, a, b)
if cond, v = a; else, v = b; end
end
