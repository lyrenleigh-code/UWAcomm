# 交织/解交织模块 (Interleaving)

打散突发错误以提升信道编码纠错效果，覆盖块交织、随机交织和卷积交织三种方案，广泛用于Turbo迭代回环。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| random_interleave | 基于seed的伪随机置换交织 | data, seed | interleaved, perm |
| random_deinterleave | 随机交织逆操作 | data, perm | deinterleaved |
| block_interleave | 块交织（按行写入、按列读出） | data, num_rows, num_cols | interleaved, num_rows, num_cols, pad_len |
| block_deinterleave | 块解交织（逆操作） | data, num_rows, num_cols, pad_len | deinterleaved |
| conv_interleave | 卷积交织（延迟递增移位寄存器） | data, num_branches, branch_delay | interleaved, num_branches, branch_delay |
| conv_deinterleave | 卷积解交织（互补延迟） | data, num_branches, branch_delay | deinterleaved |

## 使用示例

```matlab
%% 随机交织（Turbo均衡中最常用）
data = randi([0 1], 1, 100);
[intlv, perm] = random_interleave(data, 42);
deintlv = random_deinterleave(intlv, perm);

%% 块交织
[intlv, nr, nc, pl] = block_interleave(data, 3, 4);
deintlv = block_deinterleave(intlv, nr, nc, pl);
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- plot_burst_scatter.m -- 突发错误打散效果可视化
- test_interleaving.m -- 单元测试（19项），覆盖块交织、随机交织、卷积交织、异常输入和Turbo码集成

## 依赖关系

- 无外部模块依赖
- 被模块02（信道编码）的 turbo_encode/turbo_decode 内部调用（random_interleave/random_deinterleave）
- 被Turbo均衡迭代回环调用（交织/解交织外信息）
- 上游：模块02（信道编码）输出的编码比特流
- 下游：模块04（符号映射）接收交织后比特流
