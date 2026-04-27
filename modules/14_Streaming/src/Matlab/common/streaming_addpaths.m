function paths = streaming_addpaths()
%STREAMING_ADDPATHS Add Streaming and cross-module dependencies to path.

this_file = mfilename('fullpath');
common_dir = fileparts(this_file);
matlab_dir = fileparts(common_dir);
src_dir = fileparts(matlab_dir);
streaming_dir = fileparts(src_dir);
modules_dir = fileparts(streaming_dir);
proj_root = fileparts(modules_dir);

paths = struct();
paths.proj_root = proj_root;
paths.modules_dir = modules_dir;
paths.streaming_dir = streaming_dir;
paths.matlab_dir = matlab_dir;
paths.common_dir = common_dir;

addpath(common_dir);
addpath(fullfile(matlab_dir, 'tx'));
addpath(fullfile(matlab_dir, 'rx'));
addpath(fullfile(matlab_dir, 'channel'));
addpath(fullfile(matlab_dir, 'amc'));

deps = {'02_ChannelCoding', '03_Interleaving', '05_SpreadSpectrum', ...
    '06_MultiCarrier', '07_ChannelEstEq', '08_Sync', '09_Waveform', ...
    '10_DopplerProc', '12_IterativeProc'};
for k = 1:length(deps)
    dep_path = fullfile(modules_dir, deps{k}, 'src', 'Matlab');
    if exist(dep_path, 'dir')
        addpath(dep_path);
    end
end

end
