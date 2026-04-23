---
project: uwacomm
type: task
status: active
created: 2026-04-24
updated: 2026-04-24
tags: [SC-TDE, fix, alpha补偿, 13_SourceCode, 10_DopplerProc]
branch: fix/sctde-remove-post-cfo-compensation
parent_spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
---

# SC-TDE 删除 post-CFO 伪补偿

## 背景

2026-04-23 RCA（上述 parent_spec）锁定根因：`test_sctde_timevarying.m:436-441` 在 basic 基带 Doppler 信道模型下做 `exp(-j·2π·α·fc·t)` 补偿是**伪操作**，凭空添加 fc·α 频偏，破坏 Turbo 输入对齐。

**D10 验证数据**：

| α | baseline BER | disable_cfo BER |
|---|-------------|----------------|
| 0 | 1.84±1.63% | 0.04±0.09% |
| +1e-3 | 50.66% | 0.00% |
| +1e-2 | 50.36% | 0.29±0.44% |

**物理依据**：`gen_uwa_channel` 基带模型仅做时间伸缩 `s_bb((1+α)t)` + 多径，无载波频偏。`comp_resample_spline` 补偿时间伸缩后，`bb_comp` 完全无 CFO。历史 post-CFO 补偿可能源自某个 passband Doppler 模型（已废弃或未使用）的继承代码。

## 目标

一处代码删除 + 三处场景回归验证，关闭 α 常数多普勒下 SC-TDE 100% 灾难。

## 改动范围

### 主改动（1 处）

**文件**：`modules/13_SourceCode/src/Matlab/tests/SC-TDE/test_sctde_timevarying.m`

**删除 line 436-441 的 post-CFO 补偿块**（以及相关注释），保留 diag toggle 支持作为"反面教材"可选启用（默认关闭）：

```matlab
% === 历史 post-CFO 补偿已删除（RCA spec 2026-04-23-sctde-alpha-1e2-rca） ===
% 原代码在基带 Doppler 模型下是伪操作，α·fc 会被凭空注入破坏对齐。
% 若未来切 passband Doppler 信道，需重新评估是否恢复。
% 保留 diag toggle 以支持历史行为回溯：
if abs(alpha_est) > 1e-10 && ...
   ((exist('diag_enable_legacy_cfo','var') && diag_enable_legacy_cfo))
    cfo_res_hz = alpha_est * fc;
    t_sym_vec = (0:length(rx_sym_recv)-1) / sym_rate;
    rx_sym_recv = rx_sym_recv .* exp(-1j*2*pi*cfo_res_hz*t_sym_vec);
end
```

原有 D6/D7/D10 toggle 可清理为只保留 `diag_enable_legacy_cfo`（反义），其他 diag_* 已完成使命。

### RCA diag 脚本保留策略

- **保留**：D0b / D1 / D2 / D3 / D5 / D6 / D7 / D9 / D10 全部脚本和输出（归档到 `modules/13_SourceCode/src/Matlab/tests/SC-TDE/archived_diag/` 子目录，或随 RCA spec 一起归档）
- **runner 插桩 toggle 清理**：
  - 保留：`diag_oracle_alpha`, `diag_oracle_h`, `diag_use_ls`, `diag_turbo_iter`, `diag_dump_h`, `diag_dump_signal`, `diag_dump_rxfilt`（都是只读 diag，无副作用）
  - 改名：`diag_disable_cfo_postcomp` → `diag_enable_legacy_cfo`（反义，默认 false 即新行为）
  - 删除：`diag_precomp_cfo`, `diag_precomp_cfo_data` + 相关插桩（D6/D7 已证伪，保留无意义）

## 验证矩阵（回归 benchmark）

### V1. α 扫描（主验证）

**命令**：运行新脚本 `modules/13_SourceCode/src/Matlab/tests/SC-TDE/verify_alpha_sweep.m`

| α | SNR=10 期望 BER | 历史 baseline BER |
|---|---------------|------------------|
| 0 | <0.5% | 1.84% (D10) |
| +1e-4 | <0.5% | 未测（历史认为 work） |
| +1e-3 | <1.0% | **50.66%** (D10) |
| +3e-3 | <2.0% | 未测 |
| +1e-2 | <1.0% | **50.36%** (D10) |
| +3e-2 | 5-30%（物理极限） | 未测 |
| -1e-3 | <1.0% | 需验证 |
| -1e-2 | <5%（α<0 auto-pad） | 需验证 |

