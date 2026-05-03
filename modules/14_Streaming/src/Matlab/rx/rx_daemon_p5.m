function processed = rx_daemon_p5(session, sys, opts)
%RX_DAEMON_P5 Poll channel frame ready files and decode completed frames.

if nargin < 3 || ~isstruct(opts), opts = struct(); end

chan_dir = fullfile(session, 'channel_frames');
rx_out_dir = fullfile(session, 'rx_out');
if ~exist(rx_out_dir, 'dir'), mkdir(rx_out_dir); end

poll_sec = getfield_def(opts, 'poll_sec', 0.2);
max_idle_sec = getfield_def(opts, 'max_idle_sec', Inf);
max_frames = getfield_def(opts, 'max_frames', Inf);
once = getfield_def(opts, 'once', false);
stop_file = getfield_def(opts, 'stop_file', fullfile(session, 'stop.rx'));
rx_opts = getfield_def(opts, 'rx_opts', struct());
if ~isstruct(rx_opts), rx_opts = struct(); end
enable_amc = getfield_def(opts, 'enable_amc', false);
amc_opts = getfield_def(opts, 'amc_opts', struct());
if ~isstruct(amc_opts), amc_opts = struct(); end
amc_state = getfield_def(opts, 'amc_state', struct());
if ~isstruct(amc_state), amc_state = struct(); end

processed = [];
failed_idx = [];
processed_count = 0;
idle_clock = tic;

write_pid(fullfile(session, 'rx.pid'), 'rx');
append_log(session, '[RX-P5] daemon started');

while true
    if exist(stop_file, 'file')
        append_log(session, '[RX-P5] stop file observed');
        break;
    end

    ready_idx = list_ready_indices(chan_dir);
    did_work = false;

    for k = 1:length(ready_idx)
        frame_idx = ready_idx(k);
        out_ready = fullfile(rx_out_dir, sprintf('%04d.ready', frame_idx));
        if exist(out_ready, 'file') || any(failed_idx == frame_idx)
            continue;
        end

        did_work = true;
        local_opts = rx_opts;
        local_opts.frame_idx = frame_idx;
        try
            append_log(session, sprintf('[RX-P5] frame %04d start', frame_idx));
            rx_stream_p4(session, sys, local_opts);
            if enable_amc
                [amc_decision, amc_state] = amc_update_session(session, frame_idx, sys, ...
                    amc_opts, amc_state); %#ok<ASGLU>
                append_log(session, sprintf('[RX-P5] frame %04d AMC -> %s', ...
                    frame_idx, amc_decision.selected_scheme));
            end
            processed(end+1) = frame_idx; %#ok<AGROW>
            processed_count = processed_count + 1;
            append_log(session, sprintf('[RX-P5] frame %04d done', frame_idx));
        catch ME
            failed_idx(end+1) = frame_idx; %#ok<AGROW>
            write_error(rx_out_dir, frame_idx, ME);
            append_log(session, sprintf('[RX-P5] frame %04d error: %s', ...
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
            append_log(session, '[RX-P5] idle timeout');
            break;
        end
        pause(poll_sec);
    end
end

append_log(session, sprintf('[RX-P5] daemon stopped, processed=%d', ...
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
