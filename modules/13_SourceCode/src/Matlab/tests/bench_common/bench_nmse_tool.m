function nmse_db = bench_nmse_tool(h_est, h_true, opts)
% 功能：信道估计 NMSE（dB），处理体制间对齐差异
% 版本：V1.0.0
% 输入：
%   h_est  - 估计信道（形式因体制而异）：
%              * SC-FDE/SC-TDE 时域稀疏抽头 [K × N_sym] 或 [K × 1]
%              * OFDM 频域 CFR [N_fft × N_blk] 或 [N_fft × 1]
%              * OTFS DD 域 [N_dop × N_del]
%   h_true - gen_uwa_channel 输出 ch_info.h_time [num_paths × N_tx]
%   opts   - struct：
%              .type           'time_sparse' | 'freq_cfr' | 'dd_grid'
%              .delays_samp    稀疏抽头对应的采样点时延（time_sparse 必需）
%              .fft_len        FFT 长度（freq_cfr 必需）
%              .sample_idx     h_est 对应 h_true 的采样时刻索引（可选，默认取中点）
% 输出：
%   nmse_db - NMSE（dB）；h_est 为空/尺寸异常时返回 NaN
%
% 备注：
%   h_true 是采样率 fs 下每采样点一列，而 h_est 通常是每块/每符号/每帧一次
%   对齐策略：从 h_true 取代表列（默认中点），再按估计形式投影到可比空间
%   NMSE = 10*log10(||h_est - h_true_aligned||^2 / ||h_true_aligned||^2)

if nargin < 3, opts = struct(); end
type = getfield_def(opts, 'type', 'time_sparse');

if isempty(h_est) || isempty(h_true)
    nmse_db = NaN;
    return;
end

try
    switch lower(type)
        case 'time_sparse'
            delays_samp = opts.delays_samp(:).';
            % h_est 第一列作为代表；h_true 按 delays_samp 下标抽取
            h_est_vec  = h_est(:, min(size(h_est,2), max(1, round(size(h_est,2)/2))));
            sample_idx = getfield_def(opts, 'sample_idx', round(size(h_true,2)/2));
            sample_idx = max(1, min(sample_idx, size(h_true,2)));
            h_true_col = h_true(:, sample_idx);

            if numel(h_est_vec) ~= numel(h_true_col)
                % 形状不一致 → 按 h_est 长度截断 h_true 抽头
                n_common = min(numel(h_est_vec), numel(h_true_col));
                h_est_vec  = h_est_vec(1:n_common);
                h_true_col = h_true_col(1:n_common);
            end
            num = norm(h_est_vec(:) - h_true_col(:))^2;
            den = norm(h_true_col(:))^2;

        case 'freq_cfr'
            fft_len = opts.fft_len;
            delays_samp = getfield_def(opts, 'delays_samp', []);
            sample_idx = getfield_def(opts, 'sample_idx', round(size(h_true,2)/2));
            sample_idx = max(1, min(sample_idx, size(h_true,2)));
            h_true_col = h_true(:, sample_idx);

            % h_true_col 是稀疏抽头（num_paths × 1），构造时域 → FFT
            h_td = zeros(1, fft_len);
            for p = 1:numel(h_true_col)
                if ~isempty(delays_samp) && p <= numel(delays_samp)
                    idx = mod(delays_samp(p), fft_len) + 1;
                else
                    idx = p;
                end
                h_td(idx) = h_td(idx) + h_true_col(p);
            end
            H_true = fft(h_td);
            H_est  = h_est(:, min(size(h_est,2), max(1, round(size(h_est,2)/2))));
            n_common = min(numel(H_true), numel(H_est));
            num = norm(H_est(1:n_common).' - H_true(1:n_common).')^2;
            den = norm(H_true(1:n_common).')^2;

        case 'dd_grid'
            % OTFS DD 域 NMSE 需要 TX 侧的 delay/doppler 真值
            % 本工具暂不支持（OTFS 用 ch_info.h_time 到 DD 域的映射太体制特定）
            % 留给阶段 B OTFS runner 内部计算后直接写入 row.nmse_db
            nmse_db = NaN;
            return;

        otherwise
            error('bench_nmse_tool:UnknownType', '未知类型: %s', type);
    end

    if den < eps
        nmse_db = NaN;
    else
        nmse_db = 10 * log10(num / den);
    end

catch ME
    warning('bench_nmse_tool:ComputeFail', '%s', ME.message);
    nmse_db = NaN;
end

end

function v = getfield_def(s, f, d)
if isfield(s, f), v = s.(f); else, v = d; end
end
