%% diag_ui_error.m — 捕获 p1_demo_ui 的完整错误堆栈
% 运行：run('diag_ui_error.m')

fid = fopen('diag_ui_error.txt', 'w');

% 先确认 uilabel 在当前 MATLAB state 下确实存在
fprintf(fid, '=== 运行前 state 检查 ===\n');
fprintf(fid, 'which uilabel:\n');
w = which('uilabel');
if isempty(w), fprintf(fid, '  (empty)\n'); else, fprintf(fid, '  %s\n', w); end
fprintf(fid, 'exist(''uilabel'') = %d\n', exist('uilabel'));
fprintf(fid, 'pwd = %s\n', pwd);

% 注册路径（和 p1_demo_ui 开头完全一致）
this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));
fprintf(fid, 'proj_root = %s\n', proj_root);

streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(streaming_root, 'channel'));
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '09_Waveform', 'src', 'Matlab'));

fprintf(fid, 'which p1_demo_ui:\n');
w = which('p1_demo_ui');
if isempty(w), fprintf(fid, '  (empty)\n'); else, fprintf(fid, '  %s\n', w); end

fprintf(fid, 'which uilabel 路径注册后:\n');
w = which('uilabel');
if isempty(w), fprintf(fid, '  (empty)\n'); else, fprintf(fid, '  %s\n', w); end

fprintf(fid, '\n=== 尝试运行 p1_demo_ui ===\n');

try
    p1_demo_ui();
    fprintf(fid, '  [OK] 未报错\n');
catch ME
    fprintf(fid, '  [ERROR] message: %s\n', ME.message);
    fprintf(fid, '  identifier: %s\n', ME.identifier);
    fprintf(fid, '\n--- 完整堆栈 ---\n');
    fprintf(fid, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
end

fclose(fid);

fprintf('诊断结束，输出写入 diag_ui_error.txt\n');
type('diag_ui_error.txt');
