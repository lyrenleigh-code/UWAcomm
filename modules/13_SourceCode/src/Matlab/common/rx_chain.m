function [bits_out, rx_info] = rx_chain(rx_signal, params, tx_info, ch_info)
% 功能：通用接收链路——6种体制统一入口
% 版本：V1.0.0
% 输入：
%   rx_signal - 接收基带信号 (1×N)
%   params    - 系统参数（由sys_params生成）
%   tx_info   - 发射端信息（由tx_chain生成，含training/perm等）
%   ch_info   - 信道信息（由gen_uwa_channel生成）
% 输出：
%   bits_out  - 译码后信息比特
%   rx_info   - 接收端信息结构体
%       .ber_info   : 信息比特BER
%       .ber_sym    : 符号BER（如可计算）
%       .eq_output  : 均衡输出符号
%       .scheme     : 体制名称

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '12_IterativeProc', 'src', 'Matlab'));

rx_info.scheme = params.scheme;
noise_var = ch_info.noise_var;
if noise_var == 0, noise_var = 1e-10; end

%% ========== 通带→基带（下变频+匹配滤波+定时+下采样） ========== %%
is_real_otfs = strcmpi(params.scheme, 'OTFS') && ...
    isfield(params, 'rx') && isfield(params.rx, 'otfs_mode') && ...
    strcmpi(params.rx.otfs_mode, 'real');
if isfield(tx_info, 'is_passband') && tx_info.is_passband && ~is_real_otfs
    sps = params.waveform.sps;
    span = params.waveform.span;

    % 下变频：通带实信号 → 复基带
    lpf_bw = params.sym_rate * (1 + params.waveform.rolloff);
    [bb_raw, ~] = downconvert(rx_signal, params.fs_passband, params.fc, lpf_bw);

    if false
        % OTFS通带占位（OTFS走DD域直接模式，不经此路径）
        N_ot = params.tx.N_doppler;
        M_ot = params.tx.M_delay;
        cp_sym = params.tx.cp_len;
        otfs_sps = tx_info.otfs_sps;
        n_up = N_ot * M_ot * otfs_sps;
        cp_up = cp_sym * otfs_sps;

        % 相关定时：用TX上采样基带信号找帧起始（补偿LPF群延迟）
        ref = tx_info.shaped_baseband;
        ref_seg = ref(1:min(2*M_ot*otfs_sps, length(ref)));
        search_range = min(cp_up*3, length(bb_raw)-length(ref_seg));
        best_off = 0; best_corr = 0;
        for off = 0:search_range
            if off+length(ref_seg) > length(bb_raw), break; end
            seg = bb_raw(off+1 : off+length(ref_seg));
            c = abs(sum(seg .* conj(ref_seg)));
            if c > best_corr, best_corr = c; best_off = off; end
        end

        % 从帧起始跳过CP，提取数据帧
        frame_start = best_off + cp_up + 1;
        if frame_start+n_up-1 <= length(bb_raw)
            bb_frame = bb_raw(frame_start : frame_start+n_up-1);
        else
            bb_frame = bb_raw(min(frame_start,end):end);
            bb_frame = [bb_frame, zeros(1, n_up-length(bb_frame))];
        end

        % 每时隙频域截断下采样
        rx_sym_mat = zeros(N_ot, M_ot);
        for n = 1:N_ot
            slot = bb_frame((n-1)*M_ot*otfs_sps+1 : n*M_ot*otfs_sps);
            S = fft(slot);
            S_trunc = zeros(1, M_ot);
            S_trunc(1:M_ot/2) = S(1:M_ot/2);
            S_trunc(M_ot/2+1:M_ot) = S(end-M_ot/2+1:end);
            rx_sym_mat(n,:) = ifft(S_trunc) / otfs_sps;
        end

        % 重组为时域 + CP占位 → otfs_demodulate
        rx_time = zeros(1, N_ot*M_ot);
        for n = 1:N_ot
            rx_time((n-1)*M_ot+1:n*M_ot) = rx_sym_mat(n,:);
        end
        rx_signal = [zeros(1, cp_sym), rx_time];
        rx_info.baseband_recovered = rx_signal;
    else

    % 匹配滤波（RRC）
    sps = params.waveform.sps;
    span = params.waveform.span;
    [bb_filtered, ~] = match_filter(bb_raw, sps, ...
        params.waveform.filter_type, params.waveform.rolloff, span);

    % 最优采样点搜索（在一个符号周期内遍历）
    best_off = 0;
    best_power = 0;
    ref_sym = tx_info.baseband_signal;
    N_ref = min(20, length(ref_sym));  % 用前20个符号做参考
    for off = 0 : sps-1
        sym_test = bb_filtered(off+1 : sps : end);
        if length(sym_test) >= N_ref
            % 选择使恢复符号与参考符号相关性最大的偏移
            corr_val = abs(sum(sym_test(1:N_ref) .* conj(ref_sym(1:N_ref))));
            if corr_val > best_power
                best_power = corr_val;
                best_off = off;
            end
        end
    end

    % 下采样
    rx_downsampled = bb_filtered(best_off+1 : sps : end);

    % 截断到原始符号长度
    N_orig = length(tx_info.baseband_signal);
    if length(rx_downsampled) > N_orig
        rx_signal = rx_downsampled(1:N_orig);
    elseif length(rx_downsampled) < N_orig
        rx_signal = [rx_downsampled, zeros(1, N_orig - length(rx_downsampled))];
    else
        rx_signal = rx_downsampled;
    end
    rx_info.baseband_recovered = rx_signal;
    end  % if otfs_no_rrc else
