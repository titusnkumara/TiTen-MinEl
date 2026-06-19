"""
Download all MIT-BIH Arrhythmia Database records,
save first channel (MLII) as .txt and QRS annotation indices as .txt
Output folder: mitdb-mat
"""

import wfdb
import os
import numpy as np

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------
output_dir = "mitdb-mat"
os.makedirs(output_dir, exist_ok=True)

# List of all 48 records (same as in the original MATLAB script)
records = [
    "100", "101", "102", "103", "104", "105", "106", "107", "108", "109",
    "111", "112", "113", "114", "115", "116", "117", "118", "119", "121",
    "122", "123", "124", "200", "201", "202", "203", "205", "207", "208",
    "209", "210", "212", "213", "214", "215", "217", "219", "220", "221",
    "222", "223", "228", "230", "231", "232", "233", "234"
]

# Beat types to be considered as true QRS complexes
# (same as the 'beatTypes' string in the original MATLAB script)
beat_types = "NLRBAaJSrFeVjnE/fQ?"
beat_set = set(beat_types)   # fast membership test

# Set to True if you want the annotation sample indices to be 1‑based (MATLAB style)
USE_ONE_BASED_INDICES = True    # MATLAB uses 1‑based; wfdb returns 0‑based

# ----------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------
for rec in records:
    print(f"Processing record {rec}...")

    # ---- 1. Read first channel (lead MLII) ----
    # 'channels=[0]' selects only the first channel (usually MLII)
    try:
        signals, fields = wfdb.rdsamp(rec, pn_dir="mitdb", channels=[0])
    except Exception as e:
        print(f"  ERROR: Could not load record {rec} - {e}")
        continue

    # signals is a 2D array with one column (since we asked for one channel)
    ecg_signal = signals[:, 0]          # shape (N,)

    # ---- 2. Read annotations and filter beat types ----
    try:
        ann = wfdb.rdann(rec, "atr", pn_dir="mitdb")
    except Exception as e:
        print(f"  ERROR: Could not load annotations for {rec} - {e}")
        continue

    # Filter: keep only annotation samples whose symbol is in beat_set
    keep = [sym in beat_set for sym in ann.symbol]
    qrs_indices = ann.sample[keep]      # 0‑based indices as returned by wfdb

    # Optionally convert to 1‑based (MATLAB style)
    if USE_ONE_BASED_INDICES:
        qrs_indices = qrs_indices + 1

    # ---- 3. Write ECG signal to .txt (one value per line) ----
    # We'll write with 8 decimal places (sufficient for mV precision)
    sig_file = os.path.join(output_dir, f"{rec}.txt")
    np.savetxt(sig_file, ecg_signal, fmt="%.8f")
    print(f"  Saved {len(ecg_signal)} samples to {sig_file}")

    # ---- 4. Write annotation indices to .txt (one index per line) ----
    ann_file = os.path.join(output_dir, f"{rec}-ann.txt")
    np.savetxt(ann_file, qrs_indices, fmt="%d")
    print(f"  Saved {len(qrs_indices)} QRS annotations to {ann_file}")

print("\nAll records processed successfully.")