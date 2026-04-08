# 信道编解码模块 (ChannelCoding)

为比特流添加冗余保护，覆盖分组码（Hamming）、卷积码（Viterbi）、迭代码（Turbo/LDPC）及Turbo均衡所需的SISO译码器。

## 对外接口列表

其他模块/端到端应调用的函数：

### conv_encode

**功能**：卷积编码器，支持任意码率1/n和约束长度

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | message | 1xN 数值数组 | 信息比特序列（0/1） | 无（必填） |
| 输入 | gen_polys | 1xn 数组 | 生成多项式（八进制表示） | [171, 133]（NASA标准码） |
| 输入 | constraint_len | 正整数 | 约束长度K | 7 |
| 输出 | coded | 1x(N+K-1)*n 数组 | 编码后比特序列（含K-1尾比特） | — |
| 输出 | trellis | 结构体 | 网格结构（.numStates, .n, .K, .nextState, .output） | — |

### viterbi_decode

**功能**：Viterbi译码器，支持硬判决和软判决

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | received | 1xM 数组 | 接收比特/软值序列 | 无（必填） |
| 输入 | trellis | 结构体 | 网格结构（由conv_encode生成） | 无（必填） |
| 输入 | decision_type | 字符串 | 'hard'(汉明距离) 或 'soft'(欧氏距离) | 'hard' |
| 输出 | decoded | 1xN 数组 | 译码后信息比特（去除尾比特） | — |
| 输出 | min_metric | 标量 | 最优路径累计度量值 | — |

### siso_decode_conv

**功能**：BCJR(MAP) SISO卷积码译码器，输出外信息供Turbo均衡

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | LLR_ch | 1xM 数组 | 信道LLR（编码比特），正值→bit 1 | 无（必填） |
| 输入 | LLR_prior | 1xN_info 数组 | 信息比特先验LLR（首次迭代全0） | zeros(1, N_info) |
| 输入 | gen_polys | 1xn 数组 | 生成多项式（八进制） | [7, 5] |
| 输入 | constraint_len | 正整数 | 约束长度K | 3 |
| 输入 | decode_mode | 字符串 | 'max-log'(快速) 或 'log-map'(精确Jacobian) | 'max-log' |
| 输出 | LLR_ext | 1xN_info 数组 | 外信息LLR = LLR_post - LLR_prior | — |
| 输出 | LLR_post | 1xN_info 数组 | 信息比特后验LLR | — |
| 输出 | LLR_post_coded | 1xM 数组 | 编码比特后验LLR（供soft_mapper用） | — |

### sova_decode_conv

**功能**：SOVA软输出Viterbi译码器，Turbo均衡对比用

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | LLR_ch | 1xM 数组 | 信道LLR（编码比特），正值→bit 1 | 无（必填） |
| 输入 | LLR_prior | 1xN_info 数组 | 信息比特先验LLR | zeros(1, N_info) |
| 输入 | gen_polys | 1xn 数组 | 生成多项式（八进制） | [7, 5] |
| 输入 | constraint_len | 正整数 | 约束长度K | 3 |
| 输出 | LLR_ext | 1xN_info 数组 | 信息比特外信息 | — |
| 输出 | LLR_post | 1xN_info 数组 | 信息比特后验LLR | — |
| 输出 | LLR_post_coded | 1xM 数组 | 编码比特后验LLR | — |

### hamming_encode

