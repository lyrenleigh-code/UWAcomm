function [frame_bb, meta] = assemble_routed_physical_frame(header_bb, payload_bb, sys)
%ASSEMBLE_ROUTED_PHYSICAL_FRAME Build P4 frame with separate header/payload.
%
% Physical layout:
%   [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|Hdr(FH-MFSK)|guard|Payload]

if isfield(sys.frame, 'header_payload_guard_samp')
    hp_guard = sys.frame.header_payload_guard_samp;
else
    hp_guard = sys.preamble.guard_samp;
end

header_bb = header_bb(:).';
payload_bb = payload_bb(:).';
body_bb = [header_bb, zeros(1, hp_guard), payload_bb];

[frame_bb, meta] = assemble_physical_frame(body_bb, sys);
meta.header_samples = length(header_bb);
meta.header_payload_guard_samp = hp_guard;
meta.payload_samples = length(payload_bb);
meta.header_start = meta.data_start;
meta.payload_start = meta.header_start + meta.header_samples + hp_guard;

end
