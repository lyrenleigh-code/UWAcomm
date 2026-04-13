function [y_comp, residual_info] = doppler_residual_compensate(y, fs, varargin)
% 功能：10-2残余多普勒补偿统一入口——基于信道估计结果的精细校正
% 版本：V1.0.0
% 输入：
%   y  - 信号 (1xN 或 KxN_fft频域)
%   fs - 采样率 (Hz)
%   可选参数（Name-Value对）：
%     'method'    : 补偿方法 ('cfo_rotate'(默认)/'ici_matrix')
%     'cfo_hz'    : 残余CFO频偏 (Hz，cfo_rotate需要，默认 0)
%     'alpha_res' : 残余α (ici_matrix需要，默认 0)
%     'N_fft'     : FFT点数 (ici_matrix需要，默认 256)
% 输出：
%   y_comp        - 补偿后信号
%   residual_info - 补偿信息结构体

%% ========== 入参解析 ========== %%
p = inputParser;
addParameter(p, 'method', 'cfo_rotate');
addParameter(p, 'cfo_hz', 0);
addParameter(p, 'alpha_res', 0);
addParameter(p, 'N_fft', 256);
parse(p, varargin{:});
opts = p.Results;

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end

%% ========== 残余补偿 ========== %%
residual_info = struct('method', opts.method);

switch opts.method
    case 'cfo_rotate'
        y_comp = comp_cfo_rotate(y, opts.cfo_hz, fs);
        residual_info.cfo_hz = opts.cfo_hz;

    case 'ici_matrix'
        y_comp = comp_ici_matrix(y, opts.alpha_res, opts.N_fft);
        residual_info.alpha_res = opts.alpha_res;

    otherwise
        error('不支持的方法: %s！支持 cfo_rotate/ici_matrix', opts.method);
end

end
