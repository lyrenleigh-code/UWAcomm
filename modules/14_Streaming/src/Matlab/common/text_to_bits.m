function bits = text_to_bits(text)
% 功能：UTF-8 字符串 → 比特流（MSB first）
% 版本：V1.0.0
% 输入：
%   text - 字符串（支持 UTF-8，含中英文混合）
% 输出：
%   bits - 比特行向量 (1×N double, 0/1)，长度为字节数×8

if isempty(text)
    bits = [];
    return;
end

% UTF-8 编码为 byte array
bytes = unicode2native(text, 'UTF-8');

% 每字节展开为 8 bit（MSB first）
N = length(bytes);
bits = zeros(1, N*8);
for i = 1:N
    b = uint8(bytes(i));
    bits((i-1)*8+1 : i*8) = double(bitget(b, 8:-1:1));
end

end