**功能**：Hamming(2^r-1, 2^r-1-r)分组码编码

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | message | 1xN 数组 | 信息比特序列（N须为k的整数倍，k=2^r-1-r） | 无（必填） |
| 输入 | r | 正整数 | 校验比特数（r>=2） | 3（即Hamming(7,4)） |
| 输出 | codeword | 1xM 数组 | 编码后比特序列（M = N/k * n） | — |
| 输出 | G | kxn 矩阵 | 生成矩阵（系统形式 [I_k \| P]） | — |
| 输出 | H | rxn 矩阵 | 校验矩阵（系统形式 [P' \| I_r]） | — |

### hamming_decode

**功能**：Hamming伴随式译码，纠正单比特错误

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | received | 1xM 数组 | 接收比特序列（M须为n的整数倍） | 无（必填） |
| 输入 | r | 正整数 | 校验比特数 | 3 |
| 输出 | decoded | 1xN 数组 | 译码后信息比特 | — |
| 输出 | num_corrected | 整数 | 纠正的错误比特总数 | — |

### turbo_encode

**功能**：Turbo编码器（双RSC并行级联，码率1/3）

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | message | 1xN 数组 | 信息比特序列（N>=2） | 无（必填） |
| 输入 | num_iter_hint | 正整数 | 建议译码迭代次数（记录到params） | 6 |
| 输入 | interleaver_seed | 正整数 | 交织器随机种子（编解码须一致） | 0 |
| 输出 | coded | 1x3N 数组 | 编码后序列 [系统位, 校验位1, 校验位2] | — |
| 输出 | params | 结构体 | 编码参数（.msg_len, .interleaver, .deinterleaver, .num_iter, .fb_poly, .ff_poly, .constraint_len） | — |

### turbo_decode

**功能**：Turbo迭代译码器（Max-Log-MAP）

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | received | 1x3N 实数数组 | 接收软值（顺序同编码） | 无（必填） |
| 输入 | params | 结构体 | 编码参数（由turbo_encode生成） | 无（必填） |
| 输入 | snr_db | 实数 | 信噪比(dB)，计算信道可靠度Lc | 无（必填） |
| 输入 | num_iter | 正整数 | 迭代次数 | params.num_iter |
| 输出 | decoded | 1xN 数组 | 硬判决译码结果 | — |
| 输出 | LLR_out | 1xN 数组 | 最终LLR | — |

### ldpc_encode

**功能**：LDPC编码器（Gallager正则构造）

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | message | 1xN 数组 | 信息比特序列（N须为k的整数倍） | 无（必填） |
| 输入 | n | 正整数 | 码字长度 | 64 |
| 输入 | rate | (0,1)实数 | 码率（k = round(n*rate)） | 0.5 |
| 输入 | H_seed | 正整数 | 校验矩阵随机种子（编解码须一致） | 0 |
| 输出 | codeword | 1xM 数组 | 编码后比特序列 | — |
| 输出 | H | (n-k)xn 矩阵 | 稀疏二进制校验矩阵 | — |
| 输出 | G | kxn 矩阵 | 二进制生成矩阵 | — |

### ldpc_decode

**功能**：LDPC码置信传播(BP)迭代译码（Min-Sum近似）

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | received | 1xM 实数数组 | 接收软值（M须为n的整数倍） | 无（必填） |
| 输入 | H | (n-k)xn 矩阵 | 校验矩阵（由ldpc_encode生成） | 无（必填） |
| 输入 | k | 正整数 | 信息位长度 | 无（必填） |
| 输入 | snr_db | 实数 | 信噪比(dB)，计算初始LLR | 无（必填） |
| 输入 | max_iter | 正整数 | 最大迭代次数 | 50 |
| 输出 | decoded | 1xN 数组 | 译码后信息比特 | — |
| 输出 | LLR_out | 1xM 数组 | 最终全码字LLR | — |
| 输出 | num_iter_done | 1xnum_blocks 数组 | 各码块实际迭代次数 | — |

## 内部函数接口列表

以下为辅助函数，不建议外部直接调用：

### build_huffman_matrices（hamming_encode.m内部）

**功能**：构造系统形式的Hamming码生成矩阵G和校验矩阵H

### rsc_encode_local（turbo_encode.m内部）

**功能**：RSC递归系统卷积编码，输出校验比特流

### bcjr_decode_local（turbo_decode.m内部）

**功能**：Max-Log-MAP分量译码器，前向alpha + 后向beta + 后验LLR

### build_rsc_trellis（turbo_decode.m内部）

**功能**：构建RSC编码器的状态转移表和输出表

### build_ldpc_H（ldpc_encode.m内部）

**功能**：基于Gallager方法构造正则LDPC码校验矩阵（列重wc=3）

### build_generator_from_H（ldpc_encode.m内部）

**功能**：GF(2)高斯消元将H化为系统形式，求生成矩阵G

### bp_decode_block（ldpc_decode.m内部）

**功能**：单码块Min-Sum BP译码

### jac_log（siso_decode_conv.m内部）

**功能**：Jacobian对数函数 max*(a,b) = max(a,b) + log(1+exp(-|a-b|))

### plot_ber_curve.m

**功能**：BER vs SNR曲线绘制工具

| 参数方向 | 参数名 | 类型 | 含义 | 默认值 |
|---------|--------|------|------|--------|
| 输入 | snr_db | 1xK 数组 | SNR(dB)坐标 | 无（必填） |
| 输入 | ber_data | MxK 矩阵 | BER数据，每行一条曲线 | 无（必填） |
| 输入 | legend_labels | 1xM cell数组 | 图例标签 | 自动生成 |
| 输入 | title_str | 字符串 | 图标题 | 'BER Performance' |

### test_channel_coding.m

**功能**：信道编解码模块单元测试（22项）

## 核心算法技术描述

### Hamming码

**算法原理**：线性分组码，码长 n=2^r-1，信息位 k=n-r，码率 R=k/n。通过校验矩阵H的伴随式(syndrome)定位单比特错误。

**关键公式**：

编码：

```
c = m * G (mod 2),  G = [I_k | P],  H = [P' | I_r]
```

伴随式译码：

```
s = H * r^T (mod 2)
```

s=0表示无错误；s非零时，s对应H中某列的位置即为错误位。

**参数选择依据**：
- r=3: Hamming(7,4)，码率0.571，纠1位错
- r=4: Hamming(15,11)，码率0.733，纠1位错

**适用条件与局限性**：仅能纠正1位错误，检测2位错误。适合低误码率信道，不适合突发错误信道。

### 卷积码 + Viterbi译码

**算法原理**：卷积编码器通过K级移位寄存器对输入比特进行卷积运算，产生码率1/n的编码输出。Viterbi译码器在网格图上搜索最大似然路径。

**关键公式**：

编码器输出（第i个生成多项式）：

```
c_i(t) = sum_{j=0}^{K-1} g_i(j) * u(t-j)  (mod 2)
```

Viterbi前向递推（加-比-选ACS）：

```
M(s, t) = min_{s'->s} [M(s', t-1) + BM(s'->s, t)]
```

其中BM为分支度量：硬判决用汉明距离，软判决用欧氏距离。

```
BM_hard = sum(c_expected XOR c_received)
BM_soft = sum((c_received - c_expected_bpsk)^2)
```

尾比特截断：编码器末尾追加K-1个零比特使状态归零，确保回溯从状态0开始。

**参数选择依据**：
- 默认[171,133], K=7：NASA深空通信标准码，自由距离d_free=10
- [7,5], K=3：低复杂度码，d_free=5，适合Turbo均衡内环

**适用条件与局限性**：
- 软判决比硬判决约有2dB编码增益
- 复杂度O(N * 2^(K-1))，K>10时不实用

### BCJR (MAP) SISO译码器

**算法原理**：前向-后向算法(BCJR)，在网格图上同时进行前向alpha递推和后向beta递推，精确计算每个信息比特的后验LLR。Max-Log-MAP用max近似log-sum-exp；Log-MAP用Jacobian对数校正。

**关键公式**：

分支度量（对数域）：

```
gamma(t, s->s') = (2u-1)*La/2 + sum_i (2c_i-1)*Lc_i/2
```

前向递推：

```
alpha(s, t+1) = max*_{s': s'->s} [alpha(s', t) + gamma(t, s'->s)]
```

后向递推：

```
beta(s, t) = max*_{s': s->s'} [beta(s', t+1) + gamma(t, s->s')]
```

后验LLR：

```
L_post(t) = max*_{(s,s'):u=1} [alpha(s,t) + gamma + beta(s',t+1)]
          - max*_{(s,s'):u=0} [alpha(s,t) + gamma + beta(s',t+1)]
```

外信息：

```
L_ext = L_post - L_prior
```

Jacobian对数（Log-MAP）：

```
max*(a, b) = max(a, b) + log(1 + exp(-|a - b|))
```

**适用条件与局限性**：
- Max-Log-MAP比真Log-MAP损失约0.2~0.5dB，但计算量减半
- SOVA精度低于BCJR，但单向递推常数更小
- 复杂度O(N * S * n)，S=状态数

### Turbo码

**算法原理**：两个RSC编码器并行级联，通过随机交织器连接。译码时两个BCJR分量译码器交替迭代，交换外信息。

**关键公式**：

RSC编码器（反馈/前馈结构）：

```
fb_bit(t) = u(t) XOR sum(state * fb_poly[2:end])  (mod 2)
parity(t) = sum([fb_bit, state] * ff_poly)  (mod 2)
```

默认分量码：K=4, 反馈多项式=15(八进制,=1+D+D^2+D^3), 前馈=13(八进制,=1+D^2+D^3)

信道可靠度：

```
Lc = 4 * R * Eb/N0,  R = 1/3
```

迭代译码：

```
La_dec1 = Le_dec2 经解交织
La_dec2 = Le_dec1 经交织
```

**参数选择依据**：
- 迭代次数：6~8次通常收敛，更多次增益边际递减
- 交织器seed：同一seed保证编解码一致性

**适用条件与局限性**：
- 码率1/3（不含删余），适合低SNR场景
- 迭代增益在低SNR时最显著
- 无尾比特截断（简化实现），实际系统需补充

### LDPC码

**算法原理**：基于稀疏校验矩阵H的线性分组码。Gallager正则构造保证每列恒定重量wc=3。译码采用置信传播(BP)算法在Tanner图上传递消息，使用Min-Sum近似降低计算复杂度。

**关键公式**：

校验节点更新（Min-Sum）：

```
mc->v = alpha * prod(sign(mv'->c)) * min(|mv'->c|),  v' != v
```

其中alpha=0.75为缩放因子。

变量节点更新：

```
L(v) = L_ch(v) + sum_{c in N(v)} mc->v
mv->c = L(v) - mc->v
```

初始LLR（BPSK）：

```
L_ch = 2 * y / sigma^2
```

提前终止：当 H * c_hat = 0 (mod 2) 时停止迭代。

**参数选择依据**：
- 码长n：越长性能越接近Shannon限，但延迟和复杂度增大
- 码率：0.5为常用折衷
- max_iter=50：大多数码块在10~20次内收敛

**适用条件与局限性**：
- 长码长（n>=256）时性能优异
- 短码长（n<64）时性能不及Turbo码
- Gallager正则构造简单但非最优，工程中常用QC-LDPC

## 使用示例

```matlab
%% 卷积编码 + Viterbi译码
msg = randi([0 1], 1, 100);
[coded, trellis] = conv_encode(msg);
[decoded, ~] = viterbi_decode(coded, trellis, 'hard');

%% Turbo均衡中的SISO译码调用
[Le_dec, Lpost_info, Lpost_coded] = siso_decode_conv(Le_eq_deint, La_info, [7,5], 3);
bits_out = double(Lpost_info > 0);

%% Turbo编解码
msg = randi([0 1], 1, 500);
[coded, params] = turbo_encode(msg, 8, 42);
bpsk = 2*coded - 1;
rx = bpsk + 0.5*randn(size(bpsk));
[decoded, LLR] = turbo_decode(rx, params, 3, 8);

%% LDPC编解码
msg = randi([0 1], 1, 32);
[cw, H, G] = ldpc_encode(msg, 64, 0.5, 0);
rx = 2*cw - 1 + 0.3*randn(1, 64);
[decoded, ~, ~] = ldpc_decode(rx, H, 32, 10, 50);
```

## 依赖关系

- 依赖模块03（交织）的 `random_interleave` / `random_deinterleave`（turbo_encode/turbo_decode内部调用）
- 上游：模块01（信源编码）输出的比特流
- 下游：模块03（交织）接收编码后比特流

## 测试覆盖 (test_channel_coding.m V1.0.0, 22项)

| 编号 | 测试名称 | 断言条件 | 说明 |
|------|---------|---------|------|
| 1.1 | Hamming(7,4)无差错 | isequal(decoded, msg), num_corr==0, len(codeword)==14 | 无错编解码一致，码字长度正确 |
| 1.2 | Hamming(7,4)单比特纠错 | 7个错误位置全部纠正：decoded==msg, num_corr==1 | 逐位翻转均可纠正 |
| 1.3 | Hamming(15,11)编解码 | isequal(decoded, msg), len(codeword)==60 | 44bit信息，4块编码正确 |
| 1.4 | G和H正交性 | H*G' mod 2 == 0 | 校验矩阵与生成矩阵正交 |
| 2.1 | (2,1,3)码无噪声 | isequal(decoded, msg), metric==0 | 无噪声路径度量为0 |
| 2.2 | (2,1,7)标准码无噪声 | isequal(decoded, msg) | 100bit默认参数编解码一致 |
| 2.3 | 硬判决纠错 | BER < 0.05 | 信道5%误码率，译码后BER<5% |
| 2.4 | 软/硬判决对比 | 记录两者BER（软判决通常更优） | SNR=3dB下对比 |
| 2.5 | 网格结构验证 | numStates==4, n==2, K==3 | (2,1,3)码网格参数正确 |
| 3.1 | Turbo无噪声回环 | isequal(decoded, msg) | 100bit无噪声解码一致 |
| 3.2 | Turbo迭代增益 | diff(ber_list)<=0.01（BER随迭代不增） | 1/2/4/8次迭代BER单调不增 |
| 3.3 | Turbo编码结构 | len(coded)==3*64, coded(1:64)==msg, params.msg_len==64 | 码率1/3，系统位保持 |
| 3.4 | 交织器一致性 | 同seed同结果, 不同seed不同结果, 交织+解交织=恒等 | seed确定性和逆映射正确 |
| 4.1 | LDPC无噪声回环 | syndrome==0, isequal(decoded, msg) | 码字满足校验方程，解码一致 |
| 4.2 | LDPC H*G'=0 | H*G' mod 2 == 0 | 生成矩阵与校验矩阵正交 |
| 4.3 | LDPC AWGN译码 | 记录BER和迭代次数 | SNR=4dB下2块译码 |
| 4.4 | 多码长码率 | 所有配置 syndrome==0 | (32,16)/(64,48)/(128,64)校验通过 |
| 4.5 | LDPC seed一致性 | 同seed同H, 不同seed不同H | seed确定性验证 |
| 5.1 | 空输入拒绝 | 5个编码函数对[]均报错 | hamming/conv/turbo/ldpc全覆盖 |
| 5.2 | 非二进制输入拒绝 | 4个编码函数对非0/1输入报错 | 输入校验正确 |
| 5.3 | Hamming块长度校验 | 非k整数倍长度报错 | 3bit输入到(7,4)码被拒绝 |

## 可视化说明

test_channel_coding.m V1.0.0 无独立figure输出（纯数值验证测试）。plot_ber_curve.m 可在外部调用，生成BER vs SNR对比曲线图（含BPSK理论曲线）。
