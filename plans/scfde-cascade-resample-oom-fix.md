---
project: uwacomm
type: plan
status: active
spec: specs/active/2026-04-22-scfde-cascade-resample-oom-fix.md
created: 2026-04-22
updated: 2026-04-22
tags: [内存优化, poly_resample, cascade, SC-FDE]
---

# SC-FDE cascade 盲估 OOM 修复 — 实施计划

## Phase 0 产出：允许 APIs 清单（证据驱动）

### 函数签名（只允许调用，不允许臆造）

| API | 位置 | 签名 | 关键语义 |
|-----|------|------|---------|
| `poly_resample` | `modules/10_DopplerProc/src/Matlab/poly_resample.m:1` | `y = poly_resample(x, p, q, varargin)` | 显式 `x_up=zeros(1,N*p)` 上采 → Kaiser sinc FIR conv → 降采；峰值 O(N·p) |
| `comp_resample_spline` | `modules/10_DopplerProc/src/Matlab/comp_resample_spline.m:1` | `y = comp_resample_spline(y, alpha, fs, mode)` | `alpha>0` = 压缩；`mode='fast'` Catmull-Rom 向量化；V7.1 α<0 auto-pad |
| `est_alpha_cascade` | `modules/10_DopplerProc/src/Matlab/est_alpha_cascade.m:1` | `[alpha, diag] = est_alpha_cascade(rx_pb, hfm_up_pb, hfm_dn_pb, lfm_up_bb, lfm_dn_bb, fs, fc, k_lfm, hfm_params, lfm_cfg)` | 内部 `\|α_hfm\|>1e-3` guard (L33)；tiny α 直接走 LFM 阶段 |
| `est_alpha_dual_chirp` | test L402 | `[alpha_raw, diag] = est_alpha_dual_chirp(bb, lfm_up, lfm_dn, fs, fc, k, cfg)` | 符号约定：raw 与 gen_uwa_channel `doppler_rate` **反号**（test L405 `alpha_lfm = -alpha_lfm_raw`），**但 cascade 内部 Stage 4 合成后为同号**（cascade.m L51 `+alpha_lfm_raw`） |
| `rat` | MATLAB base | `[p,q] = rat(X, tol)` | 连分式展开；`tol=1e-7` 对 `X=1+1e-5` 可产出 `p≈100001, q≈100000` |
| `conv` | MATLAB base | `y = conv(x, h, 'valid')` | 输出长度 = length(x) - length(h) + 1 |

### 已证实的反模式

1. ❌ **`rat(1+tiny_α, 1e-7)` 无 guard** — tiny α（<1e-3）产生 huge p/q，触发 `zeros(1, N*p)` OOM。证据：cascade.m L33 注释明确 "避免 rat() 对 tiny α 出 huge p/q"
2. ❌ **对已补偿信号二次 `poly_resample`** — test L340-343 对 `rx_pb`（原始）再次 resample 作最终补偿，忽视 L307-309 已产出的 `rx_pb_stage1`
3. ❌ **基带 `comp_resample_spline` 和通带 `poly_resample` 混用时符号约定不一致** — 基带约定：`alpha>0` = 压缩（与 gen_uwa_channel 同）；通带：`poly_resample(x, p, q)` p/q=1+α 也是同号。已验证无冲突

### 符号链路复核（cascade 激活时的数据流）

```
rx_pb (passband noisy) 
  ↓ [L297] est_alpha_cascade 内部（内部已完成 HFM 粗估 + 通带补偿 + LFM 精估）
  → α_cas_1 (cascade 综合结果，与 dop_rate 同号)
  ↓ [L307-309] 若 |α_cas_1|>1e-10（BAD）: rx_pb_stage1 = poly_resample(rx_pb, rat(1+α_cas_1))
  ↓ [L314] downconvert(rx_pb_stage1) → bb_stage1
  ↓ [L326-334] est_alpha_dual_chirp(bb_stage1) → α_p2_raw; α_p2 = +α_p2_raw（已补偿后的残余约定）
  ↓ [L336] α_cascade = (1+α_cas_1)(1+α_p2) - 1
  ↓ [L340-343] 若 |α_cascade|>1e-10（BAD）: rx_pb = poly_resample(rx_pb, rat(1+α_cascade))  ← 从原始 rx_pb 再来一次
  ↓ [L354-356] downconvert(rx_pb) → bb_raw
  ↓ [L408-410] cascade 路径强制 alpha_lfm = 0（通带已补偿完）
  ↓ [L461-465] 若 |alpha_lfm|>1e-10: bb_comp1 = comp_resample_spline(bb_raw, alpha_lfm)  ← cascade 下跳过
```

