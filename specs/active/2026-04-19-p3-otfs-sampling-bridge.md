---
project: uwacomm
type: enhancement
status: active
created: 2026-04-19
tags: [14_Streaming, OTFS, 采样率桥接, P3-demo-UI, 去oracle]
---

# P3 demo UI OTFS 采样率桥接

## 目标

让 OTFS 能在 P3 demo UI 下正常 Transmit/Decode，与其他 5 体制走相同的
`assemble_physical_frame + upconvert + conv(h_tap) + downconvert` passband 链路。

**非目标**：
- 不改 OTFS 算法本身（`otfs_modulate/demodulate/pilot_embed/ch_est_otfs_dd`
  全部保持）
- 不改 `test_p3_3_dsss_otfs.m` 的基带 loopback 测试路径
- 不改其他 5 体制的编解码

## 根因分析

### 现状采样率矩阵

| 体制 | body_bb 采样率 | body_bb 长度（N_info≈3000） |
|------|---------------|----------------------------|
| FH-MFSK | fs = 48000 | ~140k 样本 |
| SC-FDE | fs = 48000（RRC sps=8 过采样）| ~65k 样本 |
| OFDM | fs = 48000 | ~65k 样本 |
| SC-TDE | fs = 48000 | ~65k 样本 |
| DSSS | fs = 48000（RRC sps=4 过采样）| ~70k 样本 |
| **OTFS** | **sym_rate = 6000**（符号域，未过采样）| **3072 样本**（N×M+cp = 32×96）|

### P3 demo UI 链路假设

`p3_demo_ui.m` `on_transmit`:
```matlab
[body_bb, meta_tx] = modem_encode(info_bits, sch, app.sys);
[frame_bb, frame_meta] = assemble_physical_frame(body_bb, app.sys);
%   ↑ preamble 基带在 fs = 48000 生成（HFM/LFM dur×fs 样本）
frame_ch = conv(frame_bb, h_tap);  % 基带卷积
[tx_pb, ~] = upconvert(frame_ch, app.sys.fs, app.sys.fc);  % 乘 fc 载波
```

假设 `body_bb` 采样率 = `app.sys.fs = 48000`。OTFS body_bb 采样率 = 6000，
拼接 48000 的 preamble 产生 **Frankenstein 信号**，upconvert 后 passband 完全错误。

## 方案设计

### 方案 A — modem_encode_otfs 内部上采样（推荐）

**TX 端**：`modem_encode_otfs` 输出前加 RRC 脉冲成形 + 上采样到 fs：
```matlab
% 当前（V1）
[otfs_signal, ~] = otfs_modulate(dd_frame, N, M, cp_len, 'dft');
body_bb = otfs_signal;  % 3072 样本 @ sym_rate

% 新（V2）
[otfs_signal, ~] = otfs_modulate(dd_frame, N, M, cp_len, 'dft');
% 上采样：每 sym_rate 样本插入 sps-1 个 0，再 RRC 滤波
sps = sys.sps;                                % 8
upsampled = upsample(otfs_signal, sps);       % 3072 × 8 = 24576
body_bb = match_filter(upsampled, sps, 'rrc', cfg.rolloff, cfg.span);  % ~24608 samples @ fs
meta.sps_otfs = sps;                          % RX 需要下采样
```

**RX 端**：`modem_decode_otfs` 接收 body_bb 后下采样回 sym_rate：
```matlab
% 当前（V1）
[Y_dd, ~] = otfs_demodulate(body_bb, N, M, cp_len, 'dft');

% 新（V2）
[rx_filt, ~] = match_filter(body_bb, sps, 'rrc', cfg.rolloff, cfg.span);
% 符号定时搜索（复用 SC-FDE 思路）
best_off = search_sym_timing(rx_filt, sps, otfs_pilot_ref);
body_sym = rx_filt(best_off+1 : sps : end);    % 下采样到 sym_rate
[Y_dd, ~] = otfs_demodulate(body_sym, N, M, cp_len, 'dft');
```

**优势**：
- OTFS 和其他 5 体制接口一致（body_bb 都 @ fs）
- 复用 RRC 脉冲成形（模块 09 `pulse_shape` / `match_filter`）
- `assemble_physical_frame` 无需改动

