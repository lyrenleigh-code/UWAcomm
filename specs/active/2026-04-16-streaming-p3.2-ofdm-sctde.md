---
project: uwacomm
type: task
status: done
created: 2026-04-16
parent: 2026-04-15-streaming-framework-master.md
phase: P3.2
depends_on: [P3.1]
tags: [流式仿真, 14_Streaming, 统一API, OFDM, SC-TDE]
---

# Streaming P3.2 — OFDM + SC-TDE 统一 modem API

## 目标

在 P3.1（FH-MFSK + SC-FDE）基础上，按同一 `modem_encode / modem_decode` 接口抽取 OFDM 和 SC-TDE 两个体制。源码来自 `13_SourceCode/tests/OFDM/test_ofdm_timevarying.m` 和 `tests/SC-TDE/test_sctde_timevarying.m`。

## 架构边界（与 P3.1 一致）

```
modem_encode(bits, 'OFDM', sys) → body_bb, meta     % 基带 body，不含 HFM/LFM
modem_decode(body_bb, 'OFDM', sys, meta) → bits, info
```

- body = scheme 特定波形（OFDM 符号 / RRC 成形数据流），**不含前导码**
- Doppler 补偿在外层（P4 做）
- 符号定时通过 `meta.pilot_sym`（TX 首 N 符号）传入
- `meta.noise_var` 由外层注入，decoder 内部可用残差兜底

## OFDM 抽取设计

### TX（modem_encode_ofdm）

来源：`test_ofdm_timevarying.m` L118–151

```
bits → conv_encode → random_interleave → QPSK
  → 分配到 data_idx（跳过 null_idx）
  → ofdm_modulate(freq_sym, blk_fft, blk_cp, 'cp')   % 06_MultiCarrier
  → 拼接 N_blocks 个 OFDM 符号 → all_cp_data
  → pulse_shape(RRC) → body_bb
```

meta 字段：`perm_all, all_cp_data, N_total_sym, blk_fft, blk_cp, N_blocks, null_idx, data_idx, M_per_blk, pilot_sym`

### RX（modem_decode_ofdm）

来源：`test_ofdm_timevarying.m` L342–632（跳过 L197–340 同步/Doppler 段，由外层处理）

```
body_bb → match_filter(RRC) → 符号定时(pilot_sym)
  → [时变] 空子载波 CFO 估计（null_idx 能量最小化）→ 逐块相位修正
  → 信道估计: static → OMP; time-varying → BEM(DCT)
  → nv_post 兜底（CP 残差实测）
  → 去 CP + FFT
  → Turbo: 逐子载波 MMSE-IC ⇌ BCJR (10 轮)
  → [时变 iter≥2] DD-BEM 重估 + 软反馈
  → bits
```

### OFDM 特殊机制

| 机制 | 说明 |
|------|------|
| 空子载波 | 每 `null_spacing=32` 个子载波置零，用于 CFO 估计（时变） |
| CFO 网格搜索 | 粗搜 ±3Hz + 精搜 ±0.15Hz，仅时变通路 |
| 逐子载波均衡 | G[k] = var_x·H*[k] / (var_x·|H[k]|² + nv_eq) |
| nv_post 兜底 | CP 段残差实测，防止 LLR 过度自信 |
| IFFT 归一化 | √N 系数保功率 |

### sys.ofdm 子结构

```matlab
sys.ofdm.blk_fft       = 256;       % FFT 大小
sys.ofdm.blk_cp        = 96;        % CP 长度
sys.ofdm.N_blocks      = 16;        % OFDM 符号数
sys.ofdm.null_spacing  = 32;        % 空子载波间距
sys.ofdm.rolloff       = 0.35;      % RRC 滚降
sys.ofdm.span          = 6;         % RRC 截断
sys.ofdm.turbo_iter    = 10;        % Turbo 迭代数
sys.ofdm.fading_type   = 'static';  % 'static' | 'slow'
sys.ofdm.fd_hz         = 0;         % Jakes 多普勒频率
sys.ofdm.sym_delays    = [0, 5, 15, 40, 60, 90];
sys.ofdm.gains_raw     = [与 scfde 相同的 6 径增益];
```

---

## SC-TDE 抽取设计

### TX（modem_encode_sctde）

来源：`test_sctde_timevarying.m` L129–197

```
bits → conv_encode → random_interleave → QPSK
  → 组装符号流：
      static:  [training(500sym) | data_sym]
      tv:      [training(500sym) | data_sym 中散布 pilot_cluster]
  → pulse_shape(RRC) → body_bb
```

meta 字段：`perm_all, all_sym, known_map, pilot_positions, train_len, N_data_sym, N_total_sym, pilot_sym`

### RX（modem_decode_sctde）

来源：`test_sctde_timevarying.m` L337–547（跳过 L218–335 同步段）

```
body_bb → match_filter(RRC) → 符号定时(pilot_sym)
  → 残余 CFO 补偿（alpha_est × fc → 逐符号相位旋转）
  → static 路径:
      GAMP 信道估计（训练段）
      → turbo_equalizer_sctde（12_IterativeProc, DFE iter1）
  → time-varying 路径:
      BEM(DCT) 信道估计（训练 + 散布导频）
      → nv_post 兜底
      → iter1: 逐符号已知 ISI 消除 + 单抽头 MMSE
      → iter2+: DD-BEM 重估（置信门控 |L|>0.5, 子采样 dd_step=4）
               + 全软 ISI 消除 + MMSE
      → BCJR 解码
  → bits
```

