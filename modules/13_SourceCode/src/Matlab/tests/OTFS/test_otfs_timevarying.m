%% test_otfs_timevarying.m — OTFS通带仿真 时变信道测试
% TX: 编码→交织→QPSK→DD域导频→OTFS调制→frame_assemble_otfs(两级同步)→通带
% 信道: 等效基带(离散Doppler/Rician混合/Jakes)
% RX: frame_parse_otfs(sync_dual_hfm+LFM精定时)→OTFS解调→DD估计→LMMSE+Turbo→译码
% 版本：V5.1.0 — 集成frame_assemble/parse_otfs V2.0 两级同步架构；支持 benchmark_mode
% 特点：[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|OTFS] + 双HFM粗同步+LFM精定时
% V5.1: 加 benchmark_mode 注入（spec 2026-04-19-e2e-timevarying-baseline）

%% ========== Benchmark mode 注入（2026-04-19） ========== %%
if ~exist('benchmark_mode','var') || isempty(benchmark_mode)
    benchmark_mode = false;
end
if ~benchmark_mode
    clc; close all;
end
use_oracle = false;
eq_type = 'lmmse';
uamp_inner = 5;
otfs_pulse_type = 'rect';
otfs_cp_window = 'none';
otfs_slm_candidates = 1;
otfs_slm_seed = 0;
otfs_clip_papr_db = Inf;
otfs_clip_method = 'clip';
passband_mode = true;  % true=通带仿真, false=基带仿真
pilot_mode = 'impulse';   % 'impulse'=A冲激, 'sequence'=B ZC, 'superimposed'=C叠加
                          % 2026-04-21 回滚：sequence 在 SNR=10dB 下 BER=28-32%（regression）
                          % 详见 wiki/modules/13_SourceCode/OTFS调试日志.md
otfs_superimposed_pilot_power = 0.2;

fprintf('========================================\n');
if passband_mode
    fprintf('  OTFS 通带仿真 V4.0\n');
else
    fprintf('  OTFS 基带仿真 V4.0\n');
end
fprintf('  均衡: %s, Oracle=%d\n', upper(eq_type), use_oracle);
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

%% ========== 参数 ========== %%
sym_rate = 6000;  % 基带采样率
fc = 12000;

% 5径信道 (须在OTFS参数前定义，cp_len依赖max delay)
delay_bins = [0, 1, 3, 5, 8];
delays_s = delay_bins / sym_rate;
gains_raw = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];

if benchmark_mode
    if ~exist('bench_channel_profile','var') || isempty(bench_channel_profile)
        bench_channel_profile = 'custom6';
    end
    if ~strcmpi(bench_channel_profile, 'custom6')
        bench_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'bench_common');
        addpath(bench_dir);
        profile_seed = 42;
        if exist('bench_seed','var') && ~isempty(bench_seed)
            profile_seed = bench_seed;
        end
        [delay_bins, gains_raw] = bench_profile_taps(bench_channel_profile, delay_bins, gains_raw, 'integer', profile_seed);
        delays_s = delay_bins / sym_rate;
    end
    if exist('bench_otfs_pilot_mode','var') && ~isempty(bench_otfs_pilot_mode)
        pilot_mode = bench_otfs_pilot_mode;
    end
    if exist('bench_otfs_superimposed_power','var') && ~isempty(bench_otfs_superimposed_power)
        otfs_superimposed_pilot_power = bench_otfs_superimposed_power;
    end
end

% OTFS参数
N = 32;          % 多普勒格点
M = 64;          % 时延格点
cp_len = 32;     % per-sub-block CP (需>max_delay, 较大余量避免ISI)
mp_iters = 20;
num_turbo = 3;

% 通带参数
sps = 6;                    % 上采样倍数 (需满足 fs_pb > 2*(fc+sym_rate/2))
fs_pb = sym_rate * sps;     % 通带采样率 36kHz

% QPSK
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits_per_sym = 2;

% 导频配置（根据 pilot_mode 切换）
switch pilot_mode
    case 'impulse'
        pilot_config = struct('mode','impulse', 'guard_k',4, 'guard_l',max(delay_bins)+2, ...
            'pilot_value',1);
    case 'sequence'  % B: ZC 序列 pilot
        pilot_config = struct('mode','sequence', 'seq_type','zc', 'seq_root',1, ...
            'guard_k',4, 'guard_l',max(delay_bins)+2, 'pilot_value',1);
    case 'superimposed'  % C: 叠加/扩散 pilot
        pilot_config = struct('mode','superimposed', 'pilot_power',otfs_superimposed_pilot_power, ...
            'guard_k',4, 'guard_l',max(delay_bins)+2);
    otherwise
        error('不支持的 pilot_mode: %s', pilot_mode);
end
[~,~,~,data_indices] = otfs_pilot_embed(zeros(1,1), N, M, pilot_config);
N_data_slots = length(data_indices);
if ismember(pilot_mode, {'impulse','sequence'})
    pilot_config.pilot_value = sqrt(N_data_slots);
end

% 编解码
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;
M_coded = N_data_slots * bits_per_sym;
N_info = M_coded / n_code - mem;

% 通信速率
subcarrier_spacing = sym_rate / M;
frame_duration = (N*M + cp_len) / sym_rate;
info_rate_bps = N_info / frame_duration;

% 生成交织置换
[~, perm] = random_interleave(zeros(1, M_coded), codec.interleave_seed);

snr_list = [0, 5, 10, 15, 20];

% 多普勒分辨率 (DD域网格间距)
delta_nu = sym_rate / (N * M);  % = fs/(N*M) ≈ 2.93 Hz

% 信道配置：离散Doppler vs Jakes对比
% 格式: {名称, 类型, 参数}
%   'discrete': 每径固定Doppler ν_p → h_p*exp(j2πν_p*t)
%   'jakes':    Jakes衰落 (连续Doppler谱)
%   'static':   无Doppler
% 混合信道: Rician = sqrt(K/(K+1))*exp(j2πν_p*t) + sqrt(1/(K+1))*jakes(fd_sc)
% K=Rician因子(谱直散比), fd_sc=散射Doppler展宽
fading_cfgs = {
    'static',   'static',   zeros(1,5);
    'disc-5Hz', 'discrete', [0, 3, -4, 5, -2];
    'hyb-K20',  'hybrid',   struct('doppler_hz',[0,3,-4,5,-2], 'fd_scatter',0.5, 'K_rice',20);
    'hyb-K10',  'hybrid',   struct('doppler_hz',[0,3,-4,5,-2], 'fd_scatter',0.5, 'K_rice',10);
    'hyb-K5',   'hybrid',   struct('doppler_hz',[0,3,-4,5,-2], 'fd_scatter',1.0, 'K_rice',5);
    'jakes5Hz', 'jakes',    5;
};

