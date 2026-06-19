function [qrs_i_raw, qrs_amp_raw] = TiTen(ecg, fs)
% TiTen QRS detector – optimised for 10 Hz ECG (min‑max downsampled)
%   Default parameters maximise F1 on MIT‑DB, QT‑DB and NST‑DB (165 records).
%
%   Input:
%     ecg : column vector of pre‑processed ECG (bandpass filtered)
%     fs  : sampling frequency in Hz (10 Hz for best performance)
%
%   Output:
%     qrs_i_raw   : indices of detected QRS complexes in the input signal
%     qrs_amp_raw : corresponding amplitudes

% =========================================================================
% 1.  PARAMETERS (tuned for 10 Hz) – all values match the original exactly
% =========================================================================
integration_window   = 2;        % 0.20 s – moving average for squared ECG
min_peak_distance    = 3;        % 0.30 s – minimum separation between candidates
init_signal_fraction = 0.101;    % initial threshold scaling (signal)
signal_smoothing     = 0.1090;   % signal level smoothing factor
searchback_multiplier= 1.66;     % searchback window multiplier
threshold_fraction   = 0.197;    % fraction for adaptive threshold calculation
rr_low_bound         = 0.733;    % lower bound for RR adaptation
rr_high_bound        = 1.089;    % upper bound for RR adaptation
rr_start_beats       = 14;       % number of beats before RR adaptation kicks in

