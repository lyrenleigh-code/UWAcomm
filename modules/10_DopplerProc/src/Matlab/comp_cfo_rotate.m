function y_comp = comp_cfo_rotate(y, cfo_hz, fs)
% 功能：残余CFO相位旋转补偿（10-2）
% 版本：V1.0.0
% 输入：
%   y      - 接收信号 (1xN)
%   cfo_hz - 残余载波频偏 (Hz)
%   fs     - 采样率 (Hz)
% 输出：
%   y_comp - 频偏补偿后信号 (1xN)
%
% 备注：
%   - 补偿：y_comp(n) = y(n) * exp(-j*2π*cfo*n/fs)
%   - 用于粗多普勒补偿后的残余频偏校正
%   - 通常在信道估计后基于导频残余相位估计cfo

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 相位旋转补偿 ========== %%
n = 0:N-1;
y_comp = y .* exp(-1j * 2 * pi * cfo_hz * n / fs);

end
