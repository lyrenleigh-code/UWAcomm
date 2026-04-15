function wav_write_frame(frame_pb, session_subdir, frame_idx, sys)
% 功能：写一帧 passband 信号到 session_subdir/NNNN.wav，close 后原子创建 .ready 标记
% 版本：V1.0.0
% 输入：
%   frame_pb       - passband 实信号 (1×N double)
%   session_subdir - 例如 fullfile(session, 'raw_frames')
%   frame_idx      - 帧序号 (>=1)，用于文件名 NNNN（4 位零填充）
%   sys            - 系统参数（使用 sys.fs, sys.wav.scale, sys.wav.bit_depth）
%
% 产出：
%   <session_subdir>/NNNN.wav          int16 归一化 wav
%   <session_subdir>/NNNN.scale.mat    归一化因子（RX 反归一化用）
%   <session_subdir>/NNNN.ready        空标记文件（写完 close 后创建）
%
% 备注：
%   - int16 归一化到 [-sys.wav.scale, sys.wav.scale] 防 clipping
%   - audiowrite 自动处理 int16 转换
%   - .ready 用 fopen+fclose 原子创建（OS 保证对下游可见）

frame_pb = frame_pb(:).';  % 行向量

wav_name   = sprintf('%04d.wav', frame_idx);
ready_name = sprintf('%04d.ready', frame_idx);
scale_name = sprintf('%04d.scale.mat', frame_idx);

wav_path   = fullfile(session_subdir, wav_name);
ready_path = fullfile(session_subdir, ready_name);
scale_path = fullfile(session_subdir, scale_name);

% 归一化
max_abs = max(abs(frame_pb));
if max_abs > 0
    scale_factor = sys.wav.scale / max_abs;
else
    scale_factor = 1;
    warning('wav_write_frame: frame %04d 全零？max_abs=0', frame_idx);
end
normalized = frame_pb * scale_factor;

% 写 wav（audiowrite 自动 float → int16）
audiowrite(wav_path, normalized, sys.fs, 'BitsPerSample', sys.wav.bit_depth);

% 保存归一化因子（供 RX 反归一化）
meta_scale = struct('scale_factor', scale_factor, 'frame_idx', frame_idx, 'max_abs', max_abs);
save(scale_path, '-struct', 'meta_scale');

% 原子创建 .ready（fopen+fclose 完成后对下游可见）
fid = fopen(ready_path, 'w');
fprintf(fid, '%s frame=%04d N=%d max_abs=%.6e\n', ...
    datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'), frame_idx, length(frame_pb), max_abs);
fclose(fid);

end
