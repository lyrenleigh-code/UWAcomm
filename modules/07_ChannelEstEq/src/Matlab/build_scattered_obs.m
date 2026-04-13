function [obs_y, obs_x, obs_t] = build_scattered_obs(rx, training, pilot_sym, pilot_positions, sym_delays, train_len, N_frame)
% 功能：从帧结构构建BEM散布导频观测矩阵
% 版本：V1.0.0
% 输入：
%   rx              - 接收信号 (1×N)
%   training        - 训练序列 (1×T)
%   pilot_sym       - 导频符号 (1×L_pilot, 各导频段共用)
%   pilot_positions - 各导频段起始位置 (1×N_pilot, 帧中的1-based索引)
%   sym_delays      - 各径符号级时延 (1×P)
%   train_len       - 训练段长度
%   N_frame         - 帧总长度
% 输出：
%   obs_y - 导频位置接收值 (M×1)
%   obs_x - 已知发送符号矩阵 (M×P)
%   obs_t - 导频时刻索引 (M×1)
%
% 备注：
%   帧结构: [训练(1:T) | 数据/导频交替 | 尾导频]
%   每个导频位置从 pilot_positions(i) 开始，长度为 length(pilot_sym)
%   仅取max_delay之后的观测（确保所有径的延迟符号已知）

%% ========== 1. 入参解析 ========== %%
P = length(sym_delays);
max_d = max(sym_delays);
pilot_len = length(pilot_sym);

%% ========== 2. 参数校验 ========== %%
if isempty(rx), error('接收信号不能为空！'); end
if isempty(training), error('训练序列不能为空！'); end

%% ========== 3. 训练段观测 ========== %%
obs_y = []; obs_x = []; obs_t = [];
for n = max_d+1 : train_len
    xv = zeros(1, P);
    for p = 1:P
        idx = n - sym_delays(p);
        if idx >= 1
            xv(p) = training(idx);
        end
    end
    obs_y(end+1) = rx(n);
    obs_x = [obs_x; xv];
    obs_t(end+1) = n;
end

%% ========== 4. 散布导频段观测 ========== %%
for pi_i = 1:length(pilot_positions)
    pp = pilot_positions(pi_i);
    for kk = max_d+1 : pilot_len
        n = pp + kk - 1;
        if n > N_frame, break; end
        xv = zeros(1, P);
        for p = 1:P
            idx = n - sym_delays(p);
            if idx >= pp && idx < pp + pilot_len
                xv(p) = pilot_sym(idx - pp + 1);
            elseif idx >= 1 && idx <= train_len
                xv(p) = training(idx);
            end
        end
        if any(xv ~= 0)
            obs_y(end+1) = rx(n);
            obs_x = [obs_x; xv];
            obs_t(end+1) = n;
        end
    end
end

obs_y = obs_y(:);
obs_t = obs_t(:);

end
