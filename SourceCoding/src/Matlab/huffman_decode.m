function symbols = huffman_decode(bitstream, codebook, num_symbols)
% 功能：根据码本对Huffman比特流进行解码，还原符号序列
% 版本：V1.0.0
% 输入：
%   bitstream   - 编码后的比特流 (1xM logical数组)
%   codebook    - 码本结构体数组（由 huffman_encode 生成），每个元素包含：
%       .symbol : 符号值
%       .code   : 对应的Huffman码字 (字符串)
%       .prob   : 符号出现概率
%   num_symbols - 原始符号序列长度 (正整数)，用于确定解码终止位置
% 输出：
%   symbols     - 解码还原的符号序列 (1xN 数值数组)
%
% 备注：
%   - codebook 必须与编码时使用的码本一致，否则解码结果错误
%   - num_symbols 用于防止比特流末尾填充导致多解码

%% ========== 1. 入参解析与初始化 ========== %%
bitstream = bitstream(:).';            % 强制转为行向量

%% ========== 2. 严格参数校验 ========== %%
if isempty(bitstream)
    error('输入比特流不能为空！');
end
if isempty(codebook)
    error('码本不能为空！');
end
if ~isfield(codebook, 'symbol') || ~isfield(codebook, 'code')
    error('码本必须包含 symbol 和 code 字段！');
end
if nargin < 3 || isempty(num_symbols)
    num_symbols = inf;                 % 不限制，解码到比特流耗尽
end
if num_symbols <= 0
    error('num_symbols必须为正整数！');
end

%% ========== 3. 构建码字查找表 ========== %%
% 用 containers.Map 实现码字字符串到符号值的映射
num_codes = length(codebook);
code_keys = cell(1, num_codes);
sym_vals  = zeros(1, num_codes);

for k = 1:num_codes
    code_keys{k} = codebook(k).code;
    sym_vals(k)  = codebook(k).symbol;
end

code_map = containers.Map(code_keys, sym_vals);

% 计算最大码字长度（用于限制匹配搜索范围）
max_code_len = max(cellfun(@length, code_keys));  % 最长码字比特数

%% ========== 4. 逐比特解码 ========== %%
symbols = zeros(1, num_symbols);       % 预分配输出（按最大长度）
bit_pos = 1;                           % 比特流读取位置
sym_count = 0;                         % 已解码符号计数
total_bits = length(bitstream);

while bit_pos <= total_bits && sym_count < num_symbols
    matched = false;

    % 从当前位置尝试匹配码字，从短到长逐一尝试
    search_len = min(max_code_len, total_bits - bit_pos + 1);
    for clen = 1:search_len
        candidate = char('0' + bitstream(bit_pos:bit_pos+clen-1));

        if code_map.isKey(candidate)
            sym_count = sym_count + 1;
            symbols(sym_count) = code_map(candidate);
            bit_pos = bit_pos + clen;
            matched = true;
            break;
        end
    end

    if ~matched
        warning('比特位置 %d 处无法匹配任何码字，解码终止！', bit_pos);
        break;
    end
end

%% ========== 5. 裁剪输出 ========== %%
symbols = symbols(1:sym_count);

end
