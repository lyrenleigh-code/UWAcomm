---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-19-constant-doppler-isolation.md
created: 2026-04-19
updated: 2026-04-19
tags: [多普勒, 10_DopplerProc, 13_SourceCode, 测试矩阵]
---

# 恒定多普勒隔离测试 — 实现计划

## 架构定位

**挂靠位置**：`modules/10_DopplerProc/src/Matlab/`（多普勒模块级测试）

**理由**：
- 主题是"恒定多普勒估计+补偿能力"，属 10_DopplerProc 范畴
- 跨 6 体制调用 `modem_dispatch`，避免在各体制子目录下重复 6 份脚本
- 与现有 `test_doppler.m`（单元测试）并列，命名 `test_constant_doppler_sweep.m`

**依赖**：
```
10_DopplerProc/test_constant_doppler_sweep.m
├── 13_SourceCode/common/gen_uwa_channel.m    (fading_type='static' + doppler_rate=α)
├── 13_SourceCode/common/tx_chain.m           (各体制 TX)
├── 14_Streaming/rx/modem_dispatch.m          (统一 RX 入口)
└── 08_Sync/sync_dual_hfm.m + 10_DopplerProc/est_doppler_xcorr.m
```

## 步骤拆解

### Step 1：信道适配层（0.5h）

**问题**：`apply_channel.m` 当前 `static` 分支**不支持 α**（见 L37-45，只做纯卷积）。

**选项 A（推荐）**：直接调 `gen_uwa_channel` + `fading_type='static'` + `doppler_rate=α`。
已验证路径（gen_uwa_channel L98-104 当 fading_type='static' 时 h_time 仅取 gains_init，
不做 Jakes 衰落；L120 独立施加 α 重采样）。

**选项 B**：扩展 `apply_channel` 增加 `'static_doppler'` 分支。暂不做，避免膨胀。

**采用 A**：测试脚本内调 `gen_uwa_channel`，不动 `apply_channel`。

### Step 2：主测试脚本框架（1.5h）

**文件**：`modules/10_DopplerProc/src/Matlab/test_constant_doppler_sweep.m`

**伪代码骨架**：

```matlab
% test_constant_doppler_sweep.m
% 恒定多普勒隔离测试 V1.0
% 对应 spec: specs/active/2026-04-19-constant-doppler-isolation.md

clear functions; clear all; close all; clc;
diary('test_constant_doppler_sweep_results.txt');

%% 1. 路径 + 配置
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(genpath(fullfile(proj_root, '13_SourceCode')));
addpath(genpath(fullfile(proj_root, '14_Streaming')));
addpath(genpath(fullfile(proj_root, '08_Sync')));

alpha_list   = [0, 1e-4, -1e-4, 5e-4, -5e-4, 1e-3, -1e-3, ...
                3e-3, -3e-3, 1e-2, -1e-2, 3e-2, -3e-2];   % 13 点
snr_list     = [0, 5, 10, 15, 20];                        % 5 点
scheme_list  = {'SC-FDE','OFDM','SC-TDE','OTFS','DSSS','FH-MFSK'};
N_trials     = 3;  % 蒙特卡洛次数（每格点）

% 固定静态 6 径信道
delay_bins  = [0,5,15,40,60,90];
gains_raw   = gen_fixed_gains(delay_bins, seed=42);

fs = 192000; fc = 12000;  % 项目标准参数

%% 2. 结果矩阵
N_a = numel(alpha_list); N_s = numel(snr_list); N_sch = numel(scheme_list);
ber_tensor       = zeros(N_sch, N_a, N_s);
alpha_est_tensor = zeros(N_sch, N_a, N_s, N_trials);
alpha_rmse       = zeros(N_sch, N_a, N_s);
frame_det_rate   = zeros(N_sch, N_a, N_s);

%% 3. 三重扫描
for sch_i = 1:N_sch
    scheme = scheme_list{sch_i};
    for a_i = 1:N_a
        alpha = alpha_list(a_i);
        for s_i = 1:N_s
            snr = snr_list(s_i);
            for t_i = 1:N_trials
                % (a) TX 生成（按体制分派）
                [tx_pb, meta] = tx_chain(scheme, cfg);

                % (b) Channel：静态多径 + 恒定 α + AWGN
                ch_params = struct('fs',fs, 'delay_profile','custom', ...
                    'delays_s',delay_bins/fs, 'gains',gains_raw, ...
                    'num_paths',numel(delay_bins), ...
                    'doppler_rate',alpha, ...
                    'fading_type','static', ...       % 关 Jakes
                    'snr_db',snr, 'seed',100+t_i);
                [rx_pb, ch_info] = gen_uwa_channel(tx_pb, ch_params);

                % (c) RX：统一 dispatch
                rx_out = modem_dispatch(scheme, rx_pb, meta, cfg);

                % (d) 收集指标
                ber_tensor(sch_i,a_i,s_i) = ber_tensor(sch_i,a_i,s_i) + rx_out.ber;
                alpha_est_tensor(sch_i,a_i,s_i,t_i) = rx_out.alpha_est;
                frame_det_rate(sch_i,a_i,s_i) = frame_det_rate(sch_i,a_i,s_i) + rx_out.frame_detected;
            end
            % 平均
            ber_tensor(sch_i,a_i,s_i) = ber_tensor(sch_i,a_i,s_i) / N_trials;
            frame_det_rate(sch_i,a_i,s_i) = frame_det_rate(sch_i,a_i,s_i) / N_trials;
            alpha_rmse(sch_i,a_i,s_i) = sqrt(mean((alpha_est_tensor(sch_i,a_i,s_i,:) - alpha).^2));

            fprintf('%s α=%+.0e SNR=%2ddB: BER=%.2f%%, α_RMSE=%.2e, 帧检测=%.0f%%\n', ...
                scheme, alpha, snr, 100*ber_tensor(sch_i,a_i,s_i), ...
                alpha_rmse(sch_i,a_i,s_i), 100*frame_det_rate(sch_i,a_i,s_i));
        end
    end
end

%% 4. 保存
save('constant_doppler_sweep_results.mat', ...
     'ber_tensor','alpha_est_tensor','alpha_rmse','frame_det_rate', ...
     'alpha_list','snr_list','scheme_list');

%% 5. 可视化
plot_constant_doppler_sweep(ber_tensor, alpha_rmse, alpha_list, snr_list, scheme_list);

diary off;
```

