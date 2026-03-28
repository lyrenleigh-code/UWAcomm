# Turbo 均衡实现方案

> 基于 `turbo_equalizer_frameworks.md` 理论框架，映射到具体 MATLAB 函数实现。
> 本文档覆盖：数据流、函数接口、模块改动清单。

---

## 1 发射端约定

所有体制共享统一的发射链路（测试/仿真用）：

```
info_bits → conv_encode → coded_bits → random_interleave → interleaved_bits → QPSK映射 → x[n]
```

| 步骤 | 函数 | 模块 | 状态 |
|------|------|------|------|
| 卷积编码 | `conv_encode` | 02_ChannelCoding | 已有，无需改动 |
| 随机交织 | `random_interleave` | 03_Interleaving | 已有，无需改动 |
| QPSK 映射 | `bits2qpsk`（内联） | — | 测试脚本内联 |

**关键约定**：交织在编码比特级进行（coded bit 级），交织种子 `seed` 在发收端一致。

---

## 2 SC-FDE 频域 Turbo 均衡（主方案）

### 2.1 完整迭代数据流

```
初始化: x̄ = 0 (1×N), σ²_x = 1 (标量), La_eq = 0 (1×M_coded)

for iter = 1 : K
    ┌─────────── SISO 均衡器 ───────────┐
    │ 1. X̄ = FFT(x̄)                     │
    │ 2. W[k] = H*[k] / (|H[k]|² + σ²w/σ²x)         ... eq_mmse_ic_fde
    │ 3. Ỹ[k] = Y[k] - (1 - W[k]·H[k]) · X̄[k]      │
    │ 4. x̃ = IFFT(W · Ỹ)                              │
    │ 5. μ = (1/N) Σ W[k]·H[k]                        │
    │ 6. σ²ñ = μ·(1 - μ)·σ²x + μ·σ²w/(N·σ²x)        ... (等效噪声)
    │ 7. Le_eq = (2μ/σ²ñ) · x̃_bits - La_eq            ... soft_demapper
    └───────────────────────────────────┘
                     │ Le_eq (1×M_coded, 编码比特级外信息)
                     ↓
    ┌─────────── 解交织 ──────────────┐
    │ 8. Le_eq_deint = Le_eq(inv_perm)                  ... random_deinterleave
    └─────────────────────────────────┘
                     │ Le_eq_deint (1×M_coded)
                     ↓
    ┌─────────── SISO 译码器 ─────────┐
    │ 9. [Le_dec, Lpost_info] =                         ... siso_decode_conv
    │      siso_decode_conv(Le_eq_deint, La_dec_info)   │
    │    其中 La_dec_info 为信息比特先验（首次=0）      │
    │                                                    │
    │ 10. 后验编码比特LLR:                              ... 新增: coded_bit_posterior
    │     Lpost_coded = Le_eq_deint + La_dec_coded      │
    │     (通过重编码硬判决 + SISO后验幅度合成)         │
    └─────────────────────────────────┘
                     │ Le_dec (信息比特外信息)
                     │ Lpost_coded (编码比特后验)
                     ↓
    ┌─────────── 交织 + 软映射 ───────┐
    │ 11. La_eq = Lpost_coded(perm) - Le_eq             ... 外信息 = 后验 - 来自均衡器的
    │     (或简化: La_eq = Le_dec重编码后交织)           │
    │                                                    │
    │ 12. Lpost_interleaved = Lpost_coded(perm)          │
    │ 13. [x̄, σ²_x] = soft_mapper(Lpost_interleaved)   ... soft_mapper
    └─────────────────────────────────┘
end

输出: bits_out = (Lpost_info > 0)
```

### 2.2 各步骤函数映射

| 步骤 | 函数名 | 所属模块 | 现状 | 需要改动 |
|------|--------|---------|------|---------|
| 2-6 | `eq_mmse_ic_fde` | 07_ChannelEstEq | **不存在** | **新建** |
| 7 | `soft_demapper` | 07_ChannelEstEq | 不存在（`symbol_to_llr` 不含 μ 和先验减除） | **新建** |
| 8 | `random_deinterleave` | 03_Interleaving | 已有 | 无需改动 |
| 9-10 | `siso_decode_conv` | 02_ChannelCoding | 已有，但只输出信息比特级 | **改造**（增加编码比特后验输出） |
| 11 | 交织 + 外信息计算 | 内联 | — | 在调度器中实现 |
| 12 | `random_interleave` | 03_Interleaving | 已有 | 无需改动 |
| 13 | `soft_mapper` | 07_ChannelEstEq | 不存在（`llr_to_symbol` 不输出 σ²_x） | **新建** |
| 调度器 | `turbo_equalizer_scfde` | 12_IterativeProc | 已有（架构错误） | **重写** |

---

## 3 各模块改动详细说明

### 3.1 新建: `eq_mmse_ic_fde.m`（07_ChannelEstEq）

迭代 MMSE-IC 频域均衡器，对照框架文档 §3.2。

