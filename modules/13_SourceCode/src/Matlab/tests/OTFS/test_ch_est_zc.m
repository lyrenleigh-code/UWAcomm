%% test_ch_est_zc.m — ZC/叠加 pilot 信道估计对比测试
% 对比冲激pilot(A), ZC pilot(B), 叠加pilot(C)的信道估计精度
% 用法: run('test_ch_est_zc.m')

clc; close all;
fprintf('========================================\n');
fprintf('  ZC Pilot 信道估计验证\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '07_ChannelEstEq', 'src', 'Matlab'));

%% 参数
N = 32; M = 64; cp_len = 32;
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);

% 5径信道（静态）
delay_bins = [0, 1, 3, 5, 8];
gains_true = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];

%% 工具: 对DD帧施加DD域信道（静态）
apply_dd_channel = @(dd, delays, gains) apply_dd_static(dd, delays, gains, N, M);

%% 测试 1: 无噪声 — 冲激pilot vs ZC pilot
fprintf('--- 测试1: 无噪声信道估计对比 ---\n\n');

% Config A: 冲激pilot
cfgA = struct('mode','impulse', 'guard_k',4, 'guard_l',10);
[~, ~, ~, didxA] = otfs_pilot_embed(zeros(1,1), N, M, cfgA);
cfgA.pilot_value = sqrt(length(didxA));

% Config B: ZC pilot
cfgB = struct('mode','sequence', 'seq_type','zc', 'seq_root',1, 'guard_k',4, 'guard_l',10);
[~, ~, ~, didxB] = otfs_pilot_embed(zeros(1,1), N, M, cfgB);
cfgB.pilot_value = sqrt(length(didxB));

% Config C: 叠加 pilot
cfgC = struct('mode','superimposed', 'pilot_power',0.2);

% 用pilot-only信号探测真实DD信道
dd_pilot_A = zeros(N, M);
dd_pilot_A(ceil(N/2), ceil(M/2)) = cfgA.pilot_value;
% 对DD应用信道（静态离散径）
dd_after_A = apply_dd_channel(dd_pilot_A, delay_bins, gains_true);

% 用dummy数据获取pilot结构, 然后只保留pilot部分
dummy_data = zeros(1, length(didxB));  % 数据位全0
[~, pinfo_B, ~, ~] = otfs_pilot_embed(constellation(ones(1,length(didxB))), N, M, cfgB);
dd_pilot_B = zeros(N, M);
for pi_idx = 1:size(pinfo_B.positions, 1)
    kk = pinfo_B.positions(pi_idx, 1);
    ll = pinfo_B.positions(pi_idx, 2);
    dd_pilot_B(kk, ll) = pinfo_B.values(pi_idx);
end
dd_after_B = apply_dd_channel(dd_pilot_B, delay_bins, gains_true);

% 信道估计
Y_A = dd_after_A;
[h_A, pi_A] = ch_est_otfs_dd(Y_A, struct('positions',[ceil(N/2),ceil(M/2)], 'values',cfgA.pilot_value, ...
    'guard_mask',build_guard(N,M,ceil(N/2),ceil(M/2),4,10)), N, M);

Y_B = dd_after_B;
[h_B, pi_B] = ch_est_otfs_zc(Y_B, pinfo_B, N, M);

% 叠加 pilot: 完整 dd_frame = data + pilot (需要真实数据因为它们叠加)
[~, didxC] = deal([], []);
[~, ~, ~, didxC] = otfs_pilot_embed(zeros(1,1), N, M, cfgC);
% Superimposed: dd = data + pilot_pattern (pilot_pattern自动生成)
[dd_frame_C, pinfo_C, ~, ~] = otfs_pilot_embed(constellation(ones(1,length(didxC))), N, M, cfgC);
% 对完整帧施加信道
dd_after_C = apply_dd_channel(dd_frame_C, delay_bins, gains_true);
% 估计
Y_C = dd_after_C;
[h_C, pi_C] = ch_est_otfs_superimposed(Y_C, pinfo_C, N, M, struct('iter',3));

% 对比估计 vs 真实
fprintf('冲激 A: paths=%d\n', pi_A.num_paths);
fprintf('  delays=[%s], |gains|=[%s]\n', ...
    num2str(pi_A.delay_idx), num2str(abs(pi_A.gain), '%.3f '));
fprintf('ZC    B: paths=%d\n', pi_B.num_paths);
fprintf('  delays=[%s], |gains|=[%s]\n', ...
    num2str(pi_B.delay_idx), num2str(abs(pi_B.gain), '%.3f '));
fprintf('叠加 C: paths=%d\n', pi_C.num_paths);
fprintf('  delays=[%s], |gains|=[%s]\n', ...
    num2str(pi_C.delay_idx), num2str(abs(pi_C.gain), '%.3f '));
fprintf('真实: delays=[%s], |gains|=[%s]\n\n', ...
    num2str(delay_bins), num2str(abs(gains_true), '%.3f '));

% 计算NMSE
nmse_A = compute_nmse(h_A, delay_bins, gains_true, N, M);
nmse_B = compute_nmse(h_B, delay_bins, gains_true, N, M);
nmse_C = compute_nmse(h_C, delay_bins, gains_true, N, M);
fprintf('NMSE (无噪声): A冲激=%.2fdB, B ZC=%.2fdB, C叠加=%.2fdB\n\n', ...
    nmse_A, nmse_B, nmse_C);

