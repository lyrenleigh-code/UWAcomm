# 信道编解码模块 (ChannelCoding)

水声通信系统信道编解码算法库，覆盖分组码、卷积码和迭代码三类编码方案。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `hamming_encode.m` | Hamming分组码编码 | 分组码 |
| `hamming_decode.m` | Hamming伴随式译码（纠1位错） | 分组码 |
| `conv_encode.m` | 卷积编码器 | 卷积码 |
| `viterbi_decode.m` | Viterbi译码器（硬/软判决） | 卷积码 |
| `turbo_encode.m` | Turbo编码器（双RSC并行级联） | 迭代码 |
| `turbo_decode.m` | Turbo译码器（Max-Log-MAP迭代） | 迭代码 |
| `ldpc_encode.m` | LDPC编码器（Gallager正则构造） | 迭代码 |
| `ldpc_decode.m` | LDPC译码器（Min-Sum BP迭代） | 迭代码 |
| `test_channel_coding.m` | 单元测试（22项） | 测试 |

## 各编码方案说明

### 1. Hamming码（分组码）

- 码型：Hamming(2^r-1, 2^r-1-r)，r可配置
- 默认 r=3 即 Hamming(7,4)，码率 R=0.571
- 编码：系统形式 G=[I_k | P]，分块编码
- 译码：伴随式(syndrome)查表，纠正单比特错误

```matlab
msg = [1 0 1 1 0 0 1 0];
[codeword, G, H] = hamming_encode(msg, 3);      % r=3, Hamming(7,4)
[decoded, num_corr] = hamming_decode(codeword, 3);
```

### 2. 卷积码 + Viterbi译码

- 码率：1/n，n由生成多项式个数决定
- 默认 [171, 133]（八进制），K=7，码率1/2（NASA标准码）
- 编码器追加 K-1 个尾比特使状态归零
- Viterbi支持硬判决（汉明距离）和软判决（欧氏距离）

```matlab
msg = randi([0 1], 1, 100);
[coded, trellis] = conv_encode(msg);                     % 默认(2,1,7)
[decoded, ~] = viterbi_decode(coded, trellis, 'hard');    % 硬判决

% 软判决（BPSK+AWGN场景，性能更优）
bpsk = 2*coded - 1;
rx = bpsk + 0.5*randn(size(bpsk));
[decoded, ~] = viterbi_decode(rx, trellis, 'soft');
```

### 3. Turbo码

- 分量码：RSC编码器，K=4，反馈多项式15(八进制)，前馈多项式13(八进制)
- 码率：1/3（系统位 + 校验位1 + 校验位2）
- 交织器：伪随机交织，由seed控制（编解码须一致）
- 译码：Max-Log-MAP (BCJR) 迭代，默认6次迭代

```matlab
msg = randi([0 1], 1, 500);
[coded, params] = turbo_encode(msg, 6, 42);    % 6次迭代建议，seed=42

% BPSK + AWGN
bpsk = 2*coded - 1;
snr_db = 2.0;
noise_std = 1 / sqrt(2 * 10^(snr_db/10) * (1/3));
rx = bpsk + noise_std * randn(size(bpsk));

[decoded, LLR] = turbo_decode(rx, params, snr_db, 6);
```

### 4. LDPC码

- 构造：Gallager正则方法，列重 wc=3
- 码长/码率可配置，默认 n=64, R=0.5
- H矩阵由seed确定（编解码须一致）
- 译码：Min-Sum近似置信传播(BP)，支持提前终止

```matlab
n = 128; rate = 0.5; seed = 0;
k = round(n * rate);
msg = randi([0 1], 1, k);

[codeword, H, G] = ldpc_encode(msg, n, rate, seed);

% BPSK + AWGN
bpsk = 2*codeword - 1;
snr_db = 4.0;
sigma = 1 / sqrt(2 * rate * 10^(snr_db/10));
rx = bpsk + sigma * randn(size(bpsk));

[decoded, LLR, iters] = ldpc_decode(rx, H, k, snr_db, 50);
```

