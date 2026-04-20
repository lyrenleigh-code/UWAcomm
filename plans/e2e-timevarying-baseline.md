---
project: uwacomm
type: plan
status: active
created: 2026-04-19
updated: 2026-04-19
parent_spec: specs/active/2026-04-19-e2e-timevarying-baseline.md
phase: E2E-benchmark
tags: [端到端, 基线, 时变信道, benchmark, 13_SourceCode]
---

# E2E 时变信道性能基线 benchmark — 实施计划

## 目标

执行 spec `2026-04-19-e2e-timevarying-baseline.md` 五阶段（A1/A2/A3/B/C）扫描，共
1278 次运行，产出 BER/NMSE/turbo收敛/同步/检测率的统一基线。

## 非目标

- ❌ 修改任何 01–12 算法模块代码（eq_*, ch_est_*, turbo_*, sync_* 原样跑）
- ❌ 修改 `gen_uwa_channel`（直接用其 `.h_time` oracle 输出算 NMSE）
- ❌ 改 `modem_decode_*`（14_Streaming 范畴，spec 已决策延后）
- ❌ 新增新算法/新体制

## 关键设计决策

### 1. 不写统一 harness，用 "runner 注入 + CSV 追加" 模式

13_SourceCode 六个 `test_*_timevarying.m`（330~943 行）都把 TX/RX 全流程内联 —— 不抽取，
只加参数注入开关。好处：不碰算法逻辑，风险最小。

### 2. NMSE Oracle 旁路严格合规（CLAUDE.md §7）

`gen_uwa_channel` 返回的 `ch_info.h_time` 在 runner 里**只用于 NMSE 统计计算**，
不得回写到 TX→RX 的任何中间变量。Benchmark 读取点在：

```matlab
[rx_bb_frame, ch_info] = gen_uwa_channel(frame_bb, ch_params);
% ... 正常 RX 流程（不用 ch_info）...
h_true = ch_info.h_time;         % oracle 旁路，ONLY for NMSE metric
h_est  = <runner 内现有估计值>;
nmse_db = 10*log10(norm(h_est(:) - h_true_aligned(:))^2 / norm(h_true_aligned(:))^2);
bench_append_csv(..., nmse_db);  % 只写 CSV，不反馈 decoder
```

排查清单每阶段结束 grep：`meta.all_cp_data / meta.all_sym / meta.noise_var` 不得出现在
新增代码（runner benchmark 块、harness）里。

### 3. Turbo 迭代 BER 从现有 runner 提取

各 `test_*_timevarying.m` 里 turbo 循环已存在（eq_bem_turbo_fde / turbo_equalizer_ofdm 等），
但一般只保留最后一轮 BER。改造：在 turbo 循环体内部每轮追加 `ber_per_iter(titer) = sum(hard_decision ~= info_bits)/length(info_bits);`，
末尾写 CSV 长表。

### 4. 每阶段独立 MATLAB session

`clear functions; clear all` 重启避免缓存污染（CLAUDE.md MATLAB 调试规则）。

## 影响文件

### 新建（10 文件）

| 文件 | 作用 |
|------|------|
| `modules/13_SourceCode/src/Matlab/tests/benchmark_e2e_baseline.m` | 主入口（`stage` 参数 A1/A2/A3/B/C） |
| `tests/bench_common/bench_grids.m` | 返回五阶段的参数网格 struct |
| `tests/bench_common/bench_channel_profiles.m` | 返回 custom-6径 / exponential / 离散 / Rician 的 `ch_params` 模板 |
| `tests/bench_common/bench_run_point.m` | 调用指定体制 runner 单点执行，捕获指标 |
| `tests/bench_common/bench_nmse_tool.m` | h_true vs h_est 对齐 + NMSE 计算（处理 delay 对齐 / 长度差异） |
| `tests/bench_common/bench_append_csv.m` | 原子 CSV 追加写入（含 header 首次建立） |
| `tests/bench_common/bench_turbo_iter_log.m` | turbo 每轮 BER 的长表追加 |
| `tests/bench_common/bench_format_row.m` | 统一 CSV 行格式（时间戳+MATLAB版本+字段） |
| `plans/e2e-timevarying-baseline.md` | 本文件 |
| `wiki/comparisons/e2e-timevarying-baseline.md` | 报告（S3 产出） |

### 修改（6 + 1 文件）

