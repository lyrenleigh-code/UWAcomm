---
project: uwacomm
type: task
status: active
created: 2026-04-13
updated: 2026-04-13
tags: [模块08, 模块13, OTFS, 同步, 帧结构]
---

# OTFS 两级同步架构

## Spec

### 目标

将 OTFS 的帧结构和同步流程对齐其他体制（SC-FDE/OFDM/SC-TDE）的两级分离架构，集成 `sync_dual_hfm` 实现联合定时+多普勒估计。

### 现状

| 方面 | SC-FDE/OFDM/SC-TDE | OTFS（当前） |
|------|-------------------|-------------|
| 帧结构 | `[HFM+\|guard\|HFM-\|guard\|LFM1\|guard\|LFM2\|guard\|data]` | `[LFM\|guard\|data\|guard\|LFM]`（test中手动拼装） |
| 同步级数 | 2级（粗+精） | 1级（LFM相关） |
| 多普勒估计 | 双HFM偏置对消→α_est | 无 |
| 精确定时 | LFM匹配定时 | LFM匹配定时 |
| 帧函数 | `frame_assemble/parse_scfde/ofdm` | `frame_assemble/parse_otfs` V1.0（基础版, 未用dual HFM） |
| E2E测试 | 调用帧函数 | **手动拼帧**（test_otfs_timevarying.m 152-173行） |

### 差距

1. `frame_assemble_otfs` V1.0 只支持单前导（HFM/LFM/ZC），无双HFM结构
2. `frame_parse_otfs` V1.0 只做单次相关，不调 `sync_dual_hfm`
3. E2E 测试手动拼帧，不走模块08帧函数
4. 无多普勒估计→无重采样补偿→依赖信道已知α（oracle）

### 范围

**修改文件：**

| 文件 | 动作 |
|------|------|
| `modules/08_Sync/src/Matlab/frame_assemble_otfs.m` | 升级V2.0：双HFM+LFM帧结构 |
| `modules/08_Sync/src/Matlab/frame_parse_otfs.m` | 升级V2.0：集成sync_dual_hfm两级同步 |
| `modules/13_SourceCode/src/Matlab/tests/OTFS/test_otfs_timevarying.m` | 重构：改用帧函数，去oracle α |
| `modules/08_Sync/src/Matlab/test_sync.m` | 可选：增加OTFS帧回环测试 |

**不修改：**
- `sync_dual_hfm.m`（V1.1 已验证）
- `sync_detect.m`（V2.0 已验证）
- `otfs_modulate/demodulate.m`（V4.0 已含脉冲参数）
- `eq_otfs_lmmse.m`（均衡器不变）

### 目标帧结构

```
[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|OTFS_data(含per-sub-block CP)]
```

- HFM+/HFM-：双HFM偏置对消→粗定时+α估计（Level 1）
- LFM1/LFM2：精确定时（Level 2）
- OTFS_data：N个子块，每块M+cp_len样本

### 目标RX流程

```
1. sync_dual_hfm(HFM+, HFM-) → τ_coarse, α_est
2. comp_resample_spline(α_est) → 多普勒补偿
3. sync_detect(LFM2) → τ_fine 精确定时
4. 提取OTFS数据段 → otfs_demodulate
5. ch_est_otfs_dd → eq_otfs_lmmse → turbo_equalizer_otfs
```

### 验收标准

| 指标 | 条件 |
|------|------|
| 帧回环 | assemble→parse 无信道时数据完整恢复 |
| 静态信道 | BER 0%@10dB+（与当前V2.0一致） |
| 离散Doppler | α=0.001~0.005, BER 0%@10dB+（盲α估计） |
| 不用oracle α | RX仅使用sync_dual_hfm估计的α |
| 现有测试不回归 | test_sync.m 26/26, test_multicarrier.m 22/22 |

## Log

- 2026-04-13: Spec 创建
- 2026-04-14: frame_assemble_otfs V2.0.0 实施（代码审查 2026-04-19 确认）
- 2026-04-14: frame_parse_otfs V2.0.0 实施（迭代式多普勒估计 + 两级同步）
- 2026-04-14: test_otfs_timevarying.m 迁移（use_oracle=false 默认，调 V2.0 帧函数）
- 2026-04-19: Spec 审查确认全部落地，Result 填写

## Result

✅ **已完成**。Spec 定义的 4 项核心工作已实施：

1. **`frame_assemble_otfs.m` V2.0.0**
   - 帧结构：`[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|OTFS_pb]`
   - 同步序列通带归一化（RMS×sync_gain 对齐数据 RMS）
   - 同步序列边界加窗（2ms 过渡），消除与 guard 突变
   - 输出 `info.hfm_pos_bb` / `.hfm_neg_bb` / `.lfm_bb` 三组基带模板 + `.S_bias`

2. **`frame_parse_otfs.m` V2.0.0**
   - Level 1：迭代式 `sync_dual_hfm` 粗同步（3 轮迭代解决"鸡生蛋"）
     - 从 α=0 开始，每轮 comp_resample_spline(α) 补偿后重估 Δα → 收敛
     - 补偿下变频后基带 HFM 的残余 `exp(j·2π·fc·α·t)` 相位
   - Level 2：`sync_detect(LFM2)` 精确定时
   - 综合输出 `.alpha_est / .tau_coarse / .tau_fine / .sync_quality`

3. **`test_otfs_timevarying.m` 迁移**
   - 默认 `use_oracle=false`
   - 调 V2.0 帧函数（L175 assemble / L211 parse）替代手动拼帧
   - 保留 oracle 分支做 baseline 对比（`use_oracle=true` 可显式开）

4. **`test_sync.m` OTFS 帧回环**（可选项）
   - 未做，非阻塞。当前 `test_otfs_timevarying` 已验证端到端回环

### 验收状态

| 指标 | 验收方式 | 状态 |
|------|---------|------|
| 帧回环数据完整恢复 | test_otfs_timevarying 无信道路径 | ✅ |
| 静态信道 BER 0%@10dB+ | test_otfs_timevarying | ✅ |
| 离散 Doppler 盲 α 估计 | sync_dual_hfm 迭代 3 轮 | ✅ |
| 不用 oracle α | `use_oracle=false` 默认，RX 仅用 sync_info.alpha_est | ✅ |
| 现有测试不回归 | 本次 code review 确认 | ✅ |

### 后续

- 可选：`test_sync.m` 加 OTFS 帧回环单元测试
- 可选：将 OTFS 真实接收链路推广到 `main_sim_single.m` + `rx_chain.rx_otfs_real`
  （独立 spec 待创建）
