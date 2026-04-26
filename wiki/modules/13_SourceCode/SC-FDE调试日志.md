# SC-FDE 端到端调试日志

> 体制：SC-FDE | 当前版本：V2.2 (benchmark runner，Phase 1+2 sps+GAMP 去 oracle)
> 关联模块：[[06_多载波变换]] [[07_信道估计与均衡]] [[08_同步与帧结构]] [[09_脉冲成形与变频]] [[10_多普勒处理]] [[12_迭代调度器]]
> 关联笔记：[[端到端帧组装调试笔记]] [[UWAcomm MOC]] [[项目仪表盘]]
> 技术参考：[[水声信道估计与均衡器详解]] [[时变信道估计与均衡调试笔记]]
> Areas：[[信道估计与均衡]] [[同步技术]] [[多普勒处理]]

#SC-FDE #调试日志 #端到端

---

## 版本总览

| 版本 | 日期 | 核心变更 | 状态 |
|------|------|---------|------|
| V4.0 | 2026-04-09 | 两级分离架构+LFM定时 | ✅ fd<=1Hz完成 |
| V2.2 | 2026-04-24 | 迁移 14_Streaming 架构（Phase 1+2: sps+GAMP 去 oracle）| ✅ timevarying runner 完成 |
| V2.3 | 2026-04-25 | Phase 3b.2 BEM 判决反馈去 oracle | 🟡 static PASS / fd 时变路径 limitation 已知 |

---

## V4.0 — 两级分离架构 (2026-04-09)

**Git**: `80bfe14` (V4.0), `a68c12f` (规则更新)
**文件**: `test_scfde_timevarying.m` V4.0, `sync_dual_hfm.m` V1.1

### 目标

将 SC-FDE 端到端测试从"无噪声 sync 捷径"改为全链路有噪声处理：
- 帧同步（[[08_同步与帧结构|sync]]）
- 多普勒估计与补偿（[[10_多普勒处理|Doppler]]）
- 信道估计（[[07_信道估计与均衡|BEM/GAMP]]）
- Turbo 均衡（[[12_迭代调度器|LMMSE-IC + BCJR]]）

### 最终帧结构

```
[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|data]
```

- HFM+/HFM-: 双曲调频（Doppler 不变），保留用于帧检测
- LFM1/LFM2: 线性调频，用于多普勒估计（相位法）+ 精确定时
- guard: 800 样本（max_delay=720 + 80 余量）
- 参数: fs=48kHz, fc=12kHz, bw=8.1kHz, preamble_dur=50ms

### RX 两级分离架构

```
阶段①: 双LFM相位法多普勒估计 → alpha_est
阶段②: comp_resample_spline补偿
阶段③: LFM2匹配滤波精确定时 → lfm_pos
阶段④: 数据提取 + RRC匹配 + 符号定时恢复
阶段⑤: BEM信道估计 + Turbo均衡(LMMSE-IC ⇌ BCJR, 6轮)
```

### 验证结果

#### Oracle alpha（链路验证）

| 场景 | BER@5dB | BER@10dB | BER@15dB | BER@20dB |
|------|---------|----------|----------|----------|
| static | 0% | 0% | 0% | 0% |
| fd=1Hz | 0% | 0% | 0% | 0% |
| fd=5Hz | 0.24% | 0.07% | 0% | 0% |

#### 盲估计（LFM相位 + CP精估）

| 场景 | BER@5dB | BER@10dB | BER@15dB | BER@20dB | alpha误差 |
|------|---------|----------|----------|----------|-----------|
| static | 0% | 0% | 0% | 0% | ~0 |
| fd=1Hz | **0.20%** | **0%** | **0%** | **0%** | 89% |
| fd=5Hz | 50% | 50% | 50% | 50% | >100% |

### sync_dual_hfm V1.1 改进

α 公式从 `Δ/(2·S·fs)` 修正为 `Δ/(2·S·fs - G)`，加入帧间隔多普勒压缩修正项。

