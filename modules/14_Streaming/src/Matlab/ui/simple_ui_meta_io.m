function out = simple_ui_meta_io(op, arg)
% 功能：tx_simple_ui 写 / rx_simple_ui 读 wav 同名 JSON meta 编解码
% 版本：V1.0.0（2026-05-04）
% 用法：
%   json_str = simple_ui_meta_io('encode', meta_struct)   % struct → JSON 字符串
%   meta     = simple_ui_meta_io('decode', json_str)      % JSON 字符串 → struct
%
% Meta schema v1.0：
%   .version         字符串 '1.0'
%   .scheme          'SC-FDE' | 'OFDM' | 'SC-TDE' | 'OTFS' | 'DSSS' | 'FH-MFSK'
%   .created_at      'yyyymmdd_HHMMSS'
%   .sys             子结构（fs/fc/sps/sym_rate + scheme 子结构 .scfde/.ofdm/...）
%   .frame           子结构（N_info / body_offset / frame_pb_samples / scale_factor）
%   .known_bits_b64  字符串（base64 编码 known info bits，可选；空则 RX BER 不计）
%
% 备注：
%   - JSON 不支持 complex/cell；本函数只编码 sys 中数值型 + scheme 子结构（dropped: gains_raw 复数）
%   - known_bits 用 base64 紧凑编码（vs 直接数组列表，文件小一半）
%   - 不存 noise_var / fading_type 等 channel-side 字段（RX 侧自行选）

if nargin < 1, error('simple_ui_meta_io: op required'); end

switch lower(op)
    case 'encode'
        out = local_encode(arg);
    case 'decode'
        out = local_decode(arg);
    otherwise
        error('simple_ui_meta_io: unknown op "%s"', op);
end
end

%% =========================================================================
function json_str = local_encode(meta)
% meta struct → JSON string

% 必填字段验证
required = {'scheme', 'sys', 'frame'};
for k = 1:length(required)
    if ~isfield(meta, required{k})
        error('simple_ui_meta_io.encode: missing field "%s"', required{k});
    end
end

% 默认填充
out = struct();
out.version    = '1.0';
out.scheme     = char(meta.scheme);
out.created_at = local_get_or_default(meta, 'created_at', datestr(now, 'yyyymmdd_HHMMSS'));
out.sys        = local_strip_complex(meta.sys);
out.frame      = meta.frame;

% known_bits（可选，base64 编码）
if isfield(meta, 'known_bits') && ~isempty(meta.known_bits)
    bits_uint8 = uint8(meta.known_bits(:));
    out.known_bits_b64 = matlab.net.base64encode(bits_uint8);
    out.frame.N_info_bits = length(meta.known_bits);
else
    out.known_bits_b64 = '';
end

% encode_meta（modem_encode 输出的帧结构白名单字段，CLAUDE.md §2 合规）
if isfield(meta, 'encode_meta') && isstruct(meta.encode_meta)
    out.encode_meta = local_strip_complex(meta.encode_meta);
end

json_str = jsonencode(out, 'PrettyPrint', true);
end

%% =========================================================================
function meta = local_decode(json_str)
raw = jsondecode(json_str);

if ~isfield(raw, 'version')
    error('simple_ui_meta_io.decode: missing version field');
end
if ~strcmp(raw.version, '1.0')
    warning('simple_ui_meta_io: unknown meta version %s', raw.version);
end

meta = struct();
meta.version    = raw.version;
meta.scheme     = raw.scheme;
meta.created_at = raw.created_at;
meta.sys        = raw.sys;
meta.frame      = raw.frame;

if isfield(raw, 'known_bits_b64') && ~isempty(raw.known_bits_b64)
    bits_uint8 = matlab.net.base64decode(raw.known_bits_b64);
    meta.known_bits = double(bits_uint8(:)).';
    if isfield(raw.frame, 'N_info_bits')
        meta.known_bits = meta.known_bits(1:raw.frame.N_info_bits);
    end
else
    meta.known_bits = [];
end

if isfield(raw, 'encode_meta')
    meta.encode_meta = raw.encode_meta;
end
end

%% =========================================================================
function s_clean = local_strip_complex(s)
% 递归剥离 struct 中的复数字段（jsonencode 会把复数变奇怪格式）
% gains_raw 是复数数组 → 拆 real/imag 两段
if ~isstruct(s)
    s_clean = s;
    return;
end
fns = fieldnames(s);
s_clean = struct();
for k = 1:length(fns)
    fn = fns{k};
    val = s.(fn);
    if isstruct(val)
        if numel(val) > 1
            % struct array — 逐个递归
            s_clean.(fn) = arrayfun(@local_strip_complex, val);
        else
            s_clean.(fn) = local_strip_complex(val);
        end
    elseif isnumeric(val) && ~isreal(val)
        % 复数 → 拆 real/imag
        s_clean.(fn) = struct('re', real(val(:).'), 'im', imag(val(:).'));
    else
        s_clean.(fn) = val;
    end
end
end

%% =========================================================================
function v = local_get_or_default(s, name, def)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = def;
end
end
