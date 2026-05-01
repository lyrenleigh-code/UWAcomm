function [N_info, sys_out] = p4_apply_scheme_params(sch, sys, ui_vals)
% 功能：按体制 + UI 输入计算 N_info 并更新 sys 子结构（modem encode 前置）
% 版本：V3.0.0（2026-05-01 解耦 SC-FDE blk_cp/blk_fft + pilot_per_blk N_info 推导）
% 历史：
%   V1.0.0 (2026-04-22) - 抽自 p3_demo_ui.m on_transmit L810-855，6 体制 hardcode static
%   V2.0.0 (2026-04-28) - fading_type/fd_hz 透传 5 体制（FH-MFSK 除外）；SC-FDE 加
%                         pilot_per_blk/train_period_K 字段透传（默认 V1.0 行为）
%   V3.0.0 (2026-05-01) - 解 R3：blk_cp 不再强制 = blk_fft，可由 ui_vals.blk_cp 独立指定
%                         （缺省 fallback = blk_fft，向后兼容）；N_info 推导按 V4.0 公式
%                         (blk_fft - pilot_per_blk) * N_data_blocks - mem
%
% 用法：[N_info, sys_out] = p4_apply_scheme_params(sch, sys, ui_vals)
% 输入：
%   sch     体制名：'SC-FDE'|'OFDM'|'SC-TDE'|'DSSS'|'OTFS'|'FH-MFSK'
%   sys     系统参数（caller 侧 app.sys）
%   ui_vals struct，字段：
%           .blk_fft         blk_dd 解析后整数（SC-FDE/OFDM 用）
%           .blk_cp          (可选，SC-FDE V3.0 新增) cp 段长度，默认 = blk_fft（V2.0 兼容）
%           .turbo_iter      iter_edit 值（SC-FDE/OFDM/SC-TDE/OTFS 用）
%           .payload         pl_dd 解析后整数（FH-MFSK 用）
%           .fading_type     UI 衰落类型字符串（V2.0 新增，可选，默认 'static (恒定)'）
%                            'static (恒定)' / 'slow (Jakes 慢衰落)' / 'fast (Jakes 快衰落)'
%           .fd_hz           Jakes 多普勒扩展 Hz（V2.0 新增，可选，默认 0）
%           .pilot_per_blk   (可选，SC-FDE) 每数据块尾 pilot 段长度，默认 0（V1.0 行为兼容）
%           .train_period_K  (可选，SC-FDE) 训练块插入周期，默认 N_blocks-1（单训练块原行为）
% 输出：
%   N_info  信息比特数（供 text_to_bits 截断/填充）
%   sys_out 更新后的 sys（caller 写回 app.sys）
%
% 备注：
%   - V3.0 后：UI 推荐让 pilot_per_blk == blk_cp 才能激活 V4.0 干净 BEM 物理条件
%     (CP 段是 pilot 副本 → ~1178 干净 BEM obs/帧，jakes fd=1Hz BER 47%→3.37%，
%      runner 实测，spec archive `2026-04-26-scfde-time-varying-pilot-arch.md`)。
%   - blk_cp 不进 N_info 公式，仅影响 sym_per_block = blk_cp + blk_fft 信道时延裕度。
%   - SC-TDE V5.6 HFM signature toggle 仅 13_SourceCode runner 用，14_Streaming
%     modem_decode_sctde 不带 post-CFO 伪补偿，UI 路径无需透传。
%   - FH-MFSK schema 不含 fading_type 字段，信道层独立处理 fading，本函数不动其结构。

    sys_out = sys;
    mem = sys_out.codec.constraint_len - 1;

    %% ---- UI 衰落字段映射（V2.0 新增）----
    fading_ui = local_get_or_default(ui_vals, 'fading_type', 'static (恒定)');
    fd_hz_ui  = local_get_or_default(ui_vals, 'fd_hz', 0);
    fading_type_val = local_parse_fading(fading_ui);

    %% ---- 体制分发 ----
    if strcmp(sch, 'SC-FDE')
        sys_out.scfde.blk_fft     = ui_vals.blk_fft;
        % V3.0：blk_cp 解耦（缺省 fallback = blk_fft，向后兼容 V2.0）
        sys_out.scfde.blk_cp      = local_get_or_default(ui_vals, 'blk_cp', sys_out.scfde.blk_fft);
        sys_out.scfde.N_blocks    = 32;
        sys_out.scfde.turbo_iter  = ui_vals.turbo_iter;
        sys_out.scfde.fading_type = fading_type_val;
        sys_out.scfde.fd_hz       = fd_hz_ui;
        % V2.0：SC-FDE Phase 4+5 字段透传通道（默认值 = V1.0 行为，向后兼容）
        sys_out.scfde.pilot_per_blk  = local_get_or_default(ui_vals, 'pilot_per_blk',  0);
        sys_out.scfde.train_period_K = local_get_or_default(ui_vals, 'train_period_K', sys_out.scfde.N_blocks - 1);
        % V3.0 N_info 推导（参 modem_encode_scfde V4.0:35,49-60,81）
        N_info = local_scfde_n_info(sys_out.scfde, mem);

    elseif strcmp(sch, 'OFDM')
        sys_out.ofdm.blk_fft     = ui_vals.blk_fft;
        sys_out.ofdm.blk_cp      = round(sys_out.ofdm.blk_fft / 2);
        sys_out.ofdm.N_blocks    = 16;
        sys_out.ofdm.turbo_iter  = ui_vals.turbo_iter;
        sys_out.ofdm.fading_type = fading_type_val;
        sys_out.ofdm.fd_hz       = fd_hz_ui;
        null_idx_tmp = 1:sys_out.ofdm.null_spacing:sys_out.ofdm.blk_fft;
        N_data_sc = sys_out.ofdm.blk_fft - length(null_idx_tmp);
        N_info = N_data_sc * (sys_out.ofdm.N_blocks - 1) - mem;

    elseif strcmp(sch, 'SC-TDE')
        sys_out.sctde.turbo_iter  = ui_vals.turbo_iter;
        sys_out.sctde.fading_type = fading_type_val;
        sys_out.sctde.fd_hz       = fd_hz_ui;
        N_data_sym = 2000;
        N_info = N_data_sym - mem;

    elseif strcmp(sch, 'DSSS')
        sys_out.dsss.fading_type = fading_type_val;
        sys_out.dsss.fd_hz       = fd_hz_ui;
        N_info = 1200;  % ~150 字节(~50 汉字)

    elseif strcmp(sch, 'OTFS')
        sys_out.otfs.turbo_iter  = ui_vals.turbo_iter;
        sys_out.otfs.fading_type = fading_type_val;
        sys_out.otfs.fd_hz       = fd_hz_ui;
        pc_tmp = struct('mode', sys_out.otfs.pilot_mode, ...
            'guard_k', 4, 'guard_l', max(sys_out.otfs.sym_delays)+2, ...
            'pilot_value', 1);
        [~,~,~,di_tmp] = otfs_pilot_embed(zeros(1,1), ...
            sys_out.otfs.N, sys_out.otfs.M, pc_tmp);
        N_info = length(di_tmp) * 2 / 2 - mem;  % QPSK, R=1/2

    else  % FH-MFSK：信道层独立处理 fading，schema 不含 fading_type
        sys_out.frame.payload_bits = ui_vals.payload;
        sys_out.frame.body_bits    = sys_out.frame.header_bits + ui_vals.payload + ...
                                     sys_out.frame.payload_crc_bits;
        N_info = sys_out.frame.body_bits;
    end
