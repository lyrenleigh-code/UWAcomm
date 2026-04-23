---
project: uwacomm
type: task
status: active
created: 2026-04-24
updated: 2026-04-24
tags: [audit, alpha补偿, 13_SourceCode, SC-FDE, OFDM, DSSS, FH-MFSK, OTFS]
branch: audit/cfo-postcomp-cross-scheme
parent_spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
---

# 横向检查：其他 5 体制是否有 post-CFO 伪补偿 bug

## 背景

SC-TDE RCA（parent spec）发现 post-CFO 补偿 `rx_sym_recv .* exp(-j·2π·α·fc·t)` 在基带 Doppler 信道模型下是伪操作。SC-TDE 因时域 DFE 对载波频偏脆弱，被该伪操作放大到 100% 灾难。

**怀疑面**：6 个体制 runner（`tests/{SC-FDE,OFDM,SC-TDE,DSSS,FH-MFSK,OTFS}/test_*_timevarying.m`）可能共享相同编码模式。SC-TDE 已修，余下 5 个需审计。

**为何 SC-FDE/OFDM 同 bug 却不爆**：FFT 域均衡吸收了伪 CFO（表现为 1-2 子载波偏移），但**仍是错操作**，可能被其他 α 范围或复杂场景暴露。DSSS 同 Phase c 100% 灾难，可能有独立根因（Sun-2020 符号跟踪）+ 同 bug 叠加。

## 审计清单

### 第一步：代码 grep（静态审计）

扫描关键模式并分类：

```bash
# 在 UWAcomm/modules/13_SourceCode/src/Matlab/tests/ 下搜索
grep -rn "exp(-1j\*2\*pi.*alpha.*fc\|alpha_est \* fc\|cfo_res_hz" \
    modules/13_SourceCode/src/Matlab/tests/
grep -rn "exp(-1j\*2\*pi.*alpha.*fc\|alpha_est \* fc\|cfo_res_hz" \
    modules/13_SourceCode/src/Matlab/common/
```

### 第二步：每个体制 runner 审计

按以下矩阵（每行一个体制）填充：

| 体制 | Runner 路径 | 有无 post-CFO? | 位置 | 作用于 | 是否应删除 |
|------|-------------|----------------|------|--------|----------|
| SC-FDE | `tests/SC-FDE/test_scfde_timevarying.m` | ? | 第 ? 行 | rx_sym / bb_comp / 其他 | ? |
| OFDM | `tests/OFDM/test_ofdm_timevarying.m` | ? | ? | ? | ? |
| DSSS | `tests/DSSS/test_dsss_timevarying.m` | ? | ? | ? | ? |
| FH-MFSK | `tests/FH-MFSK/test_fhmfsk_timevarying.m` | ? | ? | ? | ? |
| OTFS | `tests/OTFS/test_otfs_timevarying.m` | ? | ? | ? | ? |

### 第三步：共用层审计

检查 common：
- `common/rx_chain.m`
- `common/modem_decode_*.m`
- `common/modem_*.m`
- 是否有公共 post-CFO 模板

14_Streaming 也要查：
- `14_Streaming/src/Matlab/rx_stream_*.m`
- 与 SC-TDE 共用部分

### 第四步：对每个命中的 runner 做相同 D10 验证

若某个体制 runner 发现 post-CFO 补偿，写对应的 `diag_D10_<scheme>.m`：
- α ∈ {0, +1e-3, +1e-2}（覆盖 D10 范围）
- 2 模式 × 3 α × 5 seed = 30 trial

对比 baseline vs disable_cfo BER。

### 第五步：Fix 决策

按每个体制的审计结果：

| 情况 | 动作 |
|------|------|
| **无 post-CFO** | 跳过 |
| **有 post-CFO 但 D10 baseline=disable（无害）** | 仍建议删除（清理伪操作），低优先 |
| **有 post-CFO 且 D10 disable 有改善** | 立即删除，开独立 fix spec（例如 DSSS） |
| **α<0 场景** | 单独验证，可能需要保留某些符号逻辑 |

## 预期冷热点

- **热**（高度怀疑有同 bug）：DSSS（Phase c 也 100% 灾难）、SC-FDE（历史记录 ~10% 灾难率触发）
- **温**（可能有但 FFT 体制吸收）：OFDM（0% 灾难但可能大 α 扩展下暴露）
- **冷**（体制结构不同）：FH-MFSK（能量检测，对 CFO 鲁棒）、OTFS（DD 域处理）

## 接受准则

- [ ] 静态 grep 扫描完成，填充审计矩阵
- [ ] 5 体制 runner 逐一审计（即使"无"也要有明确结论）
- [ ] common/ + 14_Streaming/ 共用层审计完成
- [ ] 对每个命中 post-CFO 的 runner 做对应 D10 验证
- [ ] 对有改善的 runner 开独立 fix spec（列出清单）
- [ ] 总审计报告写入 `wiki/conclusions.md`（附交叉引用表）
- [ ] `todo.md` 加"横向审计完成"条目

## 非目标

- ❌ 修复每个发现的 bug（由独立 fix spec 接管）
- ❌ 审计 alpha 补偿链路其他层（comp_resample, est_alpha, lfm_pos 等 — 已在 RCA 中覆盖）
- ❌ 重构 post-CFO 为统一模块（过早抽象）

## 风险

- **R1**：DSSS 的 100% 灾难可能有**多重根因**（Sun-2020 独立 spec 已开），post-CFO 只是其中一层。审计结论可能"disable 部分改善但不完全"。缓解：单独分析 DSSS D10，与 Sun-2020 spec 协调。
- **R2**：审计时 runner 正在被其他 task 改动（merge 冲突）。缓解：本 spec 应在 SC-TDE fix spec 完成且 commit 后开始。
- **R3**：α<0 场景的 post-CFO 可能是**正确的**（某些推导下）。缓解：若遇到，单独 D10 覆盖 α<0 并查 passband 推导。

## 执行建议顺序

1. SC-TDE fix spec 先 merge → HEAD 稳定
2. 本 spec Step 1-3（静态 grep + 矩阵填充）先做，~30 min
3. 按命中度排序 Step 4（DSSS → SC-FDE → OFDM → FH-MFSK → OTFS）
4. 每个命中独立 fix spec

## 参考

- Parent RCA：`specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md`
- SC-TDE fix：`specs/active/2026-04-24-sctde-remove-post-cfo-compensation.md`
- DSSS 并行 spec（独立根因）：`todo.md` 内"DSSS α=+1e-2 100% 灾难根因深挖"
- 物理推导：`wiki/modules/13_SourceCode/SC-TDE调试日志.md` V5.3 "物理解释"段
