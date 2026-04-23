---
project: uwacomm
type: task
status: active
created: 2026-04-23
updated: 2026-04-23
tags: [SC-TDE, 调试, alpha补偿, 13_SourceCode, 12_IterativeProc, 07_ChannelEstEq, GAMP, Turbo均衡]
branch: feat/sctde-alpha-1e2-disaster-rca
---

# SC-TDE α=+1e-2 100% 灾难根因深挖

## 背景

**触发事件**：2026-04-23 Phase c 5 体制灾难率横向 sanity check（`diag_5scheme_monte_carlo.m`）发现 —

| scheme | mean | median | std | min | max | 灾难率 (>30%) |
|--------|------|--------|-----|-----|-----|---------------|
| SC-FDE | 3.41 | 0.00 | 8.06 | 0.0 | 29.09 | 0/15 (0.0%) |
| OFDM | 0.01 | 0.00 | 0.03 | 0.0 | 0.13 | 0/15 (0.0%) |
| **SC-TDE** | **49.73** | **49.60** | **1.05** | **47.5** | **51.15** | **15/15 (100.0%)** |
| DSSS | 44.97 | 46.20 | 3.98 | 37.0 | 50.20 | 15/15 (100.0%) |
| FH-MFSK | 0.23 | 0.00 | 0.46 | 0.0 | 1.40 | 0/15 (0.0%) |

配置：α=+1e-2 / SNR=10 dB / ftype='static' / dop_rate=+1e-2（常数多普勒）/ seed 1..15 / custom6 信道。

**特征三点**
1. **std=1.05% 极低** — 15 seed 几乎相同 BER，**确定性失败**而非随机波动
2. **BER ≈ 50%** — QPSK 下等效"完全随机猜测"
3. **修正旧虚报** — todo.md 中 `α 补偿推广到其他 4 体制` 的"SC-TDE 失败"仅定性描述，首次定量确认 100% 灾难率

## Pipeline 路径（Phase c 配置下）

`test_sctde_timevarying.m` + `fading_cfgs = {'a=+1e-2', 'static', 0, +1e-2}` 触发 **static 分支**：

```
TX: info_bits → conv_encode → interleave → QPSK → [training(500) + data(2000)] → RRC + 上变频
Channel: gen_uwa_channel (custom6 + dop_rate=+1e-2 常数 α + static fading) → 上变频 → +AWGN
RX:
  1. 下变频 → LFM 相位粗估 α (est_alpha_dual_chirp + 迭代 refinement×2 + 大α精扫)
  2. 粗补偿 (comp_resample_spline) → 训练精估 α_train (带门禁，大α时跳过)
  3. 精补偿 → LFM2 精确定时 (down-chirp 模板)
  4. 数据段提取 → RRC 匹配 → sps 训练对齐
  5. 残余 CFO 补偿 (α_est*fc)
  6. GAMP 信道估计 (L_h=91, iter=50, train_len=500)
  7. Turbo 均衡 turbo_equalizer_sctde V8.1 × 10 轮：
     - iter=1: eq_dfe (num_ff=31, num_fb=90, λ=0.998, PLL Kp=0.01 Ki=0.005, h_est 初始化)
     - iter≥2: conv(full_est, h_ptr) 软 ISI 消除 + 单抽头 ZF (rx_ic/h0) + BCJR(max-log)
     - 反馈: Lpost_coded → interleave → soft_mapper → x_bar_data
  8. 硬判决 → BER
```

## 对比 SC-FDE（同配置）的差异面

| 层 | SC-FDE | SC-TDE | 差异 |
|----|--------|--------|------|
| α 估计 | est_alpha_dual_chirp V1.1 | est_alpha_dual_chirp V1.1 | **相同** |
| α 补偿 | comp_resample_spline | comp_resample_spline | **相同** |
| 信道估计 | ch_est_gamp V1.4 | ch_est_gamp V1.4 | **相同函数**，但 T_mat 维度/观测长度不同 |
| 均衡 | MMSE-IC-FDE（频域） | DFE + 软 ISI 消除（时域） | **不同** |
| PLL | 无 | 有（iter=1 内嵌） | **SC-TDE 独有** |
| 灾难率 | 10% (3/30 Monte Carlo) | **100% (15/15)** | **10× 差异** |

差异点集中在：**GAMP 的 T_mat 配置** / **时域 DFE+PLL** / **软 ISI 消除的 h_ptr 依赖**。

## 失败模式分析（50% BER + 低方差意味着什么）

