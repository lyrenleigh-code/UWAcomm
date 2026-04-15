%% diag_uilabel.m — 诊断 uilabel 为何不可用
% 运行：
%   cd D:\Claude\TechReq\UWAcomm\modules\14_Streaming\src\Matlab\tests
%   run('diag_uilabel.m')
% 输出：diag_uilabel_results.txt

clear all; clear classes; %#ok<CLALL>
rehash toolboxcache

fid = fopen('diag_uilabel_results.txt', 'w');
if fid < 0
    error('无法打开输出文件');
end

print_line = @(msg) fprintf(fid, '%s\n', msg);

print_line('=== MATLAB 版本 ===');
v = ver('MATLAB');
print_line(sprintf('Name     : %s', v(1).Name));
print_line(sprintf('Version  : %s', v(1).Version));
print_line(sprintf('Release  : %s', v(1).Release));
print_line(sprintf('Date     : %s', v(1).Date));
print_line(sprintf('version()           = %s', version));
print_line(sprintf('version(''-release'') = %s', version('-release')));

print_line(' ');
print_line('=== uilabel 可用性 ===');
print_line(sprintf('exist(''uilabel'')           = %d  (2=m-file, 5=built-in, 0=not found)', ...
    exist('uilabel')));
print_line(sprintf('exist(''uilabel'',''builtin'') = %d', exist('uilabel', 'builtin')));
print_line(sprintf('exist(''uilabel'',''file'')    = %d', exist('uilabel', 'file')));

print_line(' ');
print_line('=== which uilabel -all ===');
try
    w = which('uilabel', '-all');
    if ischar(w)
        print_line(w);
    elseif iscell(w)
        for i = 1:length(w)
            print_line(sprintf('  [%d] %s', i, w{i}));
        end
    end
catch ME
    print_line(sprintf('which 报错: %s', ME.message));
end

print_line(' ');
print_line('=== 相关 uifigure 组件检查 ===');
checks = {'uifigure', 'uilabel', 'uibutton', 'uieditfield', 'uitextarea', ...
          'uidropdown', 'uipanel', 'uigridlayout', 'uitabgroup', 'uitab', ...
          'uiaxes', 'uicontrol', 'figure'};
for i = 1:length(checks)
    name = checks{i};
    e = exist(name);
    if e == 5
        status = 'built-in';
    elseif e == 2
        status = 'm-file';
    elseif e == 3
        status = 'MEX';
    elseif e == 6
        status = 'P-code';
    elseif e == 0
        status = 'NOT FOUND';
    else
        status = sprintf('unknown (exist=%d)', e);
    end
    print_line(sprintf('  %-16s : %s', name, status));
end

print_line(' ');
print_line('=== 尝试创建 uilabel ===');
try
    fig_test = uifigure('Visible', 'off');
    lbl = uilabel(fig_test, 'Text', 'hello');
    print_line('  [OK] uilabel 创建成功');
    print_line(sprintf('  Text = %s', lbl.Text));
    close(fig_test);
catch ME
    print_line(sprintf('  [FAIL] %s', ME.message));
    if ~isempty(ME.stack)
        print_line(sprintf('  @ %s line %d', ME.stack(1).name, ME.stack(1).line));
    end
end

print_line(' ');
print_line('=== ver（全部 toolbox）===');
all_prod = ver;
for i = 1:length(all_prod)
    print_line(sprintf('  %s %s (%s)', ...
        all_prod(i).Name, all_prod(i).Version, all_prod(i).Release));
end

fclose(fid);
fprintf('\n诊断完成。结果已写入 diag_uilabel_results.txt\n');
type('diag_uilabel_results.txt');
