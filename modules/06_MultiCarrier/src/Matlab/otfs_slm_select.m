function [dd_best, signal_best, slm_info] = otfs_slm_select(dd_frame, data_indices, N, M, cp_len, method, pulse_type, cp_window, num_candidates, seed)
%OTFS_SLM_SELECT Select an OTFS data-phase mask with the lowest time-domain PAPR.
%
% Candidate 1 is always the unmodified DD frame. Later candidates rotate data
% cells by deterministic QPSK phases while pilot/guard cells stay unchanged.
% The receiver must know slm_info.data_phase and remove it before demapping.

if nargin < 10 || isempty(num_candidates), num_candidates = 1; end
if nargin < 11 || isempty(seed), seed = 0; end
if nargin < 8 || isempty(cp_window), cp_window = 'none'; end
if nargin < 7 || isempty(pulse_type), pulse_type = 'rect'; end
if nargin < 6 || isempty(method), method = 'dft'; end

if isempty(dd_frame), error('otfs_slm_select:EmptyFrame', 'dd_frame must not be empty'); end
if isvector(dd_frame)
    dd_frame = reshape(dd_frame(:), N, M);
end
if any(size(dd_frame) ~= [N, M])
    error('otfs_slm_select:SizeMismatch', 'dd_frame must be %dx%d', N, M);
end

num_candidates = max(1, round(num_candidates));
data_indices = data_indices(:);
num_data = length(data_indices);
if any(data_indices < 1) || any(data_indices > N*M)
    error('otfs_slm_select:BadDataIndex', 'data_indices contains out-of-range entries');
end

rng_state = rng;
restore_rng = onCleanup(@() rng(rng_state));

phase_alphabet = [1; -1; 1j; -1j];
papr_list = inf(1, num_candidates);
best_papr = inf;
best_idx = 1;
best_phase = ones(num_data, 1);
dd_best = dd_frame;
signal_best = [];
params_best = struct();

for ci = 1:num_candidates
    if ci == 1 || num_data == 0
        phase_vec = ones(num_data, 1);
    else
        rng(seed + ci - 2);
        phase_vec = phase_alphabet(randi(numel(phase_alphabet), num_data, 1));
    end

    dd_candidate = dd_frame;
    dd_candidate(data_indices) = dd_frame(data_indices) .* phase_vec;
    [signal_candidate, params_candidate] = otfs_modulate(dd_candidate, N, M, cp_len, method, pulse_type, cp_window);
    papr_list(ci) = papr_calculate(signal_candidate);

    if papr_list(ci) < best_papr
        best_papr = papr_list(ci);
        best_idx = ci;
        best_phase = phase_vec;
        dd_best = dd_candidate;
        signal_best = signal_candidate;
        params_best = params_candidate;
    end
end

slm_info = struct();
slm_info.enabled = num_candidates > 1;
slm_info.num_candidates = num_candidates;
slm_info.selected = best_idx;
slm_info.seed = seed;
slm_info.data_indices = data_indices;
slm_info.data_phase = best_phase;
slm_info.papr_candidates_db = papr_list;
slm_info.papr_before_db = papr_list(1);
slm_info.papr_after_db = papr_list(best_idx);
slm_info.papr_reduction_db = papr_list(1) - papr_list(best_idx);
slm_info.params_out = params_best;

clear restore_rng;

end
