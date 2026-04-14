---
spec: specs/active/2026-04-13-otfs-sync-architecture.md
created: 2026-04-13
status: implementing
---

# OTFS 两级同步架构 — 实现计划

## 修改文件（4个，一起改）

### 1. frame_assemble_otfs.m V1.0→V2.0

升级帧结构为通带 `[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|OTFS_pb]`

接口变更：
```
V1.0: frame_assemble_otfs(data_symbols, fs, preamble_type, guard_len)
V2.0: frame_assemble_otfs(otfs_signal, params)
  params: .fs, .fc, .sps, .N, .M, .cp_len
          .T_hfm, .T_lfm, .bw (同步序列参数)
          .guard_samples (保护间隔)
```

内部流程：
1. 生成 HFM+/HFM- 通带实信号（gen_hfm）
2. 生成 LFM1/LFM2 通带实信号（gen_lfm）
3. OTFS 基带→通带（otfs_to_passband 或 upconvert）
4. 拼装：[HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|OTFS_pb]
5. 输出 frame_info（各段起止位置、模板等）

### 2. frame_parse_otfs.m V1.0→V2.0

两级同步 RX 流程：
```
V2.0: [otfs_bb, sync_info] = frame_parse_otfs(rx_signal, params)
```

内部流程：
1. downconvert → 基带
2. Level 1: sync_dual_hfm(HFM+, HFM-) → τ_coarse, α_est
3. comp_resample_spline(α_est) → 多普勒补偿
4. Level 2: sync_detect(LFM2模板) → τ_fine
5. 提取 OTFS 通带段 → passband_to_otfs 或 downconvert → 基带 OTFS
6. 输出 sync_info（α_est, τ_coarse, τ_fine, 质量指标）

### 3. test_otfs_timevarying.m 重构

- 替换手动拼帧（152-173行）为 frame_assemble_otfs V2.0
- 替换手动同步（178行+）为 frame_parse_otfs V2.0
- 去掉 oracle α（当前通过 known dop_rate 补偿）
- 保持 BER 测试矩阵和可视化

### 4. test_sync.m 增加 OTFS 帧回环

- 5.4 OTFS帧回环：已有，检查是否需要升级到V2.0接口

## 依赖关系

```
frame_assemble_otfs V2.0 + frame_parse_otfs V2.0
  ↓
test_otfs_timevarying.m 重构
  ↓
验证 BER
```

## 风险

| 风险 | 缓解 |
|------|------|
| otfs_to_passband/passband_to_otfs 可能耦合在测试中 | 检查是否可复用或需提取 |
| sync_dual_hfm 在通带OTFS帧中的HFM检测精度 | 已在test_sync 8.1验证 |
| α补偿后的残余CFO | 参考SC-FDE流程加 comp_cfo_rotate |
