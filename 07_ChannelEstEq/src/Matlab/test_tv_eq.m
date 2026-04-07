%% test_tv_eq.m — 时变信道均衡测试（RRC过采样+分块FDE）
% oracle vs BEM(CE) 公平对比：同一信号，只变H_est来源
% 版本：V3.0.0 — 重构：信号生成一次，方法循环只变H_est

clc; close all;
fprintf('========================================\n');
fprintf('  时变均衡测试（RRC过采样+分块FDE）\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2),2,[]).','left-msb')+1);

%% ========== 参数 ========== %%
sym_rate = 6000; sps = 8; rolloff = 0.35; span_rrc = 6;
codec = struct('gen_polys',[7,5],'constraint_len',3,'interleave_seed',7,'decode_mode','max-log');
n_code = 2; mem = codec.constraint_len - 1;
sym_delays = [0, 5, 15, 40, 60, 90];
gains_raw = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
gains = gains_raw / sqrt(sum(abs(gains_raw).^2));
L_h = max(sym_delays)+1; K = length(sym_delays);
train_len = 500; N_data_sym = 2000;
max_d = max(sym_delays);
pilot_useful = 100; pilot_len = max_d + pilot_useful;

snr_list = [0, 5, 10, 15, 20];
fd_list = [0, 1, 5];
methods = {'oracle', 'BEM(CE)'};
N_methods = length(methods);

fprintf('RRC过采样(sps=%d), 6径, 训练=%d, 导频=%d/段\n', sps, train_len, pilot_len);
fprintf('均衡: 分块LMMSE-IC + 跨块Turbo BCJR 6次\n\n');