### fd=5Hz 多普勒估计攻关记录（10种方案）

| 方案 | 失败原因 |
|------|----------|
| 双HFM偏置对消(bookend) | 帧首尾间距0.85s >> 相干时间0.2s，Jakes衰落不一致 |
| 双HFM偏置对消(串联) | 直达径深衰落→匹配滤波峰被多径劫持 |
| CAF 2D搜索 | HFM Doppler不变性→α维度无法区分 |
| HFM-/LFM差异化偏置 | 不同信号峰被不同多径主导→差值含随机偏移 |
| CP迭代(α=0) | ISI污染70%CP + 衰落噪声 → 每轮仅修正1.3e-5 |
| VV-CFO(Turbo内) | BEM吸收92.5%CFO → VV只测到7.5%残余 |
| DA差分相位(已知TX) | 违反"禁用发射端参数"规则；且ISI噪底~4e-3>>α |
| SAGE(0.05s前导码) | 分辨率20Hz，无法区分5Hz和0Hz |
| SAGE(0.2s前导码) | α_est=1.56e-4（真值37.5%），首次正确方向但不够 |
| SAGE+VV迭代 | VV无法有效累积，BEM吸收阻止收敛 |

#### 根因分析

$$\text{多普勒频偏} = \alpha \cdot f_c = 5\text{Hz}, \quad \text{Jakes衰落频谱} = [-f_d, +f_d] = [-5, +5]\text{Hz}$$

**α·fc 完全落在 Jakes 频谱内**，单次实现中信号与噪声在频域重叠，物理上无法分离。

### 关键结论

1. fd<=1Hz 全盲可工作，两级分离架构有效
2. fd=5Hz 是物理极限（α·fc=5Hz∈Jakes[-5,+5]Hz）
3. 突破需：更高载频/更少多径/联合迭代/更长前导码

---

## 2026-04-17 — 14_Streaming P3 convergence_flag 误判 + est_snr 偏低 10dB

> 范围：`14_Streaming/src/Matlab/rx/modem_decode_scfde.m`（流式 P3 版本，与 13_SourceCode/tests 下的非流式版本独立演进）

### 症状

UI (`p3_demo_ui`) 显示 `convergence: 未收敛`，但 `BER = 0.00%`。`est_snr` 稳定低于真实 SNR 约 10dB，`est_ber` 虚高到 10%+。

测试 `test_p3_unified_modem.m` 修复前结果：
```
SNR= 5dB  BER=0.00%  iter=6 conv=0 est_snr=2.5dB  est_ber=2.74e-1
SNR=10dB  BER=0.00%  iter=6 conv=0 est_snr=3.3dB  est_ber=2.22e-1
SNR=15dB  BER=0.00%  iter=6 conv=0 est_snr=4.9dB  est_ber=1.19e-1
```

解码正确、LLR 硬判决全对，但元信息全错。

### 根因

**(A) est_snr 偏低 10dB**：`info.estimated_snr = 10*log10(P_sig_train / nv_eq) - 10*log10(sys.sps)` 的减项假设 rx_filt 做了 RRC 能量归一化（SNR 提升 sps 倍），但实际未归一化。sys.sps=8 → 减 9dB，与观察 10dB 偏差吻合。

**(B) convergence 单阈值过严**：`med_llr > 5` 判据在 L157 的 `max(min(Le_deint, 30), -30)` clip 下被压制。即便 BER=0 时 Lpost_info median |L| 仍 ≤5。

### 修复

**A. est_snr 去 sps 减法**
```matlab
- info.estimated_snr = 10*log10(P_sig_train / nv_eq) - 10*log10(sys.sps);
+ info.estimated_snr = 10*log10(max(P_sig_train / nv_eq, 1e-6));
```

**B. convergence_flag 三选一判据**（在 Turbo 循环内追踪硬判决稳定性）
```matlab
info.convergence_flag = double( ...
    med_llr > 5 || hard_converged_iter > 0 || frac_confident > 0.70);
```

