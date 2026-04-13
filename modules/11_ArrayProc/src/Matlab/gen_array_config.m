function config = gen_array_config(array_type, M, d, fc, varargin)
% 功能：生成阵列配置参数
% 版本：V1.0.0
% 输入：
%   array_type - 阵列类型 ('ula'均匀线阵(默认)/'uca'均匀圆阵/'custom'任意阵型)
%   M          - 阵元数 (默认 8)
%   d          - 阵元间距 (米，ULA用；UCA用半径，默认 lambda/2)
%   fc         - 载频 (Hz，默认 12000，用于计算波长)
%   varargin   - 自定义阵型时：positions (Mx3矩阵，每行[x,y,z]坐标)
% 输出：
%   config - 阵列配置结构体
%       .type      : 阵列类型
%       .M         : 阵元数
%       .positions : Mx3坐标矩阵 (米)
%       .d         : 阵元间距/半径
%       .fc        : 载频
%       .lambda    : 波长
%       .c         : 声速 (1500 m/s)

%% ========== 入参 ========== %%
c = 1500;
if nargin < 4 || isempty(fc), fc = 12000; end
lambda = c / fc;
if nargin < 3 || isempty(d), d = lambda / 2; end
if nargin < 2 || isempty(M), M = 8; end
if nargin < 1 || isempty(array_type), array_type = 'ula'; end

%% ========== 生成阵元坐标 ========== %%
switch array_type
    case 'ula'
        % 均匀线阵：沿y轴排列
        positions = zeros(M, 3);
        positions(:, 2) = (0:M-1).' * d;

    case 'uca'
        % 均匀圆阵：在xOy平面上
        radius = d;
        angles = (0:M-1).' * 2 * pi / M;
        positions = [radius * cos(angles), radius * sin(angles), zeros(M, 1)];

    case 'custom'
        if ~isempty(varargin) && ~isempty(varargin{1})
            positions = varargin{1};
            if size(positions, 1) ~= M
                error('自定义坐标行数(%d)与阵元数(%d)不匹配！', size(positions,1), M);
            end
        else
            error('custom阵型须提供positions参数！');
        end

    otherwise
        error('不支持的阵列类型: %s！支持 ula/uca/custom', array_type);
end

%% ========== 输出 ========== %%
config.type = array_type;
config.M = M;
config.positions = positions;
config.d = d;
config.fc = fc;
config.lambda = lambda;
config.c = c;

end
