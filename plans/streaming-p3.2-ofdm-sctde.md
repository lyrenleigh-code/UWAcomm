---
project: uwacomm
type: plan
status: done
created: 2026-04-16
parent_spec: specs/active/2026-04-16-streaming-p3.2-ofdm-sctde.md
phase: P3.2
tags: [流式仿真, 14_Streaming, 统一API, OFDM, SC-TDE]
---

# Streaming P3.2 — OFDM + SC-TDE 实施计划

## 目标

为 OFDM 和 SC-TDE 实现 `modem_encode / modem_decode`，接入 `modem_dispatch`。
Static + time-varying 一步到位。尽量复用模块 06/07/12 现有函数。

## 非目标

- 不改 01–13 算法模块代码
- 不加 UI 体制专属参数行（仅 scheme 下拉）
- 不做 passband 端到端（P4 范围）

## 影响文件

### 新建（6 文件）

| 文件 | 作用 |
|------|------|
| `tx/modem_encode_ofdm.m` | OFDM TX：conv→interleave→QPSK→null 子载波分配→ofdm_modulate→RRC |
| `rx/modem_decode_ofdm.m` | OFDM RX：RRC→定时→[CFO]→OMP/BEM→去CP+FFT→crossblock Turbo→bits |
| `tx/modem_encode_sctde.m` | SC-TDE TX：conv→interleave→QPSK→训练+[散布导频]→RRC |
| `rx/modem_decode_sctde.m` | SC-TDE RX：RRC→定时→static:GAMP+turbo_sctde / tv:BEM+ISI消除→bits |
| `tests/test_p3.2_ofdm_sctde.m` | 双体制×3SNR 回归测试 |
| `plans/streaming-p3.2-ofdm-sctde.md` | 本文件 |

### 修改（3 文件）

| 文件 | 改动 |
|------|------|
| `common/modem_dispatch.m` | 加 `'OFDM'` 和 `'SCTDE'` case |
| `common/sys_params_default.m` | 加 `sys.ofdm` 和 `sys.sctde` 子结构 |
| `ui/p3_demo_ui.m` | scheme 下拉加 OFDM/SC-TDE；on_transmit 参数分支；addpath 06/12 |

## 关键函数签名（已验证）

```matlab
% 06_MultiCarrier
[signal, params] = ofdm_modulate(freq_symbols, N, cp_len, 'cp')

% 07_ChannelEstEq
[h_est, H_est, support] = ch_est_omp(y, Phi, N, K_sparse, noise_var)

% 12_IterativeProc
[bits_out, iter_info] = turbo_equalizer_scfde_crossblock(Y_freq_blocks, H_est_blocks, num_iter, nv, codec_p)
[bits_out, iter_info] = turbo_equalizer_sctde(rx, h_est, training, num_iter, snr_or_nv, eq_params, codec_p)
```

## 实现步骤

### Step 1: sys_params_default 加子结构

```matlab
%% OFDM
sys.ofdm.blk_fft      = 256;
sys.ofdm.blk_cp       = 96;
sys.ofdm.N_blocks     = 16;
sys.ofdm.null_spacing = 32;
sys.ofdm.rolloff      = 0.35;
sys.ofdm.span         = 6;
sys.ofdm.turbo_iter   = 10;
sys.ofdm.fading_type  = 'static';
sys.ofdm.fd_hz        = 0;
sys.ofdm.sym_delays   = [0, 5, 15, 40, 60, 90];
sys.ofdm.gains_raw    = [同 scfde];

%% SC-TDE
sys.sctde.train_len         = 500;
sys.sctde.pilot_cluster_len = 140;
sys.sctde.pilot_spacing     = 300;
sys.sctde.turbo_iter        = 10;
sys.sctde.rolloff           = 0.35;
sys.sctde.span              = 6;
sys.sctde.fading_type       = 'static';
sys.sctde.fd_hz             = 0;
sys.sctde.sym_delays        = [0, 5, 15, 40, 60, 90];
sys.sctde.gains_raw         = [同 scfde];
sys.sctde.num_ff            = 31;
sys.sctde.num_fb            = 90;
sys.sctde.lambda            = 0.998;
```

### Step 2: modem_encode_ofdm（~80 行）