%% ========== Benchmark 覆盖（benchmark_mode=true 时生效） ========== %%
if benchmark_mode
    if exist('bench_snr_list','var') && ~isempty(bench_snr_list)
        snr_list = bench_snr_list;
    end
    if exist('bench_fading_cfgs','var') && ~isempty(bench_fading_cfgs)
        fading_cfgs = bench_fading_cfgs;
    end
    if ~exist('bench_channel_profile','var') || isempty(bench_channel_profile)
        bench_channel_profile = 'custom6';
    end
    if ~exist('bench_seed','var') || isempty(bench_seed)
        bench_seed = 42;
    end
    if ~exist('bench_stage','var') || isempty(bench_stage)
        bench_stage = 'A1';
    end
    if ~exist('bench_scheme_name','var') || isempty(bench_scheme_name)
        bench_scheme_name = 'OTFS';
    end
    if exist('bench_otfs_pulse_type','var') && ~isempty(bench_otfs_pulse_type)
        otfs_pulse_type = bench_otfs_pulse_type;
    end
    if exist('bench_otfs_cp_window','var') && ~isempty(bench_otfs_cp_window)
        otfs_cp_window = bench_otfs_cp_window;
    end
    if exist('bench_otfs_slm_candidates','var') && ~isempty(bench_otfs_slm_candidates)
        otfs_slm_candidates = bench_otfs_slm_candidates;
    end
    if exist('bench_otfs_slm_seed','var') && ~isempty(bench_otfs_slm_seed)
        otfs_slm_seed = bench_otfs_slm_seed;
    end
    if exist('bench_otfs_clip_papr_db','var') && ~isempty(bench_otfs_clip_papr_db)
        otfs_clip_papr_db = bench_otfs_clip_papr_db;
    end
    if exist('bench_otfs_clip_method','var') && ~isempty(bench_otfs_clip_method)
        otfs_clip_method = bench_otfs_clip_method;
    end
    fprintf('[BENCHMARK] snr_list=%s, fading rows=%d, profile=%s, seed=%d, stage=%s\n', ...
            mat2str(snr_list), size(fading_cfgs,1), ...
            bench_channel_profile, bench_seed, bench_stage);
end

fprintf('OTFS: N=%d x M=%d, CP=%d, df=%.1fHz, fs_bb=%dHz\n', N, M, cp_len, subcarrier_spacing, sym_rate);
fprintf('Pilot: %s', pilot_mode);
if strcmp(pilot_mode, 'superimposed')
    fprintf(' (power=%.3f)', otfs_superimposed_pilot_power);
end
fprintf('\n');
fprintf('Pulse: %s, CP window: %s\n', otfs_pulse_type, otfs_cp_window);
fprintf('SLM candidates: %d, seed=%d\n', otfs_slm_candidates, otfs_slm_seed);
if isfinite(otfs_clip_papr_db)
    fprintf('PAPR clip: target=%.1fdB, method=%s\n', otfs_clip_papr_db, otfs_clip_method);
else
    fprintf('PAPR clip: off\n');
end
if passband_mode
    fprintf('通带: sps=%d, fs_pb=%dHz, fc=%dHz\n', sps, fs_pb, fc);
end
fprintf('均衡: %s + Turbo %d轮\n', upper(eq_type), num_turbo);
fprintf('速率: %.0f bps (QPSK, R=1/%d, %d data slots)\n', info_rate_bps, n_code, N_data_slots);
fprintf('帧长: %d样本 (%.1fms)\n', N*M+cp_len, frame_duration*1000);
fprintf('信道: %d径, delay_bins=[%s], max=%d < CP=%d\n', ...
    length(delay_bins), num2str(delay_bins), max(delay_bins), cp_len);
fprintf('多普勒分辨率: Δν=%.2f Hz\n\n', delta_nu);

%% ========== Loopback验证 ========== %%
fprintf('--- Loopback验证 ---\n');
rng(999);
test_data = constellation(randi(4,1,N_data_slots));
[dd_test,~,~,~] = otfs_pilot_embed(test_data, N, M, pilot_config);
[sig_test,~] = otfs_modulate(dd_test, N, M, cp_len, 'dft', otfs_pulse_type, otfs_cp_window);
[dd_recv,~] = otfs_demodulate(sig_test, N, M, cp_len, 'dft');
err_loopback = max(abs(dd_test(:) - dd_recv(:)));
fprintf('  mod->demod 误差: %.2e %s\n\n', err_loopback, ...
    char((err_loopback<1e-10)*'V' + (err_loopback>=1e-10)*'X'));

%% ========== 主测试 ========== %%
ber_matrix = zeros(size(fading_cfgs,1), length(snr_list));
ber_unc_matrix = zeros(size(fading_cfgs,1), length(snr_list));
ber_turbo_trace = cell(size(fading_cfgs,1), length(snr_list));
nmse_matrix = NaN(size(fading_cfgs,1), length(snr_list));
sync_tau_err_matrix = NaN(size(fading_cfgs,1), length(snr_list));
runtime_matrix = NaN(size(fading_cfgs,1), length(snr_list));
slm_papr_before = NaN(size(fading_cfgs,1), 1);
slm_papr_after = NaN(size(fading_cfgs,1), 1);
slm_selected = NaN(size(fading_cfgs,1), 1);
clip_papr_before = NaN(size(fading_cfgs,1), 1);
clip_papr_after = NaN(size(fading_cfgs,1), 1);
clip_ratio_matrix = zeros(size(fading_cfgs,1), 1);
% 保存每配置的真实/估计DD信道（最高SNR时）用于可视化
ch_diag = struct('h_true',{}, 'h_est',{}, 'path_info',{});

fprintf('%-9s|', '');
for si=1:length(snr_list), fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-',1,8+8*length(snr_list)));

