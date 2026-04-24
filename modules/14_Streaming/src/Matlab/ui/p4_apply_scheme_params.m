function [N_info, sys_out] = p4_apply_scheme_params(sch, sys, ui_vals)
% 功能：按体制 + UI 输入计算 N_info 并更新 sys 子结构（modem encode 前置）
% 版本：V1.0.0（2026-04-22 抽自 p3_demo_ui.m on_transmit L810-855）
% 用法：[N_info, sys_out] = p4_apply_scheme_params(sch, sys, ui_vals)
% 输入：
%   sch     体制名：'SC-FDE'|'OFDM'|'SC-TDE'|'DSSS'|'OTFS'|'FH-MFSK'
%   sys     系统参数（caller 侧 app.sys）
%   ui_vals struct，字段：
%           .blk_fft    blk_dd 解析后整数（SC-FDE/OFDM 用）
%           .turbo_iter iter_edit 值（SC-FDE/OFDM/SC-TDE/OTFS 用）
%           .payload    pl_dd 解析后整数（FH-MFSK 用）
% 输出：
%   N_info  信息比特数（供 text_to_bits 截断/填充）
%   sys_out 更新后的 sys（caller 写回 app.sys）

    sys_out = sys;
    mem = sys_out.codec.constraint_len - 1;

    if strcmp(sch, 'SC-FDE')
        sys_out.scfde.blk_fft     = ui_vals.blk_fft;
        sys_out.scfde.blk_cp      = sys_out.scfde.blk_fft;
        sys_out.scfde.N_blocks    = 32;
        sys_out.scfde.turbo_iter  = ui_vals.turbo_iter;
        sys_out.scfde.fading_type = 'static';
        sys_out.scfde.fd_hz       = 0;
        N_info = sys_out.scfde.blk_fft * (sys_out.scfde.N_blocks - 1) - mem;

    elseif strcmp(sch, 'OFDM')
        sys_out.ofdm.blk_fft     = ui_vals.blk_fft;
        sys_out.ofdm.blk_cp      = round(sys_out.ofdm.blk_fft / 2);
        sys_out.ofdm.N_blocks    = 16;
        sys_out.ofdm.turbo_iter  = ui_vals.turbo_iter;
        sys_out.ofdm.fading_type = 'static';
        sys_out.ofdm.fd_hz       = 0;
        null_idx_tmp = 1:sys_out.ofdm.null_spacing:sys_out.ofdm.blk_fft;
        N_data_sc = sys_out.ofdm.blk_fft - length(null_idx_tmp);
        N_info = N_data_sc * (sys_out.ofdm.N_blocks - 1) - mem;

    elseif strcmp(sch, 'SC-TDE')
        sys_out.sctde.turbo_iter  = ui_vals.turbo_iter;
        sys_out.sctde.fading_type = 'static';
        sys_out.sctde.fd_hz       = 0;
        N_data_sym = 2000;
        N_info = N_data_sym - mem;

    elseif strcmp(sch, 'DSSS')
        sys_out.dsss.fading_type = 'static';
        sys_out.dsss.fd_hz       = 0;
        N_info = 1200;  % ~150 字节(~50 汉字)

    elseif strcmp(sch, 'OTFS')
        sys_out.otfs.turbo_iter  = ui_vals.turbo_iter;
        sys_out.otfs.fading_type = 'static';
        sys_out.otfs.fd_hz       = 0;
        pc_tmp = struct('mode', sys_out.otfs.pilot_mode, ...
            'guard_k', 4, 'guard_l', max(sys_out.otfs.sym_delays)+2, ...
            'pilot_value', 1);
        [~,~,~,di_tmp] = otfs_pilot_embed(zeros(1,1), ...
            sys_out.otfs.N, sys_out.otfs.M, pc_tmp);
        N_info = length(di_tmp) * 2 / 2 - mem;  % QPSK, R=1/2

    else  % FH-MFSK
        sys_out.frame.payload_bits = ui_vals.payload;
        sys_out.frame.body_bits    = sys_out.frame.header_bits + ui_vals.payload + ...
                                     sys_out.frame.payload_crc_bits;
        N_info = sys_out.frame.body_bits;
    end
end
