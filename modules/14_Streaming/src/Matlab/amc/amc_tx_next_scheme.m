function [scheme, state] = amc_tx_next_scheme(current_scheme, ack, opts, state)
%AMC_TX_NEXT_SCHEME Apply ACK recommendation, or use fixed blind-mode rule.

if nargin < 2, ack = struct(); end
if nargin < 3 || ~isstruct(opts), opts = struct(); end
if nargin < 4 || ~isstruct(state), state = struct(); end
if nargin < 1 || isempty(current_scheme)
    current_scheme = getfield_def(opts, 'fixed_scheme', 'FH-MFSK');
end

blind_mode = getfield_def(opts, 'blind_mode', false);
if isstruct(ack) && isfield(ack, 'valid') && ack.valid && isfield(ack, 'recommend_scheme') && ...
        ~isempty(ack.recommend_scheme) && ~blind_mode
    scheme = ack.recommend_scheme;
    state.last_ack = ack;
    state.source = 'ack';
    state.current_profile = getfield_def(ack, 'recommend_profile', 'default');
    state.current_modem_params = getfield_def(ack, 'recommend_modem_params', struct());
    state.current_throughput_ratio = getfield_def(ack, 'recommend_throughput_ratio', 1.0);
else
    scheme = getfield_def(opts, 'fixed_scheme', current_scheme);
    state.source = 'blind_fixed';
    state.current_profile = getfield_def(opts, 'fixed_profile', 'default');
    state.current_modem_params = getfield_def(opts, 'fixed_modem_params', struct());
    state.current_throughput_ratio = getfield_def(opts, 'fixed_throughput_ratio', 1.0);
end

state.current_scheme = scheme;

end

% -------------------------------------------------------------------------
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
end

end
