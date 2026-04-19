---
project: uwacomm
type: enhancement
status: active
created: 2026-04-19
tags: [14_Streaming, 时变信道, BEM, Doppler, P3-UI, 去oracle]
---

# P3 UI decoder 时变分支移植（Level 2）

## 目标

把 `13_SourceCode/tests/*_timevarying.m` 的**时变信道估计 + 均衡算法**移植到
`14_Streaming/rx/modem_decode_*`，使 P3 UI 下高 Doppler (≥5Hz) 场景能正确解码。

**非目标**：
- 不改 modem_encode（TX 保持 V2.0）
- 不重写 α 估计（Level 2 先只做 decoder，α 补偿留 L3）
- 不改 OTFS（已有 DD 域处理）

## 13_SourceCode 端到端 RX 链路分析

以 `test_scfde_timevarying.m` L150-300 为例，完整 RX：

```
1. downconvert → bb_raw
2. LFM 相位法粗估 α_lfm   (两个 LFM peak 相位差)
3. comp_resample(α_lfm) 粗补偿
4. LFM 精定位帧起点
5. CP 精估 α_cp (CP 自相关)
6. α_total = α_lfm + α_cp 精补偿
7. 提取 rx_data_bb
8. RRC match_filter → rx_filt
9. 符号定时 best_off (← 这里用了 all_cp_data, ORACLE!)
10. 下采样 → rx_sym_all
11. 训练块 GAMP 估信道 h_est_block1
12. ch_est_bem 从信道观测构建 BEM 基
13. eq_mmse_ic_tv_fde / eq_bem_turbo_fde Turbo 迭代
14. siso_decode_conv
```

**Oracle 泄漏审查**：
- L194/L242 `all_cp_data` 作符号定时参考 → **ORACLE**（CLAUDE.md §7 #7 违规）
- 14_Streaming 已在 modem_decode_scfde V2.0 去除 oracle（用 train_seed 本地重生成 training）

## Level 2 移植范围

**只移植算法核心，不移植 α 估计**：

| 从 13_SourceCode 移植 | 状态 |
|---------------------|------|
| ch_est_bem（时变 BEM 估计）| 07_ChannelEstEq 已有函数，直接用 |
| eq_mmse_ic_tv_fde（时变 IC-FDE）| 07_ChannelEstEq 已有 |
| eq_bem_turbo_fde（BEM-Turbo，需先去 oracle）| **2026-04-19 已 V2.0 去 oracle** ✓ |
| BEM 观测构建 `build_scattered_obs` | 07 已有 |
| 散布导频位置 + 训练块 | 14_Streaming 已有协议结构 |

**不移植**：
- α 估计（Level 3，需修 estimate_alpha_dual_hfm 精度问题）
- α 补偿（Level 3，在 try_decode_frame 层）
- LFM 精定位（14_Streaming 已有 detect_frame_stream）

## 策略：自适应时变判定 vs 显式开关

### 方案 A — 自适应检测（推荐）
`modem_decode_scfde` 入口加 BEM 自检测：
```matlab
% 从首个训练块估计时变强度
h_est_init = ch_est_gamp(...);
% 第二个训练块（或跨块信道估计）估计变化率
h_est_block2 = ...;
var_h_time = var(abs(h_est_block2 - h_est_init));
is_timevarying = var_h_time > threshold;

if is_timevarying
    走 ch_est_bem + eq_mmse_ic_tv_fde
else
    走现有 ch_est_gamp + eq_mmse_ic_fde
end
```

**优点**：UI 不感知，自动切换
**缺点**：检测可能误判

### 方案 B — 显式参数开关
`sys.scfde.fading_type = 'static' | 'timevarying'`（原 test 方式）

**优点**：简单直观
**缺点**：UI 需要暴露开关；违反"decoder 不该有 fading_type 分支"（conclusions #6 消除该字段）

**决策**：方案 A（自适应），fallback 到静态分支保证向后兼容。

## 文件清单

### 修改（4 + 1 新建）

| 文件 | 改动 |
|------|------|
| `14_Streaming/rx/modem_decode_scfde.m` | V2.1→V3.0：加时变分支 |
| `14_Streaming/rx/modem_decode_ofdm.m`  | 同上 |
| `14_Streaming/rx/modem_decode_sctde.m` | 同上 |
| `14_Streaming/common/detect_timevarying.m` | **新建** 时变自适应检测 |
| `14_Streaming/rx/modem_decode_dsss.m`  | 已 OK（Rake 本身时变鲁棒），不改 |
| `14_Streaming/rx/modem_decode_otfs.m`  | 已 OK（DD 域），不改 |

### 不动
- modem_encode_*
- UI 层（try_decode_frame）
- 01-13 算法模块

## 验收标准

### 功能

