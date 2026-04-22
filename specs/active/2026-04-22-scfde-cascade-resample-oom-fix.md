---
project: uwacomm
type: task
status: active
created: 2026-04-22
updated: 2026-04-22
parent: 2026-04-22-resample-roundtrip-nodoppler-test.md
related:
  - 2026-04-20-alpha-estimator-dual-chirp-refinement.md
  - 2026-04-21-alpha-pipeline-large-alpha-debug.md
tags: [内存优化, poly_resample, cascade, SC-FDE, 10_DopplerProc, 13_SourceCode]
---

# SC-FDE cascade 盲估测试内存溢出修复（A+B+C）

## 背景

commit `2947777`（双级 α 估计器 cascade + SC-FDE 盲估集成）上线后，用户反馈
`test_scfde_timevarying.m` 扫 α 时**内存占用异常大**。经 trace：

### 热点 1：每 α 点跑 **3 次通带 `poly_resample`**

- **L297** `est_alpha_cascade` 内部（Stage 2 通带补偿）— cascade.m 已有 `|α_hfm|>1e-3` guard
- **L307~309** Stage1 refinement（pass1 后再对 `rx_pb` 做通带 resample 供 LFM 精估）— **guard = `|α_cas_1|>1e-10`**
- **L340~342** 最终补偿（对 `rx_pb` 再次 resample）— **guard = `|α_cascade|>1e-10`**

三处 guard 门限不一致，**L307/L340 的 `1e-10` 让 tiny α（1e-10~1e-3）也进 `rat()+poly_resample`**。

### 热点 2：`rat(1+α, 1e-7)` 对 tiny α 产生超大 p/q

- `rat(1+1e-5, 1e-7)` → 连分式展开到残差 ≤1e-7 → 约 **p=100001, q=100000**
- `poly_resample` 内 `x_up = zeros(1, N*p)` 显式上采样：N=50k·p=100k = **5×10⁹ 样本 ≈ 40 GB**
- commit message 自述曾遇 70 GB OOM，cascade 内部用 `|α|>1e-3` guard 堵住；**test 里漏堵**

### 热点 3：`poly_resample` 峰值内存 O(N·p) 本身偏大

- 即便 α=1e-2 合法场景（p≈100），`x_up` 约 5M samples；`conv('valid')` 再来一份
- 未分块 / 未流式 → 单帧 ≈ 100 MB；α 扫 10 点 × stage 重入 → 易触系统内存抖动

## 目标

消除 OOM，单 α 点峰值通带内存 **< 200 MB**（目前可达数十 GB），**不改估计/补偿算法，不改 BER/α 估计精度**。

## 非目标

- **不去 Signal Toolbox 依赖**（`poly_resample` 手写 polyphase + Kaiser 已 park 至 todo 🟢 区）
- 不改 cascade/LFM/HFM 估计器本身
- 不改 α 扫点集、不改 SNR 点、不改种子
- 不动 OFDM/DSSS/FH-MFSK/SC-TDE 的 runner（只改 SC-FDE + `poly_resample`）

## 设计

### Patch A — `test_scfde_timevarying.m` 三处 guard 统一 `|α|>1e-3`

对齐 `est_alpha_cascade.m:33` 内部 guard 语义。tiny α 交给下游基带 spline
（`comp_resample_spline fast`），避免通带 `rat()` 退化为超大 p/q。

```matlab
% Before (L307)
if abs(alpha_cas_1) > 1e-10
    [p_num_1, q_den_1] = rat(1 + alpha_cas_1, 1e-7);
    rx_pb_stage1 = poly_resample(rx_pb, p_num_1, q_den_1);
else
    rx_pb_stage1 = rx_pb;
end

% After
if abs(alpha_cas_1) > 1e-3
    [p_num_1, q_den_1] = rat(1 + alpha_cas_1, 1e-7);
    rx_pb_stage1 = poly_resample(rx_pb, p_num_1, q_den_1);
else
    rx_pb_stage1 = rx_pb;   % tiny α 不做通带 resample，全交 LFM 精估
end
```

**L307/L340 对称修改**（共 3 处：cascade 内部 1 处已有 + test 2 处新增）。

### Patch B — 最终补偿复用 `rx_pb_stage1`，省一次通带 resample

L340-343 当前对原始 `rx_pb` 做 `poly_resample(·, alpha_cascade)`。语义上
`alpha_cascade = (1+α_cas_1)(1+α_p2)-1`，可拆成两步：
- 通带层已有 `rx_pb_stage1 = poly_resample(rx_pb, ·, α_cas_1)`
- 只需基带层补 α_p2（小量，spline 精度足够）

```matlab
% Before (L340-343)
if abs(alpha_cascade) > 1e-10
    [p_num_c, q_den_c] = rat(1 + alpha_cascade, 1e-7);
    rx_pb = poly_resample(rx_pb, p_num_c, q_den_c);
end

% After
if abs(alpha_cas_1) > 1e-3
    rx_pb = rx_pb_stage1;   % 已补 α_cas_1，直接复用
end
% α_p2 基带补偿在 L462 附近 bb_comp1 = comp_resample_spline(bb_raw, alpha_lfm, ...)
% 已存在；将 alpha_lfm 换为 alpha_p2（若 guard 生效）或 alpha_cascade（保留原逻辑）
```

