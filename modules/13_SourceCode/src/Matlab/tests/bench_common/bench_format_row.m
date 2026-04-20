function [header_line, value_line] = bench_format_row(row)
% 功能：把 benchmark 结果 struct 序列化为 CSV 行（含 header）
% 版本：V1.0.0
% 输入：
%   row - struct，字段即 CSV 列（数值/字符串混合）
% 输出：
%   header_line - 列名行（逗号分隔 + 换行）
%   value_line  - 数值行
%
% 备注：
%   数值空缺以 NaN 写入；字符串含逗号则用双引号包裹
%   字段顺序按 fieldnames(row) 返回序（插入顺序）

fields = fieldnames(row);
N = numel(fields);

header_parts = cell(1, N);
value_parts  = cell(1, N);

for k = 1:N
    f = fields{k};
    v = row.(f);
    header_parts{k} = f;
    value_parts{k}  = value_to_csv(v);
end

header_line = [strjoin(header_parts, ','), newline];
value_line  = [strjoin(value_parts,  ','), newline];

end

function s = value_to_csv(v)
% 单个值 → CSV 字符串
if ischar(v)
    if any(v == ',') || any(v == '"')
        s = ['"', strrep(v, '"', '""'), '"'];
    else
        s = v;
    end
elseif isstring(v)
    s = value_to_csv(char(v));
elseif islogical(v)
    if v, s = '1'; else, s = '0'; end
elseif isnumeric(v) && isscalar(v)
    if isnan(v)
        s = 'NaN';
    elseif mod(v, 1) == 0 && abs(v) < 1e15
        s = sprintf('%d', v);
    else
        s = sprintf('%.6g', v);
    end
elseif isnumeric(v) && isempty(v)
    s = '';
else
    s = sprintf('%s', mat2str(v));
end
end
