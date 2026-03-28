function [y_comp, alpha_est, est_info] = doppler_coarse_compensate(y, preamble, fs, varargin)
% 功能：10-1粗多普勒补偿统一入口——估计α + 重采样
% 版本：V1.0.0
% 输入：
%   y         - 接收信号 (1xN)
%   preamble  - 前导码 (1xL)
%   fs        - 采样率 (Hz)
%   可选参数（Name-Value对）：
%     'est_method'  : 估计方法 ('xcorr'(默认)/'caf'/'cp'/'zoomfft')
%     'comp_method' : 补偿方法 ('spline'(默认)/'farrow'/'polyphase')
%     'fc'          : 载频 (Hz，xcorr/zoomfft需要，默认 12000)
%     'T_v'         : 前后导码间隔 (秒，xcorr需要，默认 0.5)
%     'N_fft'       : FFT点数 (cp方法需要，默认 256)
%     'N_cp'        : CP长度 (cp方法需要，默认 64)
%     'alpha_range' : CAF搜索范围 (默认 [-0.02, 0.02])
% 输出：
%   y_comp    - 粗补偿后信号 (1xN)
%   alpha_est - 多普勒因子估计值
%   est_info  - 估计详细信息结构体

%% ========== 入参解析 ========== %%
p = inputParser;
addParameter(p, 'est_method', 'xcorr');
addParameter(p, 'comp_method', 'spline');
addParameter(p, 'fc', 12000);
addParameter(p, 'T_v', 0.5);
addParameter(p, 'N_fft', 256);
addParameter(p, 'N_cp', 64);
addParameter(p, 'alpha_range', [-0.02, 0.02]);
parse(p, varargin{:});
opts = p.Results;

y = y(:).';

%% ========== 参数校验 ========== %%
if isempty(y), error('接收信号不能为空！'); end

%% ========== 多普勒估计 ========== %%
est_info = struct();
switch opts.est_method
    case 'caf'
        [alpha_est, tau_est, caf_map] = est_doppler_caf(y, preamble, fs, opts.alpha_range);
        est_info.tau = tau_est;
        est_info.caf_map = caf_map;

    case 'cp'
        [alpha_est, corr_vals] = est_doppler_cp(y, opts.N_fft, opts.N_cp);
        est_info.corr_vals = corr_vals;

    case 'xcorr'
        [alpha_est, alpha_coarse, tau_est] = est_doppler_xcorr(y, preamble, opts.T_v, fs, opts.fc);
        est_info.alpha_coarse = alpha_coarse;
        est_info.tau = tau_est;

    case 'zoomfft'
        [alpha_est, freq_est, spectrum] = est_doppler_zoomfft(y, preamble, fs, opts.fc);
        est_info.freq_est = freq_est;
        est_info.spectrum = spectrum;

    otherwise
        error('不支持的估计方法: %s！支持 caf/cp/xcorr/zoomfft', opts.est_method);
end
est_info.method = opts.est_method;
est_info.alpha_est = alpha_est;

%% ========== 重采样补偿 ========== %%
switch opts.comp_method
    case 'spline'
        y_comp = comp_resample_spline(y, alpha_est, fs);
    case 'farrow'
        y_comp = comp_resample_farrow(y, alpha_est, fs);
    case 'polyphase'
        y_comp = comp_resample_polyphase(y, alpha_est, fs);
    otherwise
        error('不支持的补偿方法: %s！支持 spline/farrow/polyphase', opts.comp_method);
end

end
