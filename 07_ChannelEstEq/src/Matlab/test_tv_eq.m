%% test_tv_eq.m — 时变信道估计+均衡独立测试
% 纯基带符号级：无RRC/无通带/无同步/无帧组装
% 对比：oracle / GAMP固定 / GAMP+Kalman跟踪
% 版本：V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  时变信道估计+均衡 独立测试\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '13_SourceCode', 'src', 'Matlab', 'common'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

%% ========== 参数 ========== %%
sym_rate = 6000; fs = sym_rate;  % 符号率采样（无过采样）
codec = struct('gen_polys',[7,5], 'constraint_len',3, 'interleave_seed',7, 'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;
pll = struct('enable',true,'Kp',0.01,'Ki',0.005);

% 6径水声信道
sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));
L_h = max(sym_delays)+1;  % 91
K_sparse = length(sym_delays);  % 6

train_len = 500; N_data_sym = 2000;
M_coded = 2*N_data_sym; N_info = M_coded/n_code - mem;

h_sym = zeros(1, L_h);
for p=1:length(sym_delays), h_sym(sym_delays(p)+1)=gains(p); end

snr_list = [0, 5, 10, 15, 20];
fd_list = [0, 1, 5];

%% ========== 方法定义 ========== %%
methods = {'FDE(orc短p)', 'FDE(orc长p)', 'FDE+BEM(CE)', 'FDE+BEM(CE,Q少)', 'FDE+BEM(DCT)'};
N_methods = length(methods);

fprintf('纯基带符号级（无RRC/无通带/无同步）\n');
fprintf('信道: 6径, max_delay=90sym, 训练=%d, 数据=%d\n', train_len, N_data_sym);
fprintf('均衡: DFE(31,90), Turbo 6次\n\n');