end

% =====================================================================
% 内部辅助函数
% =====================================================================

function ftype = local_parse_fading(ui_str)
% 功能：UI 衰落类型字符串 → sys.{scheme}.fading_type 字段值
% 输入：ui_str  UI 字符串（如 'static (恒定)' / 'slow (Jakes 慢衰落)' / 'fast (Jakes 快衰落)'）
% 输出：ftype   'static' 或 'jakes'（fd_hz 字段单独承载快慢区分）
    if isempty(ui_str)
        ftype = 'static';
        return;
    end
    s = char(ui_str);
    if startsWith(s, 'static')
        ftype = 'static';
    else
        ftype = 'jakes';
    end
end

function v = local_get_or_default(s, fname, default_val)
% 功能：struct 字段安全读取（缺失或为空时返回 default_val）
    if isstruct(s) && isfield(s, fname) && ~isempty(s.(fname))
        v = s.(fname);
    else
        v = default_val;
    end
end

function N_info = local_scfde_n_info(scfde, mem)
% 功能：SC-FDE V4.0 N_info 推导（V3.0 新增）
% 参考：modem_encode_scfde.m L35,49-60,81
%   N_data_blocks 取决于 train_period_K：
%     K >= N_blocks-1 → 单训练块（N_data_blocks = N_blocks - 1）
%     K <  N_blocks-1 → linspace 分布训练块
%   N_info = (blk_fft - pilot_per_blk) * N_data_blocks - mem
    N = scfde.N_blocks;
    K = scfde.train_period_K;
    if K >= N - 1
        N_train_blocks = 1;
    else
        train_idx = round(linspace(1, N, floor(N / (K + 1)) + 1));
        N_train_blocks = length(unique(train_idx));
    end
    N_data_blocks  = N - N_train_blocks;
    N_data_per_blk = scfde.blk_fft - scfde.pilot_per_blk;
    N_info = N_data_per_blk * N_data_blocks - mem;
end
