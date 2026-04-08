# 迭代调度器模块 (IterativeProc)

Turbo均衡迭代调度器，调度模块07(SISO均衡)、模块03(交织)和模块02(SISO译码)之间的外信息迭代循环，覆盖SC-FDE/OFDM/SC-TDE/OTFS四种体制，共7个文件。

## 对外接口

其他模块/端到端应调用的函数：

### `turbo_equalizer_scfde`

SC-FDE Turbo均衡（LMMSE-IC + BCJR外信息迭代）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `Y_freq` | 1xN complex | 频域接收信号 | (必需) |
| `H_est` | 1xN complex | 频域信道估计 | (必需) |
| `num_iter` | integer | Turbo迭代次数 | 5 |
| `snr_or_nv` | scalar | 信噪比(dB)或噪声方差: >0且<=100视为SNR(dB)自动转换, 否则视为噪声方差 | 10 |
| `codec_params` | struct | 编解码参数 | 见下方 |

codec_params字段：

| 字段 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `.gen_polys` | 1x2 | 生成多项式 | [7, 5] |
| `.constraint_len` | integer | 约束长度 | 3 |
| `.interleave_seed` | integer | 交织种子 | 7 |
| `.decode_mode` | string | `'max-log'`/`'log-map'`/`'sova'` | `'max-log'` |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `bits_out` | 1xN_info | 最终硬判决信息比特 |
| `iter_info` | struct | `.x_hat_per_iter`(cell,每次均衡输出符号), `.llr_per_iter`(cell,每次LLR), `.num_iter` |

---

### `turbo_equalizer_ofdm`

OFDM Turbo均衡（与SC-FDE共用频域MMSE-IC架构）。

**输入参数：** 同 `turbo_equalizer_scfde`。

**输出参数：** 同 `turbo_equalizer_scfde`。

---

### `turbo_equalizer_sctde`

SC-TDE Turbo均衡（V8: DFE首次迭代 + 软ISI消除后续迭代 + BCJR）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `rx` | 1xN 或 MxN | 接收信号（支持多通道） | (必需) |
| `h_est` | 1xL 或 MxL | 时域信道估计 | (必需) |
| `training` | 1xT complex | 训练序列已知符号 | (必需) |
| `num_iter` | integer | Turbo迭代次数 | 5 |
| `snr_or_nv` | scalar | 信噪比(dB)或噪声方差 | 10 |
| `eq_params` | struct | 均衡器参数 | 见下方 |
| `codec_params` | struct | 编解码参数（同scfde） | 同上 |

eq_params字段：

| 字段 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `.num_ff` | integer | 前馈滤波器阶数 | 21 |
| `.num_fb` | integer | 反馈滤波器阶数 | 10 |
| `.lambda` | scalar | RLS遗忘因子 | 0.998 |
| `.pll` | struct | PLL参数: `.enable`(true), `.Kp`(0.01), `.Ki`(0.005) | enable=true |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `bits_out` | 1xN_info | 最终硬判决信息比特 |
| `iter_info` | struct | `.x_hat_per_iter`(cell,含训练+数据), `.llr_per_iter`(cell,数据段LLR), `.num_iter` |

---

### `turbo_equalizer_scfde_crossblock`

SC-FDE/OFDM跨块Turbo均衡（多块LMMSE-IC + 跨块BCJR + DD信道更新）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `Y_freq_blocks` | cell(1xN_blocks) | 每块的频域接收信号(1xN_fft) | (必需) |
| `H_est_blocks` | cell(1xN_blocks) | 每块的频域信道估计(1xN_fft) | (必需) |
| `num_iter` | integer | Turbo迭代次数 | 6 |
| `noise_var` | scalar | 噪声方差 sigma^2_w | 0.01 |
| `codec_params` | struct | 编解码参数（含`.decode_mode`） | 同上 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `bits_out` | 1xN_info | 最终硬判决信息比特 |
| `iter_info` | struct | `.ber_per_iter`(每次BER), `.num_iter` |

---

### `turbo_equalizer_otfs`

OTFS Turbo均衡（DD域MP-BP均衡 + BCJR译码）。

