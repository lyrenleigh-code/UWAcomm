function sys = streaming_apply_modem_params(sys, modem_params)
%STREAMING_APPLY_MODEM_PARAMS Merge AMC profile modem parameters into sys.

if nargin < 2 || ~isstruct(modem_params) || isempty(fieldnames(modem_params))
    return;
end

families = fieldnames(modem_params);
for k = 1:length(families)
    family = families{k};
    if ~isstruct(modem_params.(family))
        continue;
    end
    if ~isfield(sys, family) || ~isstruct(sys.(family))
        sys.(family) = struct();
    end
    fields = fieldnames(modem_params.(family));
    for j = 1:length(fields)
        fname = fields{j};
        sys.(family).(fname) = modem_params.(family).(fname);
    end
end

end
