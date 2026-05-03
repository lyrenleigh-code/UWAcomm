function [delays_out, gains_out] = bench_profile_taps(profile_name, delays_default, gains_default, delay_mode, seed)
%BENCH_PROFILE_TAPS Build deterministic tap sets for benchmark channel profiles.
%   The runner-owned custom taps are preserved for custom6. Non-default
%   profiles receive reproducible tap locations in the same delay unit as the
%   caller, so estimators and guard sizing stay internally consistent.

if nargin < 1 || isempty(profile_name)
    profile_name = 'custom6';
end
if nargin < 4 || isempty(delay_mode)
    delay_mode = 'integer';
end
if nargin < 5 || isempty(seed)
    seed = 42;
end

delays_default = delays_default(:).';
gains_default = gains_default(:).';

switch lower(profile_name)
    case 'custom6'
        delays_out = delays_default;
        gains_out = gains_default;

    case 'exponential'
        rng_state = rng;
        cleanup = onCleanup(@() rng(rng_state));
        rng(double(seed), 'twister');

        n_paths = numel(gains_default);
        if n_paths < 1
            error('bench_profile_taps:EmptyGains', 'gains_default must be non-empty.');
        end

        switch lower(delay_mode)
            case 'seconds'
                max_delay = max(delays_default);
                if max_delay <= 0
                    delays_out = zeros(1, n_paths);
                else
                    delays_out = [0, sort(rand(1, n_paths-1) * max_delay)];
                end
                spread = max(max_delay, eps);

            otherwise
                max_delay = round(max(delays_default));
                if n_paths == 1 || max_delay <= 0
                    delays_out = zeros(1, n_paths);
                elseif max_delay >= n_paths - 1
                    delays_out = [0, sort(randperm(max_delay, n_paths-1))];
                else
                    delays_out = round(linspace(0, max_delay, n_paths));
                end
                spread = max(max_delay, 1);
        end

        decay = exp(-3 * delays_out / spread);
        phases = exp(1j * 2*pi*rand(1, n_paths));
        phases(1) = 1;
        gains_out = sqrt(decay) .* phases;
        gains_out = gains_out / sqrt(sum(abs(gains_out).^2));

    otherwise
        error('bench_profile_taps:UnknownProfile', 'Unknown benchmark channel profile: %s', profile_name);
end

end
