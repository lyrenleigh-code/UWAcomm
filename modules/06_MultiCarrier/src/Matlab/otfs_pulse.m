function [g, info] = otfs_pulse(M, pulse_type, params)
% 功能：生成OTFS发射/接收脉冲（per-sub-block时域窗, 长度M）
% 版本：V1.1.0 — 改用时域窗函数定义，避免短序列频域IFFT失真
% 输入：
%   M          - 子块长度（采样点数）
%   pulse_type - 脉冲类型（默认 'rect'）
%                'rect'     : 矩形脉冲（BCCB精确，当前默认）
%                'tukey'    : Tukey窗（平顶+余弦锥削, rolloff控制锥削比例）
%                'rrc'      : 根升余弦窗（频域RC谱的平方根, 时域直接构造）
%                'hann'     : Hann窗（全余弦, 最低旁瓣但主瓣最宽）
%                'gaussian' : 高斯窗
%   params     - 参数结构体（可选）
%     .rolloff   - 锥削比例 (tukey: 0~1, 0=rect, 1=hann; rrc: 滚降系数, 默认 0.3)
%     .BT        - 带宽时间积 (gaussian, 默认 0.3)
% 输出：
%   g          - 1×M 脉冲向量（归一化: sum(|g|^2) = M）
%   info       - 信息结构体
%     .pulse_type, .params
%     .freq_resp : 脉冲频率响应 (1×M)
%
% 原理：
%   OTFS Heisenberg变换: s_n(t) = IFFT{ X_tf(n,:) } .* g_tx(t)
%   矩形脉冲 g_tx=1 → 标准IFFT（当前实现）
%   非矩形脉冲 → 时域加窗 → 频谱旁瓣降低 → PAPR降低
%   代价：主瓣展宽 → 延迟/多普勒分辨力略降

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(params), params = struct(); end
if nargin < 2 || isempty(pulse_type), pulse_type = 'rect'; end
if ~isfield(params, 'rolloff'), params.rolloff = 0.3; end
if ~isfield(params, 'BT'), params.BT = 0.3; end

%% ========== 2. 参数校验 ========== %%
if M < 2, error('子块长度M必须>=2！'); end

%% ========== 3. 脉冲生成（时域窗函数）========== %%
n = (0:M-1);

switch lower(pulse_type)
    case 'rect'
        g = ones(1, M);

    case 'tukey'
        % Tukey窗: 平顶 + 两端余弦锥削
        % rolloff=0 → rect, rolloff=1 → hann
        alpha = params.rolloff;
        g = ones(1, M);
        if alpha > 0
            L_taper = floor(alpha * M / 2);
            % 左侧锥削
            g(1:L_taper) = 0.5 * (1 - cos(pi * (0:L_taper-1) / L_taper));
            % 右侧锥削
            g(M-L_taper+1:M) = 0.5 * (1 + cos(pi * (1:L_taper) / L_taper));
        end

    case 'rrc'
        % 根升余弦窗: 时域直接构造
        % 对称窗, 中心平坦, 两端按sqrt(raised-cosine)下降
        beta = params.rolloff;
        g = ones(1, M);
        if beta > 0
            L_taper = floor(beta * M / 2);
            % 左侧: sqrt(0.5*(1-cos))
            ramp = 0.5 * (1 - cos(pi * (0:L_taper-1) / L_taper));
            g(1:L_taper) = sqrt(ramp);
            % 右侧
            ramp_r = 0.5 * (1 + cos(pi * (1:L_taper) / L_taper));
            g(M-L_taper+1:M) = sqrt(ramp_r);
        end

    case 'hann'
        % Hann窗: 0.5*(1 - cos(2*pi*n/(M-1)))
        g = 0.5 * (1 - cos(2*pi*n/(M-1)));

    case 'gaussian'
        % 高斯窗: g(n) = exp(-0.5*(alpha*(n-M/2)/(M/2))^2)
        % alpha由BT控制: alpha = 1/(BT) 近似
        BT = params.BT;
        alpha_g = 1 / BT;
        g = exp(-0.5 * (alpha_g * (n - (M-1)/2) / ((M-1)/2)).^2);

    otherwise
        error('不支持的脉冲类型: %s！支持 rect/tukey/rrc/hann/gaussian', pulse_type);
end

%% ========== 4. 能量归一化 ========== %%
% 归一化使 sum(|g|^2) = M（与矩形脉冲一致）
g = g * sqrt(M / sum(abs(g).^2));

%% ========== 5. 输出信息 ========== %%
info.pulse_type = pulse_type;
info.params = params;
info.freq_resp = fft(g) / sqrt(M);

end
