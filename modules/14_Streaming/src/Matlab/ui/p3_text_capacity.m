function nb = p3_text_capacity(sch, sys)
% 功能：按体制返回最大文本字节数（TX 面板容量提示用）
% 版本：V1.0.0（2026-04-17，从 p3_demo_ui 抽出）
% 用法：nb = p3_text_capacity(sch, sys)
% 输入：
%   sch  体制名：'SC-FDE' | 'OFDM' | 'SC-TDE' | 'DSSS' | 'FH-MFSK' | 'OTFS'
%   sys  系统参数（需 sys.codec.constraint_len, sys.ofdm.null_spacing,
%                      sys.frame.body_bits）
% 输出：
%   nb   最大文本字节数（与 on_transmit 算出的 N_info/8 对齐）
% 备注：
%   原 on_scheme_changed 里的 switch 与 on_transmit 的 N_info 公式曾经不一致
%   （SC-FDE 少扣 "block 1=训练块"）。本函数作为单一事实源，与
%   p3_apply_scheme_params 的 N_info 计算必须一致（冒烟测试 assert）。

    mem = sys.codec.constraint_len - 1;
    switch sch
        case 'SC-FDE'
            blk_fft  = 128;
            N_blocks = 32;
            nb = floor((blk_fft * (N_blocks - 1) - mem) / 8);
        case 'OFDM'
            blk_fft   = 256;
            N_blocks  = 16;
            nulls     = length(1:sys.ofdm.null_spacing:blk_fft);
            N_data_sc = blk_fft - nulls;
            nb = floor((N_data_sc * (N_blocks - 1) - mem) / 8);
        case 'SC-TDE'
            N_data_sym = 2000;
            nb = floor((N_data_sym - mem) / 8);
        case 'DSSS'
            N_info = 1200;
            nb = floor(N_info / 8);
        case 'FH-MFSK'
            nb = floor(sys.frame.body_bits / 8);
        otherwise
            nb = 200;
    end
end