抽取自 test_ofdm_timevarying L118–151。要点：
1. 卷积编码 → 截断到 `N_data_subcarriers * 2 * N_blocks`
2. 交织 + QPSK
3. 构建 freq_sym：null_idx 置零，data_idx 填符号
4. 调 `ofdm_modulate(freq_sym, blk_fft, blk_cp, 'cp')` → 逐块拼接 all_cp_data
5. RRC pulse_shape → body_bb
6. meta 含 null_idx / data_idx / all_cp_data / perm_all

### Step 3: modem_decode_ofdm（~250 行）

抽取自 test_ofdm_timevarying L342–632。要点：
1. RRC match_filter + pilot_sym 符号定时
2. 时变路径：空子载波 CFO（粗搜±3Hz + 精搜±0.15Hz）→ 逐块相位修正
3. 信道估计：static → OMP (CP 段训练)；tv → BEM(DCT)
4. nv_post 兜底（CP 残差实测）
5. 去 CP + FFT → Y_freq_blocks
6. 调 `turbo_equalizer_scfde_crossblock(Y_freq_blocks, H_est_blocks, iter, nv, codec)`
7. 截取 bits + 构建 info（含 pre_eq_syms）

### Step 4: modem_encode_sctde（~100 行）

抽取自 test_sctde_timevarying L129–197。要点：
1. 用固定 seed 生成 training（500 QPSK 符号）
2. 卷积编码 + 交织 + QPSK → data_sym
3. 组装：static = [training, data_sym]；tv = 在 data_sym 中插入 pilot_cluster
4. known_map 标记训练/导频位置
5. RRC pulse_shape → body_bb
6. meta 含 training / known_map / pilot_positions / all_sym

### Step 5: modem_decode_sctde（~300 行）

抽取自 test_sctde_timevarying L337–547。要点：
1. RRC match_filter + pilot_sym 定时
2. **Static 路径**（~30 行）：
   - GAMP 信道估计（训练段 Toeplitz）
   - 构建 h_est → 调 `turbo_equalizer_sctde(rx_data, h_est, training, iter, nv, eq_p, codec_p)`
3. **Time-varying 路径**（~200 行，模块 12 无时变版需手写）：
   - BEM(DCT) 信道估计（训练 + 散布导频构建观测矩阵）
   - nv_post 兜底
   - iter1：逐符号已知 ISI 消除 + 单抽头 MMSE
   - iter2+：BCJR → soft_mapper → DD-BEM(置信门控) → 全软 ISI 消除
4. 截取 bits + 构建 info

### Step 6: modem_dispatch 更新

```matlab
case 'OFDM'
  switch op
    case 'encode', [varargout{1:2}] = modem_encode_ofdm(varargin{:});
    case 'decode', [varargout{1:2}] = modem_decode_ofdm(varargin{:});
  end
case 'SCTDE'
  switch op
    case 'encode', [varargout{1:2}] = modem_encode_sctde(varargin{:});
    case 'decode', [varargout{1:2}] = modem_decode_sctde(varargin{:});
  end
```

### Step 7: 回归测试

`tests/test_p3.2_ofdm_sctde.m`：
- OFDM × SNR=[5,10,15] × static 6 径
- SC-TDE × SNR=[5,10,15] × static 6 径
- 基线对比 test_ofdm/sctde_timevarying 同场景 BER

### Step 8: UI 最小更新

- scheme 下拉加 `'OFDM (...)'` / `'SC-TDE (...)'`
- on_transmit 参数分支（N_info 计算、信道 sps_use）
- addpath: `06_MultiCarrier`

### Step 9: 收尾

- 更新 todo.md / wiki/log.md / 14_流式仿真框架.md
- spec log 追加
- commit

## 测试策略

1. 先单独跑 encode → channel → decode 无 FIFO（test script）
2. 再跑 UI 流式路径
3. P3.1 回归（FH-MFSK + SC-FDE BER 不变）

## 风险

| 风险 | 应对 |
|------|------|
| OFDM CFO 网格搜索慢 | 时变 CFO 仅在 `fading_type='slow'` 时启用 |
| SC-TDE 时变 ISI 消除 ~200 行 | 严格对照 test_sctde_timevarying 抽取，不做优化 |
| ofdm_modulate 输出与 all_cp_data 拼接 | 逐块调用并拼接，验证长度一致 |
| 训练序列 seed 不一致 | 固定 seed=99，存入 meta.training |
| turbo_equalizer_sctde 的 eq_params.pll | static 信道关 PLL（之前调试发现 PLL 在无多普勒时不稳定） |

## Log

（实施过程追加）