**5 seed × 8 α × SNR=10 = 40 trial，预计 ~3 min**

### V2. 历史回归（D0b 再跑）

`diag_D0b_regression_multiseed.m` 必须仍 pass（α=0 gate），确认改动不破坏 α=0 场景：

| SNR | mean BER 上限 |
|-----|--------------|
| 10 | ≤ 0.5% |
| 15 | ≤ 0.5% |
| 20 | ≤ 0.1% |

**5 seed × 3 SNR = 15 trial**

### V3. 时变路径回归

检查时变分支（`ftype='slow'`, `fd_hz>0`）未受影响。post-CFO 代码在时变分支本来就走，需确认删除后 **fd=1Hz**/fd=5Hz 场景 BER 不变。

**运行**：`test_sctde_timevarying.m` 默认 3 行 `fading_cfgs`（static / fd=1Hz / fd=5Hz）× SNR=[5,10,15,20]，对比 HEAD=3dac2aa 的历史 BER。

| 场景 | 历史 BER (V5.2 日志) | 期望 |
|------|-------------------|------|
| static, SNR=10 | 0.55% | ≤1% |
| static, SNR=15 | 0.10% | ≤0.5% |
| fd=1Hz, SNR=15 | 0.76% | ≤1.5% |
| fd=5Hz | ~45%（物理极限） | ±5% |

### V4. E2E benchmark C 阶段重跑（可选，耗时长）

如果 V1/V2/V3 都过，可选再跑 `benchmark_e2e_baseline.m` 的 SC-TDE 子集验证 E2E CSV。

## 验证脚本设计

### 新建 1 个

**`modules/13_SourceCode/src/Matlab/tests/SC-TDE/verify_alpha_sweep.m`**

逻辑与 D10 相似但扩展 α 范围和去除 baseline（只测新行为）：

```matlab
h_alphas = [0, +1e-4, +1e-3, +3e-3, +1e-2, +3e-2, -1e-3, -1e-2];
% 5 seed, SNR=10，disable_cfo 已在代码里固化
```

## 接受准则

- [ ] `test_sctde_timevarying.m` line 436-441 删除（diff 可见 post-CFO 块消失）
- [ ] V1 α 扫描：`|α| ≤ 1e-2` 全部 ≤1% BER（α=3e-2 属物理极限可放宽）
- [ ] V2 D0b 回归：3 SNR 全通过
- [ ] V3 时变路径：fd=1Hz @ SNR=15 BER ≤ 1.5%
- [ ] `wiki/modules/13_SourceCode/SC-TDE调试日志.md` 追加 V5.4 章节记录 fix + 验证结果
- [ ] `wiki/conclusions.md` 追加结论（基带 Doppler 模型下不需 post-CFO）
- [ ] `todo.md` 勾掉"SC-TDE α=+1e-2 100% 灾难根因深挖"，加"SC-TDE post-CFO fix 完成"
- [ ] Parent RCA spec `2026-04-23-sctde-alpha-1e2-disaster-root-cause.md` 归档到 `specs/archive/`

## 风险

- **R1**：删除后 **passband Doppler 信道**下会有真实 CFO 但未补偿。缓解：gen_uwa_channel 基带模型明确已在 CLAUDE.md §某处记录；若未来切 passband，新开 spec 重新评估。
- **R2**：时变路径（fd>0）可能隐含对 post-CFO 的依赖（虽 RCA 未验证时变）。缓解：V3 回归覆盖。
- **R3**：α<0 大场景（-1e-2/-3e-2）未在 D10 测过，fix 后可能暴露其他 bug。缓解：V1 α 扫描覆盖 -1e-3/-1e-2；若 -3e-2 出问题单独开 spec。

## 非目标

- ❌ 修复时变路径（fd_hz>0）的其他问题
- ❌ 横向检查其他体制 runner（分到 cross-scheme-audit spec）
- ❌ 重构 post-CFO 为"信道模型自适应"（过早抽象，等有 passband 需求再做）
