function gate = streaming_alpha_gate(alpha_raw, alpha_conf, sys, opts)
%STREAMING_ALPHA_GATE Shared plausibility gate for P4 Doppler alpha estimates.

if nargin < 1 || isempty(alpha_raw), alpha_raw = 0; end
if nargin < 2 || isempty(alpha_conf), alpha_conf = 0; end
if nargin < 3 || ~isstruct(sys), sys = struct(); end
if nargin < 4 || ~isstruct(opts), opts = struct(); end

alpha_raw = alpha_raw(1);
alpha_conf = alpha_conf(1);

alpha_abs_max = getfield_def_local(opts, 'alpha_abs_max', 1e-2);
alpha_abs_min = getfield_def_local(opts, 'alpha_abs_min', 1e-6);
alpha_conf_min = getfield_def_local(opts, 'alpha_conf_min', 0.30);
fc = getfield_def_local(sys, 'fc', NaN);

gate = struct();
gate.alpha_raw = alpha_raw;
gate.confidence_raw = alpha_conf;
gate.alpha = 0;
gate.confidence = 0;
gate.accepted = false;
gate.reason = 'unknown';
gate.alpha_abs_max = alpha_abs_max;
gate.alpha_abs_min = alpha_abs_min;
gate.alpha_conf_min = alpha_conf_min;
gate.doppler_hz_raw = abs(alpha_raw) * fc;
gate.doppler_hz = 0;

if ~isfinite(alpha_raw) || ~isfinite(alpha_conf)
    gate.reason = 'nonfinite';
    return;
end

if abs(alpha_raw) <= alpha_abs_min
    gate.reason = 'below_min';
    gate.confidence = alpha_conf;
    return;
end

if alpha_conf < alpha_conf_min
    gate.reason = 'low_confidence';
    gate.confidence = alpha_conf;
    return;
end

if abs(alpha_raw) > alpha_abs_max
    gate.reason = 'outside_abs_max';
    gate.confidence = alpha_conf;
    return;
end

gate.alpha = alpha_raw;
gate.confidence = alpha_conf;
gate.accepted = true;
gate.reason = 'accepted';
gate.doppler_hz = gate.doppler_hz_raw;

end

function v = getfield_def_local(s, name, def)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = def;
end
end