### SC-TDE 特殊机制

| 机制 | 说明 |
|------|------|
| 训练序列 | 500 已知符号作为信道估计训练，嵌在 body 开头 |
| 散布导频 | 时变下每 300 符号插入 ~140 符号导频簇 |
| DFE (static iter1) | 通过 12_IterativeProc/turbo_equalizer_sctde 处理 |
| 逐符号 ISI 消除 | 时域 h(p,n) × x(n-d_p) 逐径减去 |
| DD-BEM 置信门控 | avg(|L_coded|) > 0.5 才启用 DD 重估 |
| known_map | 布尔向量标记训练/导频位置 |

### sys.sctde 子结构

```matlab
sys.sctde.train_len         = 500;     % 训练序列长度
sys.sctde.pilot_cluster_len = 140;     % 散布导频簇长度（≥max_delay+50）
sys.sctde.pilot_spacing     = 300;     % 导频簇间距
sys.sctde.turbo_iter        = 10;      % Turbo 迭代数
sys.sctde.rolloff           = 0.35;
sys.sctde.span              = 6;
sys.sctde.fading_type       = 'static';
sys.sctde.fd_hz             = 0;
sys.sctde.sym_delays        = [0, 5, 15, 40, 60, 90];
sys.sctde.gains_raw         = [同上];
```

---

## 文件清单

### 新建（6 文件）

| 文件 | 作用 | 预估行数 |
|------|------|----------|
| `tx/modem_encode_ofdm.m` | OFDM TX 链路 | ~80 |
| `rx/modem_decode_ofdm.m` | OFDM RX 含 CFO + OMP/BEM + Turbo MMSE-IC | ~300 |
| `tx/modem_encode_sctde.m` | SC-TDE TX（含训练+散布导频组装） | ~100 |
| `rx/modem_decode_sctde.m` | SC-TDE RX 含 GAMP/BEM + DFE/ISI 消除 + Turbo | ~350 |
| `tests/test_p3.2_ofdm_sctde.m` | 双体制回归测试 | ~120 |
| `plans/streaming-p3.2-ofdm-sctde.md` | 实施计划 | — |

### 修改（3 文件）

| 文件 | 修改 |
|------|------|
| `common/modem_dispatch.m` | 新增 `'OFDM'` 和 `'SCTDE'` 分支 |
| `common/sys_params_default.m` | 新增 `sys.ofdm` 和 `sys.sctde` 子结构 |
| `ui/p3_demo_ui.m` | scheme 下拉加入 OFDM / SC-TDE；on_transmit 参数分支 |

### 不动

- `modem_encode.m / modem_decode.m`（薄包装，不需改）
- P3.1 的 FH-MFSK / SC-FDE 代码
- 01–13 所有算法模块

## 模块依赖

| 体制 | 额外依赖（P3.1 未用） |
|------|----------------------|
| OFDM | `06_MultiCarrier/ofdm_modulate`、`07_ChannelEstEq/ch_est_omp` |
| SC-TDE | `12_IterativeProc/turbo_equalizer_sctde` |

UI 路径注册需追加：`04_Modulation`（若用到）、`06_MultiCarrier`、`12_IterativeProc`。

## 验收标准

- [ ] `test_p3.2_ofdm_sctde.m` 通过：
  - OFDM static 6径: 0%@10dB+（对齐 `test_ofdm_timevarying.m` ±0.5%）
  - SC-TDE static 6径: 0%@15dB+（对齐 `test_sctde_timevarying.m` ±0.5%）
- [ ] `modem_dispatch` 4 个体制（FH-MFSK/SC-FDE/OFDM/SC-TDE）均可调用
- [ ] `info` 结构 4 个统一字段齐全
- [ ] P3.1 回归不破坏（FH-MFSK + SC-FDE BER 不变）
- [ ] UI 下拉可选 4 个体制

## 风险

| 风险 | 应对 |
|------|------|
| OFDM CFO 搜索耗时（网格 >100 点） | P3.2 先只接 static 路径，时变 CFO 标记为可选 |
| SC-TDE 时变逐符号 ISI 消除 ~350 行 | 先抽 static（调 turbo_equalizer_sctde），时变路径第二步接 |
| ofdm_modulate 签名与新 API 不兼容 | 检查 06_MultiCarrier，必要时薄包装 |
| 训练序列需随机但 TX/RX 一致 | 用固定 seed 生成，存入 meta |

## 实施策略

一步到位（static + time-varying 同时实现）。

**复用模块 12 Turbo 均衡器**（P3.1 SC-FDE 手写了 Turbo 循环，P3.2 改用现成函数）：
- OFDM：`turbo_equalizer_scfde_crossblock`（跨块频域 MMSE，SC-FDE/OFDM 通用）
- SC-TDE static：`turbo_equalizer_sctde`（DFE iter1 + 软 ISI）
- SC-TDE time-varying：modem_decode 内部手写 BEM + 逐符号 ISI 消除（模块 12 无时变版）

UI 改动最小化：仅更新 dispatch + scheme 下拉，不加体制专属参数行。
