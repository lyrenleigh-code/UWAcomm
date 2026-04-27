function ch_info = channel_simulator_frame(session, ch_params, sys, frame_idx)
%CHANNEL_SIMULATOR_FRAME Apply passband channel to one frame file.
%
% Reads:
%   <session>/raw_frames/NNNN.wav
% Writes:
%   <session>/channel_frames/NNNN.wav
%   <session>/channel_frames/NNNN.chinfo.mat

if nargin < 4 || isempty(frame_idx), frame_idx = 1; end

in_subdir  = fullfile(session, 'raw_frames');
out_subdir = fullfile(session, 'channel_frames');

[frame_pb, fs] = wav_read_frame(in_subdir, frame_idx);
assert(fs == sys.fs, 'channel_simulator_frame: fs mismatch (wav=%d, sys=%d)', fs, sys.fs);

ch_in = ch_params;
ch_in.fs = sys.fs;

[rx_pb, ch_info] = gen_uwa_channel_pb(frame_pb, ch_in, sys.fc);

wav_write_frame(rx_pb, out_subdir, frame_idx, sys);

chinfo_path = fullfile(out_subdir, sprintf('%04d.chinfo.mat', frame_idx));
save(chinfo_path, '-struct', 'ch_info', '-v7.3');

fprintf('[Channel] frame %04d: SNR=%gdB, delay_spread=%.1fms, fading=%s, fd=%gHz, mode=%s\n', ...
    frame_idx, ch_params.snr_db, max(ch_params.delays_s)*1000, ...
    ch_params.fading_type, getfield_def(ch_params, 'fading_fd_hz', 0), ch_info.mode);

end

% -------------------------------------------------------------------------
function v = getfield_def(s, fname, default)

if isfield(s, fname), v = s.(fname); else, v = default; end

end
