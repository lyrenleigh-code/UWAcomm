function fig = amc_plot_history(history, out_path, opts)
%AMC_PLOT_HISTORY Plot link quality and selected schemes over time.

if nargin < 2, out_path = ''; end
if nargin < 3 || ~isstruct(opts), opts = struct(); end

visible = getfield_def(opts, 'visible', 'off');
fig = figure('Visible', visible, 'Color', 'w', 'Name', 'P6 AMC history');

N = length(history);
frames = zeros(1, N);
quality = zeros(1, N);
schemes = cell(1, N);
ber_est = nan(1, N);
for k = 1:N
    d = history{k};
    frames(k) = d.frame_idx;
    quality(k) = d.quality_db;
    schemes{k} = d.selected_scheme;
    if isfield(d, 'ber_est'), ber_est(k) = d.ber_est; end
end

subplot(2, 1, 1);
ax1 = gca;
style_axes(ax1);
yyaxis left;
plot(frames, quality, '-o', 'LineWidth', 1.5, 'Color', [0.000 0.447 0.741]);
ylabel('quality metric (dB)', 'Color', [0.000 0.447 0.741]);
grid on;

yyaxis right;
scheme_ids = zeros(1, N);
labels = {'FH-MFSK', 'DSSS', 'OTFS', 'SC-FDE', 'OFDM'};
for k = 1:N
    idx = find(strcmp(labels, schemes{k}), 1, 'first');
    if isempty(idx), idx = 1; end
    scheme_ids(k) = idx;
end
stairs(frames, scheme_ids, 'LineWidth', 1.5, 'Color', [0.850 0.325 0.098]);
ylim([0.5, length(labels) + 0.5]);
yticks(1:length(labels));
yticklabels(labels);
ylabel('selected scheme', 'Color', [0.850 0.325 0.098]);
xlabel('frame', 'Color', [0.10 0.10 0.10]);
title('P6 AMC link quality and mode switches', 'Color', [0.10 0.10 0.10]);
style_axes(ax1);

for k = 2:N
    if ~strcmp(schemes{k}, schemes{k-1})
        try
            xline(frames(k), '--', schemes{k}, 'LabelOrientation', 'horizontal');
        catch
            yl = ylim;
            line([frames(k), frames(k)], yl, 'LineStyle', '--', 'Color', [0.4 0.4 0.4]);
            text(frames(k), yl(2), schemes{k});
        end
    end
end

subplot(2, 1, 2);
ax2 = gca;
style_axes(ax2);
semilogy(frames, max(ber_est, 1e-6), '-s', 'LineWidth', 1.5, 'Color', [0.000 0.447 0.741]);
grid on;
xlabel('frame', 'Color', [0.10 0.10 0.10]);
ylabel('estimated BER', 'Color', [0.10 0.10 0.10]);
title('Estimated BER proxy from RX info', 'Color', [0.10 0.10 0.10]);
style_axes(ax2);

if ~isempty(out_path)
    saveas(fig, out_path);
end

end

% -------------------------------------------------------------------------
function style_axes(ax)

set(ax, 'Color', 'w', ...
    'XColor', [0.10 0.10 0.10], ...
    'YColor', [0.10 0.10 0.10], ...
    'GridColor', [0.75 0.75 0.75], ...
    'MinorGridColor', [0.88 0.88 0.88]);

end

% -------------------------------------------------------------------------
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
end

end
