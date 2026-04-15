function text = bits_to_text(bits)
% 功能：比特流 → UTF-8 字符串（MSB first）
% 版本：V1.0.0
% 输入：
%   bits - 比特行向量 (0/1)，长度必须是 8 的倍数
% 输出：
%   text - UTF-8 字符串

if isempty(bits)
    text = '';
    return;
end

bits = bits(:).';   % 确保行向量
assert(mod(length(bits), 8) == 0, ...
    'bits_to_text: 比特长度 %d 不是 8 的倍数', length(bits));

N_bytes = length(bits) / 8;
bytes = zeros(1, N_bytes, 'uint8');
for i = 1:N_bytes
    b8 = bits((i-1)*8+1 : i*8);
    % MSB first: b(1)*128 + b(2)*64 + ... + b(8)*1
    bytes(i) = uint8(sum(b8 .* (2.^(7:-1:0))));
end

text = native2unicode(bytes, 'UTF-8');

end
