function bench_run_single(stage, scheme, profile, snr_list, fading_cfgs, seed, csv_path, runner_path)
% 功能：单点 benchmark 执行（function workspace 隔离 runner 变量）
% 版本：V1.0.0（2026-04-19）
% 输入：
%   stage        - 'A1' | 'A2' | 'A3' | 'B'（记入 CSV.stage 字段）
%   scheme       - 体制名（记入 CSV.scheme）
%   profile      - 信道 profile 名（记入 CSV.profile，当前仅 'custom6' 实际生效）
%   snr_list     - 1×Ns double
%   fading_cfgs  - 1×N cell（单行）
%   seed         - scalar int（rng 主种子）
%   csv_path     - CSV 输出路径
%   runner_path  - runner 完整路径（.m 文件）
% 输出：
%   无（runner 内部 append 到 csv_path）
%
% 备注：
%   function 形式调用 run()，runner 的临时变量（snr_list/fading_cfgs 等）仅存在于
%   本 function workspace，调用返回即自动释放，不污染 caller。

benchmark_mode        = true;  %#ok<NASGU>
bench_snr_list        = snr_list;  %#ok<NASGU>
bench_fading_cfgs     = fading_cfgs;  %#ok<NASGU>
bench_channel_profile = profile;  %#ok<NASGU>
bench_seed            = seed;  %#ok<NASGU>
bench_stage           = stage;  %#ok<NASGU>
bench_scheme_name     = scheme;  %#ok<NASGU>
bench_csv_path        = csv_path;  %#ok<NASGU>

run(runner_path);

end