**注意**：需保证基带 spline 补偿使用的 α 等效于原 `alpha_cascade` 减去 `α_cas_1`。
实现上最简：让 `alpha_est` 仍传原值，但 `rx_pb` 已通过 stage1 预补偿 → 基带 spline
只需补残余 `α_p2`。plan 阶段详化。

### Patch C（可选）— `poly_resample` 分块处理

保留显式 upsample+conv+downsample 架构（不改数值），加外层 chunk 循环：

```matlab
CHUNK = 4096;                  % 输入块大小（样本）
overlap_in = ceil(N_h / p);    % 输入域 overlap，保 conv 边界无接缝
N = length(x);
N_out_total = floor(N * p / q);
y = zeros(1, N_out_total);
pos_in = 1;
pos_out = 1;
while pos_in <= N
    blk_end = min(pos_in + CHUNK - 1, N);
    in_lo = max(1, pos_in - overlap_in);
    in_hi = min(N, blk_end + overlap_in);
    x_blk = x(in_lo:in_hi);
    % 对 x_blk 做原 upsample+conv('valid')+downsample 流程
    y_blk = <原逻辑，输入换 x_blk>;
    % 裁掉 overlap 对应的输出（输入 overlap_in 样本 → 输出 overlap_in*p/q 样本）
    out_lo_trim = (pos_in - in_lo) * p / q;      % 需整数化处理
    out_hi_trim = (in_hi - blk_end) * p / q;
    y_blk = y_blk(out_lo_trim+1 : end - out_hi_trim);
    n_take = length(y_blk);
    y(pos_out : pos_out + n_take - 1) = y_blk;
    pos_out = pos_out + n_take;
    pos_in = blk_end + 1;
end
```

峰值内存从 **O(N·p)** → **O(CHUNK·p)**：
- N=50k, p=100, CHUNK=4096 → 4096·100·16 B = **6.4 MB**（复数，实数 3.2 MB）
- 原版 8 GB（complex）/ 4 GB（real）

**风险**：overlap 裁剪边界样本量 `(overlap_in·p/q)` 需保持整数；非整数时需
舍入+补零/截断 → 先用 `CHUNK` 使 `CHUNK·p` 整除 `q`（例如 CHUNK = LCM(q, 1024)）。

**验证**：写单元测试 `test_poly_resample_chunked.m`：
- 随机 QPSK + 10 组 (p, q) ∈ {(100,101), (103,100), ..., (10000,10001)}
- `norm(y_chunked - y_orig) / norm(y_orig) < 1e-12`
- 对比内存峰值（`profile -memory` 或手动 `memory`）

## 验收

| 指标 | 改前 | 改后目标 |
|------|:---:|:---:|
| α sweep 单点峰值内存 | 数十 GB（tiny α 触发）| **< 200 MB** |
| `poly_resample` 单次峰值 | O(N·p) ≈ 数百 MB | **O(CHUNK·p) ≈ 10 MB** |
| SC-FDE α sweep BER | baseline（fd130f7） | **零差异**（allclose `<1e-9` BER） |
| α 估计误差 | baseline | **零差异**（allclose `<1e-9` alpha_est） |
| wall-clock | baseline | **≤ 2× baseline**（分块开销容忍上限）|

## 实施阶段

1. **Phase 1 (Patch A)** — 3 处 guard 统一，跑 SC-FDE α sweep 验证 BER 零差异，确认 OOM 消失
2. **Phase 2 (Patch B)** — 复用 rx_pb_stage1，再跑 SC-FDE α sweep 验证 BER 零差异
3. **Phase 3 (Patch C, 可选)** — 若 Phase 1-2 后内存仍 >500 MB 再做；否则 park 至 todo

每 phase 独立 commit，每 phase 等用户跑完测试再进下一 phase（遵循"写完停下"规则）。

## 回归测试

- SC-FDE α sweep 10 点（±5e-4, ±1e-3, ±3e-3, ±1e-2, ±3e-2）BER + α_est 与 baseline diff
- `test_poly_resample_chunked.m`（仅 Phase 3）— 分块数值一致性
- `diag_cascade_quick.m` smoke test（cascade 本身不破）

## 关键文件

- `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m` — Patch A/B
- `modules/10_DopplerProc/src/Matlab/poly_resample.m` — Patch C（可选）
- 新增：`modules/10_DopplerProc/src/Matlab/test_poly_resample_chunked.m`（可选）

## 备注

- "去 Signal Toolbox 依赖"（手写 polyphase + Kaiser）已 park 到 `todo.md` 🟢 低优先，触发条件 = 纯 base 需求出现
- 本 spec 只解决 OOM，**不碰算法、不碰精度**；BER/α_est baseline 严格保持
