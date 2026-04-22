function [alpha, diag_out] = est_alpha_dual_hfm_iter(rx_pb, hfm_pos, hfm_neg, fs, fc, params, opts)
% EST_ALPHA_DUAL_HFM_ITER 双 HFM 迭代 α 估计（真实 Doppler 鲁棒，含自适应早停）
%
% 原理：单次 sync_dual_hfm 在 ±1.7e-2 典型工况下有 1-5% 相对误差。
%       迭代"通带 resample + 残余估计"减小残余；
%       但 HFM estimator 底层噪声 ~5e-5，残余进入此量级后迭代会震荡。
%       加入自适应早停（|α_delta| < stop_thres 时停止）+ 阻尼（避免 overshoot）。
%
% 输入：
%   rx_pb   - 接收通带实信号
%   hfm_pos / hfm_neg - HFM 模板
%   fs, fc  - 采样率 / 载频
%   params  - sync_dual_hfm 参数
%   opts    - struct：.max_iter (默认 3), .stop_thres (默认 1e-4),
%                     .damping (默认 0.9，迭代中 α_delta 乘此因子)
%
% 输出：
%   alpha    - 最终估计的 α
%   diag_out - 每轮信息
%
% 版本：V1.1.0（2026-04-22 加入自适应早停 + 阻尼）

if nargin < 7 || isempty(opts), opts = struct(); end
if ~isfield(opts, 'max_iter'),   opts.max_iter   = 3;    end
if ~isfield(opts, 'stop_thres'), opts.stop_thres = 1e-4; end
if ~isfield(opts, 'damping'),    opts.damping    = 0.9;  end

alpha = 0;
diag_out.iter_alphas = [];
diag_out.iter_info   = {};
diag_out.stopped_at  = opts.max_iter;
diag_out.stop_reason = 'max_iter';

rx_current = rx_pb;

for it = 1:opts.max_iter
    %% 当前残余 α 估计
    [~, alpha_delta, ~, info] = sync_dual_hfm(rx_current, hfm_pos, hfm_neg, fs, params);
    diag_out.iter_alphas(end+1) = alpha_delta;
    diag_out.iter_info{end+1}   = info;

    %% 累积（第 1 轮不阻尼——初值最重要；第 2+ 轮阻尼）
    if it == 1
        alpha_apply = alpha_delta;
    else
        alpha_apply = alpha_delta * opts.damping;
    end
    alpha = (1 + alpha) * (1 + alpha_apply) - 1;

    %% 自适应早停：残余已小于噪声底，继续迭代会加噪
    if it > 1 && abs(alpha_delta) < opts.stop_thres
        diag_out.stopped_at  = it;
        diag_out.stop_reason = 'residual_below_threshold';
        break;
    end

    %% 用 alpha_apply 做通带 resample，准备下一次迭代
    if it < opts.max_iter && abs(alpha_apply) > 1e-10
        [p_num, q_den] = rat(1 + alpha_apply, 1e-7);
        rx_current = poly_resample(rx_current, p_num, q_den);
    end
end

diag_out.alpha_total = alpha;
diag_out.n_iter_done = it;

end