| 文件 | 改动 |
|------|------|
| `tests/SC-FDE/test_scfde_timevarying.m` | 顶部加 `benchmark_mode` 开关；snr_list/fading_cfgs/信道 profile 外部可覆盖；turbo 循环逐轮记 BER；末尾 CSV 追加（如 `benchmark_mode`） |
| `tests/SC-FDE/test_scfde_discrete_doppler.m` | 同上（阶段 B） |
| `tests/OFDM/test_ofdm_timevarying.m` | 同 scfde |
| `tests/OFDM/test_ofdm_discrete_doppler.m` | 同上 |
| `tests/SC-TDE/test_sctde_timevarying.m` | 同 scfde |
| `tests/SC-TDE/test_sctde_discrete_doppler.m` | 同上 |
| `tests/OTFS/test_otfs_timevarying.m` | 同 scfde（OTFS turbo iters 较少） |
| `tests/DSSS/test_dsss_timevarying.m` | 同 scfde（无 turbo 循环；只记 coded BER） |
| `tests/DSSS/test_dsss_discrete_doppler.m` | 同上 |
| `tests/FH-MFSK/test_fhmfsk_timevarying.m` | 同 scfde（能量检测，无 turbo） |
| `tests/FH-MFSK/test_fhmfsk_discrete_doppler.m` | 同上 |

（共 11 文件，但机制一致，可批量加 `benchmark_mode` 块）

### 新增 wiki（S3）

| 文件 | 作用 |
|------|------|
| `wiki/comparisons/e2e-timevarying-baseline.md` | 主报告 |
| `wiki/comparisons/figures/bench_*.png` | 可视化 |
| `wiki/comparisons/raw-data/e2e_baseline_*.csv` | 6 个 CSV |

## Runner 注入协议（benchmark_mode API）

每个 `test_*_timevarying.m` 文件顶部插入统一块：

```matlab
%% ========== Benchmark mode 注入（2026-04-19 加） ==========
if ~exist('benchmark_mode','var'), benchmark_mode = false; end
if benchmark_mode
    % 外部必须注入：
    %   bench_snr_list        (1×Ns double)
    %   bench_fading_cfgs     (M×7 cell，格式同原 fading_cfgs)
    %   bench_channel_profile ('custom6' | 'exponential' | 'disc-5Hz' | 'hyb-K20' | ...)
    %   bench_doppler_rates   (1×Nd double)，对应 fading_cfgs 的 doppler_rate 列覆盖
    %   bench_seed            (scalar)
    %   bench_csv_path        (char)
    %   bench_csv_iter_path   (char)
    %   bench_scheme_name     (char)
    snr_list       = bench_snr_list;
    fading_cfgs    = bench_fading_cfgs;
    rng_seed_bench = bench_seed;
end
```

**原则**：`benchmark_mode=false` 时（直接 `run(test_...)`）行为与当前一致；`benchmark_mode=true`
时 snr_list / fading_cfgs 被覆盖，末尾写 CSV，可视化/figure 全部跳过（速度优先）。

在 runner 末尾主循环写入：

```matlab
if benchmark_mode
    for fi = 1:size(ber_matrix,1)
        for si = 1:length(snr_list)
            row = struct( ...
                'scheme', bench_scheme_name, ...
                'stage', bench_stage, ...
                'profile', bench_channel_profile, ...
                'fd_hz', fading_cfgs{fi,3}, ...
                'doppler_rate', fading_cfgs{fi,4}, ...
                'snr_db', snr_list(si), ...
                'seed', bench_seed, ...
                'ber_coded', ber_matrix(fi,si), ...
                'ber_uncoded', ber_uncoded_matrix(fi,si), ...
                'nmse_db', nmse_matrix(fi,si), ...
                'sync_tau_err', sync_tau_err_matrix(fi,si), ...
                'frame_detected', frame_detected_matrix(fi,si), ...
                'turbo_final_iter', turbo_iters_used_matrix(fi,si), ...
                'runtime_s', runtime_matrix(fi,si) );
            bench_append_csv(bench_csv_path, row);
            % 每轮 BER 长表
            for it = 1:size(ber_per_iter_matrix,3)
                bench_turbo_iter_log(bench_csv_iter_path, row, it, ber_per_iter_matrix(fi,si,it));
            end
        end
    end
end
```

## CSV Schema

### 主 CSV (`e2e_baseline_A1_jakes.csv` 等)

| 列名 | 类型 | 含义 |
|------|------|------|
| timestamp | ISO8601 | 写入时间 |
| matlab_ver | string | `version()` 前 10 字符 |
| stage | string | A1 / A2 / A3 / B / C |
| scheme | string | SC-FDE / OFDM / SC-TDE / OTFS / DSSS / FH-MFSK |
| profile | string | custom6 / exponential / disc-5Hz / hyb-K20 / ... |
| fd_hz | float | Jakes 最大多普勒 |
| doppler_rate | float | 固定多普勒 α |
| snr_db | float | |
| seed | int | |
| ber_coded | float | 译码后 BER |
| ber_uncoded | float | 硬判决 BER（NaN for FH-MFSK/DSSS 能量检测） |
| nmse_db | float | 信道估计 NMSE（dB） |
| sync_tau_err | int | 定时误差采样点（NaN if frame lost） |
| frame_detected | int | 0/1 |
| turbo_final_iter | int | 实际跑到第几轮（收敛判据可能提前） |
| runtime_s | float | 单点耗时 |