QPSK 下 BER=50% 的数学含义：解调输出符号与真实符号**接近独立**（互信息 ≈ 0）。两种典型成因：

- **A. 错误吸引子**：Turbo 迭代放大 h_est 的错误（若 h 估错符号或相位 180°，软 ISI 消除后残差放大，10 轮迭代收敛到错误不动点）
- **B. 信号完全失锁**：采样相位漂移（时长 N_shaped=24000 sample × α=1e-2 = 240 sample 累积偏移 = 30 QPSK 符号周期），接收符号与训练序列对不上

std=1.05% 低方差排除"概率性发散" — 指向 **deterministic 攻击吸引子**（A 类）。

## 候选根因假设（按先验优先级）

| H | 假设 | 支持证据 | 反证空间 |
|---|------|---------|---------|
| H1 | **GAMP 在 α=+1e-2 残余频偏下估"伪信道"**（方向错/符号翻转） | SC-FDE L5/L6 已记录 GAMP 发散史；V1.4 修复仅针对 SC-FDE 调用模式 | D2/D4 可验证 |
| H2 | **Turbo iter≥2 错误放大**：即使 iter=1 DFE 能 work，iter≥2 用错 h_ptr 做 ISI 消除，LLR 被放大到错误饱和 | V8.1 iter≥2 丢 PLL、完全依赖 h_ptr；10 轮迭代足以收敛错误吸引子 | D3 (turbo_iter=1) 可验证 |
| H3 | **DFE PLL 在 120 Hz 残余 CFO（α·fc）下跟不上**：Kp=0.01/Ki=0.005 时间常数不够 | static 路径 α_train 精估有门禁，残余 CFO 未必被补掉 | D1 (oracle α) 可验证 |
| H4 | **采样相位累积漂移**：N_shaped=24000 × 1e-2 = 240 sample = 30 sym，sps 训练对齐可能失配 | 但 comp_resample_spline 已做 α 补偿，理论上应抵消 | D1 oracle α 残留偏差可定量 |
| H5 | **α_est 本身偏差大**（est_alpha_dual_chirp 在 +1e-2 精度不足） | 已有 refinement×2 + 大α精扫，但未对 SC-TDE 单独验证偏差范围 | D1 oracle α 可验证 |

## 诊断矩阵（4 步级联 oracle-isolation）

每步产出独立 MATLAB 脚本（跑时间 < 5 min）+ 结果表格。用户跑，观察事实，不代下结论。

### D1 — Oracle α 测试

**目的**：剥离 α 估计误差，看 Turbo+GAMP 在"完美补偿"下是否仍灾难。

**修改点**（runner 内临时 toggle）：
```matlab
% 在 est_alpha_dual_chirp 之后、comp_resample_spline 之前插入：
if exist('diag_oracle_alpha','var') && diag_oracle_alpha
    alpha_est = dop_rate;   % 直接喂真值（static 路径只有常数 α）
    alpha_lfm = dop_rate;
    alpha_train = 0;
end
```

**观察点**：α=+1e-2 × SNR=10 × 5 seed × `diag_oracle_alpha ∈ {false, true}` = 10 trial。

**判据**
- 若 BER 恢复到 <1% → α 估计是主因 → 进 H5 深挖（est_alpha_dual_chirp 在 SC-TDE 场景的偏差谱）
- 若仍 50% → α 估计无关 → 进 D2

### D2 — Oracle h_time 测试

**目的**：剥离 GAMP 估计误差，看 Turbo 在"完美信道"下是否仍灾难。

**修改点**：
```matlab
% 替换 ch_est_gamp 调用：
if exist('diag_oracle_h','var') && diag_oracle_h
    h_est_gamp = h_sym;     % 直接喂真信道（runner 里已有 h_sym 真值）
else
    [h_gamp_vec, ~] = ch_est_gamp(rx_train(:), T_mat, L_h, 50, noise_var);
    h_est_gamp = h_gamp_vec(:).';
end
```

**观察点**：α=+1e-2 × SNR=10 × 5 seed × `(diag_oracle_alpha, diag_oracle_h) ∈ {(T,T), (F,T), (T,F)}` = 15 trial（叠加 D1 结果）。

**判据**
- 若 BER 恢复到 <1% → **GAMP 是直接根因**（H1 confirmed）→ 进 H1 深挖（查 SC-TDE 的 T_mat / L_h / obs 与 SC-FDE 差异）
- 若仍 50% → GAMP 无关 → 进 D3

### D3 — turbo_iter=1 测试