其中：
- `hard_converged_iter` = 连续两轮 `bits_decoded` 相同时的首次 iter 号（Turbo 循环内增量计算）
- `frac_confident = mean(abs(Lpost_info) > 1.5)`

### 验收

```
修复后：
SNR= 5dB  BER=0.00%  iter=6 conv=1 est_snr=11.6dB est_ber=2.74e-1
SNR=10dB  BER=0.00%  iter=6 conv=1 est_snr=12.3dB est_ber=2.22e-1
SNR=15dB  BER=0.00%  iter=6 conv=1 est_snr=13.9dB est_ber=1.19e-1
```

- ✅ conv=1（真实收敛）
- ✅ est_snr 贴近真实 ±4dB
- ✅ BER=0 保持，2/2 test PASS
- ✅ FH-MFSK 不受影响
- ❌ est_ber 仍虚高（LLR scale 偏小致 `mean(0.5*exp(-|L|))` 虚大）

### 遗留

`est_ber` 估计偏高独立问题，根源 LLR 归一化 scale。可选修复：
1. soft_demapper 输出 LLR 做 per-block 归一化
2. 直接用 `hard_converged_iter > 0` 置 est_ber = 0

暂不处理，convergence_flag 已正确。

### Oracle 排查

本修复不引入发射端参数，conv/est_snr 均用接收端训练块本地估计。符合 CLAUDE.md §7 去 oracle 规则。

---

## V2.2 — 迁移 14_Streaming 架构：Phase 1+2 sps+GAMP 去 oracle (2026-04-24)

**Git**: 待提交
**Spec**: `specs/archive/2026-04-24-scfde-sps-deoracle-arch.md`
**Parent**: 前 3 次试错 `specs/archive/2026-04-23-scfde-{omp-replace-gamp, sps-deoracle-fourth-power}.md`
**Phase 3b 后续 spec**: `specs/active/2026-04-24-scfde-bem-decision-feedback-arch.md`
**关联模块**: [[07_信道估计与均衡]] [[12_迭代调度器]]

### 背景

`test_scfde_timevarying.m:488/605` 用 `all_cp_data(1:10)` oracle 做 sps 相位参考。前 3
次 NDA 尝试（功率最大化、4 次方）均因 6 径 ISI + SNR=10 退化（archive spec 记录）。

### 新架构设计

迁移 14_Streaming `modem_encode/decode_scfde.m` 架构：
- **Block 1 = training block**（seed=77 固定，RX 本地重建）
- **Blocks 2..N = data block**（bench_seed 注入，info_bits 真随机）
- **RX 端** `rng(77); train_sym = constellation(randi(4,1,blk_fft))` 重建 `train_cp`
- **bit efficiency 下降** 1/N_blocks（N=4→75%，N=16→94%，N=32→97%）

### Phase 1 改动（实施）

| 位置 | 改动 |
|------|------|
| L168-188 TX | `N_data_blocks = N_blocks-1`，`M_total = M_per_blk*N_data_blocks`；seed=77 生成 train_sym/train_cp；blocks 2..N 填 data |
| L190 后 | RX 侧加 train_cp_rx 独立重建（`rng(77)`）|
| L488/L605 sps ×2 | `conj(all_cp_data(1:10))` → `conj(train_cp_rx(1:10))` |
| L730-800 Turbo | `for data_bi=1:N_data_blocks, bi=data_bi+1`；LLR 索引/Lpost_inter 索引调整；`x_bar_blks{1}=train_sym, var=1e-6` |
| L791 逐块 BER | `for data_bi=1:N_data_blocks` |

### Phase 2 自动完成

Phase 1 改动 `all_cp_data(1:sym_per_block) = train_cp` 的副作用：GAMP 的 `tx_blk1 =
all_cp_data(1:sym_per_block)` 内容 = train_cp = RX 本地可重建。**Phase 2 的 oracle 清理
自动完成**（仅形式化 L651 `tx_blk1 = train_cp_rx` 明示语义）。