**输入参数：**

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `Y_dd` | NxM complex | 接收DD域帧 | (必需) |
| `h_dd` | NxM complex | DD域信道响应（稀疏） | (必需) |
| `path_info` | struct | `.num_paths`, `.delay_idx`(1xP), `.doppler_idx`(1xP), `.gain`(1xP complex) | (必需) |
| `N` | integer | DD域多普勒格点数 | (必需) |
| `M` | integer | DD域时延格点数 | (必需) |
| `num_iter` | integer | 外层Turbo迭代次数 | 3 |
| `snr_or_nv` | scalar | 信噪比(dB)或噪声方差 | 10 |
| `codec_params` | struct | 编解码参数 | 同上 |

**输出参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `bits_out` | 1xN_info | 最终硬判决信息比特 |
| `iter_info` | struct | `.x_hat_per_iter`(cell,每次MP输出1D向量), `.llr_per_iter`(cell), `.num_iter` |

## 内部函数

辅助/测试函数（不建议外部直接调用）：

### `plot_turbo_convergence` (internal)

Turbo均衡迭代收敛可视化（BER/MSE曲线+星座图对比）。

| 参数 | 类型 | 含义 | 默认值 |
|------|------|------|--------|
| `iter_results` | struct | `.ber_per_iter`(1xK), `.mse_per_iter`(1xK), `.constellation`(cell 1xK), `.ref_symbols`, `.scheme` | (必需) |
| `title_str` | string | 图标题 | `'Turbo Equalization Convergence'` |

### `test_iterative` (internal)

单元测试脚本（V7.0, 4项: SC-FDE/OFDM/SC-TDE/OTFS）。

## 核心算法技术描述

### 1. 频域LMMSE-IC Turbo均衡（SC-FDE/OFDM）

**原理：** SISO均衡器与SISO(BCJR)译码器之间交换外信息（LLR），迭代收敛。

均衡器（MMSE-IC）：

$$G_k = \frac{\sigma_x^2 \cdot H_k^*}{\sigma_x^2 \cdot |H_k|^2 + \sigma_w^2}$$

$$\tilde{x} = \bar{x} + \text{IFFT}\bigl(G \cdot (Y - H \cdot \bar{X})\bigr)$$

其中 `x̄` 为上次迭代译码反馈的软符号先验（soft_mapper输出），首次迭代 `x̄=0`。

迭代环路：
1. LMMSE-IC均衡 → 软解映射(soft_demapper) → 外信息LLR
2. 解交织(random_deinterleave)
3. SISO(BCJR)译码(siso_decode_conv) → 后验LLR → 外信息 = 后验 - 先验
4. 交织(random_interleave) → 软映射(soft_mapper) → 软符号先验x̄
5. 回到步骤1

**参数选择：**
- 迭代次数：通常5-6次即可收敛
- 噪声方差：影响MMSE均衡滤波器权重的软硬度

**适用条件：** 适合频域均衡的体制（SC-FDE/OFDM），需要频域信道估计H。

**局限性：** 首次迭代无先验信息，等效为常规MMSE均衡；信道估计误差不可逆地传播。

### 2. SC-TDE时域Turbo均衡

**原理（V8改进）：**
- **iter1:** eq_dfe（前馈+反馈RLS自适应滤波）替代纯LE，DFE反馈抽头覆盖长时延ISI
  - h_est用于DFE权重初始化（MMSE匹配滤波）
- **iter2+:** 软ISI消除 + 单抽头ZF（用h_est）
  - ISI消除：`r_clean(n) = rx(n) - Σ_{l≠0} h(l)·x̄(n-l)`
  - ZF均衡：`x̃(n) = r_clean(n) / h(0)`
- SISO(BCJR)译码 + soft_mapper反馈（同频域架构）
- PLL用于跟踪残余相位偏移

**LLR符号修正：** QPSK映射约定 bit=1 -> Re<0，LLR取负后送译码器。

**适用条件：** 时域均衡场景，需要时域信道估计h和训练序列。

**局限性：** DFE的num_fb应>=max_delay；训练序列开销。

### 3. 跨块Turbo均衡（crossblock）

**原理：** 编码一次后分块均衡，各块LLR拼接后做一次跨块BCJR译码，编码增益更充分。

