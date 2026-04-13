function [decoded, num_corrected] = hamming_decode(received, r)
% 功能：Hamming(2^r-1, 2^r-1-r)分组码译码，纠正单比特错误
% 版本：V1.0.0
% 输入：
%   received    - 接收到的比特序列 (1xM 数组，M须为n的整数倍)
%               n = 2^r - 1（码字长度）
%   r           - 校验比特数 (正整数，默认 r=3 即 Hamming(7,4))
% 输出：
%   decoded     - 译码后的信息比特序列 (1xN 数组，N = M/n * k)
%   num_corrected - 纠正的错误比特总数
%
% 备注：
%   - 基于伴随式(syndrome)译码，可纠正每个码字中的1位错误
%   - 若码字中有2位及以上错误，译码结果不可靠

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 2 || isempty(r)
    r = 3;
end
received = double(received(:).');

n = 2^r - 1;                          % 码字长度
k = n - r;                            % 信息位长度

%% ========== 2. 严格参数校验 ========== %%
if isempty(received)
    error('接收比特序列不能为空！');
end
if any(received ~= 0 & received ~= 1)
    error('接收比特必须为二进制(0或1)！');
end
if mod(length(received), n) ~= 0
    error('接收比特长度(%d)必须为n=%d的整数倍！', length(received), n);
end

%% ========== 3. 构造校验矩阵H ========== %%
[~, ~, H] = hamming_encode(zeros(1, k), r);

%% ========== 4. 分块译码 ========== %%
num_blocks = length(received) / n;
decoded = zeros(1, num_blocks * k);
num_corrected = 0;

for b = 1:num_blocks
    idx_in = (b-1)*n + 1 : b*n;
    block = received(idx_in);

    % 计算伴随式
    syndrome = mod(H * block.', 2);

    % 伴随式非零 → 存在错误
    if any(syndrome)
        % 伴随式对应H中某列，该列位置即错误位
        syndrome_val = syndrome.';
        err_pos = 0;
        for col = 1:n
            if isequal(H(:, col).', syndrome_val)
                err_pos = col;
                break;
            end
        end

        if err_pos > 0
            block(err_pos) = 1 - block(err_pos);  % 翻转错误位
            num_corrected = num_corrected + 1;
        else
            warning('第%d个码字伴随式无法匹配，可能存在多位错误！', b);
        end
    end

    % 提取信息位（系统码前k位为信息位）
    idx_out = (b-1)*k + 1 : b*k;
    decoded(idx_out) = block(1:k);
end

end