**关键发现**：cascade 路径下 L408 已经 force `alpha_lfm=0`，基带 spline 补偿被跳过。通带做了全部补偿。Patch B 若改动 L340-343，必须让 α_p2 残余通过**某处**得到补偿（否则 BER 基线破坏）。

## 影响的文件

| 文件 | 改动范围 | Phase |
|------|---------|-------|
| `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m` | L307, L340 guard + L340-343 重构 | A, B |
| `modules/10_DopplerProc/src/Matlab/poly_resample.m` | 外层加 chunk 循环 | C（可选）|
| 新增 `modules/10_DopplerProc/src/Matlab/test_poly_resample_chunked.m` | 数值一致性单测 | C（可选）|

---

## Phase A：Test 三处 guard 统一 `|α|>1e-3`（~30 min）

### What to implement

**Copy** 与 `est_alpha_cascade.m:33` 相同的门限语义到 test 两处。

**Anti-pattern to avoid**：不要把 guard 改成 `1e-4` 或 `1e-5` 等"中间值"——`est_alpha_cascade.m:33` 的 1e-3 是经验验证值，test 必须对齐同一语义。

### 变更清单

#### A-1. `test_scfde_timevarying.m:307` Stage1 refinement guard

```matlab
% BEFORE
if abs(alpha_cas_1) > 1e-10
    [p_num_1, q_den_1] = rat(1 + alpha_cas_1, 1e-7);
    rx_pb_stage1 = poly_resample(rx_pb, p_num_1, q_den_1);
else
    rx_pb_stage1 = rx_pb;
end

% AFTER
if abs(alpha_cas_1) > 1e-3   % 对齐 est_alpha_cascade.m:33 guard
    [p_num_1, q_den_1] = rat(1 + alpha_cas_1, 1e-7);
    rx_pb_stage1 = poly_resample(rx_pb, p_num_1, q_den_1);
else
    rx_pb_stage1 = rx_pb;   % tiny α_cas_1 时通带不做 resample，LFM 精估看完整残余
end
```

#### A-2. `test_scfde_timevarying.m:340` Final compensation guard

```matlab
% BEFORE
if abs(alpha_cascade) > 1e-10
    [p_num_c, q_den_c] = rat(1 + alpha_cascade, 1e-7);
    rx_pb = poly_resample(rx_pb, p_num_c, q_den_c);
end

% AFTER
if abs(alpha_cascade) > 1e-3
    [p_num_c, q_den_c] = rat(1 + alpha_cascade, 1e-7);
    rx_pb = poly_resample(rx_pb, p_num_c, q_den_c);
end
% |α_cascade|<1e-3 时不做通带 resample（后续基带 spline 或直接跳过）
```

### 语义影响分析

- **Guard 阻断后残余 α 去哪了？**
  - A-1 阻断（|α_cas_1|<1e-3）：cascade 内部 Stage 2 同样阻断（cascade.m:33），LFM 阶段（cascade.m:44-51）看完整 α，输出 α_cas_1 仍是全量估计。正确。
  - A-2 阻断（|α_cascade|<1e-3）：下游 downconvert + BEM 对 |α|<1e-3 的残余不敏感（已验证：A2 stage baseline α=5e-4 BER=0）。正确。
- **Guard 放行时**：与旧行为完全一致。

### Phase A 验证清单

**用户跑，不代跑**（遵循 "写完脚本停下等用户跑" 规则）：

1. `clear functions; clear all` → cd test 目录 → diary 跑 `test_scfde_timevarying.m`
2. 检查无 OOM（Windows 任务管理器 MATLAB 占用 < 2 GB）
3. 10 个 α 点（±5e-4, ±1e-3, ±3e-3, ±1e-2, ±3e-2）BER 与 `fd130f7` baseline 对比：
   - 允许 α=-1e-2 仍 13.7%（baseline 已知未通点）
   - 其余 9 点应维持 0% ± 机器精度

**Phase A 独立 commit**：`fix(tests/SC-FDE): cascade 三处 α guard 统一 1e-3 消除 tiny α OOM`

---

## Phase B：复用 `rx_pb_stage1`，省一次通带 resample（~1h）

### What to implement

**精髓**：L340-343 的 `poly_resample(rx_pb, ..., α_cascade)` 数学上等价于 `poly_resample(rx_pb_stage1, ..., α_p2)` 的级联形式（若 α_cas_1 已通过 stage1 补偿）。复用 `rx_pb_stage1`，残余 α_p2 通过基带 `comp_resample_spline` 处理。

**COPY from baseline**：α_p2 基带补偿的模板已存在 — `test_scfde_timevarying.m:461-465`（非 cascade 路径使用）。复用该模式，不发明新函数。

### 变更清单

#### B-1. 重构 L340-343 — 复用 stage1 + 记录残余

