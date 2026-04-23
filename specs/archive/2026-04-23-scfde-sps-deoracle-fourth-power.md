---
project: uwacomm
type: task
status: failed
created: 2026-04-23
updated: 2026-04-23
related:
  - specs/archive/2026-04-23-scfde-omp-replace-gamp-and-oracle-clean.md
  - specs/active/2026-04-16-deoracle-rx-parameters.md
tags: [sps timing, oracle清理, QPSK, 四次方, SC-FDE, 13_SourceCode]
---

# SC-FDE sps 相位选择真去 oracle — 四次方非数据辅助 timing

## 实施结果（2026-04-23 ❌ 失败）

| 测试 | V1.4 baseline | 4 次方 NDA | 结论 |
|---|:-:|:-:|---|
| cascade_quick (5 α 单 seed) | -1e-2 13%, 其余 0% | -1e-2 14%, 其余 0% | 看似 OK ✓ |
| Monte Carlo -1e-2 灾难率 | 0/30 | **3/30 (10%)** | ❌ |
| Monte Carlo +1e-2 灾难率 | 2/30 (6.7%) | **6/30 (20%)** | ❌ 退化 3× |
| max BER | 30.6 | **50.6** | ❌ |

**根因**：QPSK 4 次方 timing 在教科书 AWGN 工作；实际 SNR=10 + 6 径 ISI 下：
- 噪声放大：`(constellation+noise)^4` 噪声项 4 次成长
- ISI 不是 Gaussian，是确定性符号混合 → `y^4` phasor 严重分散
- 加和取消反而抑制了正确定时信号

**深层教训**：所有纯 NDA blind timing（功率最大化 + 4 次方）在 6 径 ISI + SNR=10 都失效。
Oracle 之所以工作是因为有 ground truth；去 oracle 必须给 RX **等价 ground truth**：
- 加 training preamble 到帧结构（架构改动）
- 用 LFM 模板尾部相关（RX-known reference）
- Gardner TED + 量化（已有 `08_Sync/timing_fine.m`）

→ 独立架构 spec 待开

---

## 原 spec（保留为历史参考）

## 背景

上一 spec `2026-04-23-scfde-omp-replace-gamp-and-oracle-clean.m` Phase B 用功率
最大化 `sum(|st|²)` 替代 `conj(all_cp_data(1:10))` 相关，**失败**：custom6 6 径
ISI 让错误 sps 相位反而捕获更多能量泄漏 → BER 退化（α=-1e-2 13%→48%）。

但 oracle 泄漏（L484/L590 用 TX 数据 `all_cp_data(1:10)` 当参考）仍真实存在，
违反 CLAUDE.md §7 排查清单第 8 条。

## 真问题分析

`sum(|st|²)` 失败原因：
- RRC + ISI 下，错误 sps 相位采样捕获**部分相邻符号**的能量
- 总功率反而可能更大（错误相位混合两个符号能量 vs 正确相位只取一个符号）
- 功率最大化无法区分"信号能量"vs"ISI 泄漏能量"

**正确做法**：利用 QPSK 星座几何性质，做**非数据辅助** (NDA) timing recovery。

## 设计：四次方 NDA timing

### 数学原理

QPSK 4 个星座点 `{±1±j}`：
```
(1+j)^4 = 2j² × 2² = -4    (相同)
(1-j)^4 = -2j × -2 = -4
(-1+j)^4 = -4
(-1-j)^4 = -4
```

**所有符号 y^4 = -4**（统一 phasor），与发送数据无关。

正确定时：所有 y_n 是干净星座点 → `y_n^4 = -4` for all n → `sum(y_n^4) = -4N`，|sum|=4N 大。

错误定时：y_n 是 ISI 污染的中间值 → `y_n^4` 分散 phasor → 加和趋向 0。

**`abs(sum(y_n^4))` 最大化** → 正确 sps 相位。**纯接收信号统计量**，无需 TX 数据。

### 抗 ISI 性质（与 `sum(|st|²)` 失败的对比）

`sum(|st|²)` 失败：
- 错误相位 → ISI 让能量"泄漏"过来 → 功率反而大
- 不区分"信号"vs"ISI"

`abs(sum(y_n^4))` 不失败：
- 错误相位 → y_n 是污染样本 → 即使能量大，但 y_n^4 phasor 分散
- 加和取消（destructive interference）→ |sum| 反而小
- **几何性质 + 加和提供 ISI 抑制**

### 教科书出处

- Oerder & Meyr, "Digital Filter and Square Timing Recovery" (1988)
- Gardner timing recovery（更通用，连续 offset）
- 4th-power 是 Oerder-Meyr 在 QPSK 上的特化

## 目标

1. L484/L590 两处替换：`conj(all_cp_data(1:10))` 相关 → `abs(sum(st.^4))`
2. 加 toggle `tog.use_oracle_sps`（默认 false→四次方；true→旧 oracle 法用于回归对比）
3. 验证：BER 与 baseline `b1f29ba` 一致（V1.4 GAMP，仍未触发灾难的 case 都 0%）