end

%% ========== 体制分发 ========== %%
switch upper(params.scheme)
    case 'SC-TDE'
        bits_out = rx_sctde(rx_signal, params, tx_info, ch_info);

    case 'SC-FDE'
        bits_out = rx_scfde(rx_signal, params, tx_info, ch_info);

    case 'OFDM'
        bits_out = rx_ofdm(rx_signal, params, tx_info, ch_info);

    case 'OTFS'
        bits_out = rx_otfs(rx_signal, params, tx_info, ch_info);

    case 'DSSS'
        bits_out = rx_dsss(rx_signal, params, tx_info, ch_info);

    case 'FH-MFSK'
        bits_out = rx_fhmfsk(rx_signal, params, tx_info, ch_info);

    otherwise
        error('不支持的接收体制: %s', params.scheme);
end

%% ========== BER计算 ========== %%
n_cmp = min(length(bits_out), length(tx_info.info_bits));
if n_cmp > 0
    rx_info.ber_info = mean(bits_out(1:n_cmp) ~= tx_info.info_bits(1:n_cmp));
else
    rx_info.ber_info = 1;
end

end

%% ================================================================== %%
%%                         各体制接收实现                              %%
%% ================================================================== %%

function bits_out = rx_scfde(rx_signal, params, tx_info, ch_info)
    % 去CP → FFT → Turbo均衡
    cp_len = params.tx.cp_len;
    N_fft = params.tx.N_fft;

    % 去CP
    if length(rx_signal) >= cp_len + N_fft
        rx_block = rx_signal(cp_len+1 : cp_len+N_fft);
    else
        rx_block = rx_signal(1:min(length(rx_signal), N_fft));
        rx_block = [rx_block, zeros(1, N_fft - length(rx_block))];
    end
    Y_freq = fft(rx_block);

    % 信道频域响应（从已知信道参数重建）
    H_est = build_H_est(ch_info, N_fft, params);

    % Turbo均衡
    [bits_out, ~] = turbo_equalizer_scfde(Y_freq, H_est, params.rx.turbo_iter, ...
        ch_info.noise_var, params.codec);
end

