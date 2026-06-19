function [qrs_i_raw, qrs_amp_raw] = MinEl(ecg, fs)
% MinEl QRS detector – optimised on MITDB+QTDB
%   Input:
%     ecg : column or row vector of pre‑processed ECG (bandpass filtered)
%     fs  : sampling frequency in Hz
%   Output:
%     qrs_i_raw   : indices of detected QRS complexes
%     qrs_amp_raw : corresponding amplitudes

% =========================================================================
% 1.  FIXED PARAMETERS (hard‑coded)
% =========================================================================
high_factor      = 1.3;   % multiplier for RR‑deviation > tolerance
low_factor       = 0.7;   % multiplier for RR‑deviation ≤ tolerance
rr_tol           = 0.3;   % relative RR deviation tolerance
win_len_sec      = 11;    % length (in seconds) of recent window for percentile
perc             = 97;    % percentile for baseline threshold
height_thresh    = 0.104; % fraction of percentile used as base threshold
alpha            = 0.425; % blend factor for hybrid QRS signal
min_dist         = 2;     % minimum distance (samples) between beats (refractory)
beta             = 0.06;  % offset factor for first threshold
win_beat         = 12;    % moving average window for beat‑level (samples)
win_qrs          = 3;     % moving average window for QRS‑level (samples)

% =========================================================================
% 2.  INITIALISE OUTPUTS & EARLY EXIT
% =========================================================================
qrs_amp_raw = [];
qrs_i_raw = [];

if length(ecg) < win_beat + 10
    return;   % signal too short for meaningful detection
end

% Ensure row vector (original code uses row)
ecg = ecg(:)';
ekg_abs = abs(ecg);   % absolute value (instead of squared)

% =========================================================================
% 3.  STAGE 1 – STANDARD ELGENDI CANDIDATE DETECTION
% =========================================================================
% ---- 3a. Moving averages ----
ma_qrs  = conv(ekg_abs, ones(1, win_qrs)/win_qrs, 'same');      % short window (QRS)
ma_beat = conv(ekg_abs, ones(1, win_beat)/win_beat, 'same');     % long window (beat)

% ---- 3b. Hybrid signal (weighted sum of raw and short‑window MA) ----
ma_qrs_hybrid = alpha * ekg_abs + (1 - alpha) * ma_qrs;

% ---- 3c. First threshold (beat‑level MA + offset) ----
THR1 = ma_beat + beta * mean(ekg_abs);

% ---- 3d. Candidate regions (where hybrid signal exceeds THR1) ----
boi_mask = ma_qrs_hybrid > THR1;
d = diff([false, boi_mask, false]);
starts = find(d == 1);
ends   = find(d == -1) - 1;

% ---- 3e. Keep only regions with at least 1 sample ----
keep = (ends - starts + 1) >= 1;
starts = starts(keep);
ends   = ends(keep);

if isempty(starts)
    return;
end

% ---- 3f. Extract local maxima within each candidate region ----
cand_locs = zeros(size(starts));
cand_amps = zeros(size(starts));
for i = 1:length(starts)
    [cand_amps(i), idx] = max(ecg(starts(i):ends(i)));
    cand_locs(i) = starts(i) + idx - 1;
end

% =========================================================================
% 4.  GLOBAL PERCENTILE THRESHOLD
% =========================================================================
% Use the last 'win_len_sec' seconds of the signal to compute a percentile
window_len = min(length(ecg), round(win_len_sec * fs));
recent_segment = ecg(end - window_len + 1 : end);
recent_percentile = prctile(recent_segment, perc);
base_thresh = height_thresh * recent_percentile;

% ---- Keep only candidates whose amplitude exceeds base threshold ----
valid = cand_amps > base_thresh;
cand_locs = cand_locs(valid);
cand_amps = cand_amps(valid);
if isempty(cand_locs)
    return;
end

% ---- Sort candidates by time (ascending) ----
[cand_locs, sort_idx] = sort(cand_locs);
cand_amps = cand_amps(sort_idx);

% =========================================================================
% 5.  STAGE 2 – RR‑ADAPTIVE ACCEPTANCE
% =========================================================================
% Pre‑allocate output arrays (maximum possible = number of candidates)
max_out = length(cand_locs);
qrs_i_raw = zeros(1, max_out);
qrs_amp_raw = zeros(1, max_out);
accepted_cnt = 0;

rr_history = zeros(1, 10);   % fixed‑size circular buffer
rr_cnt = 0;

for i = 1:length(cand_locs)
    current_time = cand_locs(i);
    current_amp  = cand_amps(i);

    % ---- Compute expected time from RR history ----
    if accepted_cnt >= 2 && rr_cnt >= 1
        median_rr = median(rr_history(1:rr_cnt));
        expected_time = qrs_i_raw(accepted_cnt) + median_rr;
        rr_deviation = abs(current_time - expected_time) / median_rr;
    else
        rr_deviation = NaN;
    end

    % ---- Adaptive threshold based on RR deviation ----
    if isnan(rr_deviation) || rr_deviation <= rr_tol
        adaptive_mult = low_factor;
    else
        adaptive_mult = high_factor;
    end
    adaptive_thresh = adaptive_mult * base_thresh;

    % ---- Refractory check (minimum distance) ----
    if accepted_cnt >= 1
        if (current_time - qrs_i_raw(accepted_cnt)) < min_dist
            continue;   % too close to previous beat – skip
        end
    end

    % ---- Final decision ----
    if current_amp > adaptive_thresh
        accepted_cnt = accepted_cnt + 1;
        qrs_i_raw(accepted_cnt) = current_time;
        qrs_amp_raw(accepted_cnt) = current_amp;

        % Update RR history (fixed‑size circular buffer)
        if accepted_cnt >= 2
            new_rr = qrs_i_raw(accepted_cnt) - qrs_i_raw(accepted_cnt - 1);
            if rr_cnt < 10
                rr_cnt = rr_cnt + 1;
                rr_history(rr_cnt) = new_rr;
            else
                % shift left, discard oldest
                rr_history(1:9) = rr_history(2:10);
                rr_history(10) = new_rr;
            end
        end
    end
end

% Trim outputs to the actual number of accepted beats
qrs_i_raw = qrs_i_raw(1:accepted_cnt);
qrs_amp_raw = qrs_amp_raw(1:accepted_cnt);

end