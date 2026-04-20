function bench_turbo_iter_log(csv_path, main_row, iter, ber_at_iter)
% 功能：向 turbo 迭代长表追加一行
% 版本：V1.0.0
% 输入：
%   csv_path    - 长表 CSV 路径
%   main_row    - 主表 row struct（用于复制关联 key）
%   iter        - 迭代轮次（1..N）
%   ber_at_iter - 该轮 BER
%
% 备注：
%   长表字段：关联 key + (iter, ber_at_iter)
%   关联 key 从 main_row 提取固定子集，避免写入 NMSE/runtime 等不相关字段

key_fields = {'timestamp','stage','scheme','profile','fd_hz', ...
              'doppler_rate','snr_db','seed'};

iter_row = struct();
for k = 1:numel(key_fields)
    f = key_fields{k};
    if isfield(main_row, f)
        iter_row.(f) = main_row.(f);
    else
        iter_row.(f) = NaN;
    end
end
iter_row.iter        = iter;
iter_row.ber_at_iter = ber_at_iter;

bench_append_csv(csv_path, iter_row);

end
