function varargout = modem_dispatch(op, scheme, varargin)
% 功能：按 scheme 字段分发到具体 modem encode/decode 实现
% 版本：V1.0.0（P3.1）
% 输入：
%   op       - 'encode' | 'decode'
%   scheme   - 体制名，字符串（大小写、'-' 不敏感）
%              规范化后支持：'FHMFSK' 'SCFDE' 'OFDM' 'SCTDE' 'DSSS' 'OTFS'
%   varargin - 透传给底层 encode/decode 函数：
%              encode: (bits, sys)
%              decode: (body_bb, sys, meta)
% 输出：
%   encode: [body_bb, meta]
%   decode: [bits, info]
%
% 备注：
%   P3.1 实现 FH-MFSK + SC-FDE；其余体制报 "未实现"
%   后续 P3.2/P3.3 扩展，修改此 switch 即可

key = upper(strrep(scheme, '-', ''));

switch key
    case 'FHMFSK'
        switch lower(op)
            case 'encode'
                [varargout{1}, varargout{2}] = modem_encode_fhmfsk(varargin{:});
            case 'decode'
                [varargout{1}, varargout{2}] = modem_decode_fhmfsk(varargin{:});
            otherwise
                error('modem_dispatch: op 必须为 encode 或 decode，得到 %s', op);
        end

    case 'SCFDE'
        switch lower(op)
            case 'encode'
                [varargout{1}, varargout{2}] = modem_encode_scfde(varargin{:});
            case 'decode'
                [varargout{1}, varargout{2}] = modem_decode_scfde(varargin{:});
            otherwise
                error('modem_dispatch: op 必须为 encode 或 decode，得到 %s', op);
        end

    case 'OFDM'
        switch lower(op)
            case 'encode'
                [varargout{1}, varargout{2}] = modem_encode_ofdm(varargin{:});
            case 'decode'
                [varargout{1}, varargout{2}] = modem_decode_ofdm(varargin{:});
            otherwise
                error('modem_dispatch: op 必须为 encode 或 decode，得到 %s', op);
        end

    case 'SCTDE'
        switch lower(op)
            case 'encode'
                [varargout{1}, varargout{2}] = modem_encode_sctde(varargin{:});
            case 'decode'
                [varargout{1}, varargout{2}] = modem_decode_sctde(varargin{:});
            otherwise
                error('modem_dispatch: op 必须为 encode 或 decode，得到 %s', op);
        end

    case 'DSSS'
        switch lower(op)
            case 'encode'
                [varargout{1}, varargout{2}] = modem_encode_dsss(varargin{:});
            case 'decode'
                [varargout{1}, varargout{2}] = modem_decode_dsss(varargin{:});
            otherwise
                error('modem_dispatch: op 必须为 encode 或 decode，得到 %s', op);
        end

    case 'OTFS'
        switch lower(op)
            case 'encode'
                [varargout{1}, varargout{2}] = modem_encode_otfs(varargin{:});
            case 'decode'
                [varargout{1}, varargout{2}] = modem_decode_otfs(varargin{:});
            otherwise
                error('modem_dispatch: op 必须为 encode 或 decode，得到 %s', op);
        end

    otherwise
        error('modem_dispatch: 未知 scheme "%s"', scheme);
end

end
