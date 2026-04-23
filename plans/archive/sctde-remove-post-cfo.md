---
project: uwacomm
type: plan
spec: specs/active/2026-04-24-sctde-remove-post-cfo-compensation.md
status: active
created: 2026-04-24
updated: 2026-04-24
---

# SC-TDE 删 post-CFO 伪补偿 — 执行计划

## 目标回顾

删 `test_sctde_timevarying.m` 符号级 post-CFO 补偿块（实际 L499-511，非 spec 写的 436-441），关闭 α 常数多普勒下 SC-TDE 100% 灾难。Parent RCA：`specs/archive/2026-04-23-sctde-alpha-1e2-...`（改完一起归档）。

## 当前代码实况

| 位置 | 内容 | 处理 |
|------|------|------|
| L394-404 | D6: pre-CFO on `bb_comp`（bb_comp 级，已证伪） | **删** |
| L428-439 | D7: pre-CFO on `rx_data_bb`（数据段级，已证伪） | **删** |
| L499-511 | **真 post-CFO**：`rx_sym_recv .* exp(-j·2π·α·fc·t)` | **改为默认 skip + `diag_enable_legacy_cfo` 反义** |

次要清理：
- L499-503 的 `h_precomp_done` / `h_disable_cfo` 帮助变量简化（D6/D7 删后无需 `h_precomp_done`）
- 注释同步更新（指向 RCA spec）

## 执行步骤

### Step 1 — 代码改动（assistant 写）

**S1.1** 编辑 `modules/13_SourceCode/src/Matlab/tests/SC-TDE/test_sctde_timevarying.m`:
- 删 L394-404（D6 pre-CFO 块）
- 删 L428-439（D7 pre-CFO 块，含注释）
- 改 L499-511 为：默认 skip，反义 toggle `diag_enable_legacy_cfo`（默认 false）
- 注释指向 `specs/archive/2026-04-23-sctde-alpha-1e2-...`

**S1.2** 新建 `modules/13_SourceCode/src/Matlab/tests/SC-TDE/verify_alpha_sweep.m`（覆盖 V1+V2）:
- 矩阵：`α ∈ {0, +1e-4, +1e-3, +3e-3, +1e-2, +3e-2, -1e-3, -1e-2}` × 5 seed × 3 SNR(10/15/20)
- 40 × 3 = 120 trial（~9 min 预估）
- 输出：txt 保存 mean±std BER 表；figure 可视化 α vs BER
- α=0 SNR 扫描同时满足 V1（α 工作范围）+ V2（D0b 回归 α=0 gate）

### Step 2 — 用户跑验证（checkpoint，**assistant 不代跑**）

用户按 CLAUDE.md 测试流程跑：

```matlab
clear functions; clear all;
cd('D:\Claude\TechReq\UWAcomm\modules\13_SourceCode\src\Matlab\tests\SC-TDE');
diary('verify_alpha_sweep_results.txt');
run('verify_alpha_sweep.m');
diary off;
```

可选 V3 时变路径回归：

```matlab
clear functions; clear all;
diary('test_sctde_timevarying_results.txt');
run('test_sctde_timevarying.m');  % 默认 3 fading × 4 SNR
diary off;
```

用户把 BER 表（或关键指标）发回。

### Step 3 — 根据验证结果处理

**A. 全通过**（V1 |α|≤1e-2 全 ≤1%，V2 α=0 全 SNR ≤0.5%，V3 时变不退）:
- S3.1 追加 `wiki/modules/13_SourceCode/SC-TDE调试日志.md` V5.4 章节
- S3.2 追加 `wiki/conclusions.md` 结论（基带 Doppler 模型下不需 post-CFO）
- S3.3 更新 `todo.md`（勾 RCA 根因深挖+post-CFO fix，转前 2 个 🔴 为 ✅）
- S3.4 归档 spec：`specs/active/2026-04-24-sctde-remove-post-cfo-compensation.md` → `specs/archive/`；parent RCA `2026-04-23-sctde-alpha-1e2-...` 同步归档
- S3.5 等用户授权 commit

**B. 部分失败**（某 α 场景未达阈值）:
- 诊断脚本或回退策略按失败类型决定，另起 sub-spec

**C. V3 时变退化**（R2 风险，**2026-04-24 已命中然后证伪**）:
- 第一轮 V3（plan A 全 skip）：fd=1Hz SNR=15 27.96%（看似退化 vs 历史 0.76%）
- 第二轮 V3（plan C 时变 apply）：fd=1Hz SNR=10 47.71%、SNR=20 从 0%→37.20%（更差）
- **plan C 证伪**：apply post-CFO 在时变路径也是破坏性的，**全 skip 才是正确方向**
- 历史 V5.2 "fd=1Hz 0.76%" 不可复现（代码演化累积差异 — bench_seed 注入、alpha_est 门禁调整等）
- 采取路径：**回滚到 plan A（全 skip + diag_enable_legacy_cfo 反义 toggle）**
- fd=1Hz 的非单调 BER vs SNR → 独立 spec 调研：
  `specs/active/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md`（known limitation）

## 测试规则对齐

依据 CLAUDE.md：
- §2 接收端禁用发射端参数：不涉及新 oracle 注入
- §4 调试日志：V5.4 追加
- §7 Oracle 排查清单：改动不引入新 oracle（post-CFO 本是合法计算）

依据 memory `feedback_uwacomm_testing_boundary`:
- Step 2 是用户 checkpoint，assistant 不代跑
- BER 表由用户解读"成功/失败"
- assistant 只陈述数字

## Checkpoint 分布

```
S1.1/S1.2 写代码 → [Checkpoint 1: 代码 diff 给用户过目]
         ↓ (用户 approve)
Step 2 用户跑 V1+V2 → [Checkpoint 2: BER 结果]
         ↓ (用户贴 BER 表)
Step 3 文档 + 归档 → [Checkpoint 3: commit 授权]
```

## 非目标

- ❌ SC-TDE 时变分支（fd>0）其他优化
- ❌ 其他 5 体制横向清理（分给 2026-04-24-cfo-postcomp-cross-scheme-audit.md）
- ❌ 重写 comp_resample_* 方向约定