### Turbo 迭代长表 (`e2e_baseline_A_turbo_iter.csv`)

| 列 | 含义 |
|----|------|
| timestamp, stage, scheme, profile, fd_hz, doppler_rate, snr_db, seed | 关联主表 |
| iter | 1..N |
| ber_at_iter | 该轮 BER |

### 检测率聚合 (`e2e_baseline_C_detection.csv`)

| 列 | 含义 |
|----|------|
| scheme, profile, fd_hz, snr_db | 聚合 key |
| seed_count | 5 |
| detected_count | 0..5 |
| detection_rate | detected / seed_count |

## 实施步骤（S1 细分）

### S1.1 bench_common 工具（基础设施）

1. `bench_grids.m`：硬编码五阶段网格，返回 struct（`A1.snr_list / A1.fading_cfgs / ...`）
2. `bench_channel_profiles.m`：按 `profile_name` 返回 `base_ch_params`（delays/gains）
3. `bench_append_csv.m`：文件不存在时写 header，否则 append
4. `bench_nmse_tool.m`：处理 h_true (num_paths × N) vs h_est（各体制不同形式）的对齐
5. `bench_format_row.m`：struct → CSV 行字符串

### S1.2 runner 改造（11 文件，模式一致）

按体制分工：

1. **SC-FDE** 先改（参考实现）：test_scfde_timevarying + test_scfde_discrete_doppler
2. **OFDM** 镜像改
3. **SC-TDE / OTFS / DSSS / FH-MFSK** 批量套同款改动
4. 每改完一个立即 `benchmark_mode=false` 跑一次验证行为未变（防回归）

### S1.3 benchmark_e2e_baseline.m 主入口

```matlab
function benchmark_e2e_baseline(stage)
    grids = bench_grids();
    if ~ismember(stage, {'A1','A2','A3','B','C'})
        error('未知阶段: %s', stage);
    end
    grid = grids.(stage);
    for scheme = grid.schemes
        for profile = grid.profiles
            for combo = grid.combos
                % 设置 bench_* 全局变量
                benchmark_mode = true;
                bench_snr_list = grid.snr_list;
                bench_fading_cfgs = combo.fading_cfgs;
                % ...
                run(resolve_runner(scheme));
            end
        end
    end
end
```

## 验收标准

### 代码

- [ ] 11 个 test_*.m 在 `benchmark_mode=false` 时**行为与改造前一致**（直接 run 跑通，同一 seed 出同 BER）
- [ ] bench_common 工具纯函数、无副作用（CSV 写入除外）
- [ ] 无 Oracle 泄漏：`git diff` grep `meta.all_cp_data/meta.all_sym/meta.noise_var/fading_type` 应为 0 新增

### 数据

- [ ] 五阶段 CSV 齐全、行数匹配（A1=360 / A2=240 / A3=288 / B=120 / C=270）
- [ ] 主 CSV 每行字段无 NaN（frame_detected=0 除外）
- [ ] Turbo iter CSV 总行数 ≈ 主 CSV × 平均 turbo 迭代数

### 报告

- [ ] `wiki/comparisons/e2e-timevarying-baseline.md` 含 frontmatter + `[[wikilink]]` 回链
- [ ] 图 ≥ 10 张覆盖 A1/A2/A3/B/C
- [ ] `wiki/index.md` + `wiki/log.md` 已同步（Stop hook 通过）
- [ ] `wiki/comparisons/e2e-test-matrix.md` 顶部加新基线引用

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 改 runner 引入回归（benchmark_mode=false 时行为变） | 每改一个立即跑回归；关键 runner（SC-FDE）对比改造前 BER 数字完全一致 |
| 耗时超 3.25h | 各阶段独立 session，允许中断 / 分次 |
| NMSE 对齐歧义（SC-FDE freq-domain vs SC-TDE time-domain） | `bench_nmse_tool.m` 按体制分支处理，每体制 h_est 提取点在 runner 里明确标记 |
| CSV 并发写（未来扩展） | 本期单进程串行，无并发风险；CSV 写入锁留给 S5 扩展 |
| MATLAB 缓存污染 | 每阶段 session 开头 `clear functions; clear all` |
| Oracle 违规意外引入 | S1.2 改完每个 runner grep 审计；S4 归档前整体 grep |

## 时间预估

| 步骤 | 耗时 |
|------|------|
| S1.1 bench_common 工具 | 2h |
| S1.2 runner 改造（11 文件） | 3h |
| S1.3 benchmark 主入口 | 1h |
| S2 执行五阶段 | 3.25h |
| S3 可视化与报告 | 2h |
| S4 归档/commit | 0.5h |
| **合计** | **~12h**（跨 2-3 个 session） |

## Log

- 2026-04-19 依据 spec 起草 plan。待批准后进入 S1 实施。
