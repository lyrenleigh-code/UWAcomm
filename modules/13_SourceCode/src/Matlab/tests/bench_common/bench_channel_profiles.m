function ch_params = bench_channel_profiles(profile_name, base_params)
% 功能：按 profile_name 返回 gen_uwa_channel 所需的 ch_params 模板
% 版本：V1.0.0
% 输入：
%   profile_name - 'custom6' | 'exponential' | 'disc-5Hz' | 'hyb-K20' |
%                  'hyb-K10' | 'hyb-K5'
%   base_params  - struct，至少包含 fs 字段；可选 snr_db/seed/fading_* 等
% 输出：
%   ch_params - 完整 ch_params 结构体，可直接传入 gen_uwa_channel
%
% 备注：
%   custom6 / exponential 对应 gen_uwa_channel 的 delay_profile 参数
%   disc-*/hyb-K* 对应离散 Doppler 和 Rician 混合信道（参考
%   tests/*/test_*_discrete_doppler.m 的定义）

if nargin < 2, base_params = struct(); end
ch_params = base_params;
if ~isfield(ch_params, 'fs'), ch_params.fs = 48000; end

%% ========== 基础抽头：6 径归一化（高速组 benchmark 统一使用） ========== %%
sym_delays_ref_sps = [0, 5, 15, 40, 60, 90];   % 单位：符号 × sps
gains_raw_6 = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
               0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains_6 = gains_raw_6 / sqrt(sum(abs(gains_raw_6).^2));

switch lower(profile_name)
    case 'custom6'
        % 固定 6 径 custom profile（与现有 test_scfde_timevarying.m 一致）
        ch_params.delay_profile = 'custom';
        ch_params.delays_s      = sym_delays_ref_sps / 6000;  % 假设 sym_rate=6000
        ch_params.gains         = gains_6;

    case 'exponential'
        % 指数衰减随机 profile（gen_uwa_channel 默认模型）
        ch_params.delay_profile = 'exponential';
        ch_params.num_paths     = 5;
        ch_params.max_delay_ms  = 10;
        % delays_s / gains 由 gen_uwa_channel 按 seed 随机生成

    case 'disc-5hz'
        % 离散 Doppler：各路径独立频移，见 test_*_discrete_doppler.m
        % 注意：gen_uwa_channel 本身不支持离散 Doppler，需要阶段 B 的 runner
        %       (test_*_discrete_doppler.m) 内部用其它模型处理
        ch_params.delay_profile = 'custom';
        ch_params.delays_s      = sym_delays_ref_sps / 6000;
        ch_params.gains         = gains_6;
        ch_params.fading_type   = 'static';   % 基础模型先关 Jakes
        ch_params.disc_doppler  = struct('per_path_fd_hz', [0, 2, -3, 5, -1, 4]);

    case 'hyb-k20'
        % Rician 混合 K=20（95% 直达谱）
        ch_params.delay_profile = 'custom';
        ch_params.delays_s      = sym_delays_ref_sps / 6000;
        ch_params.gains         = gains_6;
        ch_params.rician_K_db   = 20;

    case 'hyb-k10'
        ch_params.delay_profile = 'custom';
        ch_params.delays_s      = sym_delays_ref_sps / 6000;
        ch_params.gains         = gains_6;
        ch_params.rician_K_db   = 10;

    case 'hyb-k5'
        ch_params.delay_profile = 'custom';
        ch_params.delays_s      = sym_delays_ref_sps / 6000;
        ch_params.gains         = gains_6;
        ch_params.rician_K_db   = 5;

    otherwise
        error('bench_channel_profiles:UnknownProfile', ...
              '未知 profile: %s', profile_name);
end

end