for fi = 1:size(fading_cfgs,1)
    fname = fading_cfgs{fi,1};
    ftype = fading_cfgs{fi,2};
    fparams = fading_cfgs{fi,3};

    %% ===== TX ===== %%
    rng(100+fi);
    info_bits = randi([0 1], 1, N_info);
    coded = conv_encode(info_bits, codec.gen_polys, codec.constraint_len);
    coded = coded(1:M_coded);
    [interleaved,~] = random_interleave(coded, codec.interleave_seed);
    data_sym = constellation(bi2de(reshape(interleaved,2,[]).','left-msb')+1);

    [dd_frame, pilot_info, guard_mask, ~] = otfs_pilot_embed(data_sym, N, M, pilot_config);
    [dd_frame, otfs_signal, slm_info] = otfs_slm_select(dd_frame, data_indices, N, M, cp_len, ...
        'dft', otfs_pulse_type, otfs_cp_window, otfs_slm_candidates, otfs_slm_seed + fi);
    slm_papr_before(fi) = slm_info.papr_before_db;
    slm_papr_after(fi) = slm_info.papr_after_db;
    slm_selected(fi) = slm_info.selected;
    clip_papr_before(fi) = papr_calculate(otfs_signal);
    if isfinite(otfs_clip_papr_db)
        [otfs_signal, clip_ratio_matrix(fi)] = papr_clip(otfs_signal, otfs_clip_papr_db, otfs_clip_method);
    end
    clip_papr_after(fi) = papr_calculate(otfs_signal);

    N_sig = length(otfs_signal);

    %% ===== 1) 信道(等效基带) ===== %%
    rx_clean = apply_channel(otfs_signal, delay_bins, gains_raw, ftype, fparams, sym_rate, fc);

    %% ===== 2) 通带帧组装 V5.0: 两级同步架构 ===== %%
    if passband_mode
        % 使用 frame_assemble_otfs V2.0: [HFM+|g|HFM-|g|LFM1|g|LFM2|g|OTFS]
        frame_p = struct('N',N, 'M',M, 'cp_len',cp_len, ...
                         'sps',sps, 'fs_bb',sym_rate, 'fc',fc, ...
                         'bw',sym_rate*1.3, ...  % 同步序列带宽(略大于OTFS基带)
                         'T_hfm',0.05, 'T_lfm',0.02, 'guard_ms',5, ...
                         'sync_gain',0.7);

        % TX帧（仅用于获取info, 不实际传输）
        [frame_tx_pb, info] = frame_assemble_otfs(otfs_signal, frame_p);
        % RX帧: 将信道后的OTFS装入同样结构的帧中
        [frame_rx_pb, ~] = frame_assemble_otfs(rx_clean, frame_p);
        sig_pwr_pb = mean(frame_rx_pb.^2);
    else
        sig_pwr = mean(abs(rx_clean).^2);
    end

    % 保存第1配置波形(供可视化)
    if fi == 1
        if passband_mode
            vis_frame_tx = frame_tx_pb;
            vis_frame_info = info;
        end
        vis_tx_bb = otfs_signal;
    end

    % === Pilot-only信道探测(基带) ===
    dd_pilot_only = zeros(N, M);
    switch pilot_mode
        case 'impulse'
            dd_pilot_only(pilot_info.positions(1,1), pilot_info.positions(1,2)) = pilot_info.values(1);
        case 'sequence'
            for pc_po = 1:size(pilot_info.positions, 1)
                dd_pilot_only(pilot_info.positions(pc_po,1), pilot_info.positions(pc_po,2)) = pilot_info.values(pc_po);
            end
        case 'superimposed'
            dd_pilot_only = pilot_info.pilot_pattern;
    end
    [sig_po, ~] = otfs_modulate(dd_pilot_only, N, M, cp_len, 'dft', otfs_pulse_type, otfs_cp_window);
    rx_po = apply_channel(sig_po, delay_bins, gains_raw, ftype, fparams, sym_rate, fc);
    [Y_dd_po, ~] = otfs_demodulate(rx_po, N, M, cp_len, 'dft');
    switch pilot_mode
        case 'impulse'
            ch_diag(fi).h_true = Y_dd_po / pilot_info.values(1);
        case 'sequence'
            [h_po, ~] = ch_est_otfs_zc(Y_dd_po, pilot_info, N, M);
            ch_diag(fi).h_true = h_po;
        case 'superimposed'
            [h_po, ~] = ch_est_otfs_superimposed(Y_dd_po, pilot_info, N, M, ...
                struct('iter',1, 'guard_k',4, 'guard_l',max(delay_bins)+2));
            ch_diag(fi).h_true = h_po;
    end

    fprintf('%-9s|', fname);

    for si = 1:length(snr_list)
        pt_timer = tic;
        snr_db = snr_list(si);
        rng(300+fi*1000+si*100);

        if passband_mode
            % 通带帧加实噪声
            noise_pwr = sig_pwr_pb * 10^(-snr_db/10);
            frame_rx_noisy = frame_rx_pb + sqrt(noise_pwr) * randn(size(frame_rx_pb));
            % 使用 frame_parse_otfs V2.0: 两级同步+多普勒补偿+基带提取
            [rx_noisy, sync_info] = frame_parse_otfs(frame_rx_noisy, info);
            sync_tau_err_matrix(fi,si) = sync_info.tau_fine - info.seg.lfm2_start;
            noise_var = mean(abs(rx_clean).^2) * 10^(-snr_db/10);
            if fi == 1 && si == length(snr_list)
                vis_frame_rx = frame_rx_noisy;
                vis_sync_info = sync_info;
            end
        else
            noise_var = mean(abs(rx_clean).^2) * 10^(-snr_db/10);
            rx_noisy = rx_clean + sqrt(noise_var/2)*(randn(size(rx_clean)) + 1j*randn(size(rx_clean)));
        end

        % 1. OTFS解调
        [Y_dd, ~] = otfs_demodulate(rx_noisy, N, M, cp_len, 'dft');
        % pilot 参考位置（impulse/sequence 用, superimposed 用 ceil(N/2), ceil(M/2)）
        if ~isempty(pilot_info.positions)
            pk_pos = pilot_info.positions(1,1);
            pl_pos = pilot_info.positions(1,2);
            pv_val = pilot_info.values(1);
        else  % superimposed
            pk_pos = ceil(N/2);
            pl_pos = ceil(M/2);
            pv_val = 1;
        end

        % 2. 信道获取：Oracle模式(真实信道) 或 估计模式
        if use_oracle
            % Oracle: guard区完整响应作为信道（无阈值，最大精度）
            % LMMSE用D=fft2(C)全局频响，完整guard给出最准确的C
            h_true = ch_diag(fi).h_true;  % NxM, 已归一化(无噪声pilot-only)
            h_dd = zeros(N, M);
            oracle_delays = []; oracle_dopplers = []; oracle_gains = [];
            for dk_o = -pilot_config.guard_k:pilot_config.guard_k
                for dl_o = 0:pilot_config.guard_l
                    kk_o = mod(pk_pos-1+dk_o, N)+1;
                    ll_o = mod(pl_pos-1+dl_o, M)+1;
                    val_o = h_true(kk_o, ll_o);
                    h_dd(kk_o, ll_o) = val_o;  % 无阈值，全部写入
                    oracle_delays = [oracle_delays, dl_o];
                    oracle_dopplers = [oracle_dopplers, dk_o];
                    oracle_gains = [oracle_gains, val_o];
                end
            end
            path_info.delay_idx = oracle_delays;
            path_info.doppler_idx = oracle_dopplers;
            path_info.gain = oracle_gains;
            path_info.num_paths = length(oracle_gains);
            nv_dd = max(noise_var, 1e-8);
        else
            % 估计模式（按 pilot_mode 选择估计器）
            switch pilot_mode
                case 'impulse'
                    [h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M);
                case 'sequence'
                    [h_dd, path_info] = ch_est_otfs_zc(Y_dd, pilot_info, N, M);
                case 'superimposed'
                    [h_dd, path_info] = ch_est_otfs_superimposed(Y_dd, pilot_info, N, M, ...
                        struct('iter',3, 'guard_k',4, 'guard_l',max(delay_bins)+2));
            end
            % 噪声方差估计
            nv_dd = max(noise_var, 1e-8);
            if strcmp(pilot_mode, 'impulse')
                detected_dl = unique(path_info.delay_idx);
                noise_mask = false(N, M);
                for dk_n = -pilot_config.guard_k:pilot_config.guard_k
                    for dl_n = 0:pilot_config.guard_l
                        if ~ismember(dl_n, detected_dl)
                            kk_n = mod(pk_pos-1+dk_n, N)+1;
                            ll_n = mod(pl_pos-1+dl_n, M)+1;
                            noise_mask(kk_n, ll_n) = true;
                        end
                    end
                end
                if any(noise_mask(:))
                    nv_dd = max(mean(abs(Y_dd(noise_mask)).^2), 1e-8);
                end
            end
        end

        % 3. 导频贡献去除（按 pilot_mode 分别处理）
        h_true_grid = ch_diag(fi).h_true;
        den_nmse = norm(h_true_grid(:))^2;
        if den_nmse > eps
            nmse_matrix(fi,si) = 10*log10(norm(h_dd(:) - h_true_grid(:))^2 / den_nmse);
        end
        Y_dd_eq = Y_dd;
        switch pilot_mode
            case {'impulse', 'sequence'}
                % 冲激/ZC: pilot 在特定位置, 减去每个检测路径的 pilot 贡献
                if strcmp(pilot_mode, 'sequence')
                    % ZC: pilot 分布在 seq_len 列, 对每路径需要在多列减去
                    for pp_r = 1:path_info.num_paths
                        dl_p = path_info.delay_idx(pp_r);
                        dk_p = path_info.doppler_idx(pp_r);
                        % pilot_info.positions 是 seq_len×2 矩阵
                        for pc_i = 1:size(pilot_info.positions, 1)
                            pk_c = pilot_info.positions(pc_i, 1);
                            pl_c = pilot_info.positions(pc_i, 2);
                            pv_c = pilot_info.values(pc_i);
                            kk_r = mod(pk_c-1+dk_p, N)+1;
                            ll_r = mod(pl_c-1+dl_p, M)+1;
                            Y_dd_eq(kk_r, ll_r) = Y_dd_eq(kk_r, ll_r) - path_info.gain(pp_r) * pv_c;
                        end
                    end
                else
                    % impulse
                    for pp_r = 1:path_info.num_paths
                        kk_r = mod(pk_pos-1+path_info.doppler_idx(pp_r), N)+1;
                        ll_r = mod(pl_pos-1+path_info.delay_idx(pp_r), M)+1;
                        Y_dd_eq(kk_r, ll_r) = Y_dd_eq(kk_r, ll_r) - path_info.gain(pp_r) * pv_val;
                    end
                end
            case 'superimposed'
                % 叠加: pilot 遍布 NM 所有位置, 从 Y 中减去 channel ⊛ pilot_pattern
                h_origin = zeros(N, M);
                for p_idx = 1:path_info.num_paths
                    dk_p = path_info.doppler_idx(p_idx);
                    dl_p = path_info.delay_idx(p_idx);
                    kk_o = mod(dk_p, N) + 1;
                    ll_o = mod(dl_p, M) + 1;
                    h_origin(kk_o, ll_o) = path_info.gain(p_idx);
                end
                Y_pilot_contrib = ifft2(fft2(pilot_info.pilot_pattern) .* fft2(h_origin));
                Y_dd_eq = Y_dd - Y_pilot_contrib;
        end

        % 诊断标记（最高SNR时保存eq_info）
        do_diag = (si == length(snr_list));
        if si == 1, diag_info = []; end

        % 保存（供可视化）
        if si == length(snr_list)
            ch_diag(fi).h_est = h_dd;
            ch_diag(fi).path_info = path_info;
        end

        %% ===== 5. Turbo迭代：UAMP/LMMSE + BCJR ===== %%
        prior_mean = [];
        prior_var = [];
        ber_trace = zeros(1, num_turbo);
        guard_indices = find(guard_mask);

        for turbo_iter = 1:num_turbo
            % 5a. 均衡器选择
            if strcmp(eq_type, 'uamp')
                % UAMP: Onsager修正允许多轮内部迭代, EM自适应噪声
                [x_hat, ~, x_mean, eq_info] = eq_otfs_uamp(Y_dd_eq, h_dd, path_info, N, M, ...
                    nv_dd, uamp_inner, constellation, prior_mean, prior_var);
            else
                % LMMSE: 单次线性滤波(max_iter=1)
                [x_hat, ~, x_mean, eq_info] = eq_otfs_lmmse(Y_dd_eq, h_dd, path_info, N, M, ...
                    nv_dd, 1, constellation, prior_mean, prior_var);
            end

            % 保存诊断信息（延迟到BER打印后输出，避免断行）
            if do_diag && turbo_iter == 1
                diag_info = eq_info;
            end

            % 5b. 提取数据符号 → LLR (用后验方差τ_r，比固定nv_dd更准确)
            x_data_soft = x_mean(data_indices);
            x_data_soft = x_data_soft(:) .* conj(slm_info.data_phase(:));
            nv_llr = max(eq_info.nv_post, 1e-8);
            LLR_eq = zeros(1, M_coded);
            for k=1:N_data_slots
                LLR_eq(2*k-1) = -2*sqrt(2)*real(x_data_soft(k)) / nv_llr;
                LLR_eq(2*k)   = -2*sqrt(2)*imag(x_data_soft(k)) / nv_llr;
            end
            LLR_eq = max(min(LLR_eq, 30), -30);

            % 5c. 解交织 → SISO译码
            LLR_coded = random_deinterleave(LLR_eq, perm);
            [~, Lp_info, Lp_coded] = siso_decode_conv(LLR_coded, [], ...
                codec.gen_polys, codec.constraint_len, codec.decode_mode);
            bits_out = double(Lp_info > 0);
            nc = min(length(bits_out), N_info);
            ber_iter = mean(bits_out(1:nc) ~= info_bits(1:nc));
            ber_trace(turbo_iter) = ber_iter;

            % 5d. Turbo反馈：SISO后验 → 交织 → soft_mapper → DD域先验
            if turbo_iter < num_turbo
                Lp_coded_inter = random_interleave(Lp_coded, codec.interleave_seed);
                if length(Lp_coded_inter) < M_coded
                    Lp_coded_inter = [Lp_coded_inter, zeros(1, M_coded-length(Lp_coded_inter))];
                else
                    Lp_coded_inter = Lp_coded_inter(1:M_coded);
                end
                [x_bar, var_x] = soft_mapper(Lp_coded_inter, 'qpsk');
                var_x = max(var_x, nv_dd);

                % 构建完整NxM先验 (BCCB要求均匀v_x，guard用相同方差)
                prior_mean = zeros(N, M);
                prior_var = var_x * ones(N, M);
                n_fill = min(length(x_bar), N_data_slots);
                for i_d = 1:n_fill
                    prior_mean(data_indices(i_d)) = x_bar(i_d) * slm_info.data_phase(i_d);
                end
            end
        end

        % uncoded BER
        x_data_hard = x_hat(data_indices);
        x_data_hard = x_data_hard(:) .* conj(slm_info.data_phase(:));
        bits_hard = zeros(1, N_data_slots*2);
        for k=1:N_data_slots
            bits_hard(2*k-1) = real(x_data_hard(k)) < 0;
            bits_hard(2*k)   = imag(x_data_hard(k)) < 0;
        end
        ber_unc = mean(bits_hard(1:M_coded) ~= interleaved);

        ber = ber_trace(end);
        ber_matrix(fi,si) = ber;
        ber_unc_matrix(fi,si) = ber_unc;
        ber_turbo_trace{fi,si} = ber_trace;
        runtime_matrix(fi,si) = toc(pt_timer);
        fprintf(' %6.2f%%', ber*100);
    end
    fprintf('  (p=%d)\n', path_info.num_paths);

    % 诊断
    if ~isempty(diag_info)
        fprintf('  nv_post=%.4f, v_x=%.4f\n', diag_info.nv_post, diag_info.v_x);
    end