function bits_out = rx_ofdm(rx_signal, params, tx_info, ch_info)
    % 全块处理（同SC-FDE）：去CP → FFT → Turbo均衡
    cp_len = params.tx.cp_len;
    N_fft = params.tx.N_fft;

    if length(rx_signal) >= cp_len + N_fft
        rx_block = rx_signal(cp_len+1 : cp_len+N_fft);
    else
        rx_block = rx_signal(1:min(length(rx_signal), N_fft));
        rx_block = [rx_block, zeros(1, N_fft - length(rx_block))];
    end
    Y_freq = fft(rx_block);
    H_est = build_H_est(ch_info, N_fft, params);

    [bits_out, ~] = turbo_equalizer_ofdm(Y_freq, H_est, params.rx.turbo_iter, ...
        ch_info.noise_var, params.codec);
end

function bits_out = rx_sctde(rx_signal, params, tx_info, ch_info)
    training = tx_info.training;
    h_est = ch_info.gains_init(1:min(ch_info.num_paths, 10));

    % 截断接收信号到发射长度
    N_tx = length(training) + length(tx_info.symbols);
    rx_trunc = rx_signal(1:min(length(rx_signal), N_tx));
    if length(rx_trunc) < N_tx
        rx_trunc = [rx_trunc, zeros(1, N_tx - length(rx_trunc))];
    end

    % 构建时域信道估计（用符号级时延）
    if isfield(params.channel, 'sym_delays')
        sd = params.channel.sym_delays;
    else
        sd = round(ch_info.delays_samp / params.waveform.sps);
    end
    h_full = zeros(1, max(sd)+1);
    for p = 1:ch_info.num_paths
        h_full(sd(p)+1) = ch_info.gains_init(p);
    end

    [bits_out, ~] = turbo_equalizer_sctde(rx_trunc, h_full, training, ...
        params.rx.turbo_iter, ch_info.noise_var, params.rx.eq_params, params.codec);
end

function bits_out = rx_otfs(rx_signal, params, tx_info, ch_info)
%% ⚠️ ORACLE BASELINE — 由 params.rx.otfs_mode 选择路径
%  默认 'oracle': 多重 oracle 泄漏，仅用作性能上界基准（见下方 ORACLE 标注）
%  'real':       走真实接收（否则需 main_sim_single 同时开启 passband 路径）
%
%  真实接收路径参考 test_otfs_timevarying.m，需要 rx_signal 为通带信号（非占位）：
%    - bb_rx = downconvert(rx_signal, fs_pb, fc)
%    - [Y_dd, ~] = otfs_demodulate(bb_rx, N, M, cp_len, 'dft')
%    - [h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M)
%    - guard 区能量 → noise_var
%    - 送 turbo_equalizer_otfs
%  生产用户应直接用 test_otfs_timevarying 的完整路径。
%
%  main_sim_single DD 模式（`rx_signal = tx_signal` 占位）**本质就是 oracle 模式**，
%  无法通过本函数 'real' 开关简单切换。真正的去 oracle 需要 main_sim_single 重构
%  （独立 spec，2026-04-13-otfs-sync-architecture.md 的 DD→通带 集成）。
%
%  违反 CLAUDE.md §2/§7 第 2/3/4/6 条（接收端使用 TX 数据/真实信道/SNR）
if isfield(params, 'rx') && isfield(params.rx, 'otfs_mode') && ...
   strcmpi(params.rx.otfs_mode, 'real')
    bits_out = rx_otfs_real(rx_signal, params, tx_info, ch_info);
    return;
