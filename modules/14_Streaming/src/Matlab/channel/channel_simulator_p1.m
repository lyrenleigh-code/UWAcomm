function ch_info = channel_simulator_p1(session, ch_params, sys)
% 功能：信道模拟（P1 单帧，方案 A passband 原生）
% 版本：V1.1.0（加时变 h_time 存 chinfo.mat）
% 输入：
%   session   - 会话目录
%   ch_params - 信道参数（传给 gen_uwa_channel_pb）
%                必需字段：fs, delays_s, gains, doppler_rate, fading_type,
%                          fading_fd_hz, snr_db, seed
%   sys       - 系统参数（用 sys.fc）
% 输出：
%   ch_info   - gen_uwa_channel_pb 返回的信道信息结构（含 h_time 时变抽头矩阵）
% 产出：
%   <session>/channel_frames/0001.wav   + .ready + .scale.mat
%   <session>/channel_frames/0001.chinfo.mat   信道信息（含时变 h_time）

frame_idx = 1;
in_subdir  = fullfile(session, 'raw_frames');
out_subdir = fullfile(session, 'channel_frames');

% 读 raw_frames/0001.wav
[frame_pb, fs] = wav_read_frame(in_subdir, frame_idx);
assert(fs == sys.fs, 'channel_simulator_p1: fs 不匹配 (wav=%d, sys=%d)', fs, sys.fs);

ch_in = ch_params;
ch_in.fs = sys.fs;

% passband 原生信道：pb → pb，一次完成多径 + 多普勒 + 时变衰落 + AWGN
[rx_pb, ch_info] = gen_uwa_channel_pb(frame_pb, ch_in, sys.fc);

% 写 channel_frames/0001.wav
wav_write_frame(rx_pb, out_subdir, frame_idx, sys);

% 保存 ch_info（用于可视化读取 h_time）
chinfo_path = fullfile(out_subdir, sprintf('%04d.chinfo.mat', frame_idx));
save(chinfo_path, '-struct', 'ch_info', '-v7.3');

fprintf('[Channel] frame %04d: SNR=%gdB, delay_spread=%.1fms, fading=%s, fd=%gHz, mode=%s\n', ...
    frame_idx, ch_params.snr_db, max(ch_params.delays_s)*1000, ...
    ch_params.fading_type, ...
    getfield_def(ch_params, 'fading_fd_hz', 0), ch_info.mode);

end

function v = getfield_def(s, fname, default)
if isfield(s, fname), v = s.(fname); else, v = default; end
end