%% 测试 2: 加噪扫描
fprintf('--- 测试2: NMSE vs SNR ---\n\n');
snr_list = [5, 10, 15, 20, 25, 30];
N_mc = 10;
nmse_A_arr = zeros(1, length(snr_list));
nmse_B_arr = zeros(1, length(snr_list));
nmse_C_arr = zeros(1, length(snr_list));

for si = 1:length(snr_list)
    snr_db = snr_list(si);
    nmse_A_trial = zeros(1, N_mc);
    nmse_B_trial = zeros(1, N_mc);
    nmse_C_trial = zeros(1, N_mc);
    for trial = 1:N_mc
        rng(si*1000 + trial);
        % A
        sig_pwr_A = mean(abs(dd_after_A(:)).^2);
        nv_A = sig_pwr_A * 10^(-snr_db/10);
        Y_An = dd_after_A + sqrt(nv_A/2)*(randn(N,M)+1j*randn(N,M));
        [h_An, ~] = ch_est_otfs_dd(Y_An, struct('positions',[ceil(N/2),ceil(M/2)], 'values',cfgA.pilot_value, ...
            'guard_mask',build_guard(N,M,ceil(N/2),ceil(M/2),4,10)), N, M);
        nmse_A_trial(trial) = compute_nmse(h_An, delay_bins, gains_true, N, M);

        % B
        sig_pwr_B = mean(abs(dd_after_B(:)).^2);
        nv_B = sig_pwr_B * 10^(-snr_db/10);
        Y_Bn = dd_after_B + sqrt(nv_B/2)*(randn(N,M)+1j*randn(N,M));
        [h_Bn, ~] = ch_est_otfs_zc(Y_Bn, pinfo_B, N, M);
        nmse_B_trial(trial) = compute_nmse(h_Bn, delay_bins, gains_true, N, M);

        % C (叠加 - 每trial重新生成随机数据)
        data_C = constellation(randi(4, 1, length(didxC)));
        [dd_frame_Cm, pinfo_Cm, ~, ~] = otfs_pilot_embed(data_C, N, M, cfgC);
        dd_after_Cm = apply_dd_channel(dd_frame_Cm, delay_bins, gains_true);
        sig_pwr_C = mean(abs(dd_after_Cm(:)).^2);
        nv_C = sig_pwr_C * 10^(-snr_db/10);
        Y_Cn = dd_after_Cm + sqrt(nv_C/2)*(randn(N,M)+1j*randn(N,M));
        [h_Cn, ~] = ch_est_otfs_superimposed(Y_Cn, pinfo_Cm, N, M, struct('iter',3));
        nmse_C_trial(trial) = compute_nmse(h_Cn, delay_bins, gains_true, N, M);
    end
    nmse_A_arr(si) = mean(nmse_A_trial);
    nmse_B_arr(si) = mean(nmse_B_trial);
    nmse_C_arr(si) = mean(nmse_C_trial);
end

fprintf('SNR(dB)  |  A冲激(dB)  |  B ZC(dB)  |  C 叠加(dB)\n');
fprintf('%s\n', repmat('-', 1, 52));
for si = 1:length(snr_list)
    fprintf('  %3d    |   %6.2f    |  %6.2f    |   %6.2f\n', ...
        snr_list(si), nmse_A_arr(si), nmse_B_arr(si), nmse_C_arr(si));
end

%% 保存
result_file = fullfile(fileparts(mfilename('fullpath')), 'test_ch_est_zc_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'ZC/叠加 Pilot 信道估计对比\n\n');
fprintf(fid, '无噪声: A冲激=%.2fdB, B ZC=%.2fdB, C叠加=%.2fdB\n\n', nmse_A, nmse_B, nmse_C);
fprintf(fid, 'SNR扫描(10次MC):\n');
for si = 1:length(snr_list)
    fprintf(fid, '  SNR=%ddB: A=%.2fdB, B=%.2fdB, C=%.2fdB\n', ...
        snr_list(si), nmse_A_arr(si), nmse_B_arr(si), nmse_C_arr(si));
end
fclose(fid);
fprintf('\n结果已保存\n');

%% ====== 辅助函数 ======
function out = apply_dd_static(dd_in, delays, gains, N, M)
% 模拟DD域静态信道：2D循环卷积
out = zeros(N, M);
for pp = 1:length(delays)
    dl = delays(pp);
    out = out + gains(pp) * circshift(dd_in, [0, dl]);
end
end

function gmask = build_guard(N, M, pk, pl, gk, gl)
gmask = false(N, M);
for dk = -gk:gk
    for dl = -gl:gl
        kk = mod(pk-1+dk, N)+1;
        ll = mod(pl-1+dl, M)+1;
        gmask(kk, ll) = true;
    end
end
end

function nmse_db = compute_nmse(h_est, delays_true, gains_true, N, M)
% 基于主径对比（以主径位置、dl=0为参考）
ref_energy = sum(abs(gains_true).^2);
err_energy = 0;
pk = ceil(N/2); pl = ceil(M/2);
for pp = 1:length(delays_true)
    dl = delays_true(pp);
    ll = mod(pl-1+dl, M)+1;
    est_gain = h_est(pk, ll);
    err_energy = err_energy + abs(est_gain - gains_true(pp))^2;
end
nmse_db = 10*log10(err_energy / ref_energy + 1e-20);
end
