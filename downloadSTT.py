#!/usr/bin/env python3
"""
Download and export the European ST-T Database (EDB) from PhysioNet.

This script uses the wfdb library to fetch the 90 two-hour recordings,
saves the two ECG leads as a .txt file (two columns) and the QRS beat
locations as a separate -ann.txt file.
"""

import os
import time
import wfdb
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed

# ======================= CONFIGURATION =======================
OUTPUT_DIR = "edb-mat"               # output folder for .txt files
USE_ONE_BASED_INDICES = True         # True: MATLAB/Julia style (1‑based), False: Python/C style (0‑based)
MAX_WORKERS = 4                      # number of parallel downloads/processes
RETRY_LIMIT = 2                      # retry attempts on error
SLEEP_BETWEEN_RETRIES = 2            # seconds between retries

# PhysioNet database identifier
DB_NAME = "edb"                      # European ST-T Database on PhysioNet

# ======================= GET RECORD NAMES =======================
def get_record_list():
    """
    Retrieve the list of record names for the EDB.
    First tries to read the local RECORDS file; if not present,
    downloads it from PhysioNet.
    """
    records_file = "RECORDS"
    if not os.path.exists(records_file):
        # Download the RECORDS file from PhysioNet
        url = "https://physionet.org/files/edb/1.0.0/RECORDS"
        import urllib.request
        try:
            urllib.request.urlretrieve(url, records_file)
            print(f"Downloaded {records_file}")
        except Exception as e:
            print(f"Failed to download RECORDS: {e}")
            return None
    with open(records_file, 'r') as f:
        records = [line.strip() for line in f if line.strip()]
    return records

# ======================= LOAD ANNOTATIONS =======================
def load_beat_annotations(record_name):
    """
    Load the reference .atr annotation file and return only the sample
    indices of heart beats (any symbol that is not a comment/st change).
    """
    ann = wfdb.rdann(record_name, 'atr', pn_dir=DB_NAME)
    # beat symbols in EDB are typical WFDB beat codes (N, V, /, f, etc.)
    # We keep all annotations that are not auxiliary symbols (e.g., (STC, (TWC)
    # or comment symbols like +, -, etc.). A simple approach: keep samples
    # whose symbol is not in a set of special markers.
    # In EDB, beat annotations are single letters or digits; ST/T events are
    # multi‑character codes enclosed in parentheses.
    beat_mask = [not (sym.startswith('(') or sym in ('+', '-', '|', '~')) for sym in ann.symbol]
    beat_samples = ann.sample[beat_mask]
    return beat_samples

# ======================= PROCESS ONE RECORD =======================
def process_record(rec, retry=0):
    """Load ECG signals and beat annotations for one record, save to text files."""
    try:
        os.makedirs(OUTPUT_DIR, exist_ok=True)

        # Load both ECG channels (channels 0 and 1)
        signals, _ = wfdb.rdsamp(rec, pn_dir=DB_NAME, channels=[0, 1])
        ecg = signals  # shape (N, 2)

        # Get beat locations
        beat_samples = load_beat_annotations(rec)

        if USE_ONE_BASED_INDICES:
            beat_samples = beat_samples + 1

        # Output files
        sig_out = os.path.join(OUTPUT_DIR, f"{rec}.txt")
        ann_out = os.path.join(OUTPUT_DIR, f"{rec}-ann.txt")

        # Save ECG (two columns, floating point)
        np.savetxt(sig_out, ecg, fmt="%.8f", delimiter='\t')

        # Save QRS indices (integers, one per line)
        np.savetxt(ann_out, beat_samples, fmt="%d")

        return (rec, "OK", ecg.shape[0], len(beat_samples))

    except Exception as e:
        if retry < RETRY_LIMIT:
            time.sleep(SLEEP_BETWEEN_RETRIES)
            return process_record(rec, retry + 1)
        return (rec, f"ERROR after {RETRY_LIMIT+1} tries: {e}", 0, 0)

# ======================= MAIN =======================
if __name__ == "__main__":
    print(f"=== European ST-T Database (EDB) export ===")
    records = get_record_list()
    if not records:
        print("No record names found. Exiting.")
        exit(1)

    print(f"Total records in EDB: {len(records)}")

    # Check which records are already processed
    missing = []
    for rec in records:
        sig_file = os.path.join(OUTPUT_DIR, f"{rec}.txt")
        ann_file = os.path.join(OUTPUT_DIR, f"{rec}-ann.txt")
        if not (os.path.exists(sig_file) and os.path.exists(ann_file)):
            missing.append(rec)

    if not missing:
        print("All records have already been exported.")
        exit(0)

    print(f"Records to process: {len(missing)}")
    print(f"Using up to {MAX_WORKERS} parallel workers (retries = {RETRY_LIMIT})...")

    with ProcessPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {executor.submit(process_record, rec): rec for rec in missing}
        for future in as_completed(futures):
            rec, status, n_samp, n_qrs = future.result()
            if status == "OK":
                print(f"✔ {rec}: {n_samp} samples, {n_qrs} beats")
            else:
                print(f"✘ {rec}: {status}")

    print("Export finished.")