function [tx_signal, tx_info] = tx_chain(params)
% 功能：通用发射链路——6种体制统一入口
% 版本：V1.0.0
% 输入：
%   params    - 系统参数（由sys_params生成）
% 输出：
%   tx_signal - 发射基带信号 (1×N 复数)
%   tx_info   - 发射端信息结构体
%       .info_bits      : 原始信息比特
%       .coded_bits     : 编码后比特
%       .interleaved    : 交织后比特
%       .symbols        : 调制符号
%       .perm           : 交织置换（解交织用）
%       .training       : 训练序列（SC-TDE用）
%       .tx_data_only   : 纯数据信号（不含CP/训练，信道估计参考用）
%
% 备注：
%   链路：信息比特 → 信道编码 → 交织 → 调制 → [扩频] → [CP/训练/帧结构] → 发射

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

%% ========== 1. 信息比特生成 ========== %%
info_bits = randi([0 1], 1, params.N_info);

%% ========== 2. 信道编码 ========== %%
coded_bits = conv_encode(info_bits, params.codec.gen_polys, params.codec.constraint_len);

%% ========== 3. 交织 ========== %%
% 确定目标编码比特长度
switch upper(params.scheme)
    case 'SC-TDE'
        N_data_sym = floor(length(coded_bits) / params.mod.bits_per_sym);
        M_coded = N_data_sym * params.mod.bits_per_sym;
    case {'SC-FDE', 'OFDM'}
        M_coded = params.mod.bits_per_sym * params.tx.N_fft;
        if strcmpi(params.scheme, 'OFDM') && isfield(params.tx, 'N_data_sc')
            M_coded = params.mod.bits_per_sym * params.tx.N_data_sc;
        end
    case 'OTFS'
        otfs_real_mode = isfield(params, 'rx') && isfield(params.rx, 'otfs_mode') && ...
            strcmpi(params.rx.otfs_mode, 'real');
        if otfs_real_mode && isfield(params.tx, 'N_data_slots')
            M_coded = params.mod.bits_per_sym * params.tx.N_data_slots;
        else
            M_coded = params.mod.bits_per_sym * params.tx.N_doppler * params.tx.M_delay;
        end
    otherwise
        M_coded = length(coded_bits);
end

% 截断/填充
if length(coded_bits) > M_coded
    coded_bits = coded_bits(1:M_coded);
elseif length(coded_bits) < M_coded
    coded_bits = [coded_bits, zeros(1, M_coded - length(coded_bits))];
end

[interleaved, perm] = random_interleave(coded_bits, params.codec.interleave_seed);

%% ========== 4. 调制 ========== %%
switch params.mod.type
    case 'qpsk'
        symbols = bits2qpsk(interleaved);
    case 'bpsk'
        symbols = 2*interleaved - 1;
    case 'mfsk'
        symbols = interleaved;  % FH-MFSK特殊处理
    otherwise
        symbols = bits2qpsk(interleaved);
end

