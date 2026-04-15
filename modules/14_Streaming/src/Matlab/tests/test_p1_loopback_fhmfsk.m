%% test_p1_loopback_fhmfsk.m — Streaming P1 闭环测试
% 文本 → raw.wav → 信道 → channel.wav → 文本 的最小闭环验证
% 体制：FH-MFSK；串行；单帧；方案 A passband 原生信道
%
% 按 CLAUDE.md MATLAB 测试调试流程运行：
%   clear functions; clear all;
%   cd 到本目录
%   diary('test_p1_loopback_fhmfsk_results.txt');
%   run('test_p1_loopback_fhmfsk.m');
%   diary off;

clc;
fprintf('========================================\n');
fprintf(' Streaming P1 — FH-MFSK loopback 闭环测试\n');
fprintf('========================================\n\n');

%% ========== 路径注册 ==========
this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));  % -> UWAcomm/

% 14_Streaming 子目录
streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(streaming_root, 'channel'));

% 复用旧模块
addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '09_Waveform', 'src', 'Matlab'));

%% ========== 参数 & 会话 ==========
sys = sys_params_default();
session_root = fullfile(proj_root, 'modules', '14_Streaming', 'sessions');
session = create_session_dir(session_root);
fprintf('Session: %s\n', session);
fprintf('fs=%d, fc=%d, FH-MFSK %d-FSK, %d跳频, samples_per_sym=%d\n\n', ...
    sys.fs, sys.fc, sys.fhmfsk.M, sys.fhmfsk.num_freqs, sys.fhmfsk.samples_per_sym);

text_in = 'Hello 水声通信测试帧 001';
fprintf('--- 输入文本 ---\n"%s" (%d 字符)\n\n', text_in, length(text_in));

%% ========== 单元预检（关键路径） ==========
fprintf('--- 单元预检 ---\n');

% 1. text ↔ bits 往返
t1_in  = 'Hello 水声 ABC 123';
t1_out = bits_to_text(text_to_bits(t1_in));
assert(strcmp(t1_in, t1_out), 'text_bits 往返失败');
fprintf('  [OK] text_to_bits / bits_to_text 往返\n');

% 2. crc16 标准向量 (CRC-16-CCITT of '123456789' = 0x29B1)
ref_bytes = uint8('123456789');
ref_bits = zeros(1, length(ref_bytes)*8);
for i = 1:length(ref_bytes)
    ref_bits((i-1)*8+1 : i*8) = bitget(ref_bytes(i), 8:-1:1);
end
crc_ref = crc16(ref_bits);
crc_val = sum(crc_ref .* 2.^(15:-1:0));
if crc_val == hex2dec('29B1')
    fprintf('  [OK] crc16 标准向量 "123456789" → 0x%04X\n', crc_val);
else
    warning('  [WARN] crc16 标准向量不匹配：got 0x%04X, expect 0x29B1', crc_val);
end

% 3. frame_header pack/unpack 往返
h_in = struct('scheme',6, 'idx',1, 'len',240, 'mod_level',1, ...
              'flags',1, 'src',0, 'dst',0);
hb = frame_header('pack', h_in, sys);
h_out = frame_header('unpack', hb, sys);
assert(h_out.crc_ok, 'header CRC check failed');
assert(h_out.magic_ok, 'header MAGIC check failed');
assert(h_out.scheme == 6 && h_out.idx == 1 && h_out.len == 240, 'header 字段错');
fprintf('  [OK] frame_header pack/unpack 往返, crc_ok=%d\n', h_out.crc_ok);

fprintf('\n');

%% ========== TX ==========
fprintf('=== TX ===\n');
tx_stream_p1(text_in, session, sys);

%% ========== Channel ==========
fprintf('\n=== Channel ===\n');

% 静态 5 径信道 + SNR=15dB
sym_delays_norm = [0, 1, 3, 5, 8];   % 符号级时延（同 sys_params.m 示例）
ch_params = struct();
ch_params.fs           = sys.fs;
ch_params.delays_s     = sym_delays_norm / sys.fhmfsk.freq_spacing;   % 秒（0, 2, 6, 10, 16 ms 等效）
% 注：以 freq_spacing 作为"符号率"单位不严谨（FH-MFSK 没有标准 sym_rate）
% P1 这里用明确的毫秒：
ch_params.delays_s     = [0, 0.167, 0.5, 0.833, 1.333] * 1e-3;
ch_params.gains        = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), ...
                          0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
