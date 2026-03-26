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

测试覆盖：无差错回环、纠错能力、矩阵正交性、AWGN信道性能、迭代增益、异常输入拒绝。
