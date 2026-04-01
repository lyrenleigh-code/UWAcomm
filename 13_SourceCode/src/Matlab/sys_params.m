function params = sys_params(scheme, snr_db)
% 功能：统一系统参数配置——6种通信体制一键切换
% 版本：V1.0.0
% 输入：
%   scheme - 通信体制字符串：
%            'SC-TDE' / 'SC-FDE' / 'DSSS' / 'OFDM' / 'OTFS' / 'FH-MFSK'
%   snr_db - 信噪比 (dB，默认 10)
% 输出：
%   params - 系统参数结构体，包含以下子结构：
%       .scheme       : 体制名称
%       .snr_db       : 信噪比
%       .fs           : 采样率 (Hz)
%       .fc           : 载波频率 (Hz)
%       .N_info       : 信息比特数
%       .mod          : 调制参数 (.type, .M)
%       .codec        : 编解码参数 (.gen_polys, .constraint_len, .interleave_seed, .decode_mode)
%       .channel      : 信道参数 (传给gen_uwa_channel)
%       .tx           : 发射参数 (体制相关)
%       .rx           : 接收参数 (体制相关)

%% ========== 默认值 ========== %%
if nargin < 2 || isempty(snr_db), snr_db = 10; end
if nargin < 1 || isempty(scheme), scheme = 'SC-FDE'; end

%% ========== 公共参数 ========== %%
params.scheme = upper(scheme);
params.snr_db = snr_db;
params.sym_rate = 6000;    % 符号率 6kBaud
params.sps = 8;            % 每符号采样数
params.fs = params.sym_rate * params.sps;  % 基带采样率 48kHz
params.fc = 12000;         % 载波频率 12kHz
params.fs_passband = params.fs;  % 通带采样率（需 ≥ 2*(fc+B/2)）
% 通带条件检查：fs_pb ≥ 2*(fc + sym_rate*(1+rolloff)/2)
params.waveform.sps = params.sps;
params.waveform.filter_type = 'rrc';
params.waveform.rolloff = 0.35;
params.waveform.span = 6;

% 编解码（所有体制共用）
params.codec.gen_polys = [7, 5];
params.codec.constraint_len = 3;
params.codec.interleave_seed = 7;
params.codec.decode_mode = 'max-log';

% 调制（默认QPSK）
params.mod.type = 'qpsk';
params.mod.M = 4;
params.mod.bits_per_sym = 2;

% 信道（默认：静态多径+AWGN，时延为整数符号周期×sps——确保下采样后整数符号时延）
params.channel.fs = params.fs_passband;
params.channel.delay_profile = 'custom';
sym_delays = [0, 1, 3, 5, 8];                          % 时延（符号数）
params.channel.delays_s = sym_delays / params.sym_rate;  % 转为秒
params.channel.gains = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
params.channel.num_paths = 5;
params.channel.sym_delays = sym_delays;                  % 保存符号级时延供均衡器用
params.channel.doppler_rate = 0;       % 无多普勒（先验证链路）
params.channel.fading_type = 'static'; % 静态信道（先验证链路）
params.channel.fading_fd_hz = 0;
params.channel.snr_db = snr_db;
params.channel.seed = 42;

%% ========== 体制特有参数 ========== %%
switch upper(scheme)
    case 'SC-TDE'
        params.N_info = 4000;
        params.tx.train_len = 200;
        params.tx.use_cp = false;
        params.rx.eq_type = 'rls';
        params.rx.eq_params = struct('num_ff',21, 'num_fb',10, 'lambda',0.998, ...
            'pll', struct('enable',true,'Kp',0.01,'Ki',0.005));
        params.rx.turbo_iter = 6;
        % 使用公共静态信道

    case 'SC-FDE'
        params.tx.N_fft = 2048;
        params.tx.cp_len = 64;
        params.tx.use_cp = true;
        N_sym = params.tx.N_fft;
        M_coded = 2 * N_sym;
        params.N_info = M_coded / 2 - (params.codec.constraint_len - 1);
        params.rx.eq_type = 'mmse-ic';
        params.rx.turbo_iter = 6;

    case 'OFDM'
        params.tx.N_fft = 2048;
        params.tx.cp_len = 64;
        params.tx.use_cp = true;
        % 端到端仿真中用全块处理（同SC-FDE），避免子载波映射引入FFT/IFFT不匹配
        N_sym = params.tx.N_fft;
        M_coded = 2 * N_sym;
        params.N_info = M_coded / 2 - (params.codec.constraint_len - 1);
        params.rx.eq_type = 'mmse-ic';
        params.rx.turbo_iter = 6;

    case 'DSSS'
        params.N_info = 2000;
        params.tx.spread_code = 'gold';
        params.tx.spread_len = 31;
        params.tx.use_cp = false;
        params.rx.eq_type = 'rake';
        params.rx.turbo_iter = 0;        % DSSS无Turbo迭代
        params.mod.type = 'bpsk';
        params.mod.M = 2;
        params.mod.bits_per_sym = 1;

    case 'OTFS'
        params.tx.N_doppler = 16;        % 多普勒格点
        params.tx.M_delay = 64;          % 时延格点（MP复杂度O(P·NM)，大格点收敛慢）
        params.tx.use_cp = true;
        params.tx.cp_len = 32;
        N_dd = params.tx.N_doppler * params.tx.M_delay;
        M_coded = 2 * N_dd;
        params.N_info = M_coded / 2 - (params.codec.constraint_len - 1);
        params.rx.eq_type = 'mp';
        params.rx.mp_iters = 20;
        params.rx.turbo_iter = 6;
        % OTFS不加RRC脉冲成形（ISFFT自然带限），使用公共SNR

    case 'FH-MFSK'
        params.N_info = 1000;
        params.tx.M_fsk = 8;             % 8-FSK
        params.tx.num_hops = 50;
        params.tx.hop_bw = 500;          % 每跳带宽 (Hz)
        params.tx.use_cp = false;
        params.rx.eq_type = 'energy';
        params.rx.turbo_iter = 0;
        params.mod.type = 'mfsk';
        params.mod.M = 8;
        params.mod.bits_per_sym = 3;

    otherwise
        error('不支持的通信体制: %s\n支持: SC-TDE/SC-FDE/DSSS/OFDM/OTFS/FH-MFSK', scheme);
end

end
