function paths = simple_ui_addpaths()
% 功能：tx_simple_ui / rx_simple_ui 共享路径注册（参 p4_demo_ui.m L18-37）
% 版本：V1.0.0（2026-05-04）
% 输出：
%   paths - struct 含各模块根目录（供调用方按需 fullfile）
%       .streaming_dir   14_Streaming/src/Matlab
%       .modules_root    modules/
%       .proj_root       repo 根

this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
mod14_root     = fileparts(fileparts(streaming_root));
modules_root   = fileparts(mod14_root);
proj_root      = fileparts(modules_root);

addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(modules_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(modules_root, '03_Interleaving',  'src', 'Matlab'));
addpath(fullfile(modules_root, '04_Modulation',    'src', 'Matlab'));
addpath(fullfile(modules_root, '05_SpreadSpectrum','src', 'Matlab'));
addpath(fullfile(modules_root, '06_MultiCarrier',  'src', 'Matlab'));
addpath(fullfile(modules_root, '07_ChannelEstEq',  'src', 'Matlab'));
addpath(fullfile(modules_root, '08_Sync',          'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform',      'src', 'Matlab'));
addpath(fullfile(modules_root, '10_DopplerProc',   'src', 'Matlab'));
addpath(fullfile(modules_root, '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(modules_root, '13_SourceCode',    'src', 'Matlab', 'common'));

paths = struct( ...
    'streaming_dir', streaming_root, ...
    'modules_root',  modules_root, ...
    'proj_root',     proj_root);
end
