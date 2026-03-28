function [codes, num_codes] = gen_kasami_code(degree)
% 功能：生成Kasami码（小集合），互相关性能优于Gold码
% 版本：V1.0.0
% 输入：
%   degree - m序列级数 (偶数正整数，如 4/6/8/10)
% 输出：
%   codes     - Kasami码集合 ((num_codes) x (2^degree-1) 矩阵，值为 0/1)
%   num_codes - 码字数量 (= 2^(degree/2) + 1)
%
% 备注：
%   - 小集合Kasami码要求degree为偶数
%   - 码字数量 = 2^(degree/2) + 1
%   - 由一条m序列及其抽取序列生成
%   - 互相关峰值 <= 2^(degree/2) + 1，优于Gold码
%   - 抽取因子 q = 2^(degree/2) + 1

%% ========== 1. 严格参数校验 ========== %%
if degree < 4 || mod(degree, 2) ~= 0
    error('degree必须为>=4的偶数！');
end

L = 2^degree - 1;                      % 码长
half_deg = degree / 2;
q = 2^half_deg + 1;                    % 抽取因子

%% ========== 2. 生成基础m序列 ========== %%
m_seq = gen_msequence(degree);

%% ========== 3. 抽取生成短序列 ========== %%
% 每隔q个采样取一个，得到周期为 2^(degree/2)-1 的短序列
short_len = 2^half_deg - 1;
short_seq = m_seq(1:q:q*short_len);

% 重复短序列至与m序列等长
short_repeated = repmat(short_seq, 1, ceil(L / short_len));
short_repeated = short_repeated(1:L);

%% ========== 4. 生成Kasami码集 ========== %%
num_codes = 2^half_deg + 1;
codes = zeros(num_codes, L);

% 第一个码 = 原始m序列
codes(1, :) = m_seq;

% 后续码 = m序列 XOR 循环移位的短序列
for k = 1:num_codes - 1
    shifted_short = circshift(short_repeated, [0, -(k-1)]);
    codes(k+1, :) = xor(m_seq, shifted_short);
end

end