end

%% ========== Benchmark CSV 写入（benchmark_mode=true 时生效） ========== %%
if benchmark_mode
    bench_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'bench_common');
    addpath(bench_dir);
    if ~exist('bench_csv_path','var') || isempty(bench_csv_path)
        bench_csv_path = fullfile(bench_dir, 'e2e_baseline_unspecified.csv');
    end
    for fi_b = 1:size(fading_cfgs,1)
        for si_b = 1:length(snr_list)
            row = bench_init_row(bench_stage, bench_scheme_name);
            % OTFS fading_cfgs 第 3 列是向量/struct/标量，记录名称到 profile
            slm_tag = sprintf('|slm=%d|sel=%d|slm_papr=%.2f->%.2f', ...
                otfs_slm_candidates, slm_selected(fi_b), slm_papr_before(fi_b), slm_papr_after(fi_b));
            if isfinite(otfs_clip_papr_db)
                clip_tag = sprintf('|clip=%.1f/%s|txpapr=%.2f->%.2f|clipr=%.4f', ...
                    otfs_clip_papr_db, otfs_clip_method, clip_papr_before(fi_b), ...
                    clip_papr_after(fi_b), clip_ratio_matrix(fi_b));
            else
                clip_tag = sprintf('|clip=off|txpapr=%.2f', clip_papr_after(fi_b));
            end
            pilot_tag = sprintf('|pilot=%s', pilot_mode);
            if strcmp(pilot_mode, 'superimposed')
                pilot_tag = sprintf('%s:%.3f', pilot_tag, otfs_superimposed_pilot_power);
            end
            row.profile          = sprintf('%s|%s%s|pulse=%s|cpwin=%s%s%s', ...
                bench_channel_profile, fading_cfgs{fi_b,1}, pilot_tag, otfs_pulse_type, otfs_cp_window, slm_tag, clip_tag);
            fd_val = NaN;
            if strcmp(fading_cfgs{fi_b, 2}, 'jakes') && isnumeric(fading_cfgs{fi_b,3})
                fd_val = fading_cfgs{fi_b,3};
            end
            row.fd_hz            = fd_val;
            row.doppler_rate     = 0;  % OTFS 框架无固定 α
            row.snr_db           = snr_list(si_b);
            row.seed             = bench_seed;
            row.ber_coded        = ber_matrix(fi_b, si_b);
            row.ber_uncoded      = ber_unc_matrix(fi_b, si_b);
            row.nmse_db          = nmse_matrix(fi_b, si_b);
            row.sync_tau_err     = sync_tau_err_matrix(fi_b, si_b);
            row.frame_detected   = 1;
            row.turbo_final_iter = num_turbo;
            row.runtime_s        = runtime_matrix(fi_b, si_b);
            bench_append_csv(bench_csv_path, row);
        end
    end
    fprintf('[BENCHMARK] CSV 写入: %s (%d 行)\n', bench_csv_path, ...
            size(fading_cfgs,1) * length(snr_list));
    return;
