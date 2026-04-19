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
% 去oracle：本地重生成 gold_code 和 training（与 TX seed 一致）
gold_01   = gen_gold_code(cfg.code_poly(1), cfg.code_poly(2));
gold_code = 2 * gold_01 - 1;
rng_st = rng; rng(88);
training  = 2 * randi([0 1], 1, train_len) - 1;
rng(rng_st);
% 去oracle：不用 cfg.chip_delays，由训练码片相关搜索发现
L_max_chips   = min(2*L, 50);  % 搜索范围上界（码片单位）
K_rake_max    = 8;             % Rake finger 数上界
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
chip_off_corr_curve = zeros(1, sps_dsss);
for off = 0:sps_dsss-1
    idx = off+1 : sps_dsss : length(rx_filt);
    n_check = min(length(idx), train_chips);
    if n_check >= L
        c = abs(sum(rx_filt(idx(1:n_check)) .* conj(train_spread(1:n_check))));
        chip_off_corr_curve(off+1) = c;
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

%% ---- 4. 噪声方差盲估计（训练码片残差）----
spread_code_pm = gold_code;
tail_n = min(L*5, train_chips);
tail_chips = rx_chips(train_chips-tail_n+1 : train_chips);
ref_chips  = train_spread(train_chips-tail_n+1 : train_chips);
% 先粗估信道增益（训练段逐符号平均）
h0_est = 0;
for k = 1:train_len
    cs = (k-1)*L + 1;
    ce = cs + L - 1;
    if ce <= train_chips
        h0_est = h0_est + (sum(rx_chips(cs:ce) .* spread_code_pm) / L) * conj(training(k));
    end
end
h0_est = h0_est / train_len;
nv = max(var(tail_chips - abs(h0_est) * ref_chips), 1e-10);

%% ---- 5. 训练段信道估计（盲搜 Rake finger 位置 + 增益估计）----

% 5a. 对所有候选时延做相关，发现有效 Rake finger 位置
h_scan = zeros(1, L_max_chips);
for d = 0:L_max_chips-1
    acc = 0;
    for k = 1:train_len
        cs = (k-1)*L + d + 1;
        ce = cs + L - 1;
        if ce <= train_chips
            acc = acc + (sum(rx_chips(cs:ce) .* spread_code_pm) / L) * conj(training(k));
        end
    end
    h_scan(d+1) = acc / train_len;
end

% 阈值检测：>5% 最大值的位置为有效径
h_abs = abs(h_scan);
thresh = 0.05 * max(h_abs);
detected = find(h_abs > thresh);
if length(detected) > K_rake_max
    [~, si] = sort(h_abs(detected), 'descend');
    detected = sort(detected(si(1:K_rake_max)));
end
if isempty(detected), detected = 1; end
chip_delays = detected - 1;  % 0-based
h_est = h_scan(detected);

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
% 信道 SNR：减去 RRC 处理增益（sps_dsss）
P_ch = sum(abs(h_est).^2);
info.estimated_snr    = 10*log10(max(P_ch / nv, 1e-6)) - 10*log10(sps_dsss);
info.estimated_ber    = mean(0.5 * exp(-abs(LLR_inter)));
info.turbo_iter       = 1;     % DSSS 无 Turbo，单次 Rake + DCD + Viterbi
info.convergence_flag = 1;  % DSSS 单次译码，无迭代收敛概念
info.noise_var        = nv;
info.sym_offset       = best_off;
info.h_est            = h_est;
info.chip_delays      = chip_delays;
% 同步诊断（sync tab 用）
info.chip_off_best     = best_off;
info.chip_off_corr     = chip_off_corr_curve;
info.chip_off_best_val = best_pwr;
info.rake_finger_delays = chip_delays;  % Rake 选中径（chip 级时延）
info.rake_finger_gains  = h_est;        % 对应增益

% 星座图诊断（BPSK）
info.pre_eq_syms  = rake_out;
info.post_eq_syms = dcd_decisions;

end
