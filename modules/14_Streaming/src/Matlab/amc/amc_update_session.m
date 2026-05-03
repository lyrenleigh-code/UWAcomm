function [decision, state, q] = amc_update_session(session, frame_idx, sys, opts, state)
%AMC_UPDATE_SESSION Run AMC on one decoded P5 frame and persist outputs.

if nargin < 4 || ~isstruct(opts), opts = struct(); end
if nargin < 5 || ~isstruct(state), state = load_state(session); end

rx_meta_path = fullfile(session, 'rx_out', sprintf('%04d.meta.mat', frame_idx));
assert(exist(rx_meta_path, 'file') == 2, 'amc_update_session: missing %s', rx_meta_path);
rx_meta = load(rx_meta_path);
rx_info = rx_meta.info;
rx_info.frame_idx = frame_idx;

chinfo_path = fullfile(session, 'channel_frames', sprintf('%04d.chinfo.mat', frame_idx));
if exist(chinfo_path, 'file') == 2
    ch_info = load(chinfo_path);
else
    ch_info = struct();
end

[q, ~] = link_quality_est(rx_info, ch_info, sys, opts);
[decision, state] = mode_selector(q, state, sys, opts);

out = struct();
out.frame_idx = frame_idx;
out.link_quality = q;
out.decision = decision;
out.ack = decision.ack;
out.created_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');

json_path = fullfile(session, 'rx_out', sprintf('%04d.amc.json', frame_idx));
fid = fopen(json_path, 'w');
fprintf(fid, '%s\n', jsonencode(out));
fclose(fid);

hist_path = fullfile(session, 'amc_history.jsonl');
fid = fopen(hist_path, 'a');
fprintf(fid, '%s\n', jsonencode(out));
fclose(fid);

save(fullfile(session, 'amc_state.mat'), 'state');

end

% -------------------------------------------------------------------------
function state = load_state(session)

state_path = fullfile(session, 'amc_state.mat');
if exist(state_path, 'file') == 2
    s = load(state_path);
    if isfield(s, 'state')
        state = s.state;
        return;
    end
end
state = struct();

end
