function [bitstream, codebook, compress_ratio] = huffman_encode(symbols)
% 功能：对输入符号序列进行Huffman编码，输出比特流和码本
% 版本：V1.0.0
% 输入：
%   symbols     - 待编码的符号序列 (1xN 或 Nx1 数值数组，元素为非负整数)
% 输出：
%   bitstream   - 编码后的比特流 (1xM logical数组，M为编码总比特数)
%   codebook    - 码本结构体数组，每个元素包含：
%       .symbol : 符号值
%       .code   : 对应的Huffman码字 (字符串，如 '010')
%       .prob   : 符号出现概率
%   compress_ratio - 压缩比 (原始比特数 / 编码比特数)
%
% 备注：
%   - 基于符号出现频率构建最优前缀码
%   - 输入符号需为非负整数（如uint8量化后的数据）
%   - 单符号输入时，码字固定为 '0'

%% ========== 1. 入参解析与初始化 ========== %%
symbols = symbols(:).';               % 强制转为行向量

%% ========== 2. 严格参数校验 ========== %%
if isempty(symbols)
    error('输入符号序列不能为空！');
end
if ~isnumeric(symbols)
    error('输入符号必须为数值类型！');
end
if any(symbols < 0) || any(symbols ~= floor(symbols))
    error('输入符号必须为非负整数！');
end

%% ========== 3. 统计符号频率 ========== %%
unique_syms = unique(symbols);         % 去重后的符号集合
num_syms = length(unique_syms);        % 不同符号个数
sym_counts = zeros(1, num_syms);       % 各符号出现次数

for k = 1:num_syms
    sym_counts(k) = sum(symbols == unique_syms(k));
end

sym_probs = sym_counts / length(symbols);  % 各符号出现概率

%% ========== 4. 构建Huffman树 ========== %%
% 特殊情况：只有一种符号
if num_syms == 1
    codes = {'0'};
else
    codes = build_huffman_tree(unique_syms, sym_probs);
end

%% ========== 5. 组装码本 ========== %%
codebook = struct('symbol', {}, 'code', {}, 'prob', {});
for k = 1:num_syms
    codebook(k).symbol = unique_syms(k);
    codebook(k).code   = codes{k};
    codebook(k).prob   = sym_probs(k);
end

%% ========== 6. 编码符号序列 ========== %%
% 构建符号到码字的映射（用containers.Map加速查找）
sym_keys = arrayfun(@num2str, unique_syms, 'UniformOutput', false);
code_map = containers.Map(sym_keys, codes);

% 预估总比特数并拼接
total_bits = 0;
for k = 1:num_syms
    total_bits = total_bits + sym_counts(k) * length(codes{k});
end

bitstream = false(1, total_bits);      % 预分配
pos = 1;                               % 写入位置指针
for n = 1:length(symbols)
    c = code_map(num2str(symbols(n))); % 当前符号的码字字符串
    clen = length(c);
    bitstream(pos:pos+clen-1) = (c == '1');
    pos = pos + clen;
end

%% ========== 7. 计算压缩比 ========== %%
bits_per_sym_orig = ceil(log2(max(unique_syms) + 1));  % 原始每符号比特数
if bits_per_sym_orig == 0
    bits_per_sym_orig = 1;             % 至少1比特
end
orig_bits = bits_per_sym_orig * length(symbols);       % 原始总比特数
compress_ratio = orig_bits / total_bits;               % 压缩比

end

% --------------- 辅助函数1：构建Huffman树并生成码字 --------------- %
function codes = build_huffman_tree(unique_syms, sym_probs)
% BUILD_HUFFMAN_TREE 基于符号概率构建Huffman二叉树，返回各符号码字
% 输入参数：
%   unique_syms - 不重复的符号值 (1xK 数组)
%   sym_probs   - 各符号对应概率 (1xK 数组，和为1)
% 输出参数：
%   codes       - 各符号的Huffman码字 (1xK cell数组，每个元素为字符串)

num_syms = length(unique_syms);

% 初始化叶子节点：每个节点用cell表示 {概率, 符号索引列表, 码字前缀}
nodes = cell(1, num_syms);
for k = 1:num_syms
    nodes{k} = struct('prob', sym_probs(k), 'indices', k);
end

% 码字存储，初始为空字符串
codes = repmat({''}, 1, num_syms);

% 迭代合并：每次取概率最小的两个节点合并
while length(nodes) > 1
    % 提取所有节点概率
    probs = zeros(1, length(nodes));
    for k = 1:length(nodes)
        probs(k) = nodes{k}.prob;
    end

    % 找到概率最小的两个节点
    [~, idx1] = min(probs);
    probs(idx1) = inf;                 % 屏蔽第一个最小值
    [~, idx2] = min(probs);

    node1 = nodes{idx1};
    node2 = nodes{idx2};

    % 为左子树(node1)所有符号码字前添加 '0'
    for j = 1:length(node1.indices)
        codes{node1.indices(j)} = ['0', codes{node1.indices(j)}];
    end

    % 为右子树(node2)所有符号码字前添加 '1'
    for j = 1:length(node2.indices)
        codes{node2.indices(j)} = ['1', codes{node2.indices(j)}];
    end

    % 合并为新节点
    new_node = struct('prob', node1.prob + node2.prob, ...
                      'indices', [node1.indices, node2.indices]);

    % 从节点列表中移除已合并的两个，加入新节点
    keep = true(1, length(nodes));
    keep(idx1) = false;
    keep(idx2) = false;
    nodes = [nodes(keep), {new_node}];
end

end
