function bench_append_csv(csv_path, row)
% 功能：原子追加单行到 CSV，首次写入自动创建 header
% 版本：V1.0.0
% 输入：
%   csv_path - 文件绝对/相对路径
%   row      - struct，字段顺序即 CSV 列顺序
%
% 备注：
%   文件不存在 → 创建并写 header + 第一行数据
%   文件存在   → 只追加数据行（不校验 header 一致性，调用方保证）
%   MATLAB 默认文本模式，换行符遵循 OS（Windows: CRLF）

[header_line, value_line] = bench_format_row(row);

if exist(csv_path, 'file') ~= 2
    ensure_dir(fileparts(csv_path));
    fid = fopen(csv_path, 'w');
    if fid < 0
        error('bench_append_csv:OpenFail', '无法创建 CSV: %s', csv_path);
    end
    fwrite(fid, header_line);
    fwrite(fid, value_line);
    fclose(fid);
else
    fid = fopen(csv_path, 'a');
    if fid < 0
        error('bench_append_csv:AppendFail', '无法追加 CSV: %s', csv_path);
    end
    fwrite(fid, value_line);
    fclose(fid);
end

end

function ensure_dir(d)
if isempty(d), return; end
if exist(d, 'dir') ~= 7
    mkdir(d);
end
end
