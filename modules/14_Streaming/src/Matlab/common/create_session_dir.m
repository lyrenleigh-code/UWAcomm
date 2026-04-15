function session = create_session_dir(root)
% 功能：创建会话目录（方案 B：每帧独立 wav + .ready 标记）
% 版本：V1.0.0
% 输入：
%   root - 根目录（可选，默认 ./sessions）
% 输出：
%   session - 会话目录绝对路径（格式：<root>/session_yyyy-mm-dd-HHMMSS）
%
% 目录结构：
%   <root>/session_<ts>/
%     ├── raw_frames/       TX 产出
%     ├── channel_frames/   Channel daemon 产出
%     ├── rx_out/           RX 产出
%     └── session.log       会话日志

if nargin < 1 || isempty(root)
    root = fullfile(pwd, 'sessions');
end

if ~exist(root, 'dir')
    mkdir(root);
end

ts = datestr(now, 'yyyy-mm-dd-HHMMSS');
session = fullfile(root, ['session_' ts]);

if exist(session, 'dir')
    % 防冲突：追加毫秒
    ts2 = [ts '-' num2str(round(mod(now*86400*1000, 1000)))];
    session = fullfile(root, ['session_' ts2]);
end

mkdir(session);
mkdir(fullfile(session, 'raw_frames'));
mkdir(fullfile(session, 'channel_frames'));
mkdir(fullfile(session, 'rx_out'));

% 写 session.log 标头
log_path = fullfile(session, 'session.log');
fid = fopen(log_path, 'w');
fprintf(fid, '[%s] session created: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), session);
fclose(fid);

end
