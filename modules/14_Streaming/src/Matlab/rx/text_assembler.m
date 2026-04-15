function text = text_assembler(decoded_chunks)
% 功能：按 frame_idx 排序 + 拼接，缺帧或 CRC 失败插入占位
% 版本：V1.0.0（P2）
% 输入：
%   decoded_chunks - cell 数组，每元素 struct：
%       .idx   帧序号 (>=1)
%       .text  该帧解出的文本
%       .ok    CRC 是否通过
%       .last  (可选) 是否末帧标志
% 输出：
%   text - 拼接后的完整 UTF-8 字符串
%
% 行为：
%   - 按 idx 升序拼接 ok=true 的 text
%   - ok=false 帧用 `[missing frame N]` 占位
%   - 检测 idx 跳号（缺帧）也用占位填补
%
% 例：
%   decoded = {{idx=2, text='', ok=false}, {idx=1, text='Hello', ok=true}, {idx=3, text='World', ok=true}}
%   → text = 'Hello[missing frame 2]World'

if isempty(decoded_chunks)
    text = '';
    return;
end

all_idx = cellfun(@(c) c.idx, decoded_chunks);
max_idx = max(all_idx);

% 按 idx 索引 cell（缺位用空）
parts = cell(1, max_idx);
for j = 1:length(decoded_chunks)
    c = decoded_chunks{j};
    if c.idx >= 1 && c.idx <= max_idx
        if c.ok
            parts{c.idx} = c.text;
        else
            parts{c.idx} = sprintf('[missing frame %d]', c.idx);
        end
    end
end

% 整帧 idx 跳号也填占位
for k = 1:max_idx
    if isempty(parts{k})
        parts{k} = sprintf('[missing frame %d]', k);
    end
end

text = strjoin(parts, '');

end
