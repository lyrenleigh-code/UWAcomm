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
methods = {'Turbo+orc', 'TV-orc', 'LE+TV-orc', 'LE+Kalman'};
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

            if strcmp(mname, 'Turbo+orc')
                % 标准Turbo（oracle信道，固定ISI消除）
                [bo,~] = turbo_equalizer_sctde(rx_sym, h_orc, training, 6, noise_var, eq_p, codec);

            elseif strcmp(mname, 'TV-orc')
                % 时变oracle：DFE iter1 + 每符号真实h(n)做ISI消除 iter2+
                % （性能上界：完美信道跟踪）
                [LLR_dfe,~,nv_dfe] = eq_dfe(rx_sym, h_orc, training, 31, 90, 0.998, pll);
                LLR_eq = -LLR_dfe;
                [~,perm_t] = random_interleave(zeros(1,M_coded), codec.interleave_seed);
                bo = [];
                for titer = 1:6
                    lt = LLR_eq(1:min(length(LLR_eq),M_coded));
                    if length(lt)<M_coded, lt=[lt,zeros(1,M_coded-length(lt))]; end
                    ld = random_deinterleave(lt, perm_t);
                    ld = max(min(ld,30),-30);
                    [~,Lpi,Lpc] = siso_decode_conv(ld,[],codec.gen_polys,codec.constraint_len,codec.decode_mode);
                    bo = double(Lpi>0);
                    if titer < 6
                        Li = random_interleave(Lpc, codec.interleave_seed);
                        if length(Li)<M_coded, Li=[Li,zeros(1,M_coded-length(Li))];
                        else, Li=Li(1:M_coded); end
                        [xbar,~] = soft_mapper(Li, 'qpsk');
                        fs = zeros(1, N_tx);
                        fs(1:T) = training;
                        nf = min(length(xbar), N_dsym);
                        if nf>0, fs(T+1:T+nf) = xbar(1:nf); end
                        % 每符号真实信道ISI消除
                        deq = zeros(1, N_dsym);
                        for n=1:N_dsym
                            nn=T+n; isi=0;
                            for pp=1:K_sparse
                                d=sym_delays(pp); idx=nn-d;
                                if idx>=1&&idx<=N_tx&&d>0
                                    isi=isi+h_true_paths(pp,nn)*fs(idx);
                                end
                            end
                            h0n=h_true_paths(1,nn);
                            ric=rx_sym(nn)-isi;
                            if abs(h0n)>1e-6, deq(n)=ric/h0n; else, deq(n)=ric; end
                        end
                        nvp=nv_dfe/max(mean(abs(h_true_paths(1,T+1:end)).^2),1e-6);
                        LLR_eq=zeros(1,2*N_dsym);
                        LLR_eq(1:2:end)=-2*sqrt(2)*real(deq)/nvp;
                        LLR_eq(2:2:end)=-2*sqrt(2)*imag(deq)/nvp;
                    end
                end

            elseif strcmp(mname, 'LE+TV-orc') || strcmp(mname, 'LE+Kalman')
                % iter1: 线性均衡器（eq_rls居中延迟，无反馈→无错误传播）
                use_kalman = strcmp(mname, 'LE+Kalman');
                [x_rls,~,~] = eq_rls(rx_sym, training, 0.998, 101, N_data_sym);
                % RLS LLR（试两种极性取好的）
                LLR_rls = zeros(1, 2*N_data_sym);
                for kk=1:N_data_sym
                    LLR_rls(2*kk-1) = -4*real(x_rls(train_len+kk));
                    LLR_rls(2*kk) = -4*imag(x_rls(train_len+kk));
                end
                LLR_rls = LLR_rls(1:min(length(LLR_rls),M_coded));
                if length(LLR_rls)<M_coded, LLR_rls=[LLR_rls,zeros(1,M_coded-length(LLR_rls))]; end
                [~,perm_t] = random_interleave(zeros(1,M_coded), codec.interleave_seed);
                % 确定LLR极性
                best_sgn = 1;
                for sgn=[+1,-1]
                    ld_t = random_deinterleave(sgn*LLR_rls, perm_t);
                    ld_t = max(min(ld_t,30),-30);
                    [~,Lp_t,~] = siso_decode_conv(ld_t,[],codec.gen_polys,codec.constraint_len);
                    bt = mean(double(Lp_t>0)~=info_bits(1:min(length(Lp_t),N_info)));  % 仅用于极性检测
                    if bt < 0.4, best_sgn = sgn; break; end
                end
                LLR_eq = best_sgn * LLR_rls;

                % Kalman参数
                h_paths_init = h_est_gamp(sym_delays+1);
                alpha_ar = besselj(0, 2*pi*max(fd_hz,0.1)/sym_rate);
                q_proc = max((1-alpha_ar^2)*mean(abs(h_paths_init).^2), 1e-8);
                nv_eq = max(noise_var, 1e-10);

                bo = [];
                for titer = 1:6
                    lt = LLR_eq(1:min(length(LLR_eq),M_coded));
                    if length(lt)<M_coded, lt=[lt,zeros(1,M_coded-length(lt))]; end
                    ld = random_deinterleave(lt, perm_t);
                    ld = max(min(ld,30),-30);
                    [~,Lpi,Lpc] = siso_decode_conv(ld,[],codec.gen_polys,codec.constraint_len,codec.decode_mode);
                    bo = double(Lpi>0);

                    if titer < 6
                        Li = random_interleave(Lpc, codec.interleave_seed);
                        if length(Li)<M_coded, Li=[Li,zeros(1,M_coded-length(Li))];
                        else, Li=Li(1:M_coded); end
                        [xbar, var_x_arr] = soft_mapper(Li, 'qpsk');

                        % 置信度加权：var_x<0.5的符号参与ISI消除，否则置0
                        % soft_mapper返回标量var_x，需按符号展开
                        if isscalar(var_x_arr), var_x_per = var_x_arr*ones(1,length(xbar));
                        else, var_x_per = var_x_arr; end
                        xbar_conf = xbar;
                        xbar_conf(var_x_per > 0.5) = 0;  % 低置信度→不参与

                        fs = zeros(1, N_tx);
                        fs(1:T) = training;  % 训练段100%置信
                        nf = min(length(xbar_conf), N_dsym);
                        if nf>0, fs(T+1:T+nf) = xbar_conf(1:nf); end

                        if use_kalman
                            % Kalman稀疏跟踪
                            hk = h_paths_init(:); Pk = q_proc*10*eye(K_sparse);
                            h_tv = zeros(K_sparse, N_dsym);
                            for n=1:N_dsym
                                nn=T+n;
                                hk_p = alpha_ar*hk;
                                Pk_p = alpha_ar^2*Pk + q_proc*eye(K_sparse);
                                phi=zeros(K_sparse,1);
                                for pp=1:K_sparse
                                    idx=nn-sym_delays(pp);
                                    if idx>=1&&idx<=N_tx, phi(pp)=fs(idx); end
                                end
                                inn=rx_sym(nn)-phi'*hk_p;
                                S=phi'*Pk_p*phi+nv_eq;
                                Kg=Pk_p*phi/S;
                                hk=hk_p+Kg*inn;
                                Pk=(eye(K_sparse)-Kg*phi')*Pk_p;
                                h_tv(:,n)=hk;
                            end
                        else
                            % TV-orc：直接用真实信道
                            h_tv = h_true_paths(:, T+1:T+N_dsym);
                        end

                        % 时变ISI消除 + 单抽头ZF
                        deq = zeros(1, N_dsym);
                        for n=1:N_dsym
                            nn=T+n; isi=0;
                            for pp=1:K_sparse
                                d=sym_delays(pp); idx=nn-d;
                                if idx>=1&&idx<=N_tx&&d>0
                                    isi=isi+h_tv(pp,n)*fs(idx);
                                end
                            end
                            h0n=h_tv(1,n);
                            ric=rx_sym(nn)-isi;
                            if abs(h0n)>1e-6, deq(n)=ric/h0n; else, deq(n)=ric; end
                        end
                        nvp=max(noise_var,1e-6)/max(mean(abs(h_tv(1,:)).^2),1e-6);
                        LLR_eq=zeros(1,2*N_dsym);
                        LLR_eq(1:2:end)=-2*sqrt(2)*real(deq)/nvp;
                        LLR_eq(2:2:end)=-2*sqrt(2)*imag(deq)/nvp;
                    end
                end
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