end

%% ========== 可视化 ========== %%
try
    n_cfg = size(fading_cfgs,1);
    markers={'o-','s-','d-','^-','v-','p-'};
    colors = lines(n_cfg);

    % --- Figure 0: 通带帧波形+频谱 ---
    if passband_mode && exist('vis_frame_tx','var')
        figure('Position',[30 50 1400 750], 'Name','OTFS 通带帧波形与频谱');
        t_frame = (0:length(vis_frame_tx)-1) / fs_pb * 1000;  % ms
        t_bb = (0:length(vis_tx_bb)-1) / sym_rate * 1000;
        dur_ms = t_frame(end);
        vfi = vis_frame_info;

        % (1,1) TX通带帧波形 (完整, 标注结构)
        subplot(3,2,1);
        plot(t_frame, vis_frame_tx, 'b', 'LineWidth', 0.3);
        xlabel('时间 (ms)'); ylabel('幅度'); grid on;
        title(sprintf('TX 通带帧 (%.1fms, fc=%dkHz)', dur_ms, fc/1000));
        hold on;
        % 标注V2.0帧结构 [HFM+|g|HFM-|g|LFM1|g|LFM2|g|OTFS]
        s = vfi.seg;
        pos_ms = @(idx) (idx-1)/fs_pb*1000;
        hfm_pos_end = pos_ms(s.guard1_start);
        hfm_neg_end = pos_ms(s.guard2_start);
        lfm1_end = pos_ms(s.guard3_start);
        lfm2_end = pos_ms(s.guard4_start);
        data_start = pos_ms(s.otfs_start);
        data_end = pos_ms(s.otfs_start + vfi.otfs_pb_len);
        yl = ylim;
        patch([pos_ms(s.hfm_pos_start) hfm_pos_end hfm_pos_end pos_ms(s.hfm_pos_start)], ...
            [yl(1) yl(1) yl(2) yl(2)], 'g', 'FaceAlpha',0.1,'EdgeColor','none');
        patch([pos_ms(s.hfm_neg_start) hfm_neg_end hfm_neg_end pos_ms(s.hfm_neg_start)], ...
            [yl(1) yl(1) yl(2) yl(2)], 'r', 'FaceAlpha',0.1,'EdgeColor','none');
        patch([pos_ms(s.lfm1_start) lfm1_end lfm1_end pos_ms(s.lfm1_start)], ...
            [yl(1) yl(1) yl(2) yl(2)], 'c', 'FaceAlpha',0.1,'EdgeColor','none');
        patch([pos_ms(s.lfm2_start) lfm2_end lfm2_end pos_ms(s.lfm2_start)], ...
            [yl(1) yl(1) yl(2) yl(2)], 'c', 'FaceAlpha',0.1,'EdgeColor','none');
        patch([data_start data_end data_end data_start], [yl(1) yl(1) yl(2) yl(2)], ...
            'b', 'FaceAlpha',0.08,'EdgeColor','none');
        text((pos_ms(s.hfm_pos_start)+hfm_pos_end)/2, yl(2)*0.9, 'HFM+', 'HorizontalAlignment','center','FontSize',7);
        text((pos_ms(s.hfm_neg_start)+hfm_neg_end)/2, yl(2)*0.9, 'HFM-', 'HorizontalAlignment','center','FontSize',7);
        text((pos_ms(s.lfm1_start)+lfm1_end)/2, yl(2)*0.9, 'LFM1', 'HorizontalAlignment','center','FontSize',7);
        text((pos_ms(s.lfm2_start)+lfm2_end)/2, yl(2)*0.9, 'LFM2', 'HorizontalAlignment','center','FontSize',7);
        text((data_start+data_end)/2, yl(2)*0.9, 'OTFS', 'HorizontalAlignment','center','FontSize',8);

        % (1,2) RX通带帧波形 (完整)
        subplot(3,2,2);
        if exist('vis_frame_rx','var')
            plot(t_frame, vis_frame_rx, 'Color',[0.85 0.33 0.1], 'LineWidth', 0.3);
            title(sprintf('RX 通带帧 @%ddB', snr_list(end)));
        else
            title('RX (无数据)');
        end
        xlabel('时间 (ms)'); ylabel('幅度'); grid on;

        % (2,1) TX基带I/Q (OTFS数据, WOLA窗后)
        subplot(3,2,3);
        plot(t_bb, real(vis_tx_bb), 'b', 'LineWidth', 0.5); hold on;
        plot(t_bb, imag(vis_tx_bb), 'r', 'LineWidth', 0.5);
        xlabel('时间 (ms)'); ylabel('幅度'); grid on;
        title('TX 基带 I/Q (WOLA窗后)'); legend('I','Q','FontSize',7);

        % (2,2) TX/RX通带包络对比
        subplot(3,2,4);
        env_tx = abs(hilbert(vis_frame_tx));
        plot(t_frame, env_tx, 'b', 'LineWidth', 0.6);
        if exist('vis_frame_rx','var')
            hold on;
            env_rx = abs(hilbert(vis_frame_rx));
            plot(t_frame, env_rx, 'Color',[0.85 0.33 0.1], 'LineWidth', 0.3);
            legend('TX','RX','FontSize',7);
        end
        xlabel('时间 (ms)'); ylabel('包络'); grid on;
        title('帧包络对比');

        % (3,1) TX通带频谱
        subplot(3,2,5);
        N_fft = length(vis_frame_tx);
        f_pb = (0:N_fft-1) * fs_pb / N_fft;
        S_tx = 20*log10(abs(fft(vis_frame_tx)) / N_fft + 1e-12);
        plot(f_pb/1000, S_tx, 'b', 'LineWidth', 0.8);
        xlabel('频率 (kHz)'); ylabel('dB'); grid on;
        title('TX 通带频谱'); xlim([0, fs_pb/2000]);
        hold on;
        xline((fc-sym_rate/2)/1000, 'g--', 'LineWidth',1);
        xline((fc+sym_rate/2)/1000, 'g--', 'LineWidth',1);

        % (3,2) RX通带频谱
        subplot(3,2,6);
        if exist('vis_frame_rx','var')
            S_rx = 20*log10(abs(fft(vis_frame_rx)) / N_fft + 1e-12);
            plot(f_pb/1000, S_rx, 'Color',[0.85 0.33 0.1], 'LineWidth', 0.8); hold on;
            plot(f_pb/1000, S_tx, 'b--', 'LineWidth', 0.4);
            legend('RX','TX','FontSize',7);
            title(sprintf('RX 通带频谱 @%ddB', snr_list(end)));
        else
            title('RX 频谱 (无数据)');
        end
        xlabel('频率 (kHz)'); ylabel('dB'); grid on;
        xlim([0, fs_pb/2000]);

        sgtitle(sprintf('OTFS 通带仿真 — N=%dx%d, %.0f bps, fc=%dkHz, BW=%dkHz', ...
            N, M, info_rate_bps, fc/1000, sym_rate/1000), 'FontSize',13);
    end

    % --- Figure 1: BER曲线 ---
    figure('Position',[50 550 700 400]);
    for fi=1:size(fading_cfgs,1)
        semilogy(snr_list, max(ber_matrix(fi,:),1e-5), markers{fi}, ...
            'Color',colors(fi,:),'LineWidth',1.8,'MarkerSize',7,'DisplayName',fading_cfgs{fi,1});
        hold on;
    end
    snr_lin=10.^(snr_list/10);
    semilogy(snr_list,max(0.5*erfc(sqrt(snr_lin)),1e-5),'k--','LineWidth',1,'DisplayName','QPSK AWGN');
    grid on; xlabel('SNR (dB)'); ylabel('BER');
    title(sprintf('OTFS %dx%d %s Turbo(%d) — %.0f bps', N, M, upper(eq_type), num_turbo, info_rate_bps));
    legend('Location','southwest'); ylim([1e-5 1]); set(gca,'FontSize',12);

    % --- Figure 2: DD域信道 真实vs估计 (前3配置 × 3列) ---
    n_vis = min(n_cfg, 3);  % 最多显示3行
    figure('Position',[50 50 1400 250*n_vis], 'Name','DD域信道: 真实 vs 估计');
    if ~isempty(pilot_info.positions)
        pk_pos = pilot_info.positions(1,1);
        pl_pos = pilot_info.positions(1,2);
    else
        pk_pos = ceil(N/2); pl_pos = ceil(M/2);
    end
    dk_range = -pilot_config.guard_k:pilot_config.guard_k;
    dl_range = -2:pilot_config.guard_l+3;
    cmax = max(abs(gains_raw)) * 1.1;

    for fi = 1:n_vis
        h_true = ch_diag(fi).h_true;
        h_est  = ch_diag(fi).h_est;
        pi_fi  = ch_diag(fi).path_info;
        crop_true = zeros(length(dk_range), length(dl_range));
        crop_est  = zeros(length(dk_range), length(dl_range));
        for i=1:length(dk_range)
            for j=1:length(dl_range)
                kk = mod(pk_pos-1+dk_range(i), N)+1;
                ll = mod(pl_pos-1+dl_range(j), M)+1;
                crop_true(i,j) = abs(h_true(kk, ll));
                crop_est(i,j)  = abs(h_est(kk, ll));
            end
        end
        subplot(n_vis,3,(fi-1)*3+1);
        imagesc(dl_range, dk_range, crop_true); axis xy; colorbar; clim([0 cmax]);
        ylabel('dk'); text(-1.5, dk_range(end)-0.5, fading_cfgs{fi,1}, 'FontSize',11, 'FontWeight','bold');
        if fi==1, title('真实DD信道'); end
        subplot(n_vis,3,(fi-1)*3+2);
        imagesc(dl_range, dk_range, crop_est); axis xy; colorbar; clim([0 cmax]);
        if fi==1, title('估计DD信道'); end
        subplot(n_vis,3,(fi-1)*3+3);
        dl_prof = 0:max(delay_bins)+4;
        prof_true = zeros(size(dl_prof)); prof_est = zeros(size(dl_prof));
        for j=1:length(dl_prof)
            ll = mod(pl_pos-1+dl_prof(j), M)+1;
            prof_true(j) = abs(h_true(pk_pos, ll));
            prof_est(j)  = abs(h_est(pk_pos, ll));
        end
        stem(dl_prof, prof_true, 'b-', 'LineWidth',1.5, 'MarkerSize',4); hold on;
        stem(dl_prof, prof_est, 'r:', 'LineWidth',1.5, 'MarkerSize',4);
        if fi==1, title('dk=0 延迟剖面'); legend('真实','估计','FontSize',7); end
        grid on;
    end
    sgtitle(sprintf('OTFS DD域信道诊断 (N=%d, M=%d)', N, M), 'FontSize',14);

    % --- Figure 3: Turbo收敛 ---
    figure('Position',[770 550 500 350]);
    for fi=1:size(fading_cfgs,1)
        for si=[2,3]
            trace = ber_turbo_trace{fi,si};
            if any(trace > 0)
                semilogy(1:num_turbo, max(trace,1e-5), [markers{fi}(1) '-'], ...
                    'Color',colors(fi,:),'LineWidth',1.2,'MarkerSize',6, ...
                    'DisplayName',sprintf('%s@%ddB',fading_cfgs{fi,1},snr_list(si)));
                hold on;
            end
        end
    end
    grid on; xlabel('Turbo迭代'); ylabel('BER');
    title('Turbo迭代收敛'); legend('Location','northeast'); set(gca,'FontSize',12);