**关键决策**：
- **N_trials=3**：平衡时间与稳健（13×5×6×3 = 1170 次端到端，按单次 5-10s 估 2h）
- **不用 parfor**：端到端测试内部已用大量全局路径 + diary，并行不可靠
- **seed 固定**：每格点 seed=100+t_i，可复现

### Step 3：各体制对接（0.5h）

**关键点**：`modem_dispatch` 在 14_Streaming/rx/ 下，签名假设：
```matlab
rx_out = modem_dispatch(scheme, rx_pb, meta, cfg)
% 返回：rx_out.ber, rx_out.alpha_est, rx_out.frame_detected
```

需核对各体制 modem_decode 是否返回 `alpha_est`；若无，需在 decode 内部曝出。

**OTFS 特殊处理**：OTFS 帧结构 `[LFM|guard|OTFS|guard|LFM]`，只有一对 LFM，estimator 单独走
`est_doppler_xcorr`（双 LFM 互相关）。`modem_decode_otfs` 应已支持。

**FH-MFSK 特殊处理**：确认其前导是否走 HFM-only，若是则用 `sync_dual_hfm` 的 α 输出。

### Step 4：可视化（0.5h）

**文件**：`modules/10_DopplerProc/src/Matlab/plot_constant_doppler_sweep.m`

**产出图**：
1. **α 估计精度曲线**：x=α_true（log 轴），y=α_NMSE (dB)，6 体制 × SNR=10dB 一条
2. **BER heatmap**：每体制一张，x=α（对数），y=SNR，cell=BER
3. **帧检测率 heatmap**：每体制一张
4. **残余 α 直方图**：α_true=1e-3, SNR=10dB 下 6 体制的 α_res 分布

### Step 5：运行 + 分析（1h）

MATLAB 测试流程（按项目 CLAUDE.md §MATLAB 测试调试流程）：

```matlab
clear functions; clear all;
cd('D:\Claude\TechReq\UWAcomm\modules\10_DopplerProc\src\Matlab');
diary('test_constant_doppler_sweep_results.txt');
run('test_constant_doppler_sweep.m');
diary off;
```

**分析要点**：
- 对照假设 H1-H5 逐条验证
- 找出每体制的 α "失效阈值"（BER 首次超过 10dB@1% 基线）
- 判断失效主因：α 估计饱和 vs resample 失真 vs 帧检测漏检

### Step 6：wiki 归档（0.5h）

**文件 1**：`wiki/modules/10_DopplerProc/恒定多普勒隔离测试.md`

```markdown
---
type: experiment
created: 2026-04-19
updated: 2026-04-19
tags: [多普勒, 恒定α, 10_DopplerProc, 测试矩阵]
---

# 恒定多普勒隔离测试

> spec: specs/active/2026-04-19-constant-doppler-isolation.md
> 测试脚本：modules/10_DopplerProc/src/Matlab/test_constant_doppler_sweep.m
> 结果：constant_doppler_sweep_results.mat

## 背景
[摘 spec]

## 方法
[摘 plan]

## 结果

### α 估计精度（SNR=10dB）
[表格/图]

### BER 矩阵（每体制）
[6 个子表]

### 失效阈值
| 体制 | α_max (α>0) | α_max (α<0) | 瓶颈 |

## 结论
[对照 H1-H5]

## 待办衍生
```

**文件 2**：更新 `wiki/comparisons/e2e-test-matrix.md`，追加"恒定多普勒隔离"小节。

**文件 3**：更新 `wiki/index.md` + `wiki/log.md`（Stop hook 强校验）。

**文件 4**：新结论入 `wiki/conclusions.md`（若有 2 条以上）。

### Step 7：spec 归档 + commit

- `specs/active/2026-04-19-constant-doppler-isolation.md` → `specs/archive/`
- commit：`feat(10_DopplerProc): 恒定多普勒隔离测试 + 6 体制扫描`

## 非目标（显式排除）

- 不改 decode 算法
- 不引入时变 α
- 不碰 14_Streaming 真流式
- 不做 oracle α 对照（已在现有矩阵）

## 开放问题（先做后议）

1. **gains_raw 是否用复数**？静态信道各径是否加随机相位？先跟现有 `test_*_discrete_doppler.m`
   的 `gen_fixed_gains` 保持一致
2. **负 α 是否等价于正 α**？理论对称但 resampler 边界可能不对称，值得显式扫
3. **α=3e-2 下 LFM 斜率估计是否溢出**？可能需要 LFM 自身多普勒估计器（而非相位差）

## 回滚策略

若运行发现 RX 链路在恒定 α 下崩得厉害（全 50% BER），先做**减半测试**：
- 只测 SC-FDE 单体制
- 定位失效在同步 / α 估计 / resample / 均衡哪一环
- 针对该环节单独开衍生 spec，而非一次改全部
