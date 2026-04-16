function sys = sys_params_default()
% 功能：14_Streaming 流式仿真默认系统参数（P1 FH-MFSK loopback）
% 版本：V1.0.0（P1）
% 输出：
%   sys - 系统参数结构体
%       .fs, .fc, .sym_rate, .sps             基本
%       .codec                                 编解码
%       .fhmfsk                                FH-MFSK 子结构（P1 起步体制）
%       .frame                                 帧协议（header + payload 长度）
%       .preamble                              前导码（HFM/LFM）
%       .wav                                   wav 文件格式
%
% 备注：
%   - P1 仅实现 FH-MFSK 路径；P3 扩展其他体制子结构
%   - sym_rate/sps 保留给 P3 其他体制使用，FH-MFSK 直接使用 samples_per_sym
%   - frame_body_bits = header_bits + payload_bits + payload_crc_bits = 128+512+16 = 656

%% 基本
sys.fs       = 48000;    % 采样率 (Hz)
sys.fc       = 12000;    % 载频 (Hz)
sys.sym_rate = 6000;     % 符号率 (FH-MFSK 不直接使用，其他体制用)
sys.sps      = 8;        % 每符号采样数

%% 编解码（所有体制共用）
sys.codec.gen_polys       = [7, 5];
sys.codec.constraint_len  = 3;
sys.codec.interleave_seed = 7;
sys.codec.decode_mode     = 'max-log';

%% FH-MFSK 子结构（P1 起步）
sys.fhmfsk.M               = 8;                    % 8-FSK
sys.fhmfsk.bits_per_sym    = 3;
sys.fhmfsk.num_freqs       = 16;                   % 跳频位数
sys.fhmfsk.freq_spacing    = 500;                  % 频率间隔 (Hz)
sys.fhmfsk.sym_duration    = 1 / sys.fhmfsk.freq_spacing;           % 2 ms
sys.fhmfsk.samples_per_sym = round(sys.fhmfsk.sym_duration * sys.fs); % 96
sys.fhmfsk.fb_base         = ((0:sys.fhmfsk.num_freqs-1) - sys.fhmfsk.num_freqs/2) ...
                              * sys.fhmfsk.freq_spacing;             % [-4000..3500]
sys.fhmfsk.total_bw        = sys.fhmfsk.num_freqs * sys.fhmfsk.freq_spacing;  % 8000 Hz
sys.fhmfsk.hop_seed        = 42;

%% SC-FDE 子结构（P3.1 新增）
sys.scfde.rolloff      = 0.35;
sys.scfde.span         = 6;
sys.scfde.blk_fft      = 128;         % 时变配置（fd=5Hz 参考）：128/128/32
sys.scfde.blk_cp       = 128;
sys.scfde.N_blocks     = 32;
% 信道先验（BEM 需要）
sys.scfde.sym_delays   = [0, 5, 15, 40, 60, 90];
sys.scfde.gains_raw    = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
                          0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
sys.scfde.fading_type  = 'static';    % 'static' | 'slow'
sys.scfde.fd_hz        = 0;
sys.scfde.turbo_iter   = 6;
sys.scfde.total_bw     = sys.sym_rate * (1 + sys.scfde.rolloff);   % 匹配 frame 前导带宽参考

%% 帧协议
sys.frame.magic             = uint16(hex2dec('A5C3'));
sys.frame.header_bytes      = 16;
sys.frame.header_bits       = 128;       % 16 * 8
sys.frame.payload_bits      = 2048;      % 固定 payload 长度（末帧补零），约 3 秒帧
sys.frame.payload_crc_bits  = 16;
sys.frame.body_bits         = sys.frame.header_bits + sys.frame.payload_bits + sys.frame.payload_crc_bits;  % 2192

% scheme 编号（与 master spec 一致）
sys.frame.scheme_ctrl    = 0;
sys.frame.scheme_scfde   = 1;
sys.frame.scheme_ofdm    = 2;
sys.frame.scheme_sctde   = 3;
sys.frame.scheme_dsss    = 4;
sys.frame.scheme_otfs    = 5;
sys.frame.scheme_fhmfsk  = 6;

%% 前导码
sys.preamble.dur        = 0.05;                                        % HFM/LFM 时长 (s)
% guard_samp 基于 P1 默认信道最大时延：5 径，最大 delay ~ 1.33 ms
sys.preamble.guard_samp = round(0.002 * sys.fs) + 80;                  % 约 2 ms + 余量
sys.preamble.bw_lfm     = sys.fhmfsk.total_bw;                         % 前导带宽 = 数据带宽

%% wav 文件格式
sys.wav.bit_depth = 16;
sys.wav.channels  = 1;
sys.wav.scale     = 0.95;   % int16 归一化上限（防 clipping）

end