catch ME
    fprintf('可视化异常: %s\n', ME.message);
end

fprintf('\n完成\n');

%% ========== 保存结果 ========== %%
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_otfs_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'OTFS 时变信道测试结果 V4.0 — %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
if passband_mode
    fprintf(fid, '模式: 通带 (sps=%d, fs_pb=%dHz, fc=%dHz)\n', sps, fs_pb, fc);
else
    fprintf(fid, '模式: 基带 (fs=%dHz)\n', sym_rate);
end
fprintf(fid, 'OTFS: N=%d, M=%d, CP=%d, 均衡=%s, Turbo=%d\n', N, M, cp_len, upper(eq_type), num_turbo);
fprintf(fid, '速率: %.0f bps (QPSK, R=1/%d, %d data slots)\n', info_rate_bps, n_code, N_data_slots);
fprintf(fid, '信道: %d径, delay_bins=[%s]\n', length(delay_bins), num2str(delay_bins));
fprintf(fid, 'Loopback误差: %.2e\n\n', err_loopback);

fprintf(fid, '=== BER (coded, Turbo %d轮) ===\n', num_turbo);
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-9s|', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end

fprintf(fid, '\n=== Turbo收敛轨迹 (每轮BER) ===\n');
for fi=1:size(fading_cfgs,1)
    for si=1:length(snr_list)
        trace = ber_turbo_trace{fi,si};
        fprintf(fid, '%s@%ddB:', fading_cfgs{fi,1}, snr_list(si));
        for t=1:num_turbo, fprintf(fid, ' %.2f%%', trace(t)*100); end
        fprintf(fid, '\n');
    end