for fi = 1:length(fd_list)
    fd_hz = fd_list(fi);
    if fd_hz == 0, ftype='static'; else, ftype='slow'; end

    fprintf('--- fd=%dHz (%s) ---\n', fd_hz, ftype);
    fprintf('%-6s |', 'SNR');
    for mi=1:N_methods, fprintf(' %14s', methods{mi}); end
    fprintf('\n%s\n', repmat('-',1,6+15*N_methods));

    for si = 1:length(snr_list)
        snr_db = snr_list(si);

        % TX
        rng(100+fi);
        info_bits = randi([0 1],1,N_info);
        coded = conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
        coded = coded(1:M_coded);
        [inter_all,~] = random_interleave(coded,codec.interleave_seed);
        data_sym = bits2qpsk(inter_all);
        training = constellation(randi(4,1,train_len));
        tx_sym = [training, data_sym];

        % 时变信道（符号率，直接卷积）
        N_tx = length(tx_sym);
        if fd_hz == 0
            % 静态
            rx_sym = conv(tx_sym, h_sym);
            rx_sym = rx_sym(1:N_tx);
            h_true_paths = repmat(gains(:), 1, N_tx);  % 恒定
        else
            % Jakes时变（逐符号施加）
            rng(200+fi);
            t = (0:N_tx-1)/sym_rate;
            N_osc = 8;
            h_tv = zeros(K_sparse, N_tx);
            for p = 1:K_sparse
                fading = zeros(1, N_tx);
                for k = 1:N_osc
                    theta = 2*pi*rand;
                    beta = pi*k/N_osc;
                    fading = fading + exp(1j*(2*pi*fd_hz*cos(beta)*t + theta));
                end
                fading = fading / sqrt(N_osc);
                h_tv(p,:) = gains(p) * fading;
            end
            % 时变卷积
            rx_sym = zeros(1, N_tx);
            for n = 1:N_tx
                for p = 1:K_sparse
                    d = sym_delays(p);
                    if n-d >= 1
                        rx_sym(n) = rx_sym(n) + h_tv(p,n) * tx_sym(n-d);
                    end
                end
            end
            h_true_paths = h_tv;
        end

        % 加噪
        sig_pwr = mean(abs(rx_sym).^2);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(300+fi*100+si);
        rx_sym = rx_sym + sqrt(noise_var/2)*(randn(size(rx_sym))+1j*randn(size(rx_sym)));

        % GAMP信道估计（训练段）
        rx_train = rx_sym(1:train_len);
        T_mat = zeros(train_len, L_h);
        for col = 1:L_h
            T_mat(col:train_len, col) = training(1:train_len-col+1).';
        end
        [h_gamp_vec,~] = ch_est_gamp(rx_train(:), T_mat, L_h, 50, noise_var);
        h_est_gamp = h_gamp_vec(:).';

        % Oracle h_est（训练中点的真实信道）
        mid_train = round(train_len/2);
        h_orc = zeros(1, L_h);
        for p=1:K_sparse, h_orc(sym_delays(p)+1) = h_true_paths(p, mid_train); end

        bers = zeros(1, N_methods);
        eq_p = struct('num_ff',31,'num_fb',90,'lambda',0.998,'pll',pll);
        T = train_len; N_dsym = N_data_sym;

        for mi = 1:N_methods
            mname = methods{mi};

            if false
                % placeholder

            elseif contains(mname, 'FDE')
                % === SC-FDE风格分块频域均衡 ===
                use_orc = contains(mname, 'orc');
                use_bem = contains(mname, 'BEM');

                % 块参数
                if fd_hz <= 1, blk_fft=256; else, blk_fft=128; end
                blk_cp = max(sym_delays) + 10;

                % 帧内导频参数
                max_d = max(sym_delays);
                if contains(mname, '短p')
                    pilot_len = 50;  % 短导频（oracle基线，帧短→Jakes有利）
                else
                    pilot_useful = 100;
                    pilot_len = max_d + pilot_useful;  % 190符号（BEM需要长导频）
                end
                rng(999); pilot_sym = constellation(randi(4,1,pilot_len));

                % 数据编码
                sym_per_blk = blk_cp + blk_fft;
                N_blks = floor(N_data_sym / blk_fft);
                M_blk = 2*blk_fft; M_tot = M_blk*N_blks;
                N_info_blk = M_tot/n_code - mem;

                rng(100+fi);
                ib_blk = randi([0 1],1,N_info_blk);
                cd_blk = conv_encode(ib_blk,codec.gen_polys,codec.constraint_len);
                cd_blk = cd_blk(1:M_tot);
                [it_blk,pm_blk] = random_interleave(cd_blk,codec.interleave_seed);
                sym_blk = bits2qpsk(it_blk);

                % TX帧组装: [训练|数据块1|导频|数据块2|导频|...|数据块N|尾导频]
                % 所有方法用同一帧结构（都有导频），确保公平对比
                frame_parts = training;
                blk_starts = zeros(1,N_blks);
                pilot_positions = [];
                for bi=1:N_blks
                    if bi > 1
                        pilot_positions(end+1) = length(frame_parts)+1;
                        frame_parts = [frame_parts, pilot_sym];
                    end
                    blk_starts(bi) = length(frame_parts)+1;
                    ds_b = sym_blk((bi-1)*blk_fft+1:bi*blk_fft);
                    frame_parts = [frame_parts, ds_b(end-blk_cp+1:end), ds_b];
                end
                % 帧尾导频
                pilot_positions(end+1) = length(frame_parts)+1;
                frame_parts = [frame_parts, pilot_sym];
                tx_blk = frame_parts;
                N_tx_blk = length(tx_blk);

                % RRC过采样信道（与端到端SC-FDE一致）
                sps = 8; rolloff = 0.35; span_rrc = 6;
                N_samp = N_tx_blk * sps;  % 过采样总长

                % RRC成形（符号→过采样基带）
                [shaped_bb,~,~] = pulse_shape(tx_blk, sps, 'rrc', rolloff, span_rrc);

                if fd_hz == 0
                    % 静态：过采样域卷积
                    h_bb = zeros(1, max_d*sps+1);
                    for p=1:K_sparse, h_bb(sym_delays(p)*sps+1)=gains(p); end
                    rx_shaped = conv(shaped_bb, h_bb);
                    rx_shaped = rx_shaped(1:length(shaped_bb));
                    h_blk_paths = repmat(gains(:), 1, N_tx_blk);
                else
                    % 时变：过采样域Jakes逐样本卷积
                    rng(200+fi);
                    N_samp_full = length(shaped_bb);
                    t_samp = (0:N_samp_full-1)/(sym_rate*sps);
                    h_samp_tv = zeros(K_sparse, N_samp_full);
                    for p=1:K_sparse
                        fad=zeros(1,N_samp_full);
                        for k=1:8
                            theta=2*pi*rand; beta=pi*k/8;
                            fad=fad+exp(1j*(2*pi*fd_hz*cos(beta)*t_samp+theta));
                        end
                        h_samp_tv(p,:) = gains(p)*fad/sqrt(8);
                    end
                    rx_shaped = zeros(1, N_samp_full);
                    for n=1:N_samp_full
                        for p=1:K_sparse
                            d_samp = sym_delays(p)*sps;
                            if n-d_samp>=1
                                rx_shaped(n) = rx_shaped(n) + h_samp_tv(p,n)*shaped_bb(n-d_samp);
                            end
                        end
                    end
                    % 符号率信道（从过采样中取每sps个点的中点）
                    h_blk_paths = zeros(K_sparse, N_tx_blk);
                    for si_sym=1:N_tx_blk
                        samp_mid = (si_sym-1)*sps + round(sps/2);
                        samp_mid = min(samp_mid, N_samp_full);
                        h_blk_paths(:, si_sym) = h_samp_tv(:, samp_mid);
                    end
                end

                % 加噪（过采样域）
                sp = mean(abs(rx_shaped).^2);
                nv_samp = sp*10^(-snr_db/10);
                rng(300+fi*100+si);
                rx_shaped = rx_shaped + sqrt(nv_samp/2)*(randn(size(rx_shaped))+1j*randn(size(rx_shaped)));

                % RRC匹配滤波 + 下采样
                [rx_filt,~] = match_filter(rx_shaped, sps, 'rrc', rolloff, span_rrc);
                % 寻找最佳采样偏移
                best_off=0; best_pwr=0;
                for off=0:sps-1
                    st=rx_filt(off+1:sps:end);
                    if length(st)>=10
                        c_corr=abs(sum(st(1:10).*conj(tx_blk(1:10))));
                        if c_corr>best_pwr, best_pwr=c_corr; best_off=off; end
                    end
                end
                rx_blk = rx_filt(best_off+1:sps:end);
                if length(rx_blk)>N_tx_blk, rx_blk=rx_blk(1:N_tx_blk);
                elseif length(rx_blk)<N_tx_blk, rx_blk=[rx_blk,zeros(1,N_tx_blk-length(rx_blk))]; end

                % 符号率噪声方差（从过采样换算）
                nv_blk = nv_samp;  % RRC匹配后噪声方差近似不变
                nv_eq = max(nv_blk, 1e-10);

                % === 信道估计 ===
                if use_bem
                    % 调用ch_est_bem函数
                    % 构建导频观测：训练段 + 帧内导频后部（所有径已知区域）
                    obs_y_arr = []; obs_x_arr = []; obs_t_arr = [];

                    % 训练段（n > max_delay时所有径都在训练内）
                    for n = max_d+1 : train_len
                        x_vec = zeros(1, K_sparse);
                        for p=1:K_sparse
                            idx = n - sym_delays(p);
                            if idx >= 1, x_vec(p) = training(idx); end
                        end
                        obs_y_arr(end+1) = rx_blk(n);
                        obs_x_arr = [obs_x_arr; x_vec];
                        obs_t_arr(end+1) = n;
                    end

                    % 帧内导频段：只用后部 [pp+max_d : pp+pilot_len-1]
                    % 此区间内所有径 x(n-d) 都落在导频段 [pp : pp+pilot_len-1] 内
                    for pi_idx = 1:length(pilot_positions)
                        pp = pilot_positions(pi_idx);
                        for kk = max_d+1 : pilot_len
                            n = pp + kk - 1;
                            if n > N_tx_blk, break; end
                            x_vec = zeros(1, K_sparse);
                            for p=1:K_sparse
                                idx = n - sym_delays(p);
                                if idx >= pp && idx < pp+pilot_len
                                    % idx在导频段内 → 已知
                                    x_vec(p) = pilot_sym(idx - pp + 1);
                                elseif idx >= 1 && idx <= train_len
                                    % idx在训练段内 → 已知
                                    x_vec(p) = training(idx);
                                end
                                % 其他情况x_vec(p)=0（未知，不参与该径）
                            end
                            if any(x_vec ~= 0)
                                obs_y_arr(end+1) = rx_blk(n);
                                obs_x_arr = [obs_x_arr; x_vec];
                                obs_t_arr(end+1) = n;
                            end
                        end
                    end

                    fd_est = max(fd_hz, 0.5);

                    % BEM类型和Q阶选择
                    if contains(mname, 'DCT')
                        bem_type = 'dct';
                        fd_for_q = fd_est;  % 标准Q
                    elseif contains(mname, 'Q少')
                        bem_type = 'ce';
                        fd_for_q = fd_est * 0.5;  % Q减半
                    else
                        bem_type = 'ce';
                        fd_for_q = fd_est;  % 标准Q
                    end

                    [h_tv_bem, ~, info_bem] = ch_est_bem(obs_y_arr(:), obs_x_arr, ...
                        obs_t_arr(:), N_tx_blk, sym_delays, fd_for_q, sym_rate, nv_eq, bem_type);

                    if si == 1
                        fprintf('\n  [%s] Q=%d, obs=%d, type=%s\n', mname, info_bem.Q, info_bem.M_obs, info_bem.bem_type);
                    end

                    % 从BEM重构每块H_est + NMSE诊断
                    nmse_blks = zeros(1, N_blks);
                    for bi = 1:N_blks
                        mid = blk_starts(bi) + round(sym_per_blk/2);
                        mid_clamp = min(mid, N_tx_blk);
                        hm_bem = h_tv_bem(:, mid_clamp);  % P×1
                        h_true_bi = h_blk_paths(:, min(mid, size(h_blk_paths,2)));
                        nmse_blks(bi) = sum(abs(hm_bem - h_true_bi).^2) / sum(abs(h_true_bi).^2);

                        htd = zeros(1, blk_fft);
                        for p=1:K_sparse
                            if sym_delays(p)+1<=blk_fft, htd(sym_delays(p)+1)=hm_bem(p); end
                        end
                        H_blks{bi} = fft(htd);
                    end
                    if si == 1
                        fprintf('  NMSE/块: '); fprintf('%.1fdB ', 10*log10(nmse_blks+1e-10));
                        fprintf('(avg=%.1fdB)\n', 10*log10(mean(nmse_blks)+1e-10));
                    end
                else
                    % 初始H_est: oracle或Turbo-VAMP（固定，不分块更新）
                    rx_tr_blk = rx_blk(1:train_len);
                    T_mat_blk = zeros(train_len, L_h);
                    for col=1:L_h, T_mat_blk(col:train_len,col)=training(1:train_len-col+1).'; end
                    [h_tvamp_blk,~,~,~] = ch_est_turbo_vamp(rx_tr_blk(:), T_mat_blk, L_h, 30, K_sparse, nv_blk);
                    for bi=1:N_blks
                        if use_orc
                            mid = blk_starts(bi) + round(sym_per_blk/2);
                            mid = min(mid, size(h_blk_paths,2));
                            hm = h_blk_paths(:,mid);
                        else
                            hm = h_tvamp_blk(sym_delays+1);
                        end
                        hn = hm(:).';
                        htd = zeros(1, blk_fft);
                        for p=1:K_sparse
                            if sym_delays(p)+1<=blk_fft, htd(sym_delays(p)+1)=hn(p); end
                        end
                        H_blks{bi} = fft(htd);
                    end
                end

                % 分块提取+FFT
                Y_blks = cell(1,N_blks);
                for bi=1:N_blks
                    blk_sym = rx_blk(blk_starts(bi):blk_starts(bi)+sym_per_blk-1);
                    Y_blks{bi} = fft(blk_sym(blk_cp+1:end));
                end

                % 跨块Turbo: LMMSE-IC + BCJR + 渐进DD信道精化
                use_dd_refine = contains(mname, 'DD');
                n_turbo = 8;  % 增加迭代次数
                H_cur = H_blks;
                x_bar_b = cell(1,N_blks); var_x_b = ones(1,N_blks);
                for bi=1:N_blks, x_bar_b{bi}=zeros(1,blk_fft); end
                [~,pm_t] = random_interleave(zeros(1,M_tot),codec.interleave_seed);
                bo = [];
                for titer = 1:n_turbo
                    LLR_all = zeros(1, M_tot);
                    for bi=1:N_blks
                        [xt,mu_t,nvt] = eq_mmse_ic_fde(Y_blks{bi}, H_cur{bi}, x_bar_b{bi}, var_x_b(bi), nv_eq);
                        le = soft_demapper(xt, mu_t, nvt, zeros(1,M_blk), 'qpsk');
                        LLR_all((bi-1)*M_blk+1:bi*M_blk) = le;
                    end
                    ld = random_deinterleave(LLR_all, pm_t);
                    ld = max(min(ld,30),-30);
                    [~,Lpi,Lpc] = siso_decode_conv(ld,[],codec.gen_polys,codec.constraint_len,codec.decode_mode);
                    bo = double(Lpi>0);
                    if titer < n_turbo
                        Li = random_interleave(Lpc, codec.interleave_seed);
                        if length(Li)<M_tot, Li=[Li,zeros(1,M_tot-length(Li))];
                        else, Li=Li(1:M_tot); end
                        for bi=1:N_blks
                            cb = Li((bi-1)*M_blk+1:bi*M_blk);
                            [x_bar_b{bi},vr] = soft_mapper(cb,'qpsk');
                            var_x_b(bi) = max(vr, nv_eq);

                            if use_dd_refine && titer >= 2
                                % 正则化DD: 不确定时自动回退BEM
                                X_bar_f = fft(x_bar_b{bi});
                                lambda_reg = nv_eq * 2;  % 正则化强度
                                H_dd_reg = (Y_blks{bi}.*conj(X_bar_f) + lambda_reg*H_blks{bi}) ...
                                         ./ (abs(X_bar_f).^2 + nv_eq + lambda_reg);
                                % 稀疏投影
                                h_dd_td = ifft(H_dd_reg);
                                h_dd_s = zeros(1, blk_fft);
                                for p=1:K_sparse
                                    if sym_delays(p)+1<=blk_fft
                                        h_dd_s(sym_delays(p)+1) = h_dd_td(sym_delays(p)+1);
                                    end
                                end
                                % 渐进权重：iter越大越信任DD
                                w_dd = min((titer-1)/(n_turbo-1), 0.8);
                                H_cur{bi} = (1-w_dd)*H_blks{bi} + w_dd*fft(h_dd_s);
                            end
                        end
                    end
                end
                % BER用块数据的info_bits（不覆盖外层变量）
                nc = min(length(bo), N_info_blk);
                bers(mi) = mean(bo(1:nc) ~= ib_blk(1:nc));
                continue;  % 跳过外层BER计算
            end

            nc = min(length(bo), N_info);
            bers(mi) = mean(bo(1:nc) ~= info_bits(1:nc));
        end

        fprintf('%-6d |', snr_db);
        for mi=1:N_methods, fprintf(' %13.2f%%', bers(mi)*100); end
        fprintf('\n');
    end
    fprintf('\n');
