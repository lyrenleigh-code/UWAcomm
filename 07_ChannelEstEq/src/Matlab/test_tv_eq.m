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
methods = {'FDE分块(orc)', 'FDE+导频+BEM', 'FDE+BEM+DD'};
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

            elseif contains(mname, 'FDE分块') || contains(mname, 'FDE+导频')
                % === SC-FDE风格分块频域均衡 ===
                use_orc = contains(mname, 'orc');
                use_bem = contains(mname, 'BEM');  % BEM信道估计

                % 块参数
                if fd_hz <= 1, blk_fft=256; else, blk_fft=128; end
                blk_cp = max(sym_delays) + 10;

                % 帧内导频参数（BEM方法用）
                pilot_len = 50;  % 每段导频50符号（短，约训练的1/10）
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
                % 前后包围：训练(头) + 散布导频(中) + 尾导频(尾)
                frame_parts = training;
                blk_starts = zeros(1,N_blks);
                pilot_positions = [];
                for bi=1:N_blks
                    if use_bem && bi > 1
                        pilot_positions(end+1) = length(frame_parts)+1;
                        frame_parts = [frame_parts, pilot_sym];
                    end
                    blk_starts(bi) = length(frame_parts)+1;
                    ds_b = sym_blk((bi-1)*blk_fft+1:bi*blk_fft);
                    frame_parts = [frame_parts, ds_b(end-blk_cp+1:end), ds_b];
                end
                % 帧尾导频（前后包围，对应实际系统的LFM2位置）
                if use_bem
                    pilot_positions(end+1) = length(frame_parts)+1;
                    frame_parts = [frame_parts, pilot_sym];
                end
                tx_blk = frame_parts;
                N_tx_blk = length(tx_blk);

                % 时变信道
                if fd_hz == 0
                    rx_blk = conv(tx_blk, h_sym); rx_blk = rx_blk(1:N_tx_blk);
                    h_blk_paths = repmat(gains(:), 1, N_tx_blk);
                else
                    rng(200+fi);
                    t_b = (0:N_tx_blk-1)/sym_rate;
                    h_blk_tv = zeros(K_sparse, N_tx_blk);
                    for p=1:K_sparse
                        fad=zeros(1,N_tx_blk);
                        for k=1:8
                            theta=2*pi*rand; beta=pi*k/8;
                            fad=fad+exp(1j*(2*pi*fd_hz*cos(beta)*t_b+theta));
                        end
                        h_blk_tv(p,:) = gains(p)*fad/sqrt(8);
                    end
                    rx_blk = zeros(1, N_tx_blk);
                    for n=1:N_tx_blk
                        for p=1:K_sparse
                            d=sym_delays(p);
                            if n-d>=1, rx_blk(n)=rx_blk(n)+h_blk_tv(p,n)*tx_blk(n-d); end
                        end
                    end
                    h_blk_paths = h_blk_tv;
                end
                % 加噪
                sp = mean(abs(rx_blk).^2);
                nv_blk = sp*10^(-snr_db/10);
                rng(300+fi*100+si);
                rx_blk = rx_blk + sqrt(nv_blk/2)*(randn(size(rx_blk))+1j*randn(size(rx_blk)));
                nv_eq = max(nv_blk, 1e-10);

                % === 信道估计 ===
                if use_bem
                    % BEM信道估计：从训练段+帧内导频联合估计
                    % CE-BEM基函数: b_q(n) = exp(j*2π*q*n/N), q=-Q/2:Q/2
                    T_frame = N_tx_blk / sym_rate;
                    Q_bem = max(5, 2*ceil(fd_hz * T_frame) + 3);  % +2余量提升频率分辨率
                    % 诊断（仅首个SNR点打印）
                    if si == 1
                        fprintf('\n  [BEM] fd=%dHz: T=%.3fs, Q=%d, N_blks=%d, pilots=%d, K*Q=%d, obs~%d\n', ...
                            fd_hz, T_frame, Q_bem, N_blks, length(pilot_positions), K_sparse*Q_bem, ...
                            train_len + length(pilot_positions)*pilot_len);
                    end
                    q_range = -(Q_bem-1)/2 : (Q_bem-1)/2;

                    % 收集所有导频观测（训练+帧内导频）
                    % 训练段
                    obs_y = []; obs_x = []; obs_n = [];
                    for n=1:train_len
                        y_n = rx_blk(n);
                        % 观测模型: y(n) = Σ_p h_p(n)*x(n-d_p)
                        % h_p(n) = Σ_q c_pq * b_q(n)
                        % y(n) = Σ_p Σ_q c_pq * b_q(n) * x(n-d_p)
                        x_vec = zeros(1, K_sparse);
                        for p=1:K_sparse
                            idx = n - sym_delays(p);
                            if idx >= 1, x_vec(p) = training(idx); end
                        end
                        if any(x_vec ~= 0)
                            obs_y(end+1) = y_n;
                            obs_x = [obs_x; x_vec];
                            obs_n(end+1) = n;
                        end
                    end
                    % 帧内导频段
                    for pi_idx = 1:length(pilot_positions)
                        pp = pilot_positions(pi_idx);
                        for kk = 1:pilot_len
                            n = pp + kk - 1;
                            if n > N_tx_blk, break; end
                            x_vec = zeros(1, K_sparse);
                            for p=1:K_sparse
                                idx = n - sym_delays(p);
                                if idx >= 1 && idx <= N_tx_blk
                                    x_vec(p) = tx_blk(idx);
                                end
                            end
                            if any(x_vec ~= 0)
                                obs_y(end+1) = rx_blk(n);
                                obs_x = [obs_x; x_vec];
                                obs_n(end+1) = n;
                            end
                        end
                    end

                    % 构建BEM观测矩阵: y = Phi * c + noise
                    % c = [c_11,...,c_1Q, c_21,...,c_PQ] (K_sparse*Q_bem × 1)
                    N_obs = length(obs_y);
                    Phi_bem = zeros(N_obs, K_sparse * Q_bem);
                    for ii = 1:N_obs
                        n = obs_n(ii);
                        for p = 1:K_sparse
                            for qi = 1:Q_bem
                                q = q_range(qi);
                                basis = exp(1j*2*pi*q*n/N_tx_blk);
                                col = (p-1)*Q_bem + qi;
                                Phi_bem(ii, col) = obs_x(ii, p) * basis;
                            end
                        end
                    end

                    % LS估计BEM系数
                    c_bem = (Phi_bem' * Phi_bem + nv_eq*eye(size(Phi_bem,2))) \ (Phi_bem' * obs_y(:));

                    % 从BEM系数重构每块中点的信道 + NMSE诊断
                    nmse_blks = zeros(1, N_blks);
                    for bi = 1:N_blks
                        mid = blk_starts(bi) + round(sym_per_blk/2);
                        hm_bem = zeros(K_sparse, 1);
                        for p = 1:K_sparse
                            for qi = 1:Q_bem
                                q = q_range(qi);
                                hm_bem(p) = hm_bem(p) + c_bem((p-1)*Q_bem+qi) * exp(1j*2*pi*q*mid/N_tx_blk);
                            end
                        end
                        % NMSE: BEM重构 vs 真实信道
                        mid_clamp = min(mid, size(h_blk_paths,2));
                        h_true_bi = h_blk_paths(:, mid_clamp);
                        nmse_blks(bi) = sum(abs(hm_bem - h_true_bi).^2) / sum(abs(h_true_bi).^2);

                        hn = hm_bem(:).' / sqrt(sum(abs(hm_bem).^2));
                        htd = zeros(1, blk_fft);
                        for p=1:K_sparse
                            if sym_delays(p)+1<=blk_fft, htd(sym_delays(p)+1)=hn(p); end
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
                        hn = hm(:).' / sqrt(sum(abs(hm).^2));
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

%% ========== 可视化：Kalman跟踪效果 ========== %%
% 最后一个fd/SNR的信道跟踪结果
if exist('h_kal','var') && exist('h_true_paths','var')
    figure('Position',[100 300 900 400]);
    for pp = 1:min(3, K_sparse)
        subplot(1,3,pp);
        plot(abs(h_true_paths(pp, T+1:end)), 'b', 'LineWidth',1); hold on;
        plot(abs(h_kal(pp,:)), 'r--', 'LineWidth',1);
        xlabel('符号'); ylabel('|h|');
        title(sprintf('径%d(d=%d): 真实 vs Kalman', pp, sym_delays(pp)));
        legend('真实','Kalman','Location','best'); grid on;
    end
    sgtitle(sprintf('Kalman信道跟踪 (fd=%dHz, SNR=%ddB)', fd_hz, snr_db));
end

fprintf('完成\n');