```matlab
function [x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var)
% 输入:
%   Y_freq    - 频域接收 (1×N)
%   H_est     - 频域信道 (1×N)
%   x_bar     - 软符号先验 (1×N, 首次迭代全0)
%   var_x     - 残余符号方差 (标量或1×N, 首次迭代=1)
%   noise_var - 噪声方差 σ²_w
% 输出:
%   x_tilde   - 时域均衡输出 (1×N)
%   mu        - 等效增益 (标量)
%   nv_tilde  - 等效噪声方差 (标量)

W = conj(H) ./ (abs(H).^2 + noise_var ./ var_x);   % 自适应MMSE权重
Y_ic = Y_freq - (1 - W .* H_est) .* fft(x_bar);    % 正确IC公式
x_tilde = ifft(W .* Y_ic);                           % 均衡输出

mu = mean(W .* H_est);                               % 等效增益
nv_tilde = real(mu) * (1 - real(mu));                 % 简化等效噪声
% 或精确: nv_tilde = mu - (1/N)*sum(|W.*H|²) 用于仿真验证
```

### 3.2 新建: `soft_demapper.m`（07_ChannelEstEq）

从均衡输出计算编码比特级**外信息LLR**，含等效增益校正和先验减除。

```matlab
function Le_eq = soft_demapper(x_tilde, mu, nv_tilde, La_eq, mod_type)
% 输入:
%   x_tilde   - 均衡后时域符号 (1×N)
%   mu        - 等效增益
%   nv_tilde  - 等效噪声方差
%   La_eq     - 编码比特先验LLR (1×2N for QPSK, 首次=0)
%   mod_type  - 'qpsk' / 'bpsk'
% 输出:
%   Le_eq     - 编码比特外信息LLR (1×2N for QPSK)
%
% QPSK公式: Le_eq(I) = 4·Re(μ)/σ²ñ · Re(x̃) - La(I)
%            Le_eq(Q) = 4·Re(μ)/σ²ñ · Im(x̃) - La(Q)
```

**关键：减去先验 La_eq，输出的是纯外信息。**

### 3.3 新建: `soft_mapper.m`（07_ChannelEstEq）

从后验LLR计算软符号 x̄ 和残余方差 σ²_x，用于下一次迭代的IC和MMSE权重。

```matlab
function [x_bar, var_x] = soft_mapper(L_posterior, mod_type)
% 输入:
%   L_posterior - 编码比特后验LLR (1×2N for QPSK)
%   mod_type    - 'qpsk' / 'bpsk'
% 输出:
%   x_bar  - 软符号估计 E[x|Lpost] (1×N 复数)
%   var_x  - 残余方差 E[|x|²] - |x̄|² (标量或1×N)
%
% QPSK: x̄ = (tanh(L_I/2) + j·tanh(L_Q/2)) / √2    ← 同 llr_to_symbol
%        σ²_x = 1 - mean(|x̄|²)                       ← 新增输出
```

注：`llr_to_symbol.m` 可保留不动（向后兼容），`soft_mapper` 是其扩展版。

### 3.4 改造: `siso_decode_conv.m`（02_ChannelCoding）

**现状**：输入编码比特LLR + 信息比特先验 → 输出信息比特外信息/后验。

**需要增加**：编码比特级后验LLR输出，供 `soft_mapper` 使用。

改造方案（保持向后兼容）：

```matlab
function [LLR_ext, LLR_post, LLR_post_coded] = siso_decode_conv(LLR_ch, LLR_prior, gen_polys, constraint_len)
% 新增第3输出:
%   LLR_post_coded - 编码比特后验LLR (1×M)
%                    利用 α/β/γ 对每个时刻的每个编码输出比特计算后验
```

实现方式：在现有 α/β 递推完成后，增加一个循环对每个时刻的 n 个编码输出比特分别求后验：

```matlab
LLR_post_coded = zeros(1, N_total * n);
for t = 1:N_total
    for i = 1:n  % n=2 for rate-1/2
        max_ci1 = -INF; max_ci0 = -INF;
        for s = 0:num_states-1
            for u = 0:1
                ns = next_state(s+1, u+1);
                ci = output_bits(s+1, u+1, i);  % 第i个编码输出比特
                metric = alpha(s+1,t) + gamma(s,u,t) + beta(ns+1,t+1);
                if ci == 1
                    max_ci1 = max(max_ci1, metric);
                else
                    max_ci0 = max(max_ci0, metric);
                end
            end
        end
        LLR_post_coded((t-1)*n + i) = max_ci1 - max_ci0;
    end
end
```

### 3.5 现有模块无需改动

| 函数 | 模块 | 说明 |
|------|------|------|
| `conv_encode` | 02_ChannelCoding | 编码器不变 |
| `viterbi_decode` | 02_ChannelCoding | 最终硬判决仍可用 Viterbi |
| `random_interleave` | 03_Interleaving | 接口不变 |
| `random_deinterleave` | 03_Interleaving | 接口不变 |
| `llr_to_symbol` | 07_ChannelEstEq | 保留向后兼容，soft_mapper 是扩展版 |
| `eq_mmse_fde` | 07_ChannelEstEq | 非迭代场景仍可用 |
| `eq_otfs_mp` | 07_ChannelEstEq | OTFS方案独立处理 |
| `eq_dfe` / `eq_linear_rls` | 07_ChannelEstEq | SC-TDE方案仍用RLS |