%% ========== 5. 体制特有处理 ========== %%
switch upper(params.scheme)
    case 'SC-TDE'
        % [训练序列, 数据符号]
        training = constellation(randi(4, 1, params.tx.train_len));
        tx_signal = [training, symbols];
        tx_info.training = training;
        tx_info.tx_data_only = symbols;

    case 'SC-FDE'
        % 零填充到N_fft + 加CP
        N_fft = params.tx.N_fft;
        x_block = zeros(1, N_fft);
        x_block(1:min(length(symbols), N_fft)) = symbols(1:min(length(symbols), N_fft));
        cp = x_block(end-params.tx.cp_len+1:end);
        tx_signal = [cp, x_block];
        tx_info.training = [];
        tx_info.tx_data_only = x_block;

    case 'OFDM'
        % 全块处理（同SC-FDE）：时域数据+CP，接收端FFT→MMSE→IFFT
        N_fft = params.tx.N_fft;
        x_block = zeros(1, N_fft);
        x_block(1:min(length(symbols), N_fft)) = symbols(1:min(length(symbols), N_fft));
        cp = x_block(end-params.tx.cp_len+1:end);
        tx_signal = [cp, x_block];
        tx_info.training = [];
        tx_info.tx_data_only = x_block;

    case 'OTFS'
        % OTFS：DD域数据→ISFFT→时域+CP
        N = params.tx.N_doppler;
        M = params.tx.M_delay;
        cp_len = params.tx.cp_len;
        otfs_real_mode = isfield(params, 'rx') && isfield(params.rx, 'otfs_mode') && ...
            strcmpi(params.rx.otfs_mode, 'real');

        if otfs_real_mode
            if isfield(params.tx, 'pilot_config')
                pilot_config = params.tx.pilot_config;
            else
                pilot_config = struct('mode','impulse', 'guard_k',4, 'guard_l',10, ...
                    'pilot_value',1);
                [~,~,~,tmp_data_idx] = otfs_pilot_embed(zeros(1,1), N, M, pilot_config);
                pilot_config.pilot_value = sqrt(length(tmp_data_idx));
            end
            [dd_data, pilot_info, guard_mask, data_indices] = ...
                otfs_pilot_embed(symbols, N, M, pilot_config);
            [tx_signal, otfs_mod_info] = otfs_modulate(dd_data, N, M, cp_len, 'dft');
            tx_info.otfs_pilot_info = pilot_info;
            tx_info.otfs_guard_mask = guard_mask;
            tx_info.otfs_data_indices = data_indices;
            tx_info.otfs_mod_info = otfs_mod_info;
        else
            n_dd = N * M;
            dd_vec = zeros(1, n_dd);
            dd_vec(1:min(length(symbols), n_dd)) = symbols(1:min(length(symbols), n_dd));
            dd_data = reshape(dd_vec, M, N).';  % NxM
            [tx_signal, otfs_mod_info] = otfs_modulate(dd_data, N, M, cp_len, 'dft');
            tx_info.dd_vec = dd_vec;
            tx_info.otfs_mod_info = otfs_mod_info;
        end

        tx_info.training = [];
        tx_info.tx_data_only = tx_signal;
        tx_info.dd_data = dd_data;

    case 'DSSS'
        % BPSK扩频
        spread_len = params.tx.spread_len;
        code = 2*randi([0 1], 1, spread_len) - 1;  % 扩频码
        tx_chips = kron(symbols, code);
        tx_signal = tx_chips;
        tx_info.training = [];
        tx_info.tx_data_only = tx_chips;
        tx_info.spread_code = code;

    case 'FH-MFSK'
        % 简化FH-MFSK：每跳选频率
        M_fsk = params.tx.M_fsk;
        bits_per_sym = log2(M_fsk);
        N_sym = floor(length(interleaved) / bits_per_sym);
        tx_freqs = zeros(1, N_sym);
        for k = 1:N_sym
            b = interleaved((k-1)*bits_per_sym+1 : k*bits_per_sym);
            tx_freqs(k) = bi2de(b(:)', 'left-msb');
        end
        % 简化：直接输出频率索引序列（不做实际调制）
        samples_per_hop = round(params.fs / params.tx.hop_bw);
        tx_signal = zeros(1, N_sym * samples_per_hop);
        for k = 1:N_sym
            f_hop = (tx_freqs(k) + 0.5) * params.tx.hop_bw;
            t = (0:samples_per_hop-1) / params.fs;
            tx_signal((k-1)*samples_per_hop+1 : k*samples_per_hop) = exp(2j*pi*f_hop*t);
        end
        tx_info.training = [];
        tx_info.tx_data_only = tx_signal;
        tx_info.tx_freqs = tx_freqs;
        tx_info.bits_per_sym = bits_per_sym;
        tx_info.samples_per_hop = samples_per_hop;

    otherwise
        tx_signal = symbols;
        tx_info.training = [];
        tx_info.tx_data_only = symbols;
end

%% ========== 6. 保存公共信息 ========== %%
tx_info.info_bits = info_bits;
tx_info.coded_bits = coded_bits;
tx_info.interleaved = interleaved;
tx_info.symbols = symbols;
tx_info.perm = perm;
tx_info.baseband_signal = tx_signal;  % 保存复基带信号

%% ========== 7. 脉冲成形 + 上变频（生成通带实信号） ========== %%
if strcmpi(params.scheme, 'OTFS')
    otfs_real_mode = isfield(params, 'rx') && isfield(params.rx, 'otfs_mode') && ...
        strcmpi(params.rx.otfs_mode, 'real');
    if otfs_real_mode
        frame_p = struct('N',params.tx.N_doppler, ...
            'M',params.tx.M_delay, ...
            'cp_len',params.tx.cp_len, ...
            'sps',params.waveform.sps, ...
            'fs_bb',params.sym_rate, ...
            'fc',params.fc, ...
            'bw',params.sym_rate * 1.3, ...
            'T_hfm',0.05, ...
            'T_lfm',0.02, ...
            'guard_ms',5, ...
            'sync_gain',0.7);
        [passband, frame_info] = frame_assemble_otfs(tx_signal, frame_p);
        tx_signal = passband;
        tx_info.passband_signal = passband;
        tx_info.frame_info = frame_info;
        tx_info.is_passband = true;
        tx_info.otfs_dd_mode = false;
    else
        % Legacy oracle baseline: DD-domain channel is applied in rx_chain.
        tx_info.is_passband = false;
        tx_info.otfs_dd_mode = true;
    end
elseif true
    % 其他体制：RRC脉冲成形+上变频

    % 脉冲成形（上采样+RRC）
    [shaped, tx_info.filter_coeff, ~] = pulse_shape(tx_signal, ...
        params.waveform.sps, params.waveform.filter_type, ...
        params.waveform.rolloff, params.waveform.span);

    % 上变频：复基带 → 通带实信号
    [passband, tx_info.t_passband] = upconvert(shaped, params.fs_passband, params.fc);
    tx_signal = passband;           % 覆盖为通带实信号
    tx_info.passband_signal = passband;
    tx_info.shaped_baseband = shaped;
    tx_info.is_passband = true;
end

end