```matlab
% BEFORE (L340-343)
if abs(alpha_cascade) > 1e-3
    [p_num_c, q_den_c] = rat(1 + alpha_cascade, 1e-7);
    rx_pb = poly_resample(rx_pb, p_num_c, q_den_c);
end

% AFTER (L340-345)
% Patch B: 复用 stage1 rx_pb_stage1（已应用 α_cas_1），残余 α_p2 交基带 spline
if abs(alpha_cas_1) > 1e-3
    rx_pb = rx_pb_stage1;   % 复用通带 stage1 结果
    alpha_residual_baseband = alpha_p2;   % 残余由基带补偿
else
    alpha_residual_baseband = alpha_cascade;   % stage1 未发生，全量走基带（仅当 α_cascade 也小时）
end
```

#### B-2. 调整 L408-410 force-zero 逻辑 — 让残余基带补偿

```matlab
% BEFORE (L406-410)
% oracle_passband：rat() 精度 ~1e-10，强制 0
% cascade：两级 cascade 后残余 <1e-6，强制 0 避免下游 LFM/CP 引入额外 bias
if (use_cascade_estimator) || is_passband_oracle
    alpha_lfm = 0;
end

% AFTER
% oracle_passband：rat() 精度 ~1e-10，强制 0
% cascade：通带已补 α_cas_1（见 L340-345），残余 α_p2 由基带 spline 补偿
if is_passband_oracle
    alpha_lfm = 0;
elseif use_cascade_estimator
    alpha_lfm = alpha_residual_baseband;   % α_p2 流入基带路径
end
```

### 预期效果

- 每 α 点通带 `poly_resample` 从 2~3 次 → **1 次**（只保留 stage1）
- 基带 `comp_resample_spline('fast')` 增加 1 次（α_p2，小量，内存 O(N) spline）
- 通带总开销约减半

### 数值一致性讨论

**非 bit-exact**：通带级联 `poly_resample(·, 1+α_cas_1)` → 基带 spline `(1+α_p2)`
与原 `poly_resample(·, (1+α_cas_1)(1+α_p2))` 存在插值核差异。

**但 BER 应 bit-exact**：
- α_p2 通常 < 1e-5（cascade 残余）
- 基带 spline C1 连续对 α=1e-5 的 NMSE < -80 dB（见 wiki/conclusions α<0 fix 记录）
- 硬判决对 < -60 dB 扰动不敏感，BER 维持 baseline

**验证方式**：比较 BER 和 α_est 数组（非 bit-exact 比较信号样本）。

### Phase B 验证清单

**用户跑**：

1. 同 Phase A 步骤 1-2
2. BER 对比：与 Phase A commit 一致（α_est 也一致，基线含 Phase A）
3. 峰值内存再降（预期 < Phase A 的 2/3）
4. wall-clock 对比（预期 ≈ Phase A 或更快）

**Phase B 独立 commit**：`perf(tests/SC-FDE): cascade 最终补偿复用 stage1 resample，残余 α_p2 走基带 spline`

---

## Phase C（可选）：`poly_resample` 分块处理（~1.5h）

**触发条件**：Phase A+B 后若单 α 点峰值内存仍 > 500 MB，再启动 C。否则 park。

### What to implement

在 `poly_resample.m` 外层加 block 循环，保留内层"upsample → conv → downsample"架构不动，
数值 bit-exact 保持。

**COPY from 教科书 overlap-save**：不发明新算法，采用标准 block conv + overlap 裁剪。

### 变更清单

#### C-1. `poly_resample.m` 分块重构

```matlab
% 关键参数
CHUNK_IN = 4096;                % 输入块大小（样本）
overlap_in = ceil(N_h / p);      % 输入域 overlap（保证输出无接缝）

% 确保 CHUNK_IN * p 能被 q 整除，使输出块长度为整数
CHUNK_IN = CHUNK_IN - mod(CHUNK_IN * p, q) / p;   % 微调
CHUNK_OUT = CHUNK_IN * p / q;                      % 每块输出样本数（整数）

% 初始化
N = length(x);
N_out = floor(N * p / q);
y = zeros(1, N_out);

pos_in = 1; pos_out = 1;
while pos_in <= N
    blk_end = min(pos_in + CHUNK_IN - 1, N);
    % 带 overlap 的输入块
    in_lo = max(1, pos_in - overlap_in);
    in_hi = min(N, blk_end + overlap_in);
    x_blk = x(in_lo:in_hi);

    % 原内核：upsample → filter → downsample
    x_up_blk = zeros(1, length(x_blk) * p);
    x_up_blk(1:p:end) = x_blk;
    x_ext_blk = [zeros(1, delay), x_up_blk, zeros(1, delay)];
    y_full_blk = conv(x_ext_blk, h, 'valid');
    y_blk = y_full_blk(1:q:end);

    % 裁掉 overlap 对应的输出
    out_skip_lo = floor((pos_in - in_lo) * p / q);
    out_skip_hi = floor((in_hi - blk_end) * p / q);
    y_blk = y_blk(out_skip_lo+1 : end - out_skip_hi);

    n_take = min(length(y_blk), N_out - pos_out + 1);
    y(pos_out : pos_out + n_take - 1) = y_blk(1:n_take);
    pos_out = pos_out + n_take;
    pos_in = blk_end + 1;
end
```

