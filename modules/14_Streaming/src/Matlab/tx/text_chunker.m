function chunks = text_chunker(text, max_bytes)
% 功能：UTF-8 文本按字节切分，保证不切断多字节字符
% 版本：V1.0.0
% 输入：
%   text       - UTF-8 字符串
%   max_bytes  - 单帧最大字节数（来自 sys.frame.payload_bits / 8）
% 输出：
%   chunks - cell 行向量，每个元素是字符串，UTF-8 字节数 ≤ max_bytes
%
% UTF-8 编码规则：
%   - 单字节字符高位 0xxxxxxx
%   - 多字节字符续字节高位 10xxxxxx
%   - 切分点必须落在字符首字节（高 2 位 != 10）
%
% 算法：
%   1. unicode2native('UTF-8') → byte 数组
%   2. 按 max_bytes 切，若切分点在续字节内则向前回退
%   3. 各段 native2unicode → 字符串

if nargin < 2 || isempty(max_bytes), max_bytes = 256; end
if isempty(text)
    chunks = {};
    return;
end

bytes = unicode2native(text, 'UTF-8');
N = length(bytes);
chunks = {};

start = 1;
while start <= N
    end_byte = min(start + max_bytes - 1, N);

    % 若不是末段，且 end_byte 后一字节是续字节（10xxxxxx），向前回退
    if end_byte < N
        % 检查 end_byte+1 是否为续字节
        % 续字节：bitand(byte, 0xC0) == 0x80
        while end_byte > start && bitand(uint8(bytes(end_byte+1)), uint8(192)) == uint8(128)
            end_byte = end_byte - 1;
        end
    end

    chunks{end+1} = native2unicode(bytes(start:end_byte), 'UTF-8'); %#ok<AGROW>
    start = end_byte + 1;
end

end