% Fixed constants (do not change unless you really know what you're doing)
peak_search_window   = 2;        % 0.20 s – raw ECG peak search radius
searchback_guard     = 2;        % 0.20 s – guard interval before searchback
init_noise_fraction  = 0.5;      % initial noise threshold fraction
noise_smoothing      = 0.125;    % noise level smoothing factor
noise_memory         = 1 - noise_smoothing;
searchback_sig_alpha = 0.25;     % searchback signal smoothing
searchback_sig_memory= 1 - searchback_sig_alpha;
noise_threshold_frac = 0.5;      % noise threshold = fraction of signal threshold
rr_halving_factor    = 0.5;      % factor to halve thresholds on abnormal RR
rr_buffer_len        = 8;        % number of recent RR intervals for mean
signal_memory        = 1 - signal_smoothing;

% =========================================================================
% 2.  PREPROCESSING – squared ECG + moving‑average integration
% =========================================================================
ecg = ecg(:);                                     % ensure column vector
ecg_squared = ecg .^ 2;
integrated_signal = conv(ecg_squared, ones(1, integration_window) / integration_window, 'full');

% =========================================================================
% 3.  FIND CANDIDATE PEAKS (with minimum distance constraint)
% =========================================================================
[candidate_peaks, candidate_locs] = findpeaks_minpeakdistance_fast(integrated_signal, min_peak_distance);
if isempty(candidate_peaks)
    qrs_i_raw = [];
    qrs_amp_raw = [];
    return;
end
num_candidates = length(candidate_peaks);

% =========================================================================
% 4.  INITIALISE THRESHOLDS AND DETECTION BUFFERS
% =========================================================================
init_len = min(20, length(integrated_signal));

% ---- thresholds for integrated signal (beat presence) ----
signal_threshold   = max(integrated_signal(1:init_len)) * init_signal_fraction;
noise_threshold    = mean(integrated_signal(1:init_len)) * init_noise_fraction;
signal_level       = signal_threshold;
noise_level        = noise_threshold;

% ---- thresholds for raw ECG (amplitude extraction) ----
signal_threshold_raw = max(ecg(1:init_len)) * init_signal_fraction;
noise_threshold_raw  = mean(ecg(1:init_len)) * init_noise_fraction;
signal_level_raw     = signal_threshold_raw;
noise_level_raw      = noise_threshold_raw;

% ---- counters and arrays (pre‑allocate) ----
beat_counter         = 0;          % number of beats detected in integrated domain
beat_counter_raw     = 0;          % number of beats stored in raw domain
qrs_integrated       = zeros(1, 2 * num_candidates);
qrs_raw_indices      = zeros(1, 2 * num_candidates);
qrs_raw_amplitudes   = zeros(1, 2 * num_candidates);
mean_rr_interval     = 0;          % current mean RR
selected_mean_rr     = 0;          % mean RR used for searchback (only valid intervals)

% =========================================================================
% 5.  MAIN DETECTION LOOP – process each candidate peak
% =========================================================================
for idx = 1:num_candidates

    % ---- 5a. RR adaptation (once enough beats are collected) ----
    if beat_counter >= rr_start_beats
        start_idx = max(1, beat_counter - rr_buffer_len);
        recent_rrs = diff(qrs_integrated(start_idx:beat_counter));
        mean_rr_interval = mean(recent_rrs);
        current_rr = qrs_integrated(beat_counter) - qrs_integrated(beat_counter - 1);
        if (current_rr <= rr_low_bound * mean_rr_interval) || ...
           (current_rr >= rr_high_bound * mean_rr_interval)
            signal_threshold     = rr_halving_factor * signal_threshold;
            signal_threshold_raw = rr_halving_factor * signal_threshold_raw;
        else
            selected_mean_rr = mean_rr_interval;   % only update on normal RR
        end
    end

    % ---- 5b. Searchback (recover missed beats after a long pause) ----
    if (selected_mean_rr > 0) && (beat_counter > 0)
        expected_interval = round(searchback_multiplier * selected_mean_rr);
        if (candidate_locs(idx) - qrs_integrated(beat_counter)) >= expected_interval
            search_start = qrs_integrated(beat_counter) + searchback_guard;
            search_end   = candidate_locs(idx) - searchback_guard;
            if (search_start < search_end) && ...
               (search_start >= 1) && (search_end <= length(integrated_signal))
                [peak_val, peak_idx] = max(integrated_signal(search_start:search_end));
                peak_idx = search_start + peak_idx - 1;
                if peak_val > noise_threshold
                    % Accept as a missed beat
                    beat_counter = beat_counter + 1;
                    qrs_integrated(beat_counter) = peak_idx;

                    % Extract raw ECG amplitude around this point
                    left_raw  = max(1, peak_idx - peak_search_window);
                    right_raw = min(length(ecg), peak_idx);
                    [amp_raw, idx_raw] = max(ecg(left_raw:right_raw));
                    idx_raw = left_raw + idx_raw - 1;

                    if amp_raw > noise_threshold_raw
                        beat_counter_raw = beat_counter_raw + 1;
                        qrs_raw_indices(beat_counter_raw)    = idx_raw;
                        qrs_raw_amplitudes(beat_counter_raw) = amp_raw;
                        signal_level_raw = searchback_sig_alpha * amp_raw + ...
                                           searchback_sig_memory * signal_level_raw;
                    end
                    signal_level = searchback_sig_alpha * peak_val + ...
                                   searchback_sig_memory * signal_level;
                end
            end
        end
    end

    % ---- 5c. Normal detection ----
    if candidate_peaks(idx) >= signal_threshold
        % Extract raw amplitude around the candidate location
        left_raw  = max(1, candidate_locs(idx) - peak_search_window);
        right_raw = min(length(ecg), candidate_locs(idx));
        [amp_raw, idx_raw] = max(ecg(left_raw:right_raw));
        idx_raw = left_raw + idx_raw - 1;

        % Artefact rejection: check for unusually wide complexes
        skip_beat = false;
        if beat_counter >= 3
            % Count samples backward while integrated signal stays above half threshold
            backward_width = 1;
            for k = candidate_locs(idx)-1 : -1 : max(1, candidate_locs(idx)-10)
                if integrated_signal(k) < 0.5 * signal_threshold
                    break;
                end
                backward_width = backward_width + 1;
            end
            forward_width = 1;
            for k = candidate_locs(idx)+1 : min(length(integrated_signal), candidate_locs(idx)+10)
                if integrated_signal(k) < 0.5 * signal_threshold
                    break;
                end
                forward_width = forward_width + 1;
            end
            if (backward_width > 3) && (forward_width > 3)
                skip_beat = true;
                % Treat as noise and update noise levels
                noise_level_raw = noise_smoothing * amp_raw + noise_memory * noise_level_raw;
                noise_level     = noise_smoothing * candidate_peaks(idx) + ...
                                  noise_memory * noise_level;
            end
        end

        if ~skip_beat
            beat_counter = beat_counter + 1;
            qrs_integrated(beat_counter) = candidate_locs(idx);

            if amp_raw >= signal_threshold_raw
                beat_counter_raw = beat_counter_raw + 1;
                qrs_raw_indices(beat_counter_raw)    = idx_raw;
                qrs_raw_amplitudes(beat_counter_raw) = amp_raw;
                signal_level_raw = signal_smoothing * amp_raw + signal_memory * signal_level_raw;
            end
            signal_level = signal_smoothing * candidate_peaks(idx) + ...
                           signal_memory * signal_level;
        end

    elseif candidate_peaks(idx) >= noise_threshold
        % Between noise and signal – update noise level
        left_raw  = max(1, candidate_locs(idx) - peak_search_window);
        right_raw = min(length(ecg), candidate_locs(idx));
        [amp_raw, ~] = max(ecg(left_raw:right_raw));
        noise_level_raw = noise_smoothing * amp_raw + noise_memory * noise_level_raw;
        noise_level     = noise_smoothing * candidate_peaks(idx) + noise_memory * noise_level;

    else
        % Below noise threshold – also update noise level
        left_raw  = max(1, candidate_locs(idx) - peak_search_window);
        right_raw = min(length(ecg), candidate_locs(idx));
        [amp_raw, ~] = max(ecg(left_raw:right_raw));
        noise_level_raw = noise_smoothing * amp_raw + noise_memory * noise_level_raw;
        noise_level     = noise_smoothing * candidate_peaks(idx) + noise_memory * noise_level;
    end

    % ---- 5d. Update adaptive thresholds after each candidate ----
    if (noise_level ~= 0) || (signal_level ~= 0)
        signal_threshold = noise_level + threshold_fraction * (signal_level - noise_level);
        noise_threshold  = noise_threshold_frac * signal_threshold;
    end
    if (noise_level_raw ~= 0) || (signal_level_raw ~= 0)
        signal_threshold_raw = noise_level_raw + threshold_fraction * (signal_level_raw - noise_level_raw);
        noise_threshold_raw  = noise_threshold_frac * signal_threshold_raw;
    end

end % for idx

% =========================================================================
% 6.  TRIM OUTPUT ARRAYS TO ACTUAL DETECTIONS
% =========================================================================
qrs_i_raw   = qrs_raw_indices(1:beat_counter_raw);
qrs_amp_raw = qrs_raw_amplitudes(1:beat_counter_raw);

end % function TiTen

% =========================================================================
% HELPER FUNCTION: Fast peak finder with minimum distance constraint
% =========================================================================
function [pks, locs] = findpeaks_minpeakdistance_fast(x, minDist)
    x = x(:);
    left  = x(1:end-2);
    mid   = x(2:end-1);
    right = x(3:end);
    isLocalMax = (mid > left) & (mid > right);
    allLocs = find(isLocalMax) + 1;
    allPks  = x(allLocs);
    if isempty(allLocs)
        pks = [];
        locs = [];
        return;
    end
    [~, sortIdx] = sort(allPks, 'descend');
    sortedLocs = allLocs(sortIdx);
    sortedPks  = allPks(sortIdx);
    keep = true(size(sortedLocs));
    for i = 1:length(sortedLocs)
        if keep(i)
            tooClose = (abs(sortedLocs - sortedLocs(i)) < minDist);
            tooClose(1:i) = false;
            keep = keep & ~tooClose;
        end
    end
    locs = sortedLocs(keep);
    pks  = sortedPks(keep);
    [locs, order] = sort(locs);
    pks = pks(order);
end % findpeaks_minpeakdistance_fast