**Anti-pattern**：
- ❌ 不要用 overlap-add（需要窗函数，复杂）；overlap-save（valid conv）足够
- ❌ 不要改 FIR 设计（Kaiser 参数保持 L=10, beta=5.0）
- ❌ 不要把内层算法换成 `upfirdn`（用户 parked 该方向，保持纯当前实现的分块版）

#### C-2. 单元测试 `test_poly_resample_chunked.m`

```matlab
% 10 组 (p, q) 测试：(2,3), (3,2), (100,101), (101,100), (103,100), (10001,10000) ...
% 输入：随机 complex QPSK，N = 50000
% 对比：chunked 版 vs 原版 NMSE < -200 dB（目标 machine precision -300 dB）
% 可视化：时域样本前 100 点 overlay，任一偏差 > 1e-12 标红
```

### Phase C 验证清单

**用户跑**：

1. 跑 `test_poly_resample_chunked.m` — 10 组 (p,q) NMSE < -200 dB 全 PASS
2. 再跑 SC-FDE α sweep — BER/α_est 与 Phase B commit bit-exact 一致
3. 内存：单次 poly_resample 峰值 < 10 MB（CHUNK=4096, p=100 → 6.4 MB）

**Phase C 独立 commit**：`perf(10_DopplerProc): poly_resample 分块处理消除 O(N·p) 峰值内存`

---

## 测试策略

### 回归基线

- 基线 commit：`2947777`（cascade + SC-FDE 集成）或 `fd130f7`（memory 记录）
- 基线产物：`test_scfde_timevarying.m` diary 输出（10 α 点 BER + alpha_est）

### 每 Phase 用户跑命令（不代跑）

```matlab
clear functions; clear all;
cd('D:\Claude\TechReq\UWAcomm\modules\13_SourceCode\src\Matlab\tests\SC-FDE');
diary('test_scfde_timevarying_phase<X>.txt');
run('test_scfde_timevarying.m');
diary off;
```

### 验收矩阵

| Phase | OOM 消失 | BER 基线一致 | α_est 基线一致 | 信号样本 bit-exact |
|-------|:-------:|:----------:|:-------------:|:----------------:|
| A | ✅（tiny α 不入通带）| 是 | 是 | 是（guard 阻断路径与 baseline 等价）|
| B | ✅ | 是 | 是 | **否**（基带 vs 通带插值核差异，NMSE < -60 dB）|
| C | ✅✅（峰值 <10MB）| 是 | 是 | 是（overlap-save 数值等价）|

## 风险与回退

### Phase A 风险

- **R1**：guard 1e-3 可能太宽，某些 α∈[1e-4, 1e-3] 场景下 stage1 未做通带补偿 → cascade 整体精度下降
- **缓解**：cascade.m:33 已在生产，未见回归报告；若真发生 → Phase A 独立 commit 易回退
- **回退**：`git revert <Phase A commit>`

### Phase B 风险

- **R2**：α_p2 基带补偿精度 < 通带 poly_resample，某些大残余场景（α_p2 > 1e-4）BER 可能变化
- **缓解**：α_p2 定义为 cascade 级联残余，典型 < 1e-5；加断言 `assert(abs(alpha_p2) < 1e-3)`
- **回退**：`git revert <Phase B commit>`

### Phase C 风险

- **R3**：分块边界裁剪整数化误差 → 输出样本数偏 1-2
- **缓解**：单测对比样本数；若 off-by-one 用 `pos_out + n_take` 精确控制
- **回退**：`git revert <Phase C commit>`

## 验收完成后

- 更新 `wiki/conclusions.md`：添加 "poly_resample OOM 修复 + cascade 补偿去重复"
- 更新 `wiki/log.md` + `wiki/index.md`（Stop hook 会强制）
- 归档 spec：`specs/active/2026-04-22-scfde-cascade-resample-oom-fix.md` → `specs/archive/`
- 本 plan 状态 `active` → `done`
- 更新 `todo.md`：parked "去 Signal Toolbox 依赖" 保持不动

## 备注

- 严格遵循项目规则 "写完脚本停下等用户跑"：每 Phase commit 后不自动跑测试，等用户 checkpoint
- 每 Phase 独立 commit，便于回退
- 不引入新模块 API，只改 test harness + 内部 polyphase 实现