$$Y_1, \ldots, Y_K \xrightarrow{\text{LMMSE-IC}} \text{LLR}_1, \ldots, \text{LLR}_K$$

$$[\text{LLR}_1, \ldots, \text{LLR}_K] \xrightarrow{\text{BCJR}} \text{后验LLR} \rightarrow \text{反馈各块}$$

$$\text{DD信道更新: iter} \geq 2 \text{ 时用软符号重估各块 } \hat{H}_{\text{est}}$$

**适用条件：** 多块传输、一次编码的场景（SC-FDE/OFDM端到端测试）。

### 4. OTFS DD域Turbo均衡

**原理（V3）：** 双层迭代：外层Turbo(SISO) x 内层MP(BP)。

- **内层MP-BP：** 在DD域因子图上做消息传递（10次BP迭代），利用DD域信道稀疏性
- **外层Turbo：** MP均衡输出 → soft_demapper → 解交织 → BCJR → 交织 → soft_mapper → MP先验

DD域信道模型：

$$Y[k,l] = \sum_p h_p \cdot X\bigl[(k - k_p) \bmod N,\; (l - l_p) \bmod M\bigr] + W[k,l]$$

其中 (k_p, l_p) 为第p径的多普勒索引和时延索引。

**适用条件：** OTFS体制，DD域信道具有稀疏表示。

**局限性：** MP收敛依赖于因子图的环结构；需要路径信息(path_info)。

## 使用示例

```matlab
% SC-FDE Turbo均衡（频域，6次迭代）
codec = struct('gen_polys', [7,5], 'constraint_len', 3, 'interleave_seed', 7);
[bits, info] = turbo_equalizer_scfde(Y_freq, H_est, 6, 10, codec);

% SC-TDE Turbo均衡（时域，V8 DFE首次迭代）
eq_p = struct('num_ff', 21, 'num_fb', 10, 'lambda', 0.998);
[bits, info] = turbo_equalizer_sctde(rx, h_est, training, 5, 10, eq_p, codec);

% 跨块Turbo均衡（多块编码跨块BCJR）
[bits, info] = turbo_equalizer_scfde_crossblock(Y_blocks, H_blocks, 6, nv, codec);

% OTFS Turbo均衡（DD域MP-BP + BCJR）
[bits, info] = turbo_equalizer_otfs(Y_dd, h_dd, path_info, N, M, 4, nv, codec);
```

## 依赖关系

- 依赖模块07 (ChannelEstEq) 的 `eq_mmse_ic_fde`、`soft_demapper`、`soft_mapper`（LMMSE-IC均衡核心）
- 依赖模块07 (ChannelEstEq) 的 `eq_dfe`、`eq_linear_rls`（SC-TDE时域均衡）
- 依赖模块02 (ChannelCoding) 的 `siso_decode_conv`、`conv_encode`（BCJR译码+编码）
- 依赖模块03 (Interleaving) 的 `random_interleave`、`random_deinterleave`（迭代环内交织/解交织）

## 测试覆盖 (test_iterative.m V7.0, 4项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|---------|---------|------|
| 1 | SC-FDE Turbo均衡 | `ber_sym(end) <= ber_sym(1) + 0.02` | N=256, SNR=3dB, 6次迭代, BER不发散（末次<=首次+2%） |
| 2 | OFDM Turbo均衡 | `ber_sym_o(end) <= ber_sym_o(1) + 0.02` | N=256, SNR=3dB, 6次迭代, BER不发散 |
| 3 | SC-TDE Turbo均衡 | `ber_sym_t(end) <= ber_sym_t(1) + 0.02` | SNR=8dB, 3径, 200训练+1000数据, 6次迭代, BER不发散 |
| 4 | OTFS Turbo均衡 | `ber_sym_ot(end) <= ber_sym_ot(1) + 0.02` | N=8,M=32, SNR=3dB, 2径, 4次迭代, BER不发散 |

## 可视化说明

测试生成2个figure：

- **Figure 1 — Turbo均衡BER收敛曲线：** 4种体制的符号BER随Turbo迭代次数的变化曲线，验证收敛趋势
- **Figure 2 — 星座图对比：** 4种体制x2列（迭代1 vs 最终迭代），展示均衡前后星座收敛质量，QPSK参考点用红色+标注
