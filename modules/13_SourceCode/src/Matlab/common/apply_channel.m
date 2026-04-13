function rx = apply_channel(tx, delay_bins, gains_raw, ftype, fparams, fs, fc)
% 功能：等效基带信道施加，支持4种信道模型
% 版本：V1.0.0
% 输入：
%   tx         - 发射基带信号 (1×N 复数)
%   delay_bins - 各径时延 (样本, @fs采样率)
%   gains_raw  - 各径复增益 (1×P)
%   ftype      - 信道类型: 'static'/'discrete'/'hybrid'/'jakes'
%   fparams    - 信道参数 (类型相关):
%       static:   忽略 (任意值)
%       discrete: [ν_1, ν_2, ..., ν_P] Hz — 每径Doppler频移
%       hybrid:   struct('doppler_hz',[...],'fd_scatter',..,'K_rice',..)
%                   doppler_hz: 每径离散Doppler频移(Hz)
%                   fd_scatter: 散射分量Doppler扩展(Hz)
%                   K_rice:     Rician K因子(谱/散射功率比)
%       jakes:    标量 fd_hz — 最大Doppler频移(Hz)
%   fs         - 采样率 (Hz)
%   fc         - 载波频率 (Hz, jakes模式需要)
% 输出：
%   rx         - 接收基带信号 (1×N 复数)
%
% 信道模型：
%   static:   h_p * x(n - d_p)
%   discrete: h_p * exp(j2*pi*nu_p*n/fs) * x(n - d_p)
%   hybrid:   Rician = 离散Doppler(强谱分量) + Jakes散射(弱)
%             h_p(t) = h_p * exp(j2*pi*nu_p*t) * [sqrt(K/(K+1)) + sqrt(1/(K+1))*g(t)]
%   jakes:    Jakes连续Doppler谱 (via gen_uwa_channel)
%
% 备注：
%   从端到端测试提取为公共函数，6体制离散Doppler对比共用
%   hybrid模型中N_osc=8个Jakes振荡器，seed=43保证可复现

    tx = tx(:).';
    rx = zeros(size(tx));
    N_tx = length(tx);

    switch ftype
        case 'static'
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                if d < N_tx
                    rx(d+1:end) = rx(d+1:end) + gains_raw(p) * tx(1:end-d);
                end
            end

        case 'discrete'
            % fparams = [nu_1, nu_2, ..., nu_P] Hz
            doppler_hz = fparams;
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                n_range = (d+1):N_tx;
                phase = exp(1j * 2*pi * doppler_hz(p) * (n_range-1) / fs);
                rx(n_range) = rx(n_range) + gains_raw(p) * phase .* tx(n_range-d);
            end

        case 'hybrid'
            % Rician: h_p(t) = h_p * exp(j2*pi*nu_p*t) * [sqrt(K/(K+1)) + sqrt(1/(K+1))*g(t)]
            doppler_hz = fparams.doppler_hz;
            fd_sc = fparams.fd_scatter;
            K = fparams.K_rice;
            spec_amp = sqrt(K / (K+1));
            scat_amp = sqrt(1 / (K+1));
            t = (0:N_tx-1) / fs;
            N_osc = 8;
            rng_state = rng;
            rng(43);
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                n_range = (d+1):N_tx;
                t_r = t(n_range);
                phase_disc = exp(1j * 2*pi * doppler_hz(p) * t_r);
                g_scat = zeros(1, length(n_range));
                for n_osc = 1:N_osc
                    theta = 2*pi * rand;
                    beta = pi * n_osc / N_osc;
                    g_scat = g_scat + exp(1j*(2*pi*fd_sc*cos(beta)*t_r + theta));
                end
                g_scat = g_scat / sqrt(N_osc);
                h_tv = gains_raw(p) * phase_disc .* (spec_amp + scat_amp * g_scat);
                rx(n_range) = rx(n_range) + h_tv .* tx(n_range-d);
            end
            rng(rng_state);

        case 'jakes'
            % Jakes衰落 via gen_uwa_channel (含bulk Doppler)
            fd_hz = fparams;
            delays_s = delay_bins / fs;
            ch_params = struct('fs',fs, 'delay_profile','custom', ...
                'delays_s',delays_s, 'gains',gains_raw, ...
                'num_paths',length(delay_bins), 'doppler_rate',fd_hz/fc, ...
                'fading_type','slow', 'fading_fd_hz',fd_hz, ...
                'snr_db',Inf, 'seed',42);
            [rx, ~] = gen_uwa_channel(tx, ch_params);

        otherwise
            error('不支持的信道类型: %s', ftype);
    end
end
