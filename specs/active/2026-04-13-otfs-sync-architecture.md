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

## Result

_待填写_
