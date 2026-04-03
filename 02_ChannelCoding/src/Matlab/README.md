# 信道编解码模块 (ChannelCoding)

为比特流添加冗余保护，覆盖分组码（Hamming）、卷积码（Viterbi）、迭代码（Turbo/LDPC）及Turbo均衡所需的SISO译码器。

## 对外接口

其他模块/端到端应调用的函数：

| 函数 | 功能 | 输入 | 输出 |
|------|------|------|------|
| conv_encode | 卷积编码（默认[171,133], K=7, 码率1/2） | message, gen_polys, constraint_len | coded, trellis |
| viterbi_decode | Viterbi译码（硬/软判决） | received, trellis, decision_type | decoded, min_metric |
| siso_decode_conv | BCJR(MAP) SISO卷积码译码器，输出外信息供Turbo均衡 | LLR_ch, LLR_prior, gen_polys, constraint_len | LLR_ext, LLR_post, LLR_post_coded |
| sova_decode_conv | SOVA软输出Viterbi译码器，Turbo均衡对比用 | LLR_ch, LLR_prior, gen_polys, constraint_len | LLR_ext, LLR_post, LLR_post_coded |
| hamming_encode | Hamming(2^r-1, 2^r-1-r)分组码编码 | message, r | codeword, G, H |
| hamming_decode | Hamming伴随式译码（纠1位错） | received, r | decoded, num_corrected |
| turbo_encode | Turbo编码器（双RSC并行级联，码率1/3） | message, num_iter_hint, interleaver_seed | coded, params |
| turbo_decode | Turbo迭代译码器（Max-Log-MAP） | received, params, snr_db, num_iter | decoded, LLR_out |
| ldpc_encode | LDPC编码器（Gallager正则构造） | message, n, rate, H_seed | codeword, H, G |
| ldpc_decode | LDPC译码器（Min-Sum BP迭代） | received, H, k, snr_db, max_iter | decoded, LLR_out, num_iter_done |

## 使用示例

```matlab
%% 卷积编码 + Viterbi译码
msg = randi([0 1], 1, 100);
[coded, trellis] = conv_encode(msg);
[decoded, ~] = viterbi_decode(coded, trellis, 'hard');

%% Turbo均衡中的SISO译码调用
[Le_dec, Lpost_info, Lpost_coded] = siso_decode_conv(Le_eq_deint, La_info, [7,5], 3);
bits_out = double(Lpost_info > 0);
```

## 内部函数

辅助/测试函数（不建议外部直接调用）：
- plot_ber_curve.m -- BER vs SNR曲线绘制工具，绘制多编码方案误码率对比
- test_channel_coding.m -- 单元测试（22项），覆盖Hamming、卷积码、Turbo码、LDPC码和异常输入

## 依赖关系

- 依赖模块03（交织）的 random_interleave / random_deinterleave（turbo_encode/turbo_decode内部调用）
- 上游：模块01（信源编码）输出的比特流
- 下游：模块03（交织）接收编码后比特流