ch_params.num_paths    = 5;
ch_params.doppler_rate = 0;
ch_params.fading_type  = 'static';
ch_params.fading_fd_hz = 0;
ch_params.snr_db       = 15;
ch_params.seed         = 42;

channel_simulator_p1(session, ch_params, sys);

%% ========== RX ==========
fprintf('\n=== RX ===\n');
[text_out, info] = rx_stream_p1(session, sys);

%% ========== 验收 ==========
fprintf('\n=== 验收结果 ===\n');
fprintf('输入: "%s"\n', text_in);
fprintf('输出: "%s"\n', text_out);

ok_text      = strcmp(text_in, text_out);
ok_hdr_crc   = info.hdr.crc_ok;
ok_hdr_magic = info.hdr.magic_ok;
ok_pl_crc    = info.payload_crc_ok;

fprintf('text 一致:    %d\n', ok_text);
fprintf('header CRC:   %d\n', ok_hdr_crc);
fprintf('header MAGIC: %d\n', ok_hdr_magic);
fprintf('payload CRC:  %d\n', ok_pl_crc);
fprintf('lfm_pos:      %d\n', info.lfm_pos);
fprintf('sync_peak:    %.3f\n', info.sync_peak);

if ok_text && ok_hdr_crc && ok_hdr_magic && ok_pl_crc
    fprintf('\n[PASS] P1 loopback 测试通过\n');
else
    fprintf('\n[FAIL] P1 loopback 测试失败\n');
end

% 硬断言（失败时抛错）
assert(ok_text, 'text 不一致');
assert(ok_hdr_crc, 'header CRC 失败');
assert(ok_pl_crc, 'payload CRC 失败');

%% ========== 可视化 ==========
try
    figure('Position', [100 100 1000 600]);

    % TX raw passband
    [raw_pb, fs_raw] = wav_read_frame(fullfile(session,'raw_frames'), 1);
    [chan_pb, ~]      = wav_read_frame(fullfile(session,'channel_frames'), 1);

    subplot(2,2,1);
    t_raw = (0:length(raw_pb)-1) / fs_raw * 1000;
    plot(t_raw, raw_pb, 'b', 'LineWidth', 0.3);
    xlabel('时间 (ms)'); ylabel('幅度'); grid on;
    title(sprintf('TX raw.wav (fc=%dHz, 全长%.1fms)', sys.fc, t_raw(end)));

    subplot(2,2,2);
    t_ch = (0:length(chan_pb)-1) / fs_raw * 1000;
    plot(t_ch, chan_pb, 'r', 'LineWidth', 0.3);
    xlabel('时间 (ms)'); ylabel('幅度'); grid on;
    title(sprintf('channel.wav (SNR=%ddB, 5径)', ch_params.snr_db));

    % 频谱
    subplot(2,2,3);
    Nfft = 2^nextpow2(length(raw_pb));
    F = fft(raw_pb, Nfft);
    f_ax = (0:Nfft-1) * fs_raw / Nfft / 1000;
    plot(f_ax(1:Nfft/2), 20*log10(abs(F(1:Nfft/2))+1e-10), 'b', 'LineWidth', 0.8);
    hold on;
    F2 = fft(chan_pb, Nfft);
    plot(f_ax(1:Nfft/2), 20*log10(abs(F2(1:Nfft/2))+1e-10), 'r', 'LineWidth', 0.8);
    xlabel('频率 (kHz)'); ylabel('|X| (dB)'); grid on;
    title('频谱'); legend('TX raw', 'channel', 'Location', 'best');
    xline(sys.fc/1000, 'k--'); xlim([0 fs_raw/2/1000]);

    % FH-MFSK 能量矩阵
    subplot(2,2,4);
    em = info.decode_info.energy_matrix;
    N_show = min(50, size(em, 1));
    imagesc(1:N_show, sys.fhmfsk.fb_base/1000, em(1:N_show,:).');
    axis xy; colorbar;
    xlabel('符号序号'); ylabel('基带频率 (kHz)');
    title(sprintf('RX 能量矩阵 (前 %d 符号)', N_show));

    sgtitle(sprintf('Streaming P1 — "%s"', text_in));
catch ME
    warning('可视化失败：%s', ME.message);
end

fprintf('\n结果 session: %s\n', session);
