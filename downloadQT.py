import wfdb
import os
import numpy as np
import requests
from concurrent.futures import ProcessPoolExecutor, as_completed
import time

OUTPUT_DIR = "qtdb-mat"
USE_ONE_BASED_INDICES = True
MAX_WORKERS = 4
RETRY_LIMIT = 2
SLEEP_BETWEEN_RETRIES = 2

BEAT_TYPES = "NLRBAaJSrFeVjnE/fQ?"
BEAT_SET = set(BEAT_TYPES)

MIN_RR_SAMPLES = 50

def load_annotation(rec):
    for ext in ["atr", "pu", "pu0", "pu1"]:
        try:
            return wfdb.rdann(rec, ext, pn_dir="qtdb")
        except:
            continue
    return None

def process_record(rec, retry=0):
    try:
        os.makedirs(OUTPUT_DIR, exist_ok=True)

        signals, _ = wfdb.rdsamp(rec, pn_dir="qtdb", channels=[0])
        ecg = signals[:, 0]

        ann = load_annotation(rec)
        if ann is None:
            return (rec, "NO_ANNOTATION", 0, 0)

        keep = np.array([sym in BEAT_SET for sym in ann.symbol], dtype=bool)
        qrs = ann.sample[keep]

        if len(qrs) > 0:
            filtered = [qrs[0]]
            for x in qrs[1:]:
                if (x - filtered[-1]) > MIN_RR_SAMPLES:
                    filtered.append(x)
            qrs = np.array(filtered, dtype=np.int32)

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
    url = "https://physionet.org/files/qtdb/1.0.0/RECORDS"

    r = requests.get(url, timeout=30)
    r.raise_for_status()
    all_records = r.text.strip().split()

    print(f"Total QTDB records: {len(all_records)}")

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

    print("QT Database download complete.")