end
% 以下是 ORACLE BASELINE 路径（默认）
    N = params.tx.N_doppler;
    M = params.tx.M_delay;

    % DD域信道参数（ORACLE：真实时延/增益）
    if isfield(params.channel, 'sym_delays')
        sd = params.channel.sym_delays;   % ORACLE
    else
        sd = round(ch_info.delays_samp / params.waveform.sps);
    end
    gains = ch_info.gains_init;            % ORACLE

    % DD域直接模式：在此施加信道（circshift）+ 噪声（ORACLE：tx_info.dd_data + SNR）
    dd_data = tx_info.dd_data;             % ORACLE
    Y_dd = zeros(N, M);
    for p = 1:ch_info.num_paths
        Y_dd = Y_dd + gains(p) * circshift(dd_data, [0, sd(p)]);
    end
    sig_pwr = mean(abs(Y_dd(:)).^2);
    nv = sig_pwr * 10^(-params.snr_db/10); % ORACLE
    Y_dd = Y_dd + sqrt(nv/2)*(randn(N,M)+1j*randn(N,M));

    h_dd = zeros(N, M);
    path_info = struct('num_paths', ch_info.num_paths, ...
        'delay_idx', sd, ...
        'doppler_idx', zeros(1, ch_info.num_paths), ...
        'gain', gains);
    for p = 1:ch_info.num_paths
        dl = mod(sd(p), M);
        h_dd(1, dl+1) = gains(p);
    end

    codec_otfs = params.codec;
    if isfield(params.rx, 'mp_iters')
        codec_otfs.mp_iters = params.rx.mp_iters;
    end
    [bits_out, ~] = turbo_equalizer_otfs(Y_dd, h_dd, path_info, N, M, ...
        params.rx.turbo_iter, nv, codec_otfs);
end