**劣势**：
- 引入 RRC + sps=8 × 3072 = 24576 样本（~0.5 秒@48kHz）body
- 需要同步定时（和 SC-FDE 相同方式）

### 方案 B — P3 UI 识别 OTFS 特殊路径（不推荐）

UI 在 OTFS 分支**跳过** `assemble_physical_frame`，直接符号域传输。
- 复杂度高、和 UI 统一性矛盾、preamble 帧检测失效

### 方案 C — OTFS 不接入 UI（当前状态）

- 简单诚实，UI dropdown 撤掉 OTFS
- 放弃 OTFS 在 demo 中展示

**决策**：选 A。

## 文件清单

### 修改（2 个核心 + 1 UI + 1 测试）

| 文件 | 改动 |
|------|------|
| `14_Streaming/tx/modem_encode_otfs.m` | V1→V2：加 upsample + RRC 脉冲成形；meta.sps_otfs 记录 |
| `14_Streaming/rx/modem_decode_otfs.m` | V1→V2：RRC 匹配滤波 + 符号定时搜索 + 下采样 |
| `14_Streaming/ui/p3_demo_ui.m` | 恢复 OTFS dropdown 选项（撤销当前的撤退） |
| `14_Streaming/tests/test_p3_3_dsss_otfs.m` | 验证基带 loopback 仍通（编码 + 解码新增上下采样路径） |

### 不动

- `06_MultiCarrier/otfs_modulate/demodulate.m`
- `07_ChannelEstEq/ch_est_otfs_*` / `eq_otfs_*`
- 其他 5 体制

## 验收标准

### 功能验收

- [ ] UI 切 OTFS scheme，Transmit 成功，decode BER < 5%@15dB static
- [ ] `test_p3_3_dsss_otfs.m` OTFS 分支仍 PASS
- [ ] OTFS body 在 fs = 48000 下 ~25k 样本（fs × OTFS_duration ≈ 48000 × 0.5s）
- [ ] 8 tab UI 渲染正常（特别 sync tab 的 DD path_info 子图）

### 代码指标

- [ ] `modem_encode_otfs.m` V2.0.0 注释清晰说明采样率桥接
- [ ] `modem_decode_otfs.m` V2.0.0 含符号定时搜索（类似 SC-FDE best_off）
- [ ] mlint 无新增警告

## 风险

| 风险 | 等级 | 应对 |
|------|------|------|
| RRC 脉冲成形破坏 OTFS 的 per-sub-block CP 时间结构 | 🔴 高 | 充分测试：OTFS 的 CP 复制粘贴在符号域，RRC 在时域——两者需分别正确。先做基带 loopback 冒烟 |
| 符号定时搜索在 OTFS 多径下不稳 | 🟡 中 | 用 OTFS 导频第一个符号作时域参考，类似 SC-FDE 的 `pilot = train_cp(1:10)` |
| body 长度变化（3k → 25k）可能影响 FIFO 大小 | 🟡 中 | sys.fifo_capacity 当前 16 × fs = 768k，容纳 25k 绰绰有余 |
| 和 test_p3_3_dsss_otfs 的基带 loopback 路径兼容 | 🟡 中 | `modem_dispatch` → 基带路径是否绕过 RRC？检查后决定是否需要 conditional flag |

## 实施策略（3 步）

### Step 1 — modem_encode_otfs V2.0 上采样
- 加 RRC 上采样
- meta.sps_otfs / meta.N_shaped 记录桥接参数
- 基带 loopback 冒烟：直接调 decode（需 Step 2）

### Step 2 — modem_decode_otfs V2.0 下采样 + 定时
- RRC 匹配滤波 + best_off 搜索
- 下采样到 sym_rate
- 调 otfs_demodulate

### Step 3 — UI 恢复 + 端到端验证
- p3_demo_ui.m 恢复 OTFS dropdown
- Transmit + Decode 冒烟
- BER 与 test_p3_3_dsss_otfs 基线对比

## Log

- 2026-04-19: Spec 创建

## Result

_待填写_
