---
project: uwacomm
spec: specs/active/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md
status: draft
created: 2026-04-25
---

# Plan：SC-TDE fd=1Hz α estimator 精度提升

> 上游 RCA：parent spec 阶段 2 已 confirm oracle α 下 SNR=20 mean 4.55%→0.89%、单调恢复。
> 本 plan 量化偏差 → 锁定根因 → fix V1.2 → 验证。

## Phase 1：诊断（量化 alpha_lfm vs dop_rate 偏差）

### 1.1 runner 暴露中间字段

`tests/SC-TDE/test_sctde_timevarying.m` 当前 CSV 仅写 `alpha_est`（refinement+精扫+训练精估之后的最终值）。诊断需要 4 个层级偏差：

| 层级 | 字段 | 含义 |
|------|------|------|
| L0 | `alpha_lfm_raw` | est_alpha_dual_chirp 直接输出 |
| L1 | `alpha_lfm_iter` | 加 bench_alpha_iter refinement 后 |
| L2 | `alpha_lfm_scan` | 大 α (>1.5e-2) 局部精扫后 |
| L3 | `alpha_est` | 训练精估合并后（已有） |

**改动**：runner 内打点 4 个变量 + `row.alpha_lfm_raw / alpha_lfm_iter / alpha_lfm_scan` 写 CSV。
**风险**：仅加诊断字段，不改算法路径。回滚成本低。

### 1.2 写 `diag_sctde_fd1hz_alpha_err.m`

**位置**：`tests/bench_common/diag_sctde_fd1hz_alpha_err.m`
**矩阵**：15 seed × 3 SNR × default fading (复用 H4 oracle full 模板)
**输出**：
- `alpha_err_summary.csv` — seed/snr/fi × {alpha_lfm_raw, alpha_est, dop_rate, err_L0, err_L3, ber_coded}
- 控制台分布表：mean/std/p50/p90 of |err| 按 SNR 分组
- |err_L0| vs ber_coded 散点 figure（验证 BER 与 estimator 偏差相关性）

**判定**（写到诊断结果尾部）：
- 若 |err_L0|/|dop_rate| 中位数 > 30% → estimator 主导偏差，进 Phase 2 R1-R4 诊断
- 若 |err_L0| 小但 |err_L3| 大 → refinement / 训练精估 链路引入偏差
- 若 ber 与 |err| 无显著相关 → fd=1Hz 非 estimator 唯一根因，回到 H1/H2/H3

### 1.3 用户跑诊断（checkpoint）

我写完脚本停下，你跑 `diag_sctde_fd1hz_alpha_err.m` 反馈结果。15 seed × 3 SNR ≈ 45 trial × 3 fading 行 ≈ 6-8 min。

---

## Phase 2：根因细分（按 Phase 1 数据决定路径）

四条候选机制 + 各自最小验证脚本：

| ID | 假设 | 验证 |
|----|------|------|
| **R1** | Jakes 时变让 LFM 匹配峰漂移 | 看 `alpha_diag.tau_up_frac/tau_dn_frac` 与 fading_seed 的相关；坏 seed 的 frac 是否系统偏离 |
| **R2** | fd=1Hz CFO 抖动污染 dual-chirp 时间差 | runner 加 toggle：用 oracle CFO 替换 → 看 alpha_lfm_raw 是否纠正 |
| **R3** | sub-sample 抛物线插值在 SNR=15 噪声下偏置 | 关 `use_subsample` 重跑同矩阵；对比 |err_L0| 分布 |
| **R4** | search 窗 nominal 边界偏小 | 检查 `up_win/dn_win` 与坏 seed 的 tau_up/tau_dn 是否触边 |

**先做 R3 和 R4**（无需改算法，最便宜）。R1/R2 视 R3/R4 结果决定。
**checkpoint**：每条假设跑完反馈数据后再决定下一步。

---

## Phase 3：Fix 实施（按 Phase 2 锁定的根因）

候选方案（spec 列出，按根因取一个或组合）：

| 方案 | 适用根因 | 工作量 |
|------|---------|--------|
| 加迭代 refinement 二阶（参考 `est_alpha_dsss_symbol`） | R1/R3 | 中 |
| LFM 模板 Doppler 鲁棒化（多 α 假设并行匹配） | R1 | 大 |
| 置信度门禁 + 训练精估 fallback | 混合 | 中 |
| 扩大 lfm_search_margin | R4 | 小 |
| 关闭 sub-sample 在 SNR≤15 时 | R3 | 小 |

**版本号**：`est_alpha_dual_chirp.m V1.2.0`，保持向后兼容（旧 search_cfg 路径不变）。
**checkpoint**：fix 写完先让你 review 代码，再跑 Phase 4 验证。

---

## Phase 4：验证

跑 `diag_sctde_fd1hz_h4_oracle_full.m`（不改）+ 新加 `diag_sctde_fd1hz_fix_verify.m`：
- 矩阵：15 seed × 3 SNR × default fading
- 对比三组：baseline / oracle α / fixed
- 接受准则（spec）：
  - SNR=20 mean ≤ 1.5%
  - SNR=20 灾难率 ≤ 15%
  - 单调性恢复

---

## 文档收尾

- `wiki/conclusions.md` 加条：`SC-TDE fd=1Hz α estimator V1.2 修复` + 数字
- `wiki/debug-logs/13_SourceCode/SC-TDE调试日志.md` 追加 2026-04-25 章节
- `wiki/index.md` / `wiki/log.md` 同步（Stop hook 会查）
- `modules/10_DopplerProc` README 更新 V1.2 章节
- spec 移到 `archive/`

---

## 起手提议

**Phase 1.1 → 1.2 → checkpoint**（不跑代码、不下结论）。

需要你确认：
1. plan 的 Phase 切分合不合理？
2. Phase 2 优先 R3/R4 还是直接全跑？
3. Phase 1.1 改 runner 加 4 个 CSV 字段 OK 吗？