**目的**：剥离 iter≥2 的 ISI 消除+LLR 放大，看 DFE 单独是否能 work。

**修改点**：
```matlab
if exist('diag_turbo_iter','var') && ~isempty(diag_turbo_iter)
    turbo_iter_use = diag_turbo_iter;
else
    turbo_iter_use = turbo_iter;   % 默认 10
end
[bits_out,~] = turbo_equalizer_sctde(rx_sym_recv, h_est_gamp, training, ...
    turbo_iter_use, noise_var, eq_params, codec);
```

**观察点**：α=+1e-2 × SNR=10 × 5 seed × `turbo_iter ∈ {1, 2, 3, 5, 10}` = 25 trial。

**判据**
- 若 turbo_iter=1 BER <5% 且随 iter 单调恶化 → **iter≥2 错误放大确认**（H2 confirmed）→ 修 turbo_equalizer_sctde 的 ISI 消除逻辑或加 PLL
- 若 turbo_iter=1 就已 50% → DFE(iter=1) 本身失败 → 进 D4

### D5 — Turbo 之前信号层对齐诊断（2026-04-23 扩展）

**触发原因**：D1+D2+D3 全部证伪 5 个原假设。oracle α+h 双开 BER 仍 50.51%（D2 TT 组），iter=1 DFE 单独就 50%（D3）。结论：**rx_sym_recv 送入 Turbo 之前信号层已失去信息**。

**目的**：量化 Turbo 输入数据本身的质量，定位 **sync/数据段提取/sps/CFO** 中哪一层先崩。

**修改点**（runner 插桩，在 `turbo_equalizer_sctde` 调用之前）：
```matlab
if exist('diag_dump_signal','var') && diag_dump_signal && si == 1 && fi == 1
    % 打印信号层诊断：
    % 1. 同步/定时
    lfm_expected_theory = 2*N_preamble + 3*guard_samp + N_lfm + 1;
    fprintf('  [DIAG-S] lfm_pos=%d, theory≈%d, err=%d\n', lfm_pos, lfm_expected_theory, lfm_pos-lfm_expected_theory);
    fprintf('  [DIAG-S] alpha_est=%+.4e, dop_rate=%+.4e, err=%+.2e\n', alpha_est, dop_rate, alpha_est-dop_rate);
    fprintf('  [DIAG-S] best_off (sps phase)=%d / %d\n', best_off, sps);
    % 2. 前 50 符号对齐质量
    c50 = sum(rx_sym_recv(1:50) .* conj(training(1:50))) / ...
          (norm(rx_sym_recv(1:50)) * norm(training(1:50)) + 1e-30);
    fprintf('  [DIAG-S] corr(rx_train(1:50), training(1:50)) |=%.3f, arg=%+.1f°\n', abs(c50), angle(c50)*180/pi);
    % 3. 用真 h 做模型拟合残差
    y_model = conv(training(1:train_len), h_sym);
    y_model = y_model(1:train_len);
    resid = rx_sym_recv(1:train_len) - y_model;
    pwr_sig = mean(abs(y_model).^2);
    pwr_resid = mean(abs(resid).^2);
    fprintf('  [DIAG-S] P_sig=%.4e, P_resid=%.4e, SNR_emp=%.1f dB, P_noise_exp=%.4e\n', ...
        pwr_sig, pwr_resid, 10*log10(pwr_sig/pwr_resid), noise_var);
    % 4. 后半段训练序列对齐度（检测是否中途失锁）
    c_mid = sum(rx_sym_recv(251:300) .* conj(training(251:300))) / ...
            (norm(rx_sym_recv(251:300)) * norm(training(251:300)) + 1e-30);
    fprintf('  [DIAG-S] corr(mid-train 251-300) |=%.3f, arg=%+.1f°\n', abs(c_mid), angle(c_mid)*180/pi);
end
```

**观察点**：4 组 oracle 配置（FF/TF/FT/TT）× 5 seed = 20 trial，每组第 1 seed 打印 diag，其余只收集 BER。

**判据（按发现分类）**
- **lfm_pos 偏差 > 10 sample** → 同步层错
- **|corr(1:50)| < 0.3** → 数据段提取完全错位（相关系数接近随机）
- **|corr(1:50)| > 0.8 但 |corr(251:300)| < 0.3** → **中途失锁**（累积相位漂移）
- **|corr| 全程 > 0.8 但 SNR_emp 远低于名义 noise_var** → 信道卷积/均衡残差问题（真正进入 H 未知空间）
- **|corr| 全程 > 0.8 且 SNR_emp 合理** → **输入是好的，Turbo 本身死循环**（需要深入 turbo_equalizer_sctde debug）