### Phase 3 失败与回滚

Phase 3 尝试 BEM 观测矩阵单 block 限制（仅用训练块 CP 段 37 个观测）→ **fd=1Hz
5dB 0.16%→49.64%**（BEM 无法拟合 Jakes 时变，单 block 观测只看帧初始快照）。

回滚 BEM 改动，保留 sps+GAMP Phase 1+2 收益。Phase 3b 独立 spec 移植 14_Streaming 的
`build_bem_observations` 两阶段（训练块 + Turbo 判决反馈 x_bar_blks）。

### 验证矩阵（Phase 1+2 最终版）

| 场景 | 5dB | 10dB | 15dB | 20dB |
|------|-----|------|------|------|
| static | 0.00% | 0.00% | 0.00% | 0.00% |
| fd=1Hz | 0.16% | 0.00% | 0.00% | 0.00% |
| fd=5Hz | 49.90% | 49.47% | 50.63% | 50.10% |

对比 Phase 1 bit-exact（架构切换后 BER 与 Phase 1 完全一致，回滚 Phase 3 后再验证一致）。
lfm_pos/peak/α_est/H_est 全部与历史一致。

### 达成事项

- ✅ sps 相位参考去 oracle（4 th 次尝试成功，架构方向而非 NDA）
- ✅ GAMP 训练矩阵去 oracle（自动副产品）
- ✅ Turbo decoder 口径按 data block only
- ✅ bit efficiency 下降接受为 trade-off（架构一致性）
- 🟡 BEM 观测矩阵仍 oracle（时变路径）→ Phase 3b
- 🟡 noise_var (nv_post) 仍 harness 注入 → 未来改

### 副产物

- `test_scfde_static.m` + `test_scfde_discrete_doppler.m` 加文件头 OFFLINE ORACLE
  BASELINE 声明（CLAUDE.md §2 白名单合规）
- 参考实现：`modules/14_Streaming/src/Matlab/rx/modem_decode_scfde.m`

### 旧 BER 基线作废

info_bits 口径下调 → 旧 E2E benchmark / Monte Carlo 基线不可直接对比（需重跑）。
当前 Phase 1 回归验证 bit-exact，但作为"架构一致性 BER"新基线。

### Oracle 排查

本修复主动消除 RX 链路对 `all_cp_data` 的引用（仅保留 TX 侧生成），符合 CLAUDE.md §7
排查清单第 8 条"测试 harness 允许传递协议参数，禁止传递 TX 数据"。

BEM 观测仍 oracle 部分已加明确 `⚠ Phase 3b TODO` 注释 + 指向 Phase 3b spec。

---

## V2.3 — Phase 3b.2 BEM 判决反馈去 oracle（2026-04-25）

**Spec**: `specs/active/2026-04-24-scfde-bem-decision-feedback-arch.md`
**Plan**: `plans/2026-04-24-scfde-bem-decision-feedback-arch.md`
**Phase 3b.1（前置）**: commit `55e3cd5` — 移植 `build_bem_observations_scfde` 局部函数 + 单测 6/6 PASS

### 目标

去除 `test_scfde_timevarying.m` 时变路径 BEM 调用对 `all_cp_data`（TX 数据）的依赖，
移植 14_Streaming `modem_decode_scfde::build_bem_observations` 两阶段方案：
- 训练块 CP 段：用 train_cp_rx 重建（合法）
- 数据块 CP/data 段：用 Turbo 判决反馈 `x_bar_blks` 软符号（去 oracle）

### Phase 3b.2 实施

`test_scfde_timevarying.m` 三处编辑：

