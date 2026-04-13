function [code, N] = gen_barker(N)
% 功能：生成Barker码（低旁瓣二进制同步码）
% 版本：V1.0.0
% 输入：
%   N - 码长 (支持 2/3/4/5/7/11/13，默认 13)
% 输出：
%   code - Barker码 (1xN 数组，值为 +1/-1)
%   N    - 实际码长
%
% 备注：
%   - Barker码的非周期自相关旁瓣绝对值 <= 1
%   - 已知Barker码仅存在长度 2,3,4,5,7,11,13
%   - 长度13的Barker码旁瓣最低，最常用
%   - 适用于短帧同步，处理增益 = 10*log10(N) dB

%% ========== 1. 入参解析 ========== %%
if nargin < 1 || isempty(N), N = 13; end

%% ========== 2. 查表 ========== %%
barker_table = containers.Map('KeyType', 'int32', 'ValueType', 'any');
barker_table(int32(2))  = [1, -1];
barker_table(int32(3))  = [1, 1, -1];
barker_table(int32(4))  = [1, 1, -1, 1];
barker_table(int32(5))  = [1, 1, 1, -1, 1];
barker_table(int32(7))  = [1, 1, 1, -1, -1, 1, -1];
barker_table(int32(11)) = [1, 1, 1, -1, -1, -1, 1, -1, -1, 1, -1];
barker_table(int32(13)) = [1, 1, 1, 1, 1, -1, -1, 1, 1, -1, 1, -1, 1];

if ~barker_table.isKey(int32(N))
    error('Barker码仅支持长度 2/3/4/5/7/11/13！请求的长度=%d', N);
end

code = barker_table(int32(N));

end