- [ ] Doppler=0 静态：所有 decoder BER 与 V2 一致（不回归）
- [ ] Doppler=5Hz SC-FDE：BER < 5% (当前崩 50%)
- [ ] Doppler=10Hz SC-FDE：BER < 15% (当前崩)
- [ ] 自适应检测：静态帧不误触发 BEM 分支
- [ ] Oracle 审查：新增代码无 all_cp_data / all_sym 访问

### 代码

- [ ] modem_decode_* 净增 ≤ 150 行/文件
- [ ] detect_timevarying.m ≤ 80 行
- [ ] mlint 无新增警告

## 风险

| 风险 | 等级 | 应对 |
|------|------|------|
| ch_est_bem 需要两个训练块/散布导频，modem_encode 未提供 | 🔴 高 | 编码器加导频（需改 encode，超出当前 spec） |
| 自适应检测不准 → 静态场景误触发 BEM → BER 劣化 | 🟡 中 | 保守阈值 + 首轮测试 |
| BEM 阶数 Q 自动选择错误 | 🟡 中 | 用 fd_hz_max 保守上界 |
| 符号定时 best_off 搜索范围不足 | 🟢 低 | 已验证 SC-FDE 静态路径 |

## 实施策略（4 步）

### Step 1 — 修 α 估计（passband 版本）*依赖*
实际上这不是 Level 2 必需。Level 2 先假设**无 Doppler 补偿**，只修时变信道估计。
高 Doppler 下 BER 改善主要来自时变信道估计（BEM 跟踪 Jakes），不依赖 α 补偿。
- **跳过 L2-S1**，直接做 S2

### Step 2 — modem_decode_scfde V3.0
- 自适应检测 is_timevarying
- 时变分支：ch_est_bem + eq_mmse_ic_tv_fde
- 静态分支：保持 V2.1 逻辑
- 基带 loopback 测试：静态 BER=0 / 时变 5Hz BER<5%

### Step 3 — 推广到 ofdm/sctde
参照 S2 模板，最小改动

### Step 4 — UI 端到端验证
UI 下 Doppler 0/5/10Hz 测试各体制 BER

## Log

- 2026-04-19: Spec 创建（侦察 test_scfde_timevarying 发现 oracle 泄漏，调整策略）
- 2026-04-19: Step 2 完成 — modem_decode_scfde V3.0 加 BEM 跨块时变估计分支
  + `bem_done` 门控 + `build_bem_observations` helper（训练 CP + 数据块 CP）
  + 静态回归 test_p3_unified_modem 2/2 PASS（BER=0 @ 5/10/15dB）
- 2026-04-19: Step 3 完成 — OFDM/SC-TDE 对齐
  + modem_decode_ofdm V2.0→V3.0：镜像 scfde 模式，加 BEM 分支 +
    `build_bem_observations_ofdm` helper（频域软符号 → 时域 → CP 观测）
  + modem_decode_sctde V1.0→V3.0：已有 pilot-gated TV 分支（is_timevarying），
    仅升版本号对齐（结构化开关，方案 B；自适应检测留 L2-S4）
  + 静态回归 test_p3_2_ofdm_sctde 2/2 PASS（BER=0 @ 5/10/15dB）

## Result

### 已完成（Level 2 Step 2 + Step 3）

| 文件 | 状态 |
|------|------|
| modem_decode_scfde.m | V2.1→V3.0 ✓ BEM 分支 + helper |
| modem_decode_ofdm.m | V2.0→V3.0 ✓ BEM 分支 + helper (freq→td 桥接) |
| modem_decode_sctde.m | V1.0→V3.0 ✓ 版本对齐（TV 分支已存在） |

### 未完成（Level 2 Step 4 留待后续 session）

1. **UI 端到端 Doppler 有效性验证**：当前 UI 的 Doppler 注入是纯 CFO
   resample+phase，BEM 只对 Jakes 类时变多径有效。要看到 BER 改善，需：
   - UI 改用 `gen_uwa_channel_pb`（Jakes 衰落 + Doppler），或
   - 注入"快变多径增益"（per-sample ρ 时变）
2. **eq_mmse_ic_tv_fde 替换**：当前 scfde/ofdm 均衡仍是静态 MMSE-IC（只换了
   H_cur 的来源）。纯 CFO 场景需要 TV-FDE 做 ICI 抑制才能真正改 BER。
3. **α 盲估计 + 补偿链**：当前 decoder 假设外层已做 Doppler 补偿，UI 侧依然
   没有 α 估计/补偿（Level 3 范围）。
4. **SC-TDE 自适应检测**：当前 is_timevarying 只看 meta.pilot_positions（结构
   化 B 方案）。方案 A（仅凭接收信号自动切换）需要跨块信道观测比较。
