# 迭代调度器模块 (IterativeProc)

Turbo均衡迭代调度器，非独立信号处理模块，而是调度模块7(均衡)和模块2(译码)之间的迭代循环。支持SC-TDE/SC-FDE/OTFS三种体制的Turbo均衡。

## 文件清单

| 文件 | 功能 | 体制 |
|------|------|------|
| `turbo_equalizer_sctde.m` | SC-TDE Turbo均衡（PTR→线性RLS/DFE⇌译码） | SC-TDE |
| `turbo_equalizer_scfde.m` | SC-FDE Turbo均衡（MMSE-FDE⇌译码） | SC-FDE |
| `turbo_equalizer_otfs.m` | OTFS Turbo均衡（MP-BP⇌译码） | OTFS |
| `test_iterative.m` | 单元测试（4项） | 测试 |

## 模块功能与接口概述

本模块不在框架图中作为独立处理模块，而是实现 **7'(均衡) ⇌ 10-2(残余补偿) ⇌ 2'(信道解码)** 之间的迭代回环调度。

每个调度器内部调用已有模块的函数：
- 模块07：`eq_dfe`、`eq_linear_rls`、`eq_mmse_fde`、`eq_otfs_mp`、`llr_to_symbol`、`symbol_to_llr`、`interference_cancel`、`eq_ptrm`
- 模块02：`conv_encode`、`viterbi_decode`
- 模块03：`random_interleave`、`random_deinterleave`

## 三种体制的Turbo迭代流程

### SC-TDE

```
第1次: PTR(可选) → 线性RLS(+PLL) → LLR → 解交织 → Viterbi译码
第2次: 译码比特→重编码→LLR→软符号(tanh)→交织→干扰消除→DFE(RLS+PLL)→LLR→解交织→译码
第3次: 同第2次...
```

### SC-FDE

```
第1次: MMSE-FDE → IFFT → LLR → 解交织 → Viterbi译码
第2次: 译码→软符号→FFT→频域软干扰消除→MMSE-FDE→IFFT→LLR→解交织→译码
```

### OTFS

```
第1次: MP均衡(BP 10次) → DD域符号→LLR → 解交织 → Viterbi译码
第2次: 译码→软符号→更新MP先验→MP均衡→LLR→译码
```

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\12_IterativeProc\src\Matlab');
run('test_iterative.m');
```

### 测试用例说明

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 SC-TDE 1次 | 输出非空，迭代数=1 | 基线（无Turbo增益） |
| 1.2 SC-TDE 3次 | 迭代数=3，LLR记录=3 | 多次迭代调度正确 |
| 2.1 SC-FDE 2次 | 输出非空，迭代数=2 | 频域均衡+译码迭代 |
| 3.1 OTFS 2次 | 输出非空 | MP均衡+译码迭代 |
