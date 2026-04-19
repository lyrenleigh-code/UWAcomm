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

%% OFDM 子结构（P3.2 新增）
sys.ofdm.blk_fft      = 256;
sys.ofdm.blk_cp        = 128;
sys.ofdm.N_blocks      = 16;
sys.ofdm.null_spacing  = 32;
sys.ofdm.rolloff       = 0.35;
sys.ofdm.span          = 6;
sys.ofdm.turbo_iter    = 10;
sys.ofdm.fading_type   = 'static';
sys.ofdm.fd_hz         = 0;
sys.ofdm.sym_delays    = [0, 5, 15, 40, 60, 90];
sys.ofdm.gains_raw     = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
                           0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
sys.ofdm.total_bw      = sys.sym_rate * (1 + sys.ofdm.rolloff);

%% SC-TDE 子结构（P3.2 新增）
sys.sctde.train_len         = 500;
sys.sctde.pilot_cluster_len = 140;
sys.sctde.pilot_spacing     = 300;
sys.sctde.turbo_iter        = 10;
sys.sctde.rolloff            = 0.35;
sys.sctde.span               = 6;
sys.sctde.fading_type        = 'static';
sys.sctde.fd_hz              = 0;
sys.sctde.sym_delays         = [0, 5, 15, 40, 60, 90];
sys.sctde.gains_raw          = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
                                0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
sys.sctde.num_ff             = 31;
sys.sctde.num_fb             = 90;
sys.sctde.lambda             = 0.998;
sys.sctde.total_bw           = sys.sym_rate * (1 + sys.sctde.rolloff);

%% DSSS 子结构（P3.3 新增）
sys.dsss.code_poly     = [5, 0];            % Gold 码多项式对 (degree=5, shift=0) — Gold31
sys.dsss.code_len      = 31;               % 每符号码片数（扩频增益 ~15dB）
sys.dsss.sps           = 4;                % DSSS 专属 sps（chip_rate=fs/sps=12000, 数据率翻倍）
sys.dsss.train_len     = 50;               % 训练符号数
sys.dsss.rolloff       = 0.35;
sys.dsss.span          = 6;
sys.dsss.chip_delays   = [0, 1, 3, 5, 8];  % 多径时延（单位：码片）
sys.dsss.gains_raw     = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
                           0.3*exp(1j*1.5), 0.2*exp(1j*2.1)];
sys.dsss.fading_type   = 'static';
sys.dsss.fd_hz         = 0;
sys.dsss.chip_rate     = sys.fs / sys.dsss.sps;        % 12000 chips/s
sys.dsss.total_bw      = sys.dsss.chip_rate * (1 + 0.35);  % 16200 Hz

%% OTFS 子结构（P3.3 新增）
sys.otfs.N             = 32;                % 多普勒格点
sys.otfs.M             = 64;                % 时延格点
sys.otfs.cp_len        = 32;                % per-subblock CP
sys.otfs.turbo_iter    = 3;
sys.otfs.pilot_mode    = 'impulse';         % 'impulse' | 'sequence' | 'superimposed'
% impulse 高 SNR BER 最优（5~15dB 全 0%）；但时域波形有周期性脉冲（PAPR ~20dB）
% sequence (ZC) 降 PAPR 9dB 但 5dB BER 7.59%，波形形态也不同
% decoder 按 pilot_mode 自动分派 ch_est_otfs_{dd,zc,superimposed}
sys.otfs.fading_type   = 'static';
sys.otfs.fd_hz         = 0;
sys.otfs.sym_delays    = [0, 1, 3, 5, 8];  % DD 域时延（格点）
sys.otfs.gains_raw     = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
                           0.3*exp(1j*1.5), 0.2*exp(1j*2.1)];
sys.otfs.rolloff       = 0.35;              % RRC 滚降（14_Streaming 采样率桥接用）
sys.otfs.span          = 6;                 % RRC 跨度（符号）
sys.otfs.total_bw      = sys.sym_rate * (1 + sys.otfs.rolloff); % 含滚降带宽

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
