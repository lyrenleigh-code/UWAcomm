%% run_test_save_results.m — 运行统一测试并保存结果到 txt
% 用法：在 MATLAB 中直接运行此脚本
% 输出：07_ChannelEstEq/src/Matlab/test_results_doppler_fix.txt

% 保存当前目录，确保在正确位置
script_dir = fileparts(mfilename('fullpath'));
cd(script_dir);

% 打开日志文件
log_file = fullfile(script_dir, 'test_results_doppler_fix.txt');
diary(log_file);

fprintf('================================================\n');
fprintf('  模块07 统一测试 — doppler_rate 修正后基线\n');
fprintf('  运行时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('  doppler_rate = fd / fc (fc=12kHz)\n');
fprintf('================================================\n\n');

% 运行测试
try
    test_channel_est_eq;
    fprintf('\n\n测试运行成功\n');
catch ME
    fprintf('\n\n测试运行出错: %s\n', ME.message);
    fprintf('位置: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
end

diary off;

fprintf('\n结果已保存到: %s\n', log_file);
