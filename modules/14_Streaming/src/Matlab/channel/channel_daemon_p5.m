function processed = channel_daemon_p5(session, ch_params, sys, opts)
%CHANNEL_DAEMON_P5 Poll raw frame ready files and produce channel frames.

if nargin < 4 || ~isstruct(opts), opts = struct(); end

raw_dir = fullfile(session, 'raw_frames');
out_dir = fullfile(session, 'channel_frames');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

poll_sec = getfield_def(opts, 'poll_sec', 0.2);
max_idle_sec = getfield_def(opts, 'max_idle_sec', Inf);
max_frames = getfield_def(opts, 'max_frames', Inf);
once = getfield_def(opts, 'once', false);
stop_file = getfield_def(opts, 'stop_file', fullfile(session, 'stop.channel'));

processed = [];
failed_idx = [];
processed_count = 0;
idle_clock = tic;

write_pid(fullfile(session, 'channel.pid'), 'channel');
append_log(session, '[Channel-P5] daemon started');

while true
    if exist(stop_file, 'file')
        append_log(session, '[Channel-P5] stop file observed');
        break;
    end

    ready_idx = list_ready_indices(raw_dir);
    did_work = false;

    for k = 1:length(ready_idx)
        frame_idx = ready_idx(k);
        out_ready = fullfile(out_dir, sprintf('%04d.ready', frame_idx));
        if exist(out_ready, 'file') || any(failed_idx == frame_idx)
            continue;
        end

        did_work = true;
        try
            append_log(session, sprintf('[Channel-P5] frame %04d start', frame_idx));
            channel_simulator_frame(session, ch_params, sys, frame_idx);
            processed(end+1) = frame_idx; %#ok<AGROW>
            processed_count = processed_count + 1;
            append_log(session, sprintf('[Channel-P5] frame %04d done', frame_idx));
        catch ME
            failed_idx(end+1) = frame_idx; %#ok<AGROW>
            write_error(out_dir, frame_idx, ME);
            append_log(session, sprintf('[Channel-P5] frame %04d error: %s', ...
                frame_idx, ME.message));
        end

        if processed_count >= max_frames
            break;
        end
    end

    if processed_count >= max_frames
        break;
    end
    if once
        break;
    end

    if did_work
        idle_clock = tic;
    else
        if toc(idle_clock) >= max_idle_sec
            append_log(session, '[Channel-P5] idle timeout');
            break;
        end
        pause(poll_sec);
    end
end

append_log(session, sprintf('[Channel-P5] daemon stopped, processed=%d', ...
    length(processed)));

end

% -------------------------------------------------------------------------
function idx = list_ready_indices(dir_path)

files = dir(fullfile(dir_path, '*.ready'));
idx = [];
for k = 1:length(files)
    [~, name] = fileparts(files(k).name);
    value = str2double(name);
    if ~isnan(value)
        idx(end+1) = value; %#ok<AGROW>
    end
end
idx = sort(unique(idx));

end

% -------------------------------------------------------------------------
function write_pid(path, role)

pid = NaN;
try
    pid = feature('getpid');
catch
end
fid = fopen(path, 'w');
fprintf(fid, '%s pid=%g role=%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'), pid, role);
fclose(fid);

end

% -------------------------------------------------------------------------
function write_error(out_dir, frame_idx, ME)

err_path = fullfile(out_dir, sprintf('%04d.error.txt', frame_idx));
fid = fopen(err_path, 'w');
fprintf(fid, '%s\n%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'), ME.message);
try
    fprintf(fid, '\n%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
catch
end
fclose(fid);

end

% -------------------------------------------------------------------------
function append_log(session, msg)

fid = fopen(fullfile(session, 'session.log'), 'a');
if fid > 0
    fprintf(fid, '[%s] %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), msg);
    fclose(fid);
end

end

% -------------------------------------------------------------------------
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
end

end
