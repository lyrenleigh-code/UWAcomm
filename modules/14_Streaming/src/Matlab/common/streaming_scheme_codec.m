function out = streaming_scheme_codec(op, scheme, sys)
%STREAMING_SCHEME_CODEC Scheme id/name/capacity helper for Streaming P4.
%
% Usage:
%   names = streaming_scheme_codec('list', [], sys)
%   name  = streaming_scheme_codec('name', scheme, sys)
%   code  = streaming_scheme_codec('code', scheme, sys)
%   cap   = streaming_scheme_codec('payload_capacity_bits', scheme, sys)
%   nbits = streaming_scheme_codec('payload_info_bits', scheme, sys)

if nargin < 2
    scheme = [];
end
if nargin < 3
    sys = [];
end

switch lower(op)
    case 'list'
        out = {'FH-MFSK', 'SC-FDE', 'OFDM', 'SC-TDE', 'DSSS', 'OTFS'};

    case 'name'
        out = normalize_scheme_name(scheme, sys);

    case 'code'
        name = normalize_scheme_name(scheme, sys);
        out = scheme_code(name, sys);

    case 'payload_capacity_bits'
        name = normalize_scheme_name(scheme, sys);
        cap_info = scheme_info_capacity(name, sys);
        cap_payload = cap_info - sys.frame.payload_crc_bits;
        if cap_payload < 8
            error('streaming_scheme_codec: scheme %s payload capacity too small (%d bits)', ...
                name, cap_payload);
        end
        out = min(sys.frame.payload_bits, cap_payload);

    case 'payload_info_bits'
        out = streaming_scheme_codec('payload_capacity_bits', scheme, sys) + ...
            sys.frame.payload_crc_bits;

    otherwise
        error('streaming_scheme_codec: unknown op "%s"', op);
end

end

% -------------------------------------------------------------------------
function name = normalize_scheme_name(scheme, sys)

if isnumeric(scheme)
    code = double(scheme);
    if code == sys.frame.scheme_fhmfsk
        name = 'FH-MFSK';
    elseif code == sys.frame.scheme_scfde
        name = 'SC-FDE';
    elseif code == sys.frame.scheme_ofdm
        name = 'OFDM';
    elseif code == sys.frame.scheme_sctde
        name = 'SC-TDE';
    elseif code == sys.frame.scheme_dsss
        name = 'DSSS';
    elseif code == sys.frame.scheme_otfs
        name = 'OTFS';
    else
        error('streaming_scheme_codec: unsupported scheme code %g', code);
    end
    return;
end

if isstring(scheme)
    scheme = char(scheme);
end
key = upper(strrep(strrep(strrep(strtrim(scheme), '-', ''), '_', ''), ' ', ''));
switch key
    case 'FHMFSK'
        name = 'FH-MFSK';
    case 'SCFDE'
        name = 'SC-FDE';
    case 'OFDM'
        name = 'OFDM';
    case 'SCTDE'
        name = 'SC-TDE';
    case 'DSSS'
        name = 'DSSS';
    case 'OTFS'
        name = 'OTFS';
    otherwise
        error('streaming_scheme_codec: unsupported scheme "%s"', scheme);
end

end

% -------------------------------------------------------------------------
function code = scheme_code(name, sys)

switch name
    case 'FH-MFSK'
        code = sys.frame.scheme_fhmfsk;
    case 'SC-FDE'
        code = sys.frame.scheme_scfde;
    case 'OFDM'
        code = sys.frame.scheme_ofdm;
    case 'SC-TDE'
        code = sys.frame.scheme_sctde;
    case 'DSSS'
        code = sys.frame.scheme_dsss;
    case 'OTFS'
        code = sys.frame.scheme_otfs;
    otherwise
        error('streaming_scheme_codec: unsupported canonical name "%s"', name);
end

end

% -------------------------------------------------------------------------
function cap = scheme_info_capacity(name, sys)

codec = sys.codec;
mem = codec.constraint_len - 1;

switch name
    case 'FH-MFSK'
        cap = sys.frame.payload_bits + sys.frame.payload_crc_bits;

    case 'SC-FDE'
        cfg = sys.scfde;
        n_pilot_per_blk = getfield_def(cfg, 'pilot_per_blk', 0);
        n_data_per_blk = cfg.blk_fft - n_pilot_per_blk;
        if n_data_per_blk <= 0
            error('streaming_scheme_codec: SC-FDE pilot_per_blk must be < blk_fft');
        end
        n_data_blocks = scfde_data_block_count(cfg);
        cap = (2 * n_data_per_blk * n_data_blocks) / 2 - mem;

    case 'OFDM'
        cfg = sys.ofdm;
        null_idx = 1:cfg.null_spacing:cfg.blk_fft;
        data_idx = setdiff(1:cfg.blk_fft, null_idx);
        n_data_blocks = cfg.N_blocks - 1;
        cap = (2 * length(data_idx) * n_data_blocks) / 2 - mem;

    case 'SC-TDE'
        cfg = sys.sctde;
        n_data_sym = 2000;
        if strcmpi(cfg.fading_type, 'static')
            n_data_actual = n_data_sym;
        else
            n_clusters = floor(n_data_sym / (cfg.pilot_spacing + cfg.pilot_cluster_len));
            n_data_actual = n_data_sym - n_clusters * cfg.pilot_cluster_len;
        end
        cap = n_data_actual - mem;

    case 'DSSS'
        cap = sys.frame.payload_bits + sys.frame.payload_crc_bits;

    case 'OTFS'
        cfg = sys.otfs;
        pilot_config = struct('mode', cfg.pilot_mode, ...
            'guard_k', 4, 'guard_l', max(cfg.sym_delays) + 2, ...
            'pilot_value', 1);
        [~, ~, ~, data_indices] = otfs_pilot_embed(zeros(1,1), ...
            cfg.N, cfg.M, pilot_config);
        cap = length(data_indices) - mem;

    otherwise
        error('streaming_scheme_codec: unsupported scheme "%s"', name);
end

cap = floor(cap);

end

% -------------------------------------------------------------------------
function n_data_blocks = scfde_data_block_count(cfg)

n_blocks = cfg.N_blocks;
K_train = getfield_def(cfg, 'train_period_K', n_blocks - 1);
if K_train >= n_blocks - 1
    n_train_blocks = 1;
else
    train_block_indices = round(linspace(1, n_blocks, floor(n_blocks / (K_train + 1)) + 1));
    n_train_blocks = length(unique(train_block_indices));
end
n_data_blocks = n_blocks - n_train_blocks;

end

% -------------------------------------------------------------------------
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname) && ~isempty(s.(fname))
    v = s.(fname);
else
    v = default;
end

end
