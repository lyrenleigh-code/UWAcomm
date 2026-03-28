%% test_iterative.m
% 功能：Turbo均衡单元测试——SC-FDE/OFDM/SC-TDE/OTFS + BER收敛验证 + 可视化
% 版本：V7.0.0
%
% 发射链路：info_bits → conv_encode → random_interleave → QPSK映射 → x[n]
% 接收链路：SISO均衡 ⇌ SISO(BCJR)译码 外信息迭代

clc; close all;
fprintf('========================================\n');
fprintf('  Turbo均衡 — 全体制测试 V7.0\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, '03_Interleaving', 'src', 'Matlab'));

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
codec = struct('gen_polys', [7,5], 'constraint_len', 3, 'interleave_seed', 7);
bits2qpsk = @(b) constellation(bi2de(reshape(b(1:floor(length(b)/2)*2), 2, []).', 'left-msb') + 1);

all_ber = {}; all_labels = {}; all_x_first = {}; all_x_last = {};

%% ==================== 一、SC-FDE ==================== %%
fprintf('--- 1. SC-FDE ---\n\n');
try
    rng(50); N_fde=256; nv=0.5; n_code=2; mem=codec.constraint_len-1;
    h=zeros(1,N_fde); h(1)=1; h(4)=0.5*exp(1j*0.5); h(8)=0.25*exp(1j*1.2);
    h=h/sqrt(sum(abs(h).^2)); H_fde=fft(h);
    M_coded=2*N_fde; N_info=M_coded/n_code-mem;
    info_bits=randi([0 1],1,N_info);
    coded=conv_encode(info_bits,codec.gen_polys,codec.constraint_len);
    coded=coded(1:M_coded);
    inter_bits=random_interleave(coded,codec.interleave_seed);
    x_tx=bits2qpsk(inter_bits);
    Y=fft(x_tx).*H_fde+sqrt(nv/2)*(randn(1,N_fde)+1j*randn(1,N_fde));

    max_iter=6;
    fprintf('SC-FDE (N=%d, SNR=%.0fdB, %d迭代):\n',N_fde,-10*log10(nv),max_iter);
    [bits_out,info_f]=turbo_equalizer_scfde(Y,H_fde,max_iter,nv,codec);

    ber_sym=zeros(1,max_iter);
    for k=1:max_iter
        xk=info_f.x_hat_per_iter{k};
        ber_sym(k)=mean(sign(real(xk(1:N_fde)))~=sign(real(x_tx)));
        fprintf('    迭代%d: symBER=%.1f%%\n',k,ber_sym(k)*100);
    end
    n_cmp=min(length(bits_out),length(info_bits));
    ber_info=mean(bits_out(1:n_cmp)~=info_bits(1:n_cmp));
    fprintf('    最终infoBER=%.2f%%\n',ber_info*100);

    all_ber{end+1}=ber_sym; all_labels{end+1}='SC-FDE';
    all_x_first{end+1}=info_f.x_hat_per_iter{1}(1:N_fde);
    all_x_last{end+1}=info_f.x_hat_per_iter{max_iter}(1:N_fde);
    if ber_sym(end)<=ber_sym(1)+0.02, pass_count=pass_count+1;
        fprintf('[通过] SC-FDE\n');
    else, fail_count=fail_count+1; fprintf('[失败] SC-FDE 发散\n'); end
catch e
    fprintf('[失败] SC-FDE | %s\n',e.message); fail_count=fail_count+1;
    all_ber{end+1}=NaN; all_labels{end+1}='SC-FDE';
    all_x_first{end+1}=[]; all_x_last{end+1}=[];
end

%% ==================== 二、OFDM ==================== %%
fprintf('\n--- 2. OFDM ---\n\n');
try
    rng(60); N_ofdm=256; nv_o=0.5;
    h_o=zeros(1,N_ofdm); h_o(1)=1; h_o(5)=0.4*exp(1j*0.7); h_o(10)=0.2*exp(1j*1.5);
    h_o=h_o/sqrt(sum(abs(h_o).^2)); H_ofdm=fft(h_o);
    M_coded_o=2*N_ofdm; N_info_o=M_coded_o/n_code-mem;
    info_o=randi([0 1],1,N_info_o);
    coded_o=conv_encode(info_o,codec.gen_polys,codec.constraint_len);
    coded_o=coded_o(1:M_coded_o);
    inter_o=random_interleave(coded_o,codec.interleave_seed);
    x_o=bits2qpsk(inter_o);
    Y_o=fft(x_o).*H_ofdm+sqrt(nv_o/2)*(randn(1,N_ofdm)+1j*randn(1,N_ofdm));

    max_iter_o=6;
    fprintf('OFDM (N=%d, SNR=%.0fdB, %d迭代):\n',N_ofdm,-10*log10(nv_o),max_iter_o);
    [bits_out_o,info_o_r]=turbo_equalizer_ofdm(Y_o,H_ofdm,max_iter_o,nv_o,codec);

    ber_sym_o=zeros(1,max_iter_o);
    for k=1:max_iter_o
        xk=info_o_r.x_hat_per_iter{k};
        ber_sym_o(k)=mean(sign(real(xk(1:N_ofdm)))~=sign(real(x_o)));
        fprintf('    迭代%d: symBER=%.1f%%\n',k,ber_sym_o(k)*100);
    end
    n_cmp_o=min(length(bits_out_o),length(info_o));
    ber_info_o=mean(bits_out_o(1:n_cmp_o)~=info_o(1:n_cmp_o));
    fprintf('    最终infoBER=%.2f%%\n',ber_info_o*100);

    all_ber{end+1}=ber_sym_o; all_labels{end+1}='OFDM';
    all_x_first{end+1}=info_o_r.x_hat_per_iter{1}(1:N_ofdm);
    all_x_last{end+1}=info_o_r.x_hat_per_iter{max_iter_o}(1:N_ofdm);
    if ber_sym_o(end)<=ber_sym_o(1)+0.02, pass_count=pass_count+1;
        fprintf('[通过] OFDM\n');
    else, fail_count=fail_count+1; fprintf('[失败] OFDM 发散\n'); end
catch e
    fprintf('[失败] OFDM | %s\n',e.message); fail_count=fail_count+1;
    all_ber{end+1}=NaN; all_labels{end+1}='OFDM';
    all_x_first{end+1}=[]; all_x_last{end+1}=[];
end

%% ==================== 三、SC-TDE ==================== %%
fprintf('\n--- 3. SC-TDE ---\n\n');
try
    rng(42);
    h_tde=[1, 0.5*exp(1j*0.4), 0.3*exp(1j*1.0)];
    h_tde=h_tde/sqrt(sum(abs(h_tde).^2));
    train_len=200; snr_tde=8; nv_tde=10^(-snr_tde/10);  % RLS需较高SNR

    % 发射端：info → 编码 → 交织 → QPSK → [training, data]
    N_data_sym=1000;  % 长数据块：BCJR编码增益更充分，交织更有效
    M_coded_t=2*N_data_sym; N_info_t=M_coded_t/n_code-mem;
    info_t=randi([0 1],1,N_info_t);
    coded_t=conv_encode(info_t,codec.gen_polys,codec.constraint_len);
    coded_t=coded_t(1:M_coded_t);
    inter_t=random_interleave(coded_t,codec.interleave_seed);
    data_sym=bits2qpsk(inter_t);
    training=constellation(randi(4,1,train_len));
    tx=[training, data_sym];
    rx=conv(tx,h_tde); rx=rx(1:length(tx));
    rx=rx+sqrt(nv_tde/2)*(randn(size(rx))+1j*randn(size(rx)));

    max_iter_t=6;
    eq_params=struct('num_ff',21,'num_fb',10,'lambda',0.998,...
                     'pll',struct('enable',true,'Kp',0.01,'Ki',0.005));
    fprintf('SC-TDE (SNR=%ddB, %d径, %d训练+%d数据, %d迭代):\n',...
            snr_tde,length(h_tde),train_len,N_data_sym,max_iter_t);

    [bits_out_t,info_t_r]=turbo_equalizer_sctde(rx,h_tde,training,...
        max_iter_t,nv_tde,eq_params,codec);

    ber_sym_t=zeros(1,max_iter_t);
    for k=1:max_iter_t
        xk=info_t_r.x_hat_per_iter{k};
        nd=min(length(xk)-train_len,N_data_sym);
        if nd>0
            ber_sym_t(k)=mean(sign(real(xk(train_len+1:train_len+nd)))~=sign(real(data_sym(1:nd))));
        else, ber_sym_t(k)=0.5; end
        fprintf('    迭代%d: symBER=%.1f%%\n',k,ber_sym_t(k)*100);
    end
    n_cmp_t=min(length(bits_out_t),length(info_t));
    ber_info_t=mean(bits_out_t(1:n_cmp_t)~=info_t(1:n_cmp_t));
    fprintf('    最终infoBER=%.2f%%\n',ber_info_t*100);

    all_ber{end+1}=ber_sym_t; all_labels{end+1}='SC-TDE';
    xk1=info_t_r.x_hat_per_iter{1}; xkL=info_t_r.x_hat_per_iter{max_iter_t};
    nd=min(length(xk1)-train_len,N_data_sym);
    all_x_first{end+1}=xk1(train_len+1:train_len+nd);
    all_x_last{end+1}=xkL(train_len+1:train_len+nd);
    if ber_sym_t(end)<=ber_sym_t(1)+0.02, pass_count=pass_count+1;
        fprintf('[通过] SC-TDE\n');
    else, fail_count=fail_count+1; fprintf('[失败] SC-TDE 发散\n'); end
catch e
    fprintf('[失败] SC-TDE | %s\n',e.message); fail_count=fail_count+1;
    all_ber{end+1}=NaN; all_labels{end+1}='SC-TDE';
    all_x_first{end+1}=[]; all_x_last{end+1}=[];
end

%% ==================== 四、OTFS ==================== %%
fprintf('\n--- 4. OTFS ---\n\n');
try
    rng(70); N_otfs=8; M_otfs=32; nv_ot=0.5;
    n_dd=N_otfs*M_otfs;
    M_coded_ot=2*n_dd; N_info_ot=M_coded_ot/n_code-mem;
    info_ot=randi([0 1],1,N_info_ot);
    coded_ot=conv_encode(info_ot,codec.gen_polys,codec.constraint_len);
    coded_ot=coded_ot(1:M_coded_ot);
    inter_ot=random_interleave(coded_ot,codec.interleave_seed);
    sym_ot=bits2qpsk(inter_ot);
    dd_vec=[sym_ot(1:min(length(sym_ot),n_dd)), zeros(1,max(0,n_dd-length(sym_ot)))];
    dd_data=reshape(dd_vec,M_otfs,N_otfs).';

    h_dd=zeros(N_otfs,M_otfs);
    h_dd(1,1)=1; h_dd(2,2)=0.4*exp(1j*0.6);
    path_info=struct('num_paths',2,'delay_idx',[0,1],'doppler_idx',[0,1],...
                     'gain',[1,0.4*exp(1j*0.6)]);
    Y_dd=dd_data;
    for p=1:path_info.num_paths
        dk=path_info.doppler_idx(p); dl=path_info.delay_idx(p);
        Y_dd=Y_dd+path_info.gain(p)*circshift(dd_data,[dk,dl])*(p>1);
    end
    Y_dd=Y_dd+sqrt(nv_ot/2)*(randn(N_otfs,M_otfs)+1j*randn(N_otfs,M_otfs));

    max_iter_ot=4;
    fprintf('OTFS (N=%d, M=%d, SNR=%.0fdB, %d迭代):\n',N_otfs,M_otfs,-10*log10(nv_ot),max_iter_ot);

    [bits_out_ot,info_ot_r]=turbo_equalizer_otfs(Y_dd,h_dd,path_info,...
        N_otfs,M_otfs,max_iter_ot,nv_ot,codec);

    ber_sym_ot=zeros(1,max_iter_ot);
    n_dd_cmp=min(length(sym_ot),n_dd);
    for k=1:max_iter_ot
        xk=info_ot_r.x_hat_per_iter{k};
        ber_sym_ot(k)=mean(sign(real(xk(1:n_dd_cmp)))~=sign(real(dd_vec(1:n_dd_cmp))));
        fprintf('    迭代%d: symBER=%.1f%%\n',k,ber_sym_ot(k)*100);
    end
    n_cmp_ot=min(length(bits_out_ot),length(info_ot));
    ber_info_ot=mean(bits_out_ot(1:n_cmp_ot)~=info_ot(1:n_cmp_ot));
    fprintf('    最终infoBER=%.2f%%\n',ber_info_ot*100);

    all_ber{end+1}=ber_sym_ot; all_labels{end+1}='OTFS';
    all_x_first{end+1}=info_ot_r.x_hat_per_iter{1}(1:n_dd_cmp);
    all_x_last{end+1}=info_ot_r.x_hat_per_iter{max_iter_ot}(1:n_dd_cmp);
    if ber_sym_ot(end)<=ber_sym_ot(1)+0.02, pass_count=pass_count+1;
        fprintf('[通过] OTFS\n');
    else, fail_count=fail_count+1; fprintf('[失败] OTFS 发散\n'); end
catch e
    fprintf('[失败] OTFS | %s\n',e.message); fail_count=fail_count+1;
    all_ber{end+1}=NaN; all_labels{end+1}='OTFS';
    all_x_first{end+1}=[]; all_x_last{end+1}=[];
end

%% ==================== 测试汇总 ==================== %%
fprintf('\n========================================\n');
fprintf('  测试完成：%d 通过, %d 失败, 共 %d 项\n',pass_count,fail_count,pass_count+fail_count);
fprintf('========================================\n');
if fail_count==0, fprintf('  全部通过！\n');
else, fprintf('  存在失败项！\n'); end

%% ==================== 可视化 ==================== %%
colors=lines(4);

figure('Name','Turbo均衡BER收敛','Position',[100 300 800 400]);
for k=1:length(all_ber)
    bv=all_ber{k};
    if isnumeric(bv) && ~any(isnan(bv))
        plot(1:length(bv),bv*100,'-o','Color',colors(k,:),...
            'LineWidth',1.8,'MarkerSize',7,'DisplayName',all_labels{k}); hold on;
    end
end
xlabel('Turbo迭代次数'); ylabel('符号BER (%)');
title('Turbo均衡 BER 收敛曲线'); legend('Location','best'); grid on;
set(gca,'FontSize',12);

figure('Name','星座图对比','Position',[100 50 1000 700]);
ns=length(all_labels);
for k=1:ns
    x1=all_x_first{k}; xL=all_x_last{k};
    if isempty(x1), continue; end
    subplot(ns,2,(k-1)*2+1);
    plot(real(x1),imag(x1),'.','MarkerSize',3,'Color',[.5 .5 .8]); hold on;
    plot(real(constellation),imag(constellation),'r+','MarkerSize',14,'LineWidth',2);
    axis equal; xlim([-1.5 1.5]); ylim([-1.5 1.5]); grid on;
    title(sprintf('%s 迭代1',all_labels{k}));
    subplot(ns,2,(k-1)*2+2);
    plot(real(xL),imag(xL),'.','MarkerSize',3,'Color',[.2 .7 .2]); hold on;
    plot(real(constellation),imag(constellation),'r+','MarkerSize',14,'LineWidth',2);
    axis equal; xlim([-1.5 1.5]); ylim([-1.5 1.5]); grid on;
    title(sprintf('%s 最终迭代',all_labels{k}));
end
sgtitle('星座图对比（左=迭代1，右=最终迭代）','FontSize',13);
fprintf('\n可视化完成\n');
