import os
import time
import requests
import numpy as np
import wfdb
from concurrent.futures import ProcessPoolExecutor, as_completed

# ========================= CONFIGURATION =========================
OUTPUT_DIR = "nsrdb-mat"
USE_ONE_BASED_INDICES = True       # 1‑based indices (like original TWA script)
MAX_WORKERS = 4
RETRY_LIMIT = 2
SLEEP_BETWEEN_RETRIES = 2
# =================================================================

# Beat types to keep: 'N' = normal beat (most common in NSRDB)
# You can add other types if needed, e.g., 'V', 'A', etc.
BEAT_TYPES = "N"
BEAT_SET = set(BEAT_TYPES)


def load_annotation(record_name):
    """Load annotation from the .atr file (NSRDB uses reference annotations)."""
    try:
        ann = wfdb.rdann(record_name, 'atr', pn_dir='nsrdb')
        return ann
    except Exception:
        return None


def process_record(record_name, retry=0):
    try:
        os.makedirs(OUTPUT_DIR, exist_ok=True)

        # Read only the first channel (original sampling rate 128 Hz)
        signals, _ = wfdb.rdsamp(record_name, pn_dir='nsrdb', channels=[0])
        ecg = signals[:, 0]

        ann = load_annotation(record_name)
        if ann is None or len(ann.sample) == 0:
            return (record_name, "NO_ANNOTATION", 0, 0)

        # ---- Beat type filtering (keep only those in BEAT_SET) ----
        keep = np.array([sym in BEAT_SET for sym in ann.symbol], dtype=bool)
        qrs = ann.sample[keep]

        # No RR filtering (keep all filtered beats as they are)
        # No additional processing

        if USE_ONE_BASED_INDICES:
            qrs = qrs + 1

        base = os.path.join(OUTPUT_DIR, record_name)
        np.savetxt(f"{base}.txt", ecg, fmt="%.8f")
        np.savetxt(f"{base}-ann.txt", qrs, fmt="%d")

        return (record_name, "OK", len(ecg), len(qrs))

    except Exception as e:
        if retry < RETRY_LIMIT:
            time.sleep(SLEEP_BETWEEN_RETRIES)
            return process_record(record_name, retry + 1)
        return (record_name, f"ERROR after {RETRY_LIMIT+1} tries: {e}", 0, 0)


if __name__ == "__main__":
    url = "https://physionet.org/files/nsrdb/1.0.0/RECORDS"
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    all_records = resp.text.strip().split()

    print(f"Total NSRDB records: {len(all_records)}")

    missing = []
    for rec in all_records:
        sig_file = os.path.join(OUTPUT_DIR, f"{rec}.txt")
        ann_file = os.path.join(OUTPUT_DIR, f"{rec}-ann.txt")
        if not (os.path.exists(sig_file) and os.path.exists(ann_file)):
            missing.append(rec)

    if not missing:
        print("All records already downloaded.")
        exit(0)

    print(f"Missing records: {len(missing)}")
    print(f"Processing with {MAX_WORKERS} workers (retries={RETRY_LIMIT})...")

    with ProcessPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {executor.submit(process_record, rec): rec for rec in missing}
        for future in as_completed(futures):
            rec, status, n_samp, n_qrs = future.result()
            if status == "OK":
                print(f"✔ {rec}: {n_samp} samples, {n_qrs} beats")
            else:
                print(f"✘ {rec}: {status}")

    print("NSRDB download complete.")