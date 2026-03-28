# 迭代调度器模块 (IterativeProc)

Turbo均衡迭代调度器，非独立信号处理模块，而是调度模块7'(SISO均衡)、模块3'/3(交织)和模块2'(SISO译码)之间的**外信息迭代循环**。

## 文件清单

| 文件 | 功能 | 体制 | 版本 |
|------|------|------|------|
| `turbo_equalizer_scfde.m` | SC-FDE Turbo均衡（MMSE-IC ⇌ BCJR外信息迭代） | SC-FDE | V6 |
| `turbo_equalizer_ofdm.m` | OFDM Turbo均衡（同SC-FDE架构） | OFDM | V6 |
| `turbo_equalizer_sctde.m` | SC-TDE Turbo均衡（RLS+软ISI消除 ⇌ 译码） | SC-TDE | V5(待P2重构) |
| `turbo_equalizer_otfs.m` | OTFS Turbo均衡（MP-BP ⇌ 译码） | OTFS | V2(待P2重构) |
| `plot_turbo_convergence.m` | 收敛可视化（BER/MSE曲线+星座图） | 通用 | — |
| `test_iterative.m` | 单元测试（SC-FDE+OFDM，含BER收敛验证+可视化） | 测试 | V6 |

## 核心原则

**外信息交换**：模块间只传递外信息 Le = Lpost - La，避免信息自我强化导致迭代发散。

## 模块依赖

| 被调用模块 | 被调用函数 | 用途 |
|-----------|-----------|------|
| 07_ChannelEstEq | `eq_mmse_ic_fde` | 迭代MMSE-IC频域均衡 |
| 07_ChannelEstEq | `soft_demapper` | 均衡输出→编码比特外信息LLR |
| 07_ChannelEstEq | `soft_mapper` | 后验LLR→软符号+残余方差 |
| 02_ChannelCoding | `siso_decode_conv` | BCJR(MAP)SISO译码，输出外信息+编码比特后验 |
| 02_ChannelCoding | `conv_encode` | 发射端卷积编码 |
| 03_Interleaving | `random_interleave` / `random_deinterleave` | 迭代环内交织/解交织 |

## SC-FDE / OFDM Turbo迭代流程（V6，主方案）

```
发射端: info_bits → conv_encode → random_interleave → QPSK映射 → x[n]

接收端迭代:
  初始化: x̄=0, σ²x=1, La_eq=0

  for iter = 1:K
      1. [x̃, μ, σ²ñ] = eq_mmse_ic_fde(Y, H, x̄, σ²x, σ²w)     MMSE-IC均衡
      2. Le_eq = soft_demapper(x̃, μ, σ²ñ, La_eq)                 外信息(减先验!)
      3. Le_eq_deint = random_deinterleave(Le_eq)                  解交织
      4. [~, Lpost_info, Lpost_coded] = siso_decode_conv(Le_eq_deint)  BCJR译码
      5. Lpost_coded_inter = random_interleave(Lpost_coded)        交织
      6. [x̄, σ²x] = soft_mapper(Lpost_coded_inter)               软符号+方差
      7. La_eq = clip(Lpost_coded_inter - Le_eq, ±8)              译码器外信息→均衡器先验
  end

  输出: bits = (Lpost_info > 0)
```

## SC-TDE Turbo迭代流程（V5，P2待重构）

```
  第1次: PTR → 线性RLS(+PLL) → LLR → 解交织 → SISO(BCJR)译码
  第2+: 译码后验→soft_mapper→软符号→交织→软ISI消除→RLS→LLR(减先验)→解交织→SISO译码
```

## OTFS Turbo迭代流程（V2，P2待重构）

```
  外层 iter=1:K_outer:
    内层 MP均衡(BP 10次，带译码器先验) → LLR → 解交织 → SISO译码
    译码后验 → 交织 → soft_mapper → 更新MP先验
```

## 函数接口

### turbo_equalizer_scfde / turbo_equalizer_ofdm

```matlab
[bits_out, iter_info] = turbo_equalizer_scfde(Y_freq, H_est, num_iter, noise_var, codec_params)
```

| 参数 | 方向 | 说明 |
|------|------|------|
| Y_freq | 输入 | 频域接收信号 (1×N) |
| H_est | 输入 | 频域信道估计 (1×N) |
| num_iter | 输入 | Turbo迭代次数（默认5） |
| noise_var | 输入 | 噪声方差 σ²w |
| codec_params | 输入 | 结构体：`.gen_polys`(默认[7,5])、`.constraint_len`(默认3)、`.interleave_seed`(默认7) |
| bits_out | 输出 | 硬判决信息比特 |
| iter_info | 输出 | 迭代详情：`.x_hat_per_iter`(每次均衡输出)、`.llr_per_iter`(每次外信息) |

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\12_IterativeProc\src\Matlab');
run('test_iterative.m');
```

### 测试用例说明

| 测试 | 断言 | 说明 |
|------|------|------|
| 1. SC-FDE | 最终符号BER ≤ 初始+2% | N=256, SNR=10dB, 3径信道, 6次迭代, 含交织 |
| 2. OFDM | 最终符号BER ≤ 初始+2% | N=256, SNR=10dB, 3径信道, 6次迭代, 含交织 |

测试输出包含：
- BER收敛曲线（Figure 1）
- 星座图对比：迭代1 vs 最终迭代（Figure 2）