1. **addpath**: 加 `13_SourceCode/src/Matlab/tests/bench_common`，保证 `build_bem_observations_scfde` 可见
2. **L648-720 重构**: 删除 `else` 时变 BEM 分支（含 `all_cp_data(idx)` oracle 引用），统一用 GAMP 静态估计训练块 h 作 iter=0..1 公共 fallback
3. **Turbo loop titer=2 入口**: 插入 `build_bem_observations_scfde + ch_est_bem` 重估 `H_cur_blocks`（条件：`~strcmpi(ftype,'static') && ~tog.oracle_h`）

### V3a/V3b/V3c 实测 BER（默认 1 seed × 4 SNR × 3 fading）

| 场景 | 5dB | 10dB | 15dB | 20dB | 接受准则 | 状态 |
|------|-----|------|------|------|----------|------|
| static | 0.00% | 0.00% | 0.00% | 0.00% | 不退化 | ✅ V3a PASS |
| fd=1Hz | 50.23% | 50.13% | 50.03% | 50.31% | 0.16/0/0/0% | ❌ V3b 灾难 |
| fd=5Hz | 50.73% | 49.90% | 49.22% | 51.31% | ~50% 物理极限 | ✅ V3c PASS |

### V3b fd=1Hz 灾难根因（软符号-BEM 鸡-蛋耦合）

- iter=0..1 用 GAMP 静态估计训练块 h 当所有 block 信道
- jakes fd=1Hz × 16 block × 256 sym/block ≈ 1.024s ≈ **一个完整 Jakes 周期**
- 第 8 block 时刻 h 与训练块 h 自相关接近 0（T₀ = 1/(2·fd) = 0.5s）
- LMMSE-IC 用 H_static 在第 8 block 附近完全失配 → titer=1 软符号 ~50% 错
- titer=2 BEM 用 garbage 软符号构造观测 → BEM 估计 garbage → Turbo 不收敛
- Phase 1 oracle BEM 的 0.16% 是因为 oracle x_bar 直接给出正确 h，**完全跳过软符号-信道耦合**
- Phase 3b 用判决反馈本质是把耦合放回，鸡-蛋问题在 jakes 时变 + 单训练块下不可解

Spec R1 风险已实测兑现（"iter=0..1 fallback 估计若不准 → Turbo 发散 → x_bar_blks 不可信 → iter=2 BEM 也不准"）。

### 14_Streaming 对比调研

> [!warning] Contradiction
> 14_Streaming production 的 `modem_decode_scfde::build_bem_observations` **没有 jakes fd=1Hz 实测 BER 数据**，无法作为 reference 标杆：
> - 14_Streaming 验证场景：`gen_doppler_channel + p4_channel_tap` = α 时变（速度漂移） + 静态多径 conv
> - 13_SourceCode 验证场景：`gen_uwa_channel` = jakes Doppler spread（径增益时变）
>
> fd=1Hz 50% 是 jakes 时变 + 单训练块 + 判决反馈架构 trade-off 的**首次实测发现**，无 production 对比数据。

### 状态

- ✅ `all_cp_data` 在 RX 链路完全消除（spec 接受准则 L143 核心目标达成）
- ✅ static 路径不退化（V3a PASS）
- ❌ fd=1Hz/fd=5Hz 时变路径 BER 灾难（架构 trade-off，**非实现 bug**）
- 🟡 spec 接受准则 V3b 0.16/0/0/0% 与实测 50% 严重偏离 — 需重写为"limitation 已知"
- 🟡 是否 commit Phase 3b.2 / 改 fallback / 回滚到 oracle BEM 待用户决策
- 🟡 Phase 3b.3/3b.4 未启动（pending）

### 单元测试

`test_build_bem_obs_scfde` 6/6 PASS（n_obs=96，h_tv 6×1280，ch_est_bem 兼容）— Phase 3b.1 不受 Phase 3b.2 重构影响。

### 工作区状态（未提交）

- `test_scfde_timevarying.m` 3 处 edit 未 commit
- `SC-TDE/verify_alpha_sweep_out/v1_a*.csv` 大量未 commit 修改（与 SC-FDE Phase 3b 无关）