end

fprintf(fid, '\n=== BER (uncoded) ===\n');
fprintf(fid, '%-8s |', '');
for si=1:length(snr_list), fprintf(fid, ' %6ddB', snr_list(si)); end
fprintf(fid, '\n%s\n', repmat('-',1,8+8*length(snr_list)));
for fi=1:size(fading_cfgs,1)
    fprintf(fid, '%-9s|', fading_cfgs{fi,1});
    for si=1:length(snr_list), fprintf(fid, ' %6.2f%%', ber_unc_matrix(fi,si)*100); end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('结果已保存: %s\n', result_file);

%% ========== 辅助函数：逐子块上变频(消除Gibbs振铃) ========== %%
function [pb_signal, bb_up] = otfs_to_passband(bb_signal, N, M, cp_len, sps, fs_pb, fc)
% 逐子块FFT上采样 + 升余弦过渡 + 上变频
% 关键: 每子块独立interpft, 避免跨子块Gibbs振铃
    sub_size = M + cp_len;
    sub_up = sub_size * sps;
    win_samp = 4 * sps;  % 过渡区样本数(通带率)
    taper_up = 0.5*(1 - cos(pi*(0:win_samp-1)/win_samp));
    taper_dn = 0.5*(1 + cos(pi*(0:win_samp-1)/win_samp));

    bb_up = zeros(1, N * sub_up);
    for n = 1:N
        offset_bb = (n-1) * sub_size;
        sub = bb_signal(offset_bb+1 : offset_bb+sub_size);
        sub_interp = interpft(sub, sub_up);  % 逐子块FFT插值

        % 升余弦过渡: CP首部上升, 数据尾部下降
        if n > 1
            sub_interp(1:win_samp) = sub_interp(1:win_samp) .* taper_up;
        end
        if n < N
            sub_interp(end-win_samp+1:end) = sub_interp(end-win_samp+1:end) .* taper_dn;
        end

        offset_up = (n-1) * sub_up;
        bb_up(offset_up+1 : offset_up+sub_up) = sub_interp;
    end

    % 上变频
    [pb_signal, ~] = upconvert(bb_up, fs_pb, fc);
