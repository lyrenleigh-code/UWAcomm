%% test_p2_multiframe.m — Streaming P2 多帧端到端测试
% 测试组：短/中/长文本 + 静态信道；中文本 + 低 SNR
% 验收：每个 case 文本完美复原 + 检测帧数 = 实际帧数

clear functions; clear all; clc;
this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));

% 14_Streaming 全子目录
streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(streaming_root, 'channel'));

% 复用旧模块
addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '09_Waveform', 'src', 'Matlab'));

diary('test_p2_multiframe_results.txt');
fprintf('========================================\n');
fprintf(' Streaming P2 — 多帧流式检测端到端测试\n');
fprintf('========================================\n\n');

% ---- 系统参数（小 payload 让短文本也能切多帧）----
sys = sys_params_default();
sys.frame.payload_bits = 256;   % 32 字节，约 32 ASCII 或 ~10 汉字
sys.frame.body_bits = sys.frame.header_bits + sys.frame.payload_bits + sys.frame.payload_crc_bits;
fprintf('payload_bits = %d (max %d 字节/帧)\n\n', sys.frame.payload_bits, sys.frame.payload_bits/8);

session_root = fullfile(proj_root, 'modules', '14_Streaming', 'sessions');

% ---- 测试组 ----
test_cases = { ...
    'short',          'Hello P2',                                                                       'static', 15;
    'medium_zh',      '这是一段中等长度的水声通信测试文本，包含中英文 ABC 123 混合内容', 'static', 15;
    'long_mixed',     ['第一段：' repmat('水声', 1, 10) ' Second: ' repmat('Hello ', 1, 10) ' 第三段：' repmat('测试', 1, 12)], 'static', 15;
    'medium_lowSNR',  '这是一段中等长度的水声通信测试文本',                                      'static', 5; ...
};

% ---- 信道（5 径，可改 SNR）----
ch_params_template = struct( ...
    'fs', sys.fs, ...
    'delays_s', [0, 0.167, 0.5, 0.833, 1.333] * 1e-3, ...
    'gains', [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)], ...
    'num_paths', 5, ...
    'doppler_rate', 0, ...
    'fading_type', 'static', ...
    'fading_fd_hz', 0, ...
    'snr_db', 15, ...
    'seed', 42);

results = {};
for ti = 1:size(test_cases, 1)
    name = test_cases{ti, 1};
    text_in = test_cases{ti, 2};
    fading = test_cases{ti, 3};
    snr = test_cases{ti, 4};

    fprintf('\n===== 测试 [%s]: SNR=%ddB, fading=%s =====\n', name, snr, fading);
    fprintf('输入文本 (%d 字符 / %d UTF-8 字节):\n  %s\n\n', ...
        length(text_in), length(unicode2native(text_in,'UTF-8')), text_in);

    session = create_session_dir(session_root);

    % TX
    tx_stream_p2(text_in, session, sys);

    % Channel
    ch_params = ch_params_template;
    ch_params.fading_type = fading;
    ch_params.snr_db = snr;
    channel_simulator_p1(session, ch_params, sys);

    % RX
    [text_out, info] = rx_stream_p2(session, sys);

    % 验收
    ok_text = strcmp(text_in, text_out);
    ok_count = (info.N_detected == info.N_expected);
    fprintf('\n--- 结果 ---\n');
    fprintf('输出文本: %s\n', text_out);
    fprintf('一致: %d, 检测/预期帧数: %d/%d\n', ok_text, info.N_detected, info.N_expected);

    results{end+1} = struct('name', name, 'in', text_in, 'out', text_out, ...
        'ok', ok_text, 'ok_count', ok_count, ...
        'N_det', info.N_detected, 'N_exp', info.N_expected); %#ok<SAGROW>
end

% ---- 汇总 ----
fprintf('\n\n========== 汇总 ==========\n');
fprintf('%-18s | %-6s | %-10s | 帧数(det/exp)\n', '测试名', '文本OK', '检测计数OK');
fprintf('%s\n', repmat('-', 1, 60));
n_pass = 0;
for ri = 1:length(results)
    r = results{ri};
    fprintf('%-18s | %-6s | %-10s | %d/%d\n', r.name, ...
        bool2str(r.ok), bool2str(r.ok_count), r.N_det, r.N_exp);
    if r.ok && r.ok_count, n_pass = n_pass + 1; end
end
fprintf('\n%d/%d 通过\n', n_pass, length(results));

if n_pass == length(results)
    fprintf('\n[PASS] P2 多帧测试全部通过\n');
else
    fprintf('\n[PARTIAL] P2 测试部分通过\n');
end

diary off;

% ================================================================
function s = bool2str(b)
    if b, s = 'PASS'; else, s = 'FAIL'; end
end