### D4 — GAMP → LS 替换测试

**目的**：换掉 GAMP 用 `ch_est_ls`（线性最小二乘），确认是否 GAMP 发散独有。

**修改点**：
```matlab
if exist('diag_use_ls','var') && diag_use_ls
    h_ls_vec = (T_mat' * T_mat + 1e-3*eye(L_h)) \ (T_mat' * rx_train(:));
    h_est_gamp = h_ls_vec(:).';
else
    [h_gamp_vec, ~] = ch_est_gamp(...);
end
```

**观察点**：α=+1e-2 × SNR=10 × 5 seed × `diag_use_ls ∈ {false, true}` = 10 trial（独立于 D2 真信道）。

**判据**
- 若 LS 恢复（BER <5%） → GAMP 发散确认（SC-TDE 需要独立 GAMP guard 或默认走 LS）
- 若 LS 也 50% → 估计器方法无关 → 回退重审 Pipeline 其他层（定时/同步/帧提取）

## 执行顺序约束

D1 → D2 → D3 → D4 → D5，**严格串行**（每步看结果再决定下一步是否跑）。若 D1 已恢复，后续可跳过。每步用户确认后进下一步。

**本次实际执行**（2026-04-23）：D0b gate → D1 → D2 → D3 → 跳 D4（D2 已证给真 h 仍崩，LS 无悬念）→ 直接进 D5 信号层诊断。

## 接受准则（本 spec 完成判定）

- [ ] 4 步 diag 脚本全部写出并可独立运行
- [ ] D1-D4 至少一步定位到根因层（oracle 恢复组/非恢复组分界清晰）
- [ ] 根因写入 `wiki/modules/13_SourceCode/SC-TDE调试日志.md`，附 BER 表格
- [ ] 若定位到可修（如 GAMP guard 扩散 / LS fallback / iter≥2 PLL 加入），创建 follow-up spec，**不在本 spec 内做修复**（保持 RCA 与 fix 解耦）
- [ ] todo.md 对应任务状态更新

## 非目标（本 spec 显式不做）

- ❌ DSSS α=+1e-2 灾难（独立 spec，todo.md 已登记）
- ❌ 时变信道分支（fd_hz>0）的灾难（本 spec 限定 static+const-α）
- ❌ 修复根因（诊断 ≠ 修复，修复走独立 spec）
- ❌ SC-TDE 跨信道 profile 扩展（custom6 之外）

## 风险与回退

- **风险 1**：D1-D4 全 50% BER（所有层都失效）→ 需反思诊断框架是否覆盖不全。回退：加 D5 定时层 diag（`lfm_pos` 是否在 ±α 下偏移）+ D6 帧提取 diag（`rx_sym_recv` 前 50 符号与 training 的相关系数）。
- **风险 2**：oracle h 需要从 `h_sym`（line 61）或 `gen_uwa_channel` 输出中正确取值。runner 内 `h_sym` 是 **符号级基带**冲激响应，实际应与 GAMP 输出的 h_est 同坐标系。需 diag 脚本内打印对比 `h_est_gamp` vs `h_sym` 相位/幅度。
- **风险 3**：test 脚本 `bench_seed` 注入已修（Phase H），5 seed 独立性有保证。

## 参考

- 5 体制 sanity check 诊断：`modules/13_SourceCode/src/Matlab/tests/bench_common/diag_5scheme_monte_carlo.{m,txt}`
- SC-TDE runner：`modules/13_SourceCode/src/Matlab/tests/SC-TDE/test_sctde_timevarying.m`（797 行）
- Turbo 均衡器：`modules/12_IterativeProc/src/Matlab/turbo_equalizer_sctde.m`（170 行，V8.1）
- GAMP 估计器（V1.4 已修 SC-FDE 发散）：`modules/07_ChannelEstEq/src/Matlab/ch_est_gamp.m`
- 同类历史 spec：
  - `specs/archive/2026-04-21-alpha-pipeline-large-alpha-debug.md`（SC-FDE α=3e-2 突破 3 patch）
  - `specs/archive/2026-04-23-scfde-omp-replace-gamp-and-oracle-clean.md`（SC-FDE GAMP→OMP 实验失败）
- CLAUDE.md §7 Oracle 排查清单（本 spec 的 diag 脚本为**临时**绕过，不进主线）
