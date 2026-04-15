function crc_bits = crc16(bits)
% 功能：CRC-16-CCITT（polynomial 0x1021, init 0xFFFF, no reflection, no xorout）
% 版本：V1.0.0
% 输入：
%   bits - 比特行向量 (0/1)，任意长度
% 输出：
%   crc_bits - 16 bit CRC（1×16 double, 0/1, MSB first）
%
% 标准测试向量（CRC-16-CCITT, init=0xFFFF）：
%   '123456789' (ASCII) → 0x29B1
%
% 备注：
%   - init = 0xFFFF（避免前导零被忽略）
%   - 多项式：x^16 + x^12 + x^5 + 1 = 0x11021（高位隐含）
%   - 按位 MSB first 处理

if isempty(bits)
    crc = uint32(hex2dec('FFFF'));
else
    bits = bits(:).';
    crc = uint32(hex2dec('FFFF'));
    for i = 1:length(bits)
        % 最高位与输入 bit 异或
        bit_in = uint32(bits(i));
        msb = bitand(bitshift(crc, -15), uint32(1));
        feedback = bitxor(msb, bit_in);
        crc = bitand(bitshift(crc, 1), uint32(hex2dec('FFFF')));
        if feedback == 1
            crc = bitxor(crc, uint32(hex2dec('1021')));
        end
    end
end

% 16 bit 转 bit array（MSB first）
crc_bits = double(bitget(crc, 16:-1:1));

end
