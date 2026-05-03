function ch_params = p5_channel_preset(preset, sys, opts)
%P5_CHANNEL_PRESET Channel presets for Streaming P5 daemons.

if nargin < 1 || isempty(preset), preset = 'static'; end
if nargin < 2 || isempty(sys), sys = sys_params_default(); end
if nargin < 3 || ~isstruct(opts), opts = struct(); end
if isstring(preset), preset = char(preset); end

base = struct();
base.fs = sys.fs;
base.delays_s = [0, 0.167, 0.5, 0.833, 1.333] * 1e-3;
base.gains = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), ...
    0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
base.num_paths = 5;
base.seed = getfield_def(opts, 'seed', 4242);

key = lower(strrep(strtrim(preset), '-', '_'));
switch key
    case 'static'
        base.doppler_rate = 0;
        base.fading_type = 'static';
        base.fading_fd_hz = 0;
        base.snr_db = getfield_def(opts, 'snr_db', 30);

    case {'low_doppler', 'lowdoppler'}
        base.doppler_rate = getfield_def(opts, 'doppler_rate', 2 / sys.fc);
        base.fading_type = 'slow';
        base.fading_fd_hz = getfield_def(opts, 'fading_fd_hz', 1);
        base.snr_db = getfield_def(opts, 'snr_db', 28);

    case {'high_doppler', 'highdoppler'}
        base.doppler_rate = getfield_def(opts, 'doppler_rate', 6 / sys.fc);
        base.fading_type = 'slow';
        base.fading_fd_hz = getfield_def(opts, 'fading_fd_hz', 3);
        base.snr_db = getfield_def(opts, 'snr_db', 30);

    otherwise
        error('p5_channel_preset: unknown preset "%s"', preset);
end

ch_params = base;

end

% -------------------------------------------------------------------------
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
end

end
