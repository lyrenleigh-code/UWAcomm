# DSSS 端到端调试日志

> 体制：DSSS | 当前版本：V1.2
> 关联模块：[[05_扩频解扩]] [[07_信道估计与均衡]] [[10_多普勒处理]]
> 关联笔记：[[SC-TDE调试日志]]（共享 post-CFO audit）[[项目仪表盘]]

#DSSS #调试日志 #端到端

---

## 版本总览

| 版本 | 日期 | 核心变更 | 状态 |
|------|------|---------|------|
| V1.0 | 2026-04-13 | Gold31 + Rake(MRC) + DBPSK + DCD 首版 | ✅ 静态 0%@-15dB+ |
| V1.1 | 2026-04-19 | benchmark_mode 注入（E2E C 阶段） | ✅ |
| V1.2 | 2026-04-24 | 删 post-CFO 伪补偿（audit 命中） | ✅ α=+1e-2 43.28%→0% |

---

## V1.2 — post-CFO 伪补偿 fix (2026-04-24)

**Git**: 待提交
**Spec**: `specs/active/2026-04-24-cfo-postcomp-cross-scheme-audit.md`（audit）
**Parent RCA**: `specs/archive/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md`（SC-TDE 同 bug 先发现）
**D10 验证脚本**: `tests/DSSS/diag_D10_dsss_disable_cfo.m`
**关联模块**: [[10_多普勒处理]]

### 触发事件

SC-TDE V5.4（6613041）RCA 完成后，audit spec `2026-04-24-cfo-postcomp-cross-scheme-audit` grep 所有体制 runner，DSSS `test_dsss_timevarying.m:344-348` 与 `test_dsss_discrete_doppler.m:265-269` 命中同模式：

```matlab
% 原代码（V1.1）：
if abs(alpha_est) > 1e-10
    cfo_res = alpha_est * fc;
    t_chip = (0:length(rx_chips)-1) / chip_rate;
    rx_chips = rx_chips .* exp(-1j*2*pi*cfo_res*t_chip);  % ← 同 SC-TDE 伪补偿
end
```

与 SC-TDE 差异：作用于 **chip 级**（不是 symbol 级），chip_rate=6000 与 sym_rate 相同值。

### D10 DSSS 验证（2 模式 × 3 α × 5 seed = 30 trial）

| mode | α=0 | α=+1e-3 | α=+1e-2 |
|------|-----|---------|---------|
| **legacy_on**（apply post-CFO，历史 V1.1） | 0.00% | 0.00% | **43.28±4.42%** |
| **legacy_off**（skip post-CFO，V1.2 新默认） | 0.00% | 0.00% | **0.00%** ✓ |

**α_est 精度**（legacy_off）：
- α=0 → +2.425e-8（-7 阶残余）
- α=+1e-3 → +9.984e-4（-0.16%）
- α=+1e-2 → +9.999e-3（-0.01%）

α 估计链完美，100% 灾难完全来自 post-CFO。

### 关键结论

1. **DSSS α=+1e-2 100% 灾难 = 单一根因 = post-CFO 伪补偿**。不是与其他问题叠加。
2. DSSS 在基带 Doppler 模型下对 α 常数**非常鲁棒**（α=+1e-2 skip 后 5 seed 全 0%）。比 SC-TDE 还干净（SC-TDE skip 后仍有 0.29% 残余）。
3. **物理原因（与 SC-TDE 同）**：`gen_uwa_channel` 基带模型仅做时间伸缩，无载波频偏；`comp_resample_spline` 补偿时间伸缩后 bb_comp 无 CFO；`rx_chips .* exp(-j·2π·α·fc·t_chip)` 凭空注入 120 Hz 频偏（α=1e-2），累积每 chip 7.2° 相位旋转，Rake finger 相关完全抵消。
4. 为何 DSSS 比 SC-TDE 更干净：DSSS **Rake(MRC) + 长扩频序列**对 ISI 有自然处理；SC-TDE 时域 DFE 对任何相位损伤都非常脆弱。

### 验证 2026-04-23 Phase c 量化的印证

Phase c sanity check（`diag_5scheme_monte_carlo`）：DSSS α=+1e-2 SNR=10 × 15 seed 全灾难，median BER 46.2%。

本次 D10：legacy_on（等同 Phase c 配置）5 seed mean 43.28%，**与 Phase c 46.2% 一致**（误差 ≤3% 属 seed 抖动）。

### 对 Sun-2020 符号级 Doppler 跟踪的影响

Memory 曾记录"Sun-2020 对 α=+1e-2 失效，需 adaptive Gold31 bank"——此结论**失效**。根因不是 Sun-2020 capacity，而是 post-CFO 伪补偿。V1.2 下 DSSS α=+1e-2 恒定 Doppler 直接 work。

**但** Sun-2020 对**加速度/时变 α**（`comp_resample_piecewise` 分段重采样）仍有价值（spec `2026-04-22-dsss-symbol-doppler-tracking` D α=+3e-2 BER 51%→2.2%），与本次恒定 α 场景不冲突。

### 改动摘要

| 改动 | 内容 |
|------|------|
| runner 主改（timevarying） | L344-348 post-CFO 改默认 skip + `diag_enable_legacy_cfo` 反义 toggle |
| runner 主改（discrete_doppler） | L265-269 同模板 |
| CSV 字段补全 | `row.alpha_est = alpha_est_matrix(fi_b, 1)` 加入 bench CSV |
| 新验证脚本 | `diag_D10_dsss_disable_cfo.m`（2 模式 × 3 α × 5 seed = 30 trial） |

### 下一步

- [ ] todo.md 修正：DSSS α=+1e-2 深挖标记完成（单一根因已锁定）
- [ ] Sun-2020 独立 spec（`2026-04-22-dsss-symbol-doppler-tracking`）保留作时变 α 方向，与本次恒定 α 场景解耦
- [ ] 扩展 verify（可选）：α=+3e-2 恒定 + α<0 对称性

---

## V1.0 / V1.1 历史（摘要）

**V1.0（2026-04-13）**: Gold31（127 chip）+ Rake(MRC, 5 finger) + DBPSK + DCD (differential coded detection) + Conv 编码 + BCJR。静态 0%@-15dB+，96.8 bps。

**V1.1（2026-04-19）**: 加 `benchmark_mode` 注入（E2E C 阶段），从 `bench_snr_list/bench_fading_cfgs/bench_seed` 注入，写 bench CSV。