## 输入输出约定

- **比特序列**：0/1数值数组，行向量
- **软值输入**：实数数组，正值倾向于比特1，负值倾向于比特0（对应BPSK映射 `2*bit - 1`）
- **LLR输出**：正值倾向于比特1，负值倾向于比特0

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\ChannelCoding\src\Matlab');
run('test_channel_coding.m');
```

### 测试用例说明

**1. Hamming分组码（4项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 1.1 无差错回环 | `decoded == msg` 且 `num_corr == 0` | Hamming(7,4)编解码无差错时完全还原，纠错计数为零 |
| 1.2 单比特纠错 | 7个错误位置全部纠正 | 逐位翻转码字中每一位，验证均能正确纠正并还原信息 |
| 1.3 Hamming(15,11) | `decoded == msg` 且码字长60 | r=4的更长码型验证，44bit信息编为60bit码字 |
| 1.4 G/H正交性 | `mod(H*G', 2) == 0` | 生成矩阵与校验矩阵满足正交关系，是正确编码的数学基础 |

**2. 卷积码 + Viterbi（5项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 2.1 (2,1,3)无噪声 | `decoded == msg` 且路径度量=0 | 简单码型无噪声回环，最优路径度量应为零（完美匹配） |
| 2.2 (2,1,7)标准码 | `decoded == msg` | NASA标准码[171,133]无噪声回环，验证64状态网格正确 |
| 2.3 硬判决纠错 | 5%信道误码率下译码后BER < 5% | 引入随机比特错误后Viterbi纠错，译码BER应显著低于信道BER |
| 2.4 软/硬判决对比 | 打印两者BER供对比 | AWGN信道下软判决利用信道可靠度信息，通常优于硬判决约2dB |
| 2.5 网格结构 | 状态数=4, n=2, K=3 | 验证(2,1,3)码的网格参数与理论一致 |

**3. Turbo码（4项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 3.1 无噪声回环 | `decoded == msg` | 双RSC编码+Max-Log-MAP迭代译码，无噪声下完全还原 |
| 3.2 迭代增益 | 打印1/2/4/8次迭代的BER | AWGN信道下迭代次数增加BER应递减，体现Turbo码的迭代增益 |
| 3.3 编码结构 | 输出长3N且前N位=原始信息 | 码率1/3系统码，系统位保持不变 |
| 3.4 交织器一致性 | 相同seed→相同交织，交织+解交织=恒等 | 交织器确定性和逆映射正确性是Turbo编解码一致的前提 |

**4. LDPC码（5项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 4.1 无噪声回环 | `H*codeword'==0` 且 `decoded == msg` | 码字满足校验方程，BP译码无噪声下完全还原 |
| 4.2 H\*G'=0 | `mod(H*G', 2) == 0` | 生成矩阵与校验矩阵正交，编码正确性的数学保证 |
| 4.3 AWGN译码 | 打印BER和迭代次数 | 4dB SNR下BP译码性能，验证Min-Sum算法收敛 |
| 4.4 多码长码率 | (32,16)/(64,48)/(128,64)校验均通过 | 不同码长和码率组合下H矩阵构造和编码均正确 |
| 4.5 seed一致性 | 相同seed→相同H，不同seed→不同H | Gallager随机构造的确定性，保证编解码端H矩阵一致 |

**5. 异常输入（3项）**

| 测试 | 断言 | 说明 |
|------|------|------|
| 5.1 空输入拒绝 | 5个编码函数均对 `[]` 抛出error | 覆盖所有编码器的空输入校验 |
| 5.2 非二进制拒绝 | 4个编码函数对非0/1输入抛出error | 信道编码输入必须为二进制比特 |
| 5.3 块长度校验 | Hamming对非k整数倍长度抛出error | 分组码要求输入长度对齐信息块长 |
