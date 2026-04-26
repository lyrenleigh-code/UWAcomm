---
project: uwacomm
type: plan
status: active
created: 2026-04-26
parent_spec: specs/active/2026-04-24-scfde-bem-decision-feedback-arch.md
related: SC-FDE Phase 3b.2 路线 4 决策
---

# A1：14_Streaming production decoder × jakes fd=1Hz 精确验证

## 目的

判定 SC-FDE Phase 3b.2 fd=1Hz 50% 灾难是**架构 trade-off**还是**13 移植实现 bug**：
- 14_Streaming production decoder 在 jakes fd=1Hz 下 ~50% → 架构 trade-off → 走 spec 路线 1
- 14_Streaming production decoder 在 jakes fd=1Hz 下 < 5% → 13 移植有 bug → 写新 spec 修

## 设计

### 输入差异点

| 维度 | 13 test_scfde_timevarying | A1 验证脚本 |
|------|--------------------------|--------------|
| TX 链 | 13 内联实现 | `modem_encode_scfde(bits, sys)` |
| Channel | `gen_uwa_channel` jakes | **同** |
| Preamble/同步 | 完整 LFM cascade | **跳过**（jakes α=0） |
| RX decode | 13 内联 Turbo + 移植 build_bem_observations | `modem_decode_scfde(body_bb, sys, meta)` |
| BEM 门控 | 13 移植版（Phase 3b.2） | 14 production 原版（含 `mean(var)<0.6` 门控 + var<0.5 fallback） |

### 关键判据

- A1 fd=1Hz BER ≈ 50%（与 13 Phase 3b.2 同水平）→ 架构 trade-off 确认
- A1 fd=1Hz BER < 5% → 13 移植有 bug
- A1 fd=1Hz BER 介于 5%~30% → 部分 bug + 部分架构问题，需深入

### 简化前提

jakes fd=1Hz 下 α=0：
- 跳过 LFM preamble + cascade α 估计（无意义）
- TX/RX 全程基带（跳过 upconvert/downconvert，复噪声直接加基带，方差对齐 13 通带噪声）
- 多径配置与 13 test 对齐：sym_delays/gains/fs/fc/blk_fft/blk_cp/N_blocks

## 执行

### 脚本路径

`modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_a1_streaming_decoder_jakes.m`

### 配置

- SNR：{5, 10, 15, 20} dB
- fading：{static, jakes_fd1, jakes_fd5}
- seed：{1, 2, 3}（与 13 test 同 fi*100+seed offset）
- blk_fft=256, blk_cp=64, N_blocks=16, sps=4
- codec: 同 sys_params_default

### 输出

- diary: `diag_a1_streaming_decoder_jakes_results.txt`
- BER 表格 (3 fading × 4 SNR × 3 seed = 36 个 BER 值)
- 与 13 Phase 3b.2 对照表

## 接受准则

- [ ] A1 脚本 36 次运行无 crash
- [ ] static SNR={5,10,15,20} BER < 1%（健全性，14 production 已知 PASS）
- [ ] jakes_fd1 / jakes_fd5 BER 数据完整
- [ ] 决策可下：架构 vs bug（一句话结论）

## 工时

- 脚本编写：30-45 min
- 跑实验：~5-10 min（36 次 SC-FDE 解码，单次 ~10-20s）
- 决策 + 更新 spec：15 min
- 总计：~1h

## 风险

- R1：13 协议与 14 协议的 bench_seed/info_bits 偏移不一致，无法直接对照 13 BER。
  缓解：A1 用独立 seed，结论看绝对值（~50% vs <5%）而非与 13 数值对照。
- R2：基带噪声方差与 13 通带噪声方差差 sps 倍。
  缓解：A1 内部按 13 公式 `sig_pwr * 10^(-snr/10)` 加在基带 body_bb 上，统一口径。