function bits_out = rx_dsss(rx_signal, params, tx_info, ch_info)
    % 简化DSSS：相关解扩 → Viterbi译码
    code = tx_info.spread_code;
    spread_len = length(code);
    N_sym = floor(length(rx_signal) / spread_len);

    % 相关解扩
    despread = zeros(1, N_sym);
    for k = 1:N_sym
        chunk = rx_signal((k-1)*spread_len+1 : k*spread_len);
        despread(k) = real(chunk * code') / spread_len;
    end

    % BPSK → LLR → Viterbi
    nv = max(ch_info.noise_var, 1e-10);
    LLR = 2 * despread / nv;

    [~, trellis] = conv_encode(zeros(1,10), params.codec.gen_polys, params.codec.constraint_len);

    % 解交织
    M_coded = length(tx_info.interleaved);
    if length(LLR) > M_coded, LLR = LLR(1:M_coded);
    elseif length(LLR) < M_coded, LLR = [LLR, zeros(1, M_coded-length(LLR))]; end
    LLR_deint = random_deinterleave(LLR, tx_info.perm);

    [bits_out, ~] = viterbi_decode(LLR_deint, trellis, 'soft');
end

function bits_out = rx_fhmfsk(rx_signal, params, tx_info, ch_info)
    % 简化FH-MFSK：能量检测 → 硬判决 → Viterbi
    M_fsk = params.tx.M_fsk;
    bits_per_sym = tx_info.bits_per_sym;
    samples_per_hop = tx_info.samples_per_hop;
    N_sym = floor(length(rx_signal) / samples_per_hop);

    detected_bits = [];
    for k = 1:N_sym
        chunk = rx_signal((k-1)*samples_per_hop+1 : min(k*samples_per_hop, length(rx_signal)));
        if length(chunk) < samples_per_hop
            chunk = [chunk, zeros(1, samples_per_hop - length(chunk))];
        end
        % 能量检测各频率
        energies = zeros(1, M_fsk);
        for m = 0:M_fsk-1
            f_test = (m + 0.5) * params.tx.hop_bw;
            t = (0:samples_per_hop-1) / params.fs;
            ref = exp(-2j*pi*f_test*t);
            energies(m+1) = abs(sum(chunk .* ref))^2;
        end
        [~, best] = max(energies);
        det_bits = de2bi(best-1, bits_per_sym, 'left-msb');
        detected_bits = [detected_bits, det_bits]; %#ok<AGROW>
    end

    % 解交织 → Viterbi
    M_coded = length(tx_info.interleaved);
    if length(detected_bits) > M_coded, detected_bits = detected_bits(1:M_coded);
    elseif length(detected_bits) < M_coded, detected_bits = [detected_bits, zeros(1, M_coded-length(detected_bits))]; end
    bits_deint = random_deinterleave(detected_bits, tx_info.perm);

    [~, trellis] = conv_encode(zeros(1,10), params.codec.gen_polys, params.codec.constraint_len);
    [bits_out, ~] = viterbi_decode(2*bits_deint-1, trellis, 'soft');
end

%% ================================================================== %%
%%                           公共辅助函数                              %%
%% ================================================================== %%

function H_est = build_H_est(ch_info, N_fft, params)
% 从信道信息构建频域响应（符号级整数时延）
    h_td = zeros(1, N_fft);
    % 优先用符号级时延（通带仿真下采样后的时延）
    if nargin >= 3 && isfield(params, 'channel') && isfield(params.channel, 'sym_delays')
        sym_delays = params.channel.sym_delays;
    else
        % 回退：用采样时延除以sps
        if nargin >= 3 && isfield(params, 'waveform')
            sym_delays = round(ch_info.delays_samp / params.waveform.sps);
        else
            sym_delays = ch_info.delays_samp;
        end
    end
    for p = 1:ch_info.num_paths
        d = sym_delays(min(p, length(sym_delays)));
        if d+1 <= N_fft
            h_td(d+1) = ch_info.gains_init(p);
        end
    end
    H_est = fft(h_td);
end


%% ============================================================
%% rx_otfs_real — 真实接收链路（无 oracle）
%% 参考 test_otfs_timevarying.m 的完整路径
%% ============================================================
function bits_out = rx_otfs_real(rx_signal, params, tx_info, ch_info)
    N = params.tx.N_doppler;
    M = params.tx.M_delay;
    cp_len = params.tx.cp_len;

    if ~isfield(tx_info, 'frame_info')
        error('rx_otfs_real:missing_frame_info', ...
            'tx_info.frame_info is required for real OTFS frame parsing.');
    end
    if ~isfield(tx_info, 'otfs_pilot_info') || ~isfield(tx_info, 'otfs_data_indices')
        error('rx_otfs_real:missing_pilot_info', ...
            'Real OTFS requires tx_info.otfs_pilot_info and tx_info.otfs_data_indices.');
    end

    [otfs_bb, ~] = frame_parse_otfs(rx_signal, tx_info.frame_info);
    [Y_dd, ~] = otfs_demodulate(otfs_bb, N, M, cp_len, 'dft');

    pilot_info = tx_info.otfs_pilot_info;
    data_indices = tx_info.otfs_data_indices(:).';
    if isfield(tx_info, 'otfs_guard_mask')
        guard_mask = tx_info.otfs_guard_mask;
    else
        guard_mask = true(N, M);
        guard_mask(data_indices) = false;
    end

    pilot_mode = 'impulse';
    if isfield(pilot_info, 'mode') && ~isempty(pilot_info.mode)
        pilot_mode = lower(pilot_info.mode);
    end
    if isfield(params.tx, 'pilot_config')
        pilot_config = params.tx.pilot_config;
    else
        pilot_config = struct('guard_k',4, 'guard_l',10);
    end

    switch pilot_mode
        case 'impulse'
            [h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M);
        case 'sequence'
            [h_dd, path_info] = ch_est_otfs_zc(Y_dd, pilot_info, N, M);
        case 'superimposed'
            [h_dd, path_info] = ch_est_otfs_superimposed(Y_dd, pilot_info, N, M, ...
                struct('iter',3, 'guard_k',4, 'guard_l',10));
        otherwise
            error('rx_otfs_real:unsupported_pilot', ...
                'Unsupported OTFS pilot mode: %s', pilot_mode);
    end

    nv_dd = max(ch_info.noise_var, 1e-8);
    if strcmp(pilot_mode, 'impulse') && isfield(pilot_config, 'guard_k') && ...
            isfield(pilot_config, 'guard_l') && ~isempty(pilot_info.positions)
        pk_pos = pilot_info.positions(1,1);
        pl_pos = pilot_info.positions(1,2);
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

    Y_dd_eq = Y_dd;
    switch pilot_mode
        case {'impulse', 'sequence'}
            for pp = 1:path_info.num_paths
                dl_p = path_info.delay_idx(pp);
                dk_p = path_info.doppler_idx(pp);
                for pc_i = 1:size(pilot_info.positions, 1)
                    pk_c = pilot_info.positions(pc_i, 1);
                    pl_c = pilot_info.positions(pc_i, 2);
                    pv_c = pilot_info.values(min(pc_i, numel(pilot_info.values)));
                    kk_r = mod(pk_c-1+dk_p, N)+1;
                    ll_r = mod(pl_c-1+dl_p, M)+1;
                    Y_dd_eq(kk_r, ll_r) = Y_dd_eq(kk_r, ll_r) - path_info.gain(pp) * pv_c;
                end
            end
        case 'superimposed'
            h_origin = zeros(N, M);
            for pp = 1:path_info.num_paths
                kk_o = mod(path_info.doppler_idx(pp), N) + 1;
                ll_o = mod(path_info.delay_idx(pp), M) + 1;
                h_origin(kk_o, ll_o) = path_info.gain(pp);
            end
            Y_dd_eq = Y_dd - ifft2(fft2(pilot_info.pilot_pattern) .* fft2(h_origin));
    end

    constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
    M_coded = length(tx_info.interleaved);
    N_data_slots = length(data_indices);
    num_turbo = max(1, params.rx.turbo_iter);
    eq_type = 'lmmse';
    if isfield(params.rx, 'eq_type') && ~isempty(params.rx.eq_type)
        eq_type = lower(params.rx.eq_type);
    end
    uamp_inner = 5;
    if isfield(params.rx, 'uamp_inner') && ~isempty(params.rx.uamp_inner)
        uamp_inner = params.rx.uamp_inner;
    end

    prior_mean = [];
    prior_var = [];
    bits_out = zeros(1, params.N_info);
    for turbo_iter = 1:num_turbo
        if strcmp(eq_type, 'uamp')
            [~, ~, x_mean, eq_info] = eq_otfs_uamp(Y_dd_eq, h_dd, path_info, N, M, ...
                nv_dd, uamp_inner, constellation, prior_mean, prior_var);
        else
            [~, ~, x_mean, eq_info] = eq_otfs_lmmse(Y_dd_eq, h_dd, path_info, N, M, ...
                nv_dd, 1, constellation, prior_mean, prior_var);
        end

        x_data_soft = x_mean(data_indices);
        nv_llr = max(eq_info.nv_post, 1e-8);
        LLR_eq = zeros(1, M_coded);
        n_llr_sym = min(N_data_slots, floor(M_coded / 2));
        for k = 1:n_llr_sym
            LLR_eq(2*k-1) = -2*sqrt(2)*real(x_data_soft(k)) / nv_llr;
            LLR_eq(2*k)   = -2*sqrt(2)*imag(x_data_soft(k)) / nv_llr;
        end
        LLR_eq = max(min(LLR_eq, 30), -30);

        LLR_coded = random_deinterleave(LLR_eq, tx_info.perm);
        [~, Lp_info, Lp_coded] = siso_decode_conv(LLR_coded, [], ...
            params.codec.gen_polys, params.codec.constraint_len, params.codec.decode_mode);
        bits_out = double(Lp_info > 0);

        if turbo_iter < num_turbo
            Lp_coded_inter = random_interleave(Lp_coded, params.codec.interleave_seed);
            if length(Lp_coded_inter) < M_coded
                Lp_coded_pad = zeros(1, M_coded);
                Lp_coded_pad(1:length(Lp_coded_inter)) = Lp_coded_inter;
                Lp_coded_inter = Lp_coded_pad;
            else
                Lp_coded_inter = Lp_coded_inter(1:M_coded);
            end
            [x_bar, var_x] = soft_mapper(Lp_coded_inter, 'qpsk');
            var_x = max(var_x, nv_dd);
            prior_mean = zeros(N, M);
            prior_var = var_x * ones(N, M);
            n_fill = min(length(x_bar), N_data_slots);
            prior_mean(data_indices(1:n_fill)) = x_bar(1:n_fill);
            prior_var(guard_mask) = var_x;
        end
    end
    return;
end
