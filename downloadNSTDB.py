import wfdb
import os
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed
import time

OUTPUT_DIR = "nstdb-mat"
USE_ONE_BASED_INDICES = True
MAX_WORKERS = 2
RETRY_LIMIT = 2
SLEEP_BETWEEN_RETRIES = 2

# Generate the list of records
all_records = [
    "118e00", "118e06", "118e12", "118e18", "118e24", "118e_6",
    "119e00", "119e06", "119e12", "119e18", "119e24", "119e_6"
]

def load_annotation(rec):
    for ext in ["atr"]:
        try:
            return wfdb.rdann(rec, ext, pn_dir="nstdb")
        except:
            continue
    return None

def process_record(rec, retry=0):
    try:
        os.makedirs(OUTPUT_DIR, exist_ok=True)

        # Load only the first channel
        signals, _ = wfdb.rdsamp(rec, pn_dir="nstdb", channels=[0])
        ecg = signals[:, 0]

        ann = load_annotation(rec)
        if ann is None:
            return (rec, "NO_ANNOTATION", 0, 0)

        # Use all beats (no filtering for NSTDB)
        qrs = ann.sample

        if USE_ONE_BASED_INDICES:
            qrs = qrs + 1

        np.savetxt(os.path.join(OUTPUT_DIR, f"{rec}.txt"), ecg, fmt="%.8f")
        np.savetxt(os.path.join(OUTPUT_DIR, f"{rec}-ann.txt"), qrs, fmt="%d")

        return (rec, "OK", len(ecg), len(qrs))

    except Exception as e:
        if retry < RETRY_LIMIT:
            time.sleep(SLEEP_BETWEEN_RETRIES)
            return process_record(rec, retry + 1)
        return (rec, f"ERROR after {RETRY_LIMIT+1} tries: {e}", 0, 0)

if __name__ == "__main__":
    print(f"Total NSTDB records: {len(all_records)}")

    missing_records = []
    for rec in all_records:
        sig_file = os.path.join(OUTPUT_DIR, f"{rec}.txt")
        ann_file = os.path.join(OUTPUT_DIR, f"{rec}-ann.txt")
        if not (os.path.exists(sig_file) and os.path.exists(ann_file)):
            missing_records.append(rec)

    if not missing_records:
        print("All records already downloaded.")
        exit(0)

    print(f"Missing records: {len(missing_records)}")
    print(f"Processing with {MAX_WORKERS} workers (retries={RETRY_LIMIT})...")

    with ProcessPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {executor.submit(process_record, rec): rec for rec in missing_records}

        for future in as_completed(futures):
            rec, status, n_samp, n_qrs = future.result()
            if status == "OK":
                print(f"✔ {rec}: {n_samp} samples, {n_qrs} beats")
            else:
                print(f"✘ {rec}: {status}")

    print("NSTDB download complete.")