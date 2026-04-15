function out = frame_header(op, input, sys)
% 功能：帧头（16 字节 / 128 比特）构造 / 解析
% 版本：V1.0.0
% 用法：
%   bits = frame_header('pack',   hdr_struct, sys)   → 128 bits
%   hdr  = frame_header('unpack', hdr_bits,   sys)   → struct + .crc_ok
%
% 帧头格式（MSB first，大端）：
%   Byte 0-1   MAGIC (2B)        = sys.frame.magic (0xA5C3)
%   Byte 2     SCH (1B)          体制编号
%   Byte 3     IDX (1B)          帧序号
%   Byte 4-5   LEN (2B)          payload 有效 bit 数
%   Byte 6     MOD (1B)          调制阶数
%   Byte 7     FLG (1B)          flags: bit0=last_frame, bit1=ack_req, bit2=is_ack
%   Byte 8-9   RSVD (2B)         保留
%   Byte 10-11 SRC_NODE (2B)     源节点 ID
%   Byte 12-13 DST_NODE (2B)     目的节点 ID
%   Byte 14-15 CRC16 (2B)        over Byte 0..13
%
% pack 输入 struct 字段：
%   .scheme, .idx, .len, .mod_level, .flags, .src, .dst
% unpack 输出 struct 字段：
%   上述全部 + .magic, .crc_ok

switch lower(op)
    case 'pack'
        out = pack_header(input, sys);
    case 'unpack'
        out = unpack_header(input, sys);
    otherwise
        error('frame_header: op 必须是 ''pack'' 或 ''unpack''');
end

end

% ================================================================
function bits = pack_header(h, sys)
bytes = zeros(1, 16, 'uint8');

% MAGIC (big-endian)
magic = uint16(sys.frame.magic);
bytes(1) = uint8(bitshift(magic, -8));
bytes(2) = uint8(bitand(magic, uint16(255)));

% 单字节字段
bytes(3) = uint8(h.scheme);
bytes(4) = uint8(h.idx);

% LEN (big-endian 2B)
len = uint16(h.len);
bytes(5) = uint8(bitshift(len, -8));
bytes(6) = uint8(bitand(len, uint16(255)));

bytes(7) = uint8(h.mod_level);
bytes(8) = uint8(h.flags);

% RSVD
bytes(9)  = 0;
bytes(10) = 0;

% SRC / DST (big-endian 2B each)
src = uint16(h.src);
bytes(11) = uint8(bitshift(src, -8));
bytes(12) = uint8(bitand(src, uint16(255)));

dst = uint16(h.dst);
bytes(13) = uint8(bitshift(dst, -8));
bytes(14) = uint8(bitand(dst, uint16(255)));

% 计算 CRC-16 over bytes(1:14)
body_bits = bytes_to_bits(bytes(1:14));
crc_bits = crc16(body_bits);
crc_bytes = bits_to_bytes(crc_bits);
bytes(15:16) = crc_bytes;

bits = bytes_to_bits(bytes);
end

% ================================================================
function h = unpack_header(bits, sys)
bits = bits(:).';
assert(length(bits) == 128, 'frame_header unpack: 需要 128 bits，实际 %d', length(bits));

bytes = bits_to_bytes(bits);

% MAGIC
h.magic = uint16(bitshift(uint16(bytes(1)), 8)) + uint16(bytes(2));

% 单字节字段
h.scheme    = double(bytes(3));
h.idx       = double(bytes(4));

% LEN
h.len = double(bitshift(uint16(bytes(5)), 8)) + double(bytes(6));

h.mod_level = double(bytes(7));
h.flags     = double(bytes(8));

% SRC / DST
h.src = double(bitshift(uint16(bytes(11)), 8)) + double(bytes(12));
h.dst = double(bitshift(uint16(bytes(13)), 8)) + double(bytes(14));

% CRC 校验
crc_recv = bytes_to_bits(bytes(15:16));
crc_calc = crc16(bits(1:112));   % 前 14 字节 = 112 bits
h.crc_ok = isequal(crc_recv(:).', crc_calc(:).');

% 校验 MAGIC（非致命，仅记录）
h.magic_ok = (h.magic == uint16(sys.frame.magic));
end

% ================================================================
function bits = bytes_to_bits(bytes)
% bytes: uint8 行向量 → bit 行向量（每字节 MSB first 展开）
N = length(bytes);
bits = zeros(1, N*8);
for i = 1:N
    bits((i-1)*8+1 : i*8) = double(bitget(uint8(bytes(i)), 8:-1:1));
end
end

% ================================================================
function bytes = bits_to_bytes(bits)
% bits: 长度为 8 的倍数的 bit 行向量 → uint8 行向量
bits = bits(:).';
assert(mod(length(bits), 8) == 0);
N = length(bits) / 8;
bytes = zeros(1, N, 'uint8');
for i = 1:N
    b8 = bits((i-1)*8+1 : i*8);
    bytes(i) = uint8(sum(b8 .* (2.^(7:-1:0))));
end
end