---

## 4 SC-TDE 时域 Turbo 均衡方案

### 4.1 架构选择

框架文档 §2 指出时域最优方案是 **BCJR/MAP 网格均衡器**（复杂度 $O(N \cdot M^{L-1})$）。但对于 $L \leq 5$ 的短信道，这是可行的。

对于水声信道（$L$ 可能较大），采用 **降低复杂度方案**：

| 方案 | 适用条件 | 说明 |
|------|---------|------|
| 精确BCJR均衡 | $L \leq 4$, QPSK | 状态数 $4^3 = 64$，可行 |
| RLS + 软ISI消除 | $L$ 任意 | 当前方案的改良版，需SISO译码 |
| MMSE-FDE (加CP) | $L$ 任意 | 转化为SC-FDE方案 |

**推荐**：对测试用的3径信道，先用 SC-FDE 频域方案验证 Turbo 收敛。SC-TDE 时域方案作为后续优化。

### 4.2 SC-TDE 改良方案（基于RLS）

若保留 RLS 均衡器，改良要点：

1. **译码器改用 SISO**：`siso_decode_conv` 替代 `viterbi_decode`
2. **反馈用后验LLR**：不再重编码硬比特，直接用 SISO 后验 → `soft_mapper` → $\bar{x}, \sigma^2_x$
3. **ISI消除用软符号**：$\bar{x}$ 自然包含可靠度分级
4. **LLR计算**：eq_dfe 的 LLR 减去先验（从译码器反馈的 La_eq）

---

## 5 OFDM Turbo 均衡方案

OFDM 各子载波独立（无ISI），Turbo增益来自：译码器纠正深衰落子载波错误 → 更新 $\sigma^2_x$ → MMSE权重自适应提升深衰落子载波增益。

**实现与 SC-FDE 完全相同**（共用 `eq_mmse_ic_fde` + `soft_demapper` + `soft_mapper`）。

---

## 6 OTFS Turbo 均衡方案

### 6.1 架构

对照框架文档 §4.3，OTFS 采用 DD 域因子图 MP 均衡器 + SISO 译码：

```
for iter = 1:K_outer
    [x_hat_dd, Le_mp] = eq_otfs_mp(Y_dd, path_info, x_bar_dd, var_x_dd, ...)  % MP内迭代
    Le_mp_vec → 解交织 → siso_decode_conv → Le_dec, Lpost
    Lpost → 交织 → soft_mapper → x_bar_dd, var_x_dd（用于下轮MP先验）
end
```

### 6.2 改动

| 函数 | 改动 |
|------|------|
| `eq_otfs_mp` | 需输出外信息LLR（当前只输出硬判决+简化LLR） |
| 调度器 `turbo_equalizer_otfs` | 重写，按上述流程 |

---

## 7 实施优先级

| 优先级 | 任务 | 涉及文件 | 理由 |
|--------|------|---------|------|
| **P0** | 新建 `eq_mmse_ic_fde.m` | 07_ChannelEstEq | 频域Turbo的核心均衡器 |
| **P0** | 新建 `soft_demapper.m` | 07_ChannelEstEq | 外信息LLR计算（含μ校正+先验减除）|
| **P0** | 新建 `soft_mapper.m` | 07_ChannelEstEq | 软符号+残余方差（MMSE权重需要）|
| **P0** | 改造 `siso_decode_conv.m` | 02_ChannelCoding | 增加编码比特后验输出 |
| **P1** | 重写 `turbo_equalizer_scfde.m` | 12_IterativeProc | 频域Turbo调度器 |
| **P1** | 重写 `turbo_equalizer_ofdm.m` | 12_IterativeProc | 同SC-FDE |
| **P1** | 重写 `test_iterative.m` | 12_IterativeProc | 发射端加交织+验证收敛 |
| **P2** | 改良 `turbo_equalizer_sctde.m` | 12_IterativeProc | 时域方案（RLS+SISO）|
| **P2** | 改造 `eq_otfs_mp.m` | 07_ChannelEstEq | OTFS外信息输出 |
| **P2** | 重写 `turbo_equalizer_otfs.m` | 12_IterativeProc | OTFS调度器 |

---

## 8 函数接口速查

### 均衡器侧

```
[x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var)
Le_eq = soft_demapper(x_tilde, mu, nv_tilde, La_eq, 'qpsk')
```

### 译码器侧

```
[Le_dec_info, Lpost_info, Lpost_coded] = siso_decode_conv(LLR_ch, La_info, gen_polys, K)
bits_final = double(Lpost_info > 0)
```

### 软映射

```
[x_bar, var_x] = soft_mapper(Lpost_coded_interleaved, 'qpsk')
```

### 交织/解交织

```
[interleaved, perm] = random_interleave(data, seed)
deinterleaved = random_deinterleave(data, perm)
```

### 调度器（SC-FDE 示例）

```
[bits_out, iter_info] = turbo_equalizer_scfde(Y_freq, H_est, num_iter, noise_var, codec_params)
% codec_params.gen_polys, .constraint_len, .interleave_seed
```
