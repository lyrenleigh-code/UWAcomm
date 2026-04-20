function grids = bench_grids()
% 功能：返回 E2E benchmark 五阶段参数网格
% 版本：V1.0.0
% 输出：
%   grids - struct，包含 A1/A2/A3/B/C 五个字段，每个字段为该阶段的扫描定义
%
% 网格规模（见 specs/active/2026-04-19-e2e-timevarying-baseline.md）：
%   A1  Jakes-only             : 6 × 5 × 6 × 2 = 360 点
%   A2  固定多普勒 α             : 6 × 5 × 4 × 2 = 240 点
%   A3  Jakes × α 二维叠加        : 6 × 4 × 4 × 3 = 288 点
%   B   离散 Doppler / Rician 混合 : 6 × 5 × 4     = 120 点
%   C   多 seed 帧检测率           : 6 × 3 × 3 × 5 = 270 次
%
% 备注：
%   schemes 顺序固定（高速组在前），便于交叉对比时列对齐
%   seeds 为单值（A1/A2/A3/B）或向量（C 多 seed）

%% ========== 通用定义 ========== %%
all_schemes = {'SC-FDE','OFDM','SC-TDE','OTFS','DSSS','FH-MFSK'};

%% ========== 阶段 A1：Jakes-only ========== %%
grids.A1 = struct();
grids.A1.schemes       = all_schemes;
grids.A1.snr_list      = [0, 5, 10, 15, 20];
grids.A1.fd_hz_list    = [0, 0.5, 1, 2, 5, 10];
grids.A1.doppler_rate  = 0;
grids.A1.profiles      = {'custom6','exponential'};
grids.A1.seed          = 42;
grids.A1.expected_pts  = numel(all_schemes) * numel(grids.A1.snr_list) * ...
                          numel(grids.A1.fd_hz_list) * numel(grids.A1.profiles);

%% ========== 阶段 A2：固定多普勒 α ========== %%
grids.A2 = struct();
grids.A2.schemes           = all_schemes;
grids.A2.snr_list          = [0, 5, 10, 15, 20];
grids.A2.fd_hz             = 0;
grids.A2.doppler_rate_list = [0, 5e-4, 1e-3, 2e-3];
grids.A2.profiles          = {'custom6','exponential'};
grids.A2.seed              = 42;
grids.A2.expected_pts      = numel(all_schemes) * numel(grids.A2.snr_list) * ...
                              numel(grids.A2.doppler_rate_list) * numel(grids.A2.profiles);

%% ========== 阶段 A3：Jakes × α 二维叠加 ========== %%
grids.A3 = struct();
grids.A3.schemes           = all_schemes;
grids.A3.snr_list          = [5, 10, 15];
grids.A3.fd_hz_list        = [0, 1, 5, 10];
grids.A3.doppler_rate_list = [0, 5e-4, 1e-3, 2e-3];
grids.A3.profiles          = {'custom6'};
grids.A3.seed              = 42;
grids.A3.expected_pts      = numel(all_schemes) * numel(grids.A3.snr_list) * ...
                              numel(grids.A3.fd_hz_list) * numel(grids.A3.doppler_rate_list);

%% ========== 阶段 B：离散 Doppler / Rician 混合对照 ========== %%
grids.B = struct();
grids.B.schemes      = all_schemes;
grids.B.snr_list     = [0, 5, 10, 15, 20];
grids.B.channel_set  = {'disc-5Hz','hyb-K20','hyb-K10','hyb-K5'};
grids.B.seed         = 42;
grids.B.expected_pts = numel(all_schemes) * numel(grids.B.snr_list) * numel(grids.B.channel_set);

%% ========== 阶段 D：恒定多普勒 α 扫描（constant-doppler-isolation） ========== %%
% 对应 spec: 2026-04-19-constant-doppler-isolation.md
% 目的：拿 alpha_est vs alpha_true 曲线定位模糊阈值
grids.D = struct();
grids.D.schemes           = all_schemes;
grids.D.snr_list          = [10];  % 单 SNR（诊断足够）
grids.D.doppler_rate_list = [0, 1e-4, -1e-4, 5e-4, -5e-4, 1e-3, -1e-3, ...
                              3e-3, -3e-3, 1e-2, -1e-2, 3e-2, -3e-2];  % 13 点
grids.D.fd_hz             = 0;        % 关 Jakes，纯 static + α
grids.D.profiles          = {'custom6'};
grids.D.seed              = 42;
grids.D.expected_pts      = numel(all_schemes) * numel(grids.D.snr_list) * ...
                              numel(grids.D.doppler_rate_list);

%% ========== 阶段 C：多 seed 帧检测率 ========== %%
grids.C = struct();
grids.C.schemes      = all_schemes;
grids.C.snr_list     = [0, 5, 10];
grids.C.fd_hz_list   = [0, 1, 5];
grids.C.doppler_rate = 0;
grids.C.profiles     = {'custom6'};
grids.C.seeds        = [42, 43, 44, 45, 46];
grids.C.expected_pts = numel(all_schemes) * numel(grids.C.snr_list) * ...
                        numel(grids.C.fd_hz_list) * numel(grids.C.seeds);

end
