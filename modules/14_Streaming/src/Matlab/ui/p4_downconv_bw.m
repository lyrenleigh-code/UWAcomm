function bw = p4_downconv_bw(sch, sys)
% 功能：按体制返回接收端下变频带宽（Hz）
% 版本：V1.0.0（2026-04-17，从 p3_demo_ui 抽出）
% 用法：bw = p4_downconv_bw(sch, sys)
% 输入：
%   sch  体制名
%   sys  系统参数
% 输出：
%   bw   接收端带通带宽 (Hz)，用于 downconvert 前的 LPF 截止频率估算、
%        频谱图带宽标记、信道频响绘图范围等。

    switch sch
        case 'SC-FDE'
            bw = sys.sym_rate * (1 + sys.scfde.rolloff);
        case 'OFDM'
            bw = sys.sym_rate * (1 + sys.ofdm.rolloff);
        case 'SC-TDE'
            bw = sys.sym_rate * (1 + sys.sctde.rolloff);
        case 'DSSS'
            bw = sys.dsss.total_bw;
        case 'OTFS'
            bw = sys.otfs.total_bw;
        otherwise  % FH-MFSK 及未知
            bw = sys.fhmfsk.total_bw;
    end
end