end

%% ========== 辅助函数：逐子块下变频(匹配上变频) ========== %%
function bb_signal = passband_to_otfs(pb_segment, N, M, cp_len, sps, fs_pb, fc)
% 下变频 + 逐子块FFT降采样
    [bb_raw, ~] = downconvert(pb_segment, fs_pb, fc, fs_pb/(2*sps)*0.9);
    sub_size = M + cp_len;
    sub_up = sub_size * sps;
    bb_signal = zeros(1, N * sub_size);

    for n = 1:N
        offset_up = (n-1) * sub_up;
        if offset_up + sub_up <= length(bb_raw)
            sub_raw = bb_raw(offset_up+1 : offset_up+sub_up);
        else
            sub_raw = [bb_raw(offset_up+1:end), zeros(1, sub_up-(length(bb_raw)-offset_up))];
        end
        sub_down = interpft(sub_raw, sub_size);  % 逐子块FFT降采样
        bb_signal((n-1)*sub_size+1 : n*sub_size) = sub_down;
    end
end

%% ========== 辅助函数：信道施加 ========== %%
function rx = apply_channel(tx, delay_bins, gains_raw, ftype, fparams, fs, fc)
% 支持三种信道类型: static, discrete(固定Doppler), jakes(连续Doppler谱)
    tx = tx(:).';
    rx = zeros(size(tx));
    N_tx = length(tx);

    switch ftype
        case 'static'
            % 静态多径: h_p * x(n-d_p)
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                rx(d+1:end) = rx(d+1:end) + gains_raw(p) * tx(1:end-d);
            end

        case 'discrete'
            % 离散Doppler: h_p * exp(j2πν_p*n/fs) * x(n-d_p)
            % fparams = [ν_1, ν_2, ..., ν_P] (Hz)
            doppler_hz = fparams;
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                n_range = (d+1):N_tx;
                phase = exp(1j * 2 * pi * doppler_hz(p) * (n_range-1) / fs);
                rx(n_range) = rx(n_range) + gains_raw(p) * phase .* tx(n_range-d);
            end

        case 'hybrid'
            % Rician混合: 离散Doppler(强) + Jakes散射(弱)
            % h_p(t) = h_p * exp(j2πν_p*t) * [√(K/(K+1)) + √(1/(K+1))*g(t)]
            % g(t) = Jakes过程(fd_scatter), 散射Doppler谱以ν_p为中心
            doppler_hz = fparams.doppler_hz;
            fd_sc = fparams.fd_scatter;
            K = fparams.K_rice;
            spec_amp = sqrt(K / (K+1));      % 直达(谱)分量幅度
            scat_amp = sqrt(1 / (K+1));       % 散射分量幅度
            t = (0:N_tx-1) / fs;
            N_osc = 8;
            rng_state = rng;  % 保存
            rng(43);          % 固定seed保证可复现
            for p = 1:length(delay_bins)
                d = delay_bins(p);
                n_range = (d+1):N_tx;
                t_r = t(n_range);
                % 离散Doppler相位
                phase_disc = exp(1j * 2*pi * doppler_hz(p) * t_r);
                % Jakes散射 (单位功率, 以ν_p为中心)
                g_scat = zeros(1, length(n_range));
                for n_osc = 1:N_osc
                    theta = 2*pi*rand;
                    beta = pi*n_osc / N_osc;
                    g_scat = g_scat + exp(1j*(2*pi*fd_sc*cos(beta)*t_r + theta));
                end
                g_scat = g_scat / sqrt(N_osc);
                % Rician组合: 稳定谱 + 弱散射, 再乘离散Doppler
                h_tv = gains_raw(p) * phase_disc .* (spec_amp + scat_amp * g_scat);
                rx(n_range) = rx(n_range) + h_tv .* tx(n_range-d);
            end
            rng(rng_state);  % 恢复

        case 'jakes'
            % Jakes衰落: fparams = fd_hz (最大多普勒频移)
            fd_hz = fparams;
            delays_s = delay_bins / fs;
            ch_params = struct('fs',fs, 'delay_profile','custom', ...
                'delays_s',delays_s, 'gains',gains_raw, ...
                'num_paths',length(delay_bins), 'doppler_rate',fd_hz/fc, ...
                'fading_type','slow', 'fading_fd_hz',fd_hz, ...
                'snr_db',Inf, 'seed',42);
            [rx,~] = gen_uwa_channel(tx, ch_params);

        otherwise
            error('不支持的信道类型: %s', ftype);
    end
end