## 非目标

- 不改 GAMP/OMP 估计器（保 V1.4）
- 不改帧结构（不加 training preamble）
- 不动其他 5 体制（OFDM/SC-TDE/DSSS/FH-MFSK 各自的 sps 处理留独立 spec）
- 不解决 SNR=10 边界 ~6.7% 灾难（已知 limitation）

## 设计

### Patch A：toggle 默认值

**位置**：`test_scfde_timevarying.m:137-141`

```matlab
% Phase A 2026-04-23 sps 去 oracle: use_oracle_sps=false 默认四次方
tog = struct(... 'use_omp_static', false, ...
             'use_oracle_sps', false);   % NEW
```

### Patch B：L484-487（CP 精估路径）

```matlab
% BEFORE
b1=0; bp1=0;
for off=0:sps-1
    st=rf1(off+1:sps:end);
    if length(st)>=10, c=abs(sum(st(1:10).*conj(all_cp_data(1:10))));
        if c>bp1, bp1=c; b1=off; end, end, end

% AFTER
b1=0; bp1=0;
for off=0:sps-1
    st=rf1(off+1:sps:end);
    if length(st) < 10, continue; end
    n_take = min(length(st), N_total_sym);
    if tog.use_oracle_sps
        % 旧 oracle 法（保留作回归对比）
        c = abs(sum(st(1:10).*conj(all_cp_data(1:10))));
    else
        % 四次方 NDA timing：QPSK y^4 = -4 统一 phasor
        c = abs(sum(st(1:n_take).^4));
    end
    if c > bp1, bp1=c; b1=off; end
end
```

### Patch C：L590-602（主数据路径）— 同样的修改

模式一致，只是变量名 `rx_filt`/`best_off`/`best_pwr`。

## 验证矩阵

### 阶段 1：toggle 回归对比

`bench_toggles.use_oracle_sps = true` → 跑 cascade_quick → 应与 baseline `b1f29ba` bit-exact。

### 阶段 2：四次方默认

`bench_toggles.use_oracle_sps = false`（默认）→ 跑：
- cascade_quick：α=-1e-2 13%（baseline）；其余 4 点 0%
- Monte Carlo：α=-1e-2 灾难率 0/30；α=+1e-2 灾难率 6.7%

**关键验收**：α=-1e-2 不破到 48%（不重蹈 Phase B 覆辙）。

### 阶段 3：低 SNR 边界

跑 `diag_residual_snr_limit.m`（α=+1e-2 s17/s26 × SNR 10/15/20）：
- 期望 SNR=15 仍救活 0%

## 实施阶段

| Phase | 内容 | 工时 | checkpoint |
|---|---|:-:|:-:|
| **A** | toggle 默认值 + L484/L590 双 if/else 结构 | 20 min | 跑 cascade_quick (toggle=true 应 bit-exact baseline)|
| **B** | 默认四次方跑 Monte Carlo + residual SNR | 5 min 编辑（用户跑测试） | BER 不退化 + 灾难率不增 |
| **结尾** | 归档 conclusions/log/todo + commit | 10 min | - |

## 风险与回退

### R1：QPSK 4 阶矩在低 SNR 下噪声 dominant
- 在 SNR=10 dB 噪声方差 ~0.1，y^4 噪声分量 ~ noise^4 ≈ 1e-4，相比信号统一 phasor 4 仍占优
- 缓解：N_total_sym >> 1 平均压噪
- 回退：toggle `use_oracle_sps=true` 一行回滚

### R2：QPSK 假设硬编码（未来支持 BPSK/8-PSK 时失效）
- 缓解：本期 SC-FDE 固定 QPSK，scope 不变
- 后续：如果需要其他星座，加 `tog.constellation_order` (BPSK→2, 8PSK→8) 参数化

### R3：与 ISI/Doppler 残余的鲁棒性
- 4 阶矩对相位/Doppler 残余敏感（多了 4 倍）
- cascade 后残余 α ~1e-6 → 帧内 1e-6×N×4 ≈ 0.2 rad 累积 → 仍可接受
- 缓解：实测验证

## 关键文件

- ✏️ `modules/13_SourceCode/src/Matlab/tests/SC-FDE/test_scfde_timevarying.m` — 3 处改动（toggle + 2 sps）
- 📖 文档：QPSK 四次方 timing 标准教科书做法

## 备注

- 本 spec 是上一 spec Phase B 失败后的纠正实施
- 严格遵循"写完停下等用户跑"规则，每 phase 单独 commit
- 不改 GAMP/OMP 配置（仍 V1.4 默认 + OMP toggle 实验）
- L621 GAMP 训练矩阵用 TX 数据 (架构层 oracle) 仍 park 独立 spec