end

%% ========== 可视化：BEM(CE)信道估计 vs 真实信道 ========== %%
if exist('h_blk_paths','var') && exist('H_blks','var')
    figure('Position',[50 50 1400 700]);

    % 每块H_est频响对比（oracle vs BEM）
    subplot(2,3,1);
    bi_show = 1;  % 第1块
    f_ax = (0:blk_fft-1)*sym_rate/blk_fft/1000;
    mid1 = blk_starts(bi_show) + round(sym_per_blk/2);
    mid1 = min(mid1, size(h_blk_paths,2));
    h_true_b1 = h_blk_paths(:, mid1);
    htd_true = zeros(1,blk_fft);
    for p=1:K_sparse, if sym_delays(p)+1<=blk_fft, htd_true(sym_delays(p)+1)=h_true_b1(p); end, end
    plot(f_ax, 20*log10(abs(fft(htd_true))+1e-10), 'k', 'LineWidth',1.5); hold on;
    plot(f_ax, 20*log10(abs(H_blks{bi_show})+1e-10), 'b--', 'LineWidth',1);
    xlabel('频率(kHz)'); ylabel('|H|(dB)'); grid on;
    title(sprintf('块1频响')); legend('真实','H_{est}','Location','best');

    subplot(2,3,2);
    bi_show = round(N_blks/2);  % 中间块
    mid2 = blk_starts(bi_show) + round(sym_per_blk/2);
    mid2 = min(mid2, size(h_blk_paths,2));
    h_true_b2 = h_blk_paths(:, mid2);
    htd_true2 = zeros(1,blk_fft);
    for p=1:K_sparse, if sym_delays(p)+1<=blk_fft, htd_true2(sym_delays(p)+1)=h_true_b2(p); end, end
    plot(f_ax, 20*log10(abs(fft(htd_true2))+1e-10), 'k', 'LineWidth',1.5); hold on;
    plot(f_ax, 20*log10(abs(H_blks{bi_show})+1e-10), 'b--', 'LineWidth',1);
    xlabel('频率(kHz)'); ylabel('|H|(dB)'); grid on;
    title(sprintf('块%d频响(中间)', bi_show)); legend('真实','H_{est}');

    subplot(2,3,3);
    bi_show = N_blks;  % 最后一块
    mid3 = blk_starts(bi_show) + round(sym_per_blk/2);
    mid3 = min(mid3, size(h_blk_paths,2));
    h_true_b3 = h_blk_paths(:, mid3);
    htd_true3 = zeros(1,blk_fft);
    for p=1:K_sparse, if sym_delays(p)+1<=blk_fft, htd_true3(sym_delays(p)+1)=h_true_b3(p); end, end
    plot(f_ax, 20*log10(abs(fft(htd_true3))+1e-10), 'k', 'LineWidth',1.5); hold on;
    plot(f_ax, 20*log10(abs(H_blks{bi_show})+1e-10), 'b--', 'LineWidth',1);
    xlabel('频率(kHz)'); ylabel('|H|(dB)'); grid on;
    title(sprintf('块%d频响(末尾)', N_blks)); legend('真实','H_{est}');

    % 各径幅度随块变化
    subplot(2,3,4);
    h_true_per_blk = zeros(K_sparse, N_blks);
    h_est_per_blk = zeros(K_sparse, N_blks);
    for bi=1:N_blks
        mid_bi = blk_starts(bi) + round(sym_per_blk/2);
        mid_bi = min(mid_bi, size(h_blk_paths,2));
        h_true_per_blk(:,bi) = h_blk_paths(:, mid_bi);
        htd_bi = ifft(H_blks{bi});
        for p=1:K_sparse
            if sym_delays(p)+1<=blk_fft
                h_est_per_blk(p,bi) = htd_bi(sym_delays(p)+1);
            end
        end
    end
    plot(1:N_blks, abs(h_true_per_blk(1,:)), 'k-o', 'LineWidth',1.5, 'MarkerSize',4); hold on;
    plot(1:N_blks, abs(h_est_per_blk(1,:)), 'b--s', 'LineWidth',1, 'MarkerSize',4);
    xlabel('块序号'); ylabel('|h_1|'); grid on;
    title('主径(d=0)逐块幅度'); legend('真实','估计','Location','best');

    subplot(2,3,5);
    plot(1:N_blks, angle(h_true_per_blk(1,:))*180/pi, 'k-o', 'LineWidth',1.5, 'MarkerSize',4); hold on;
    plot(1:N_blks, angle(h_est_per_blk(1,:))*180/pi, 'b--s', 'LineWidth',1, 'MarkerSize',4);
    xlabel('块序号'); ylabel('相位(°)'); grid on;
    title('主径(d=0)逐块相位');

    % 逐块NMSE
    subplot(2,3,6);
    nmse_per_blk = zeros(1, N_blks);
    for bi=1:N_blks
        nmse_per_blk(bi) = sum(abs(h_est_per_blk(:,bi)-h_true_per_blk(:,bi)).^2) / ...
                           sum(abs(h_true_per_blk(:,bi)).^2);
    end
    bar(1:N_blks, 10*log10(nmse_per_blk+1e-10));
    xlabel('块序号'); ylabel('NMSE(dB)'); grid on;
    title('逐块H_{est} NMSE'); yline(0,'r--','0dB');

    sgtitle(sprintf('BEM(CE)信道估计 vs 真实信道 (fd=%dHz, 最后SNR点)', fd_hz));
end

fprintf('完成\n');