for fi = 1:length(fd_list)
    fd_hz = fd_list(fi);
    if fd_hz <= 1, blk_fft=256; else, blk_fft=128; end
    blk_cp = max_d + 10;
    sym_per_blk = blk_cp + blk_fft;
    N_blks = floor(N_data_sym / blk_fft);
    M_blk = 2*blk_fft; M_tot = M_blk*N_blks;
    N_info_blk = M_tot/n_code - mem;

    %% ===== TX（per fd，固定）===== %%
    rng(100+fi);
    ib = randi([0 1],1,N_info_blk);
    cd = conv_encode(ib,codec.gen_polys,codec.constraint_len); cd=cd(1:M_tot);
    [it,pm] = random_interleave(cd,codec.interleave_seed);
    sym_blk = bits2qpsk(it);
    training = constellation(randi(4,1,train_len));
    rng(999); pilot_sym = constellation(randi(4,1,pilot_len));

    % 帧组装: [训练|数据1|导频|数据2|导频|...|数据N|尾导频]
    frame = training; blk_starts = zeros(1,N_blks); pilot_positions = [];
    for bi=1:N_blks
        if bi>1, pilot_positions(end+1)=length(frame)+1; frame=[frame,pilot_sym]; end
        blk_starts(bi)=length(frame)+1;
        ds=sym_blk((bi-1)*blk_fft+1:bi*blk_fft);
        frame=[frame, ds(end-blk_cp+1:end), ds];
    end
    pilot_positions(end+1)=length(frame)+1; frame=[frame,pilot_sym];
    N_frame = length(frame);

    %% ===== RRC成形 + 时变信道 + 加噪（per SNR）===== %%
    % RRC成形
    [shaped,~,~] = pulse_shape(frame, sps, 'rrc', rolloff, span_rrc);

    % Jakes时变信道（过采样域）
    % 用gen_uwa_channel（与端到端完全一致）
    fs_samp = sym_rate * sps;
    if fd_hz == 0, ftype='static'; else, ftype='slow'; end
    ch_params = struct('fs',fs_samp,'delay_profile','custom',...
        'delays_s',sym_delays/sym_rate,'gains',gains_raw,...
        'num_paths',K,'doppler_rate',0,...
        'fading_type',ftype,'fading_fd_hz',fd_hz,...
        'snr_db',Inf,'seed',200+fi*100);
    [rx_shaped_clean, ch_info] = gen_uwa_channel(shaped, ch_params);
    rx_shaped_clean = rx_shaped_clean(1:length(shaped));
    % 符号率信道（从h_time提取，与端到端oracle一致）
    h_paths = zeros(K, N_frame);
    for si_s=1:N_frame
        mid_s = (si_s-1)*sps + round(sps/2);
        mid_s = min(mid_s, size(ch_info.h_time,2));
        h_paths(:, si_s) = ch_info.h_time(:, mid_s);
    end

    % 无噪声采样偏移确定（一次，所有SNR共用）
    [rx_filt_clean,~] = match_filter(rx_shaped_clean, sps, 'rrc', rolloff, span_rrc);
    best_off_fixed = 0; bp_fixed = 0;
    for off=0:sps-1, st=rx_filt_clean(off+1:sps:end);
        if length(st)>=10, c=abs(sum(st(1:10).*conj(frame(1:10))));
            if c>bp_fixed, bp_fixed=c; best_off_fixed=off; end, end, end
    sig_pwr = mean(abs(rx_shaped_clean).^2);

    fprintf('--- fd=%dHz (blk=%d, %d块, offset=%d) ---\n', fd_hz, blk_fft, N_blks, best_off_fixed);
    fprintf('%-6s |', 'SNR');
    for mi=1:N_methods, fprintf(' %12s', methods{mi}); end
    fprintf('\n%s\n', repmat('-',1,6+13*N_methods));

    for si = 1:length(snr_list)
        snr_db = snr_list(si);
        nv = sig_pwr*10^(-snr_db/10);
        rng(300+fi*100+si);
        rx_shaped = rx_shaped_clean + sqrt(nv/2)*(randn(size(rx_shaped_clean))+1j*randn(size(rx_shaped_clean)));

        % RRC匹配+下采样（用无噪声确定的固定偏移）
        [rx_filt,~] = match_filter(rx_shaped, sps, 'rrc', rolloff, span_rrc);
        rx_sym = rx_filt(best_off_fixed+1:sps:end);
        if length(rx_sym)>N_frame, rx_sym=rx_sym(1:N_frame);
        elseif length(rx_sym)<N_frame, rx_sym=[rx_sym,zeros(1,N_frame-length(rx_sym))]; end
        nv_eq = max(nv, 1e-10);

        % 分块FFT（共享）
        Y_blks = cell(1,N_blks);
        for bi=1:N_blks
            bs = rx_sym(blk_starts(bi):blk_starts(bi)+sym_per_blk-1);
            Y_blks{bi} = fft(bs(blk_cp+1:end));
        end

        % BEM导频观测（共享，只构建一次）
        obs_y=[]; obs_x=[]; obs_t=[];
        for n=max_d+1:train_len
            xv=zeros(1,K);
            for p=1:K, idx=n-sym_delays(p); if idx>=1, xv(p)=training(idx); end, end
            obs_y(end+1)=rx_sym(n); obs_x=[obs_x;xv]; obs_t(end+1)=n;
        end
        for pi_i=1:length(pilot_positions)
            pp=pilot_positions(pi_i);
            for kk=max_d+1:pilot_len
                n=pp+kk-1; if n>N_frame, break; end
                xv=zeros(1,K);
                for p=1:K, idx=n-sym_delays(p);
                    if idx>=pp && idx<pp+pilot_len, xv(p)=pilot_sym(idx-pp+1);
                    elseif idx>=1 && idx<=train_len, xv(p)=training(idx); end
                end
                if any(xv~=0), obs_y(end+1)=rx_sym(n); obs_x=[obs_x;xv]; obs_t(end+1)=n; end
            end
        end

        % BEM估计（一次）
        fd_est = max(fd_hz, 0.5);
        [h_tv_bem,~,info_bem] = ch_est_bem(obs_y(:),obs_x,obs_t(:),N_frame,sym_delays,fd_est,sym_rate,nv_eq,'ce');

        bers = zeros(1, N_methods);
        for mi = 1:N_methods
            mname = methods{mi};

            % 构建每块H_est
            H_blks = cell(1,N_blks);
            for bi=1:N_blks
                mid = blk_starts(bi) + round(sym_per_blk/2);
                if strcmp(mname, 'oracle')
                    hm = h_paths(:, min(mid, N_frame));
                else
                    hm = h_tv_bem(:, min(mid, N_frame));
                end
                htd = zeros(1, blk_fft);
                for p=1:K, if sym_delays(p)+1<=blk_fft, htd(sym_delays(p)+1)=hm(p); end, end
                H_blks{bi} = fft(htd);
            end

            % 跨块Turbo: LMMSE-IC + BCJR
            x_bar_b = cell(1,N_blks); var_x_b = ones(1,N_blks);
            for bi=1:N_blks, x_bar_b{bi}=zeros(1,blk_fft); end
            [~,pm_t] = random_interleave(zeros(1,M_tot),codec.interleave_seed);
            bo_dec = [];
            for titer = 1:6
                LLR_all = zeros(1, M_tot);
                for bi=1:N_blks
                    [xt,mu_t,nvt] = eq_mmse_ic_fde(Y_blks{bi},H_blks{bi},x_bar_b{bi},var_x_b(bi),nv_eq);
                    le = soft_demapper(xt,mu_t,nvt,zeros(1,M_blk),'qpsk');
                    LLR_all((bi-1)*M_blk+1:bi*M_blk) = le;
                end
                ld = random_deinterleave(LLR_all, pm_t);
                ld = max(min(ld,30),-30);
                [~,Lpi,Lpc] = siso_decode_conv(ld,[],codec.gen_polys,codec.constraint_len,codec.decode_mode);
                bo_dec = double(Lpi>0);
                if titer < 6
                    Li = random_interleave(Lpc, codec.interleave_seed);
                    if length(Li)<M_tot, Li=[Li,zeros(1,M_tot-length(Li))];
                    else, Li=Li(1:M_tot); end
                    for bi=1:N_blks
                        [x_bar_b{bi},vr] = soft_mapper(Li((bi-1)*M_blk+1:bi*M_blk),'qpsk');
                        var_x_b(bi) = max(vr, nv_eq);
                    end
                end
            end
            nc = min(length(bo_dec), N_info_blk);
            bers(mi) = mean(bo_dec(1:nc) ~= ib(1:nc));
        end

        fprintf('%-6d |', snr_db);
        for mi=1:N_methods, fprintf(' %11.2f%%', bers(mi)*100); end
        fprintf('\n');
    end
    fprintf('\n');
end
fprintf('完成\n');