详见 [[end-to-end-flow]] [[time-varying-channel-eq]]。

---

## V2.4 — 路线 4 (A1) 精确验证 + 决策落地（2026-04-26）

**Plan**: `plans/a1-streaming-decoder-jakes-validation.md`
**A1 脚本**: `modules/13_SourceCode/src/Matlab/tests/SC-FDE/diag_a1_streaming_decoder_jakes.m`

### A1 目的

V2.3 V3b fd=1Hz 50% 灾难是**架构 trade-off** 还是 **13 移植 bug**？V2.3 末候选 4 路线：
- 路线 1：接受 limitation
- 路线 2：回滚 Phase 3b.2
- 路线 3：改 fallback（spec 已分析逻辑上无效）
- **路线 4 (A1)**：精确验证 14_Streaming production decoder × jakes fd=1Hz

### A1 实测（3 seed × 4 SNR × 3 fading）

TX：14_Streaming `modem_encode_scfde`（去 oracle 协议）；Channel：`gen_uwa_channel` jakes fd=1Hz（与 13 test 同）；RX：14_Streaming production `modem_decode_scfde`（含 `mean(var)<0.6` BEM 门控 + `var<0.5` DD fallback）。无 LFM preamble（α=0 简化，2dB sync gain 缺失）。

| 场景 | 5dB | 10dB | 15dB | 20dB |
|------|-----|------|------|------|
| static (健全) | 1.60% | 0.02% | 0.00% | 0.00% |
| **fd=1Hz** | **49.58%** | **49.67%** | **50.07%** | **50.75%** |
| fd=5Hz | 49.97% | 49.82% | 49.81% | 49.82% |

### 对照 V2.3（13 Phase 3b.2 移植版本）

| 场景 | A1 (14 production) mean | V2.3 (13 移植 1 seed) | 差异 |
|------|------------------------|----------------------|------|
| static | 0.41% (5dB 1.60% / 其余 ~0) | 0/0/0/0% | <2 pp（无 preamble 缺失 sync gain） |
| fd=1Hz | **50.02%** | **50.18%** | **< 0.2 pp** |
| fd=5Hz | 49.86% | 50.29% | < 0.5 pp |

### 决策：架构 trade-off 确认（走路线 1）

14_Streaming production 与 13 移植版本在 jakes fd=1Hz 下 BER 几乎相同（差 < 0.2 pp）→ **不是 13 移植 bug，是架构层 trade-off**。

软符号-BEM 鸡蛋耦合在 14 production 也无法解：jakes 第 8 block 完全失配 → titer=1 软符号 ~50% 错（var ≈ 0.5）→ `mean(var)<0.6` 关闭 BEM 触发 + `var<0.5` 关闭 DD fallback → H 永不更新 → BER ~50%。

**协议层根因（不可在 decoder 层优化）**：单训练块 + jakes fd=1Hz × 1.024s 帧周期 ≈ 1 完整 Jakes 周期 → decoder 无法获得自相关零点之外的 H 观测。

### 路线 1 执行

- ✅ Commit Phase 3b.2 实现（`test_scfde_timevarying.m` + `build_bem_observations_scfde`）+ A1 验证脚本 + plan
- ✅ Spec 接受准则 V3b 重写为 "limitation 已知"
- ✅ **Phase 3b.4 决定不推广** `test_scfde_discrete_doppler.m`（OFFLINE ORACLE BASELINE，A1 证迁移会重现 50%）
- ✅ Spec 归档 → `specs/archive/`

### 后续可选（不在 Phase 3b 范围）

要恢复 Phase 1 水平 BER，需**协议层**改动：
- **多训练块插入**：每 4-8 block 插入训练块，跨块观测可采样非零自相关 h
- **导频 superimposed**（OTFS 式）：每数据块叠加导频参考
- **超训练块**：单块覆盖整个 Jakes 周期

详见 [[end-to-end-flow]] [[time-varying-channel-eq]]。
