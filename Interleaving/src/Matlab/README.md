# 交织/解交织模块 (Interleaving)

水声通信系统交织算法库，覆盖块交织、随机交织和卷积交织三种方案，用于打散突发错误、提升信道编码纠错效果。

## 文件清单

| 文件 | 功能 | 类别 |
|------|------|------|
| `block_interleave.m` | 块交织（按行写入、按列读出） | 块交织 |
| `block_deinterleave.m` | 块解交织（逆操作） | 块交织 |
| `random_interleave.m` | 随机交织（伪随机置换） | 随机交织 |
| `random_deinterleave.m` | 随机解交织（逆置换） | 随机交织 |
| `conv_interleave.m` | 卷积交织（延迟递增移位寄存器） | 卷积交织 |
| `conv_deinterleave.m` | 卷积解交织（互补延迟） | 卷积交织 |
| `test_interleaving.m` | 单元测试（19项） | 测试 |

## 各交织方案说明

### 1. 块交织器

- 将数据按行写入 num_rows x num_cols 矩阵，按列读出
- 交织深度 = num_rows，连续 num_rows 个突发错误被分散到不同列
- 支持指定行列数或自动计算（近似方阵）
- 数据不足时自动补零，返回 pad_len 供解交织截断

```matlab
data = 1:12;
[intlv, nr, nc, pl] = block_interleave(data, 3, 4);
% intlv = [1 5 9 2 6 10 3 7 11 4 8 12]
deintlv = block_deinterleave(intlv, nr, nc, pl);

% 自动计算尺寸
[intlv, nr, nc, pl] = block_interleave(data);
```

### 2. 随机交织器

- 基于seed生成伪随机置换，对数据进行重排
- 同一seed和数据长度始终产生相同置换，保证编解码一致
- 不污染全局随机状态（内部保存/恢复rng）
- 已被Turbo编码器调用

```matlab
data = randi([0 1], 1, 100);
[intlv, perm] = random_interleave(data, 42);
deintlv = random_deinterleave(intlv, perm);
```

### 3. 卷积交织器

- B条支路，第i支路延迟为 (i-1)*M 个符号（i=1,...,B）
- 输入符号按轮转分配到各支路，经不同延迟后输出
- 解交织器延迟互补：第i支路延迟为 (B-i)*M，总延迟恒为 (B-1)*M
- 适合流式处理，交织+解交织后有效段完全还原

```matlab
data = 1:120;
B = 4; M = 5;                         % 4支路，延迟增量5
[intlv, ~, ~] = conv_interleave(data, B, M);
deintlv = conv_deinterleave(intlv, B, M);

% 前(B-1)*M = 15个样本为零过渡，之后完全还原
total_delay = (B-1) * M;
deintlv(total_delay+1:end)             % == data(1:end-total_delay)
```

## 三种交织器对比

| 特性 | 块交织 | 随机交织 | 卷积交织 |
|------|--------|----------|----------|
| 延迟 | 一帧 | 一帧 | (B-1)*M个符号 |
| 突发打散能力 | 取决于行数 | 全局均匀 | 取决于B*M |
| 适用场景 | 帧级批处理 | Turbo码、通用 | 流式传输 |
| 参数 | num_rows, num_cols | seed | num_branches, branch_delay |

## 输入输出约定

- **输入数据**：任意数值序列（比特、符号、软值均可），行/列向量均可
- **块交织**：返回 num_rows, num_cols, pad_len，解交织时必须传入
- **随机交织**：返回 perm（置换索引），解交织时必须传入
- **卷积交织**：返回 num_branches, branch_delay，解交织时必须传入；注意前(B-1)*M个输出为零过渡

## 运行测试

```matlab
cd('D:\TechReq\UWAcomm\Interleaving\src\Matlab');
run('test_interleaving.m');
```

测试覆盖：三种交织器回环、突发打散效果、seed确定性、rng保护、卷积延迟对齐、Turbo码集成验证、异常输入拒绝。
