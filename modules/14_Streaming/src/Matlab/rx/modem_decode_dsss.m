function [bits, info] = modem_decode_dsss(body_bb, sys, meta)
% 功能：DSSS RX（RRC 匹配滤波 + 符号定时 + 信道估计 + Rake(MRC) + DCD + 软译码）
% 版本：V1.0.0（P3.3 从 13_SourceCode/tests/DSSS/test_dsss_timevarying.m 抽取）
% 输入：
%   body_bb - 基带 body（已由外层完成对齐 + Doppler 补偿；长度 ≈ meta.N_shaped）
%   sys     - 系统参数（用 sys.codec, sys.dsss, sys.sps）
%   meta    - TX 侧 modem_encode_dsss 产出
% 输出：
%   bits - 1×N_info 解码信息比特
%   info - struct（含统一 API 字段 + 诊断）
%
% 依赖：
%   09_Waveform/match_filter
%   05_SpreadSpectrum/dsss_spread
%   07_ChannelEstEq/eq_rake
%   05_SpreadSpectrum/det_dcd
%   03_Interleaving/random_deinterleave
%   02_ChannelCoding/siso_decode_conv

cfg   = sys.dsss;
codec = sys.codec;

%% ---- 1. 关键参数 ----
L             = meta.code_len;
train_len     = meta.train_len;
N_data_sym    = meta.N_data_sym;
N_total_chips = meta.N_total_chips;
N_shaped      = meta.N_shaped;
M_coded       = meta.M_coded;
gold_code     = meta.gold_code;
training      = meta.training;
chip_delays   = cfg.chip_delays;
train_chips   = train_len * L;

%% ---- 2. body 长度对齐 ----
body_bb = body_bb(:).';
if length(body_bb) < N_shaped
    body_bb = [body_bb, zeros(1, N_shaped - length(body_bb))];
elseif length(body_bb) > N_shaped
    body_bb = body_bb(1:N_shaped);
end

%% ---- 3. RRC 匹配滤波 + 符号定时 ----
sps_dsss = cfg.sps;
[rx_filt, ~] = match_filter(body_bb, sps_dsss, 'rrc', cfg.rolloff, cfg.span);

% 用训练码片做最大相关确定采样时刻
train_spread = dsss_spread(training, gold_code);
best_off = 0; best_pwr = 0;
for off = 0:sps_dsss-1
    idx = off+1 : sps_dsss : length(rx_filt);
    n_check = min(length(idx), train_chips);
    if n_check >= L
        c = abs(sum(rx_filt(idx(1:n_check)) .* conj(train_spread(1:n_check))));
        if c > best_pwr
            best_pwr = c;
            best_off = off;
        end
    end
end
rx_chips = rx_filt(best_off+1 : sps_dsss : end);

% 长度对齐到 N_total_chips
if length(rx_chips) > N_total_chips
    rx_chips = rx_chips(1:N_total_chips);
elseif length(rx_chips) < N_total_chips
    rx_chips = [rx_chips, zeros(1, N_total_chips - length(rx_chips))];
end

%% ---- 4. 噪声方差估计 ----
if isfield(meta, 'noise_var') && ~isempty(meta.noise_var) && meta.noise_var > 0
    nv = max(meta.noise_var, 1e-10);
else
    % 用训练段尾部残差粗估
    tail_n = min(L*5, train_chips);
    tail_chips = rx_chips(train_chips-tail_n+1 : train_chips);
    ref_chips  = train_spread(train_chips-tail_n+1 : train_chips);
    nv = max(0.5 * var(tail_chips - mean(abs(tail_chips)) * ref_chips), 1e-10);
end

%% ---- 5. 训练段信道估计（Rake finger 增益）----
spread_code_pm = gold_code;
h_est = zeros(1, length(chip_delays));
for p = 1:length(chip_delays)
    d = chip_delays(p);
    acc = 0;
    for k = 1:train_len
        cs = (k-1)*L + d + 1;
        ce = cs + L - 1;
        if ce <= train_chips
            acc = acc + (sum(rx_chips(cs:ce) .* spread_code_pm) / L) * conj(training(k));
        end
    end
    h_est(p) = acc / train_len;
end

%% ---- 6. Rake 接收（MRC, 数据段含参考符号）----
rake_opts = struct('combine', 'mrc', 'offset', train_chips);
[rake_out, ~] = eq_rake(rx_chips, gold_code, chip_delays, h_est, N_data_sym, rake_opts);

%% ---- 7. DCD 差分检测 ----
% rake_out: 1×(M_coded+1), 含参考符号
[dcd_decisions, dcd_diff] = det_dcd(rake_out);
% dcd_decisions: 1×M_coded, +1/-1
% +1 = 同相 = bit0, -1 = 反相 = bit1
bits_dcd = double(dcd_decisions < 0);

%% ---- 8. 软 LLR（差分相关实部作为软信息）----
nv_diff = max(var(real(dcd_diff)) * 0.5, 1e-6);
LLR_inter = max(min(-real(dcd_diff) / nv_diff, 30), -30);

%% ---- 9. 解交织 + SISO 译码 ----
[~, perm] = random_interleave(zeros(1, M_coded), codec.interleave_seed);
LLR_coded = random_deinterleave(LLR_inter, perm);
[~, Lp_info, ~] = siso_decode_conv(LLR_coded, [], ...
    codec.gen_polys, codec.constraint_len, codec.decode_mode);
bits_out = double(Lp_info > 0);

%% ---- 10. 截取信息比特 ----
N_info = meta.N_info;
if length(bits_out) >= N_info
    bits = bits_out(1:N_info);
else
    bits = [bits_out, zeros(1, N_info - length(bits_out))];
end

%% ---- 11. info ----
med_llr = median(abs(LLR_inter));
info = struct();
info.estimated_snr    = 10*log10(max(mean(abs(rx_chips).^2) / nv, 1e-6));
info.estimated_ber    = mean(0.5 * exp(-abs(LLR_inter)));
info.turbo_iter       = 1;     % DSSS 无 Turbo，单次 Rake + DCD + Viterbi
info.convergence_flag = 1;  % DSSS 单次译码，无迭代收敛概念
info.noise_var        = nv;
info.sym_offset       = best_off;
info.h_est            = h_est;
info.chip_delays      = chip_delays;

% 星座图诊断（BPSK）
info.pre_eq_syms  = rake_out;
info.post_eq_syms = dcd_decisions;

end
