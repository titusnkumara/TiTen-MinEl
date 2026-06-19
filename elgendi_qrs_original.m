function [qrs_amp_raw, qrs_i_raw, delay] = elgendi_qrs(ekg, fs, ~)
% ELGENDI_QRS  Strict implementation of Elgendi 2013 from GitHub.
%   [QRS_AMP, QRS_IDX, DELAY] = ELGENDI_QRS(ECG, FS) 
%   Returns R‑peak indices (samples) and amplitudes (from original ECG).
%   Third input ignored.

    delay = 0;
    qrs_i_raw = [];
    qrs_amp_raw = [];

    N = length(ekg);
    Blockofinterest = zeros(1, N);

    % ----- 1. Bandpass filter 8–20 Hz (3rd order) -----
    if(fs>41)
        nyq = fs / 2;
        [bw, aw] = butter(3, [8, 20] / nyq, 'bandpass');
        ekg_filtered = filtfilt(bw, aw, ekg);
    else
        ekg_filtered = ekg;
    end

    % ----- 2. Square -----
    ekg_sqr = ekg_filtered .^ 2;

    % ----- 3. Moving averages (causal, using conv) -----
    win_qrs = round(0.097 * fs);   % 97 ms
    win_beat = round(0.611 * fs);  % 611 ms
    win_qrs = max(win_qrs, 1);
    win_beat = max(win_beat, 1);

    matrix_qrs = ones(1, win_qrs) / win_qrs;
    matrix_beat = ones(1, win_beat) / win_beat;

    ma_qrs = conv(ekg_sqr, matrix_qrs, 'same');
    ma_beat = conv(ekg_sqr, matrix_beat, 'same');

    % ----- 4. Adaptive threshold -----
    z = mean(ekg_sqr);
    beta = 0.08;               % NOTE: original uses 0.08, not 0.8
    alfa = beta * z;
    THR1 = ma_beat + alfa;

    % ----- 5. Blocks of interest -----
    Blockofinterest = (ma_qrs > THR1);   % 0/1, but original used 0.1

    % ----- 6. Find start and end indices of blocks -----
    a = zeros(1, N);
    b = zeros(1, N);
    w1 = 1;
    w2 = 1;

    for j = 1:N
        if j == 1 && Blockofinterest(1) == 1
            a(1) = 1;
            w1 = w1 + 1;
        end
        if j == N
            if Blockofinterest(j) == 1
                b(w2) = j;
            end
        else
            if Blockofinterest(j) == 0 && Blockofinterest(j+1) == 1
                a(w1) = j+1;
                w1 = w1 + 1;
            end
            if Blockofinterest(j) == 1 && Blockofinterest(j+1) == 0
                b(w2) = j;
                w2 = w2 + 1;
            end
        end
    end

    a(a == 0) = [];
    b(b == 0) = [];

    if isempty(a) || isempty(b)
        return;
    end

    % ----- 7. Block lengths -----
    Blocks = b - a + 1;
    THR2 = win_qrs;   % minimum block length (97 ms)

    % ----- 8. Candidate R peaks (using filtered ECG, not squared) -----
    x = [];
    w4 = 1;
    for i = 1:length(a)
        if Blocks(i) >= THR2
            [~, x_i_index] = max(ekg_filtered(a(i):b(i)));
            x_i_index = x_i_index + a(i) - 1;
            if isempty(x)
                x(w4) = x_i_index;
                w4 = w4 + 1;
            elseif abs(x_i_index - x(w4-1)) > round(0.3 * fs)   % 300 ms refractory
                x(w4) = x_i_index;
                w4 = w4 + 1;
            end
        end
    end

    x(x == 0) = [];

    % ----- 9. Refinement: search ±30 ms around each candidate for true max -----
    x_kon = [];
    for i = 1:length(x)
        begin_idx = max(1, x(i) - round(0.03 * fs));
        end_idx = min(N, x(i) + round(0.03 * fs));
        [~, q1_index] = max(ekg(begin_idx:end_idx));   % max of **original** ECG
        q1_index = q1_index + begin_idx - 1;
        x_kon = [x_kon, q1_index];
    end

    % ----- 10. Output -----
    qrs_i_raw = x_kon(:);
    qrs_amp_raw = ekg(qrs_i_raw);
end