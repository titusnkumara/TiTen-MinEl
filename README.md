# Data Preparation for QRS Detection Benchmark

This repository provides Python scripts to download and preprocess six standard PhysioNet ECG databases for use with the MATLAB evaluation pipeline (MinEl / TiTen QRS detection benchmark).

## Databases Supported

| Database | Script | Records | Native Fs (Hz) | Output Directory |
|-----------|----------|:-------:|:--------------:|------------------|
| MIT-BIH Arrhythmia (MITDB) | `downloadMITBIH.py` | 48 | 360 | `mitdb-mat/` |
| QT Database (QTDB) | `downloadQT.py` | 105 | 250 | `qtdb-mat/` |
| Noise Stress Test (NSTDB) | `downloadNSTDB.py` | 12 | 360 | `nstdb-mat/` |
| European ST-T (EDB) | `downloadSTT.py` | 90 | 250 | `edb-mat/` |
| Normal Sinus Rhythm (NSRDB) | `downloadNSRDB.py` | 18 | 128 | `nsrdb-mat/` |
| T-Wave Alternans (TWADB) | `downloadTWADB.py` | 100 | 500 | `twadb-mat/` |
| **Total** | | **373** | — | |

## Requirements

```bash
pip install wfdb numpy requests
```

Python 3.6+

## Usage

```bash
# Download a single database
python downloadMITBIH.py
python downloadQT.py
python downloadNSTDB.py
python downloadSTT.py
python downloadNSRDB.py
python downloadTWADB.py

# Download all
for script in download*.py; do python $script; done
```

## Configuration

Edit the variables at the top of each script:

```python
MAX_WORKERS = 4
RETRY_LIMIT = 2
USE_ONE_BASED_INDICES = True
```

- `MAX_WORKERS` – number of parallel processes
- `RETRY_LIMIT` – retries on failure
- `USE_ONE_BASED_INDICES` – 1-based annotation indices (MATLAB style)

Scripts automatically skip records that already have both `.txt` and `-ann.txt` files.

## Output Format

### Signal Files (`{rec}.txt`)

- Single-lead (first channel only)
- One sample per line, floating-point (`%.8f`)
- EDB exports two tab-separated columns; MATLAB uses the first column only

### Annotation Files (`{rec}-ann.txt`)

- 1-based indices (MATLAB style)
- One QRS location per line, integer format

## Annotation Filtering

Only genuine QRS complexes are retained.

| Database | Filtering Applied |
|-----------|------------------|
| MITDB | Beat types: `NLRBAaJSrFeVjnE/fQ?` |
| QTDB | Same as MITDB + RR-refractory (50 samples) |
| NSTDB | None (all annotations kept) |
| EDB | Excludes `(` `)` markers and `+ - \| ~` |
| NSRDB | Only `N` (normal) beats |
| TWADB | RR-refractory (50 samples) only |

The same filtered ground truth is used for both native and pipeline evaluations in MATLAB.

## MATLAB Compatibility

Output directories match the MATLAB `dataDir` variable.

For NSRDB, the script exports data at 128 Hz; MATLAB resamples to 130 Hz and converts annotation indices accordingly.

## MATLAB Usage Guide for QRS Detection Pipeline

This repository includes MATLAB scripts for training (optimising) the two adapted detectors (MinEl and TiTen) and for evaluating them on any of the six databases.

### Prerequisites
- MATLAB R2020a or newer.
- Signal Processing Toolbox (for `filtfilt`, `butter`).
- Parallel Computing Toolbox (optional, but recommended for speed; scripts use `parfor`).
- The Python scripts must have been run first to generate the `.txt` files in the expected directories (see the table above).

### Training / Optimisation
Two separate optimisation scripts are provided – one for each detector. They use mixed‑integer surrogate optimisation (`surrogateopt`) on a combined training corpus (MITDB + QTDB + NSTDB) to find the best parameters.

#### A) Optimise Elgendi (MinEl)
- **File**: `OptimizeElgendiAllrecords.mlx`
- **What it does**:
  - Loads the training databases (`'qtdb'`, `'mitdb'`, `'nstdb'`).
  - Applies bandpass filter (8–25 Hz) and min‑max extrema extraction to 10 Hz.
  - Uses `surrogateopt` to maximise F1 over 11 parameters.
- **How to run**:
  1. Open `OptimizeElgendiAllrecords.mlx` in MATLAB.
  2. Ensure the `.txt` files for MITDB, QTDB, and NSTDB are present in `mitdb-mat/`, `qtdb-mat/`, `nstdb-mat/`.
  3. Run the script. It will take several minutes (500 function evaluations).
  4. The best parameters will be printed in the command window at the end.

#### B) Optimise Pan‑Tompkins (TiTen)
- **File**: `OptimizePanTompkinsAllRecords.mlx`
- **What it does**: same workflow but for the TiTen detector (bandpass 8–36 Hz, adapted Pan‑Tompkins).
- **How to run**: same as above.

> **Note**: If you only want to use the optimised parameters reported in the paper, you can skip training and directly use the evaluation script with the default parameters (which are already set to the optimised values).

### Evaluation
The main evaluation script is where you set the database and algorithm at the top. It computes both native‑rate and 10‑Hz pipeline performance and compares them.

#### File: `EvaluateAllChunks.mlx`

#### Setup
At the top of the script, modify these two variables:
- `database` – choose one of: `'mitdb'`, `'qtdb'`, `'nstdb'`, `'edb'`, `'twadb'`, `'nsrdb'`.
- `algorithm` – choose either `'elgendi'` or `'pan-tompkins'`.

The script automatically selects the correct `dataDir`, `Fs_orig`, record list, and divisor based on the database.

#### What the evaluation does
1. **Native baseline**: Runs the chosen algorithm on the raw (native‑rate) ECG signal and evaluates using the same annotation files.
2. **Pipeline**: Chunks the signal into 40‑minute pseudo‑records, applies bandpass filter, extracts min/max extrema (10 Hz), runs the adapted detector (MinEl or TiTen), maps detections back to original samples, and evaluates.
3. **Comparison**: Provides global F1, sensitivity, precision, timing jitter, throughput, per‑record F1, and a statistical comparison (Wilcoxon signed‑rank test with 95% CI for ΔF1).

#### Parameters you can adjust
- `tol_ms = 150` – matching tolerance (milliseconds).
- `chunk_duration_sec = 40 * 60` – pseudo‑record length (change if needed).
- `AMP_THRESH = 0.05` – minimum amplitude (mV) for a detection to be kept.

### Adding a New Database
If you want to add a new database:
- Add a new `elseif` block in the database parameter section (defining `dataDir`, `Fs_orig_native`, record list, `resample_required`, and the divisor).
- The divisor must be chosen so that `Fs_orig / divisor` equals 10 (or your target Fs).
- Ensure your Python export script outputs the same format (`.txt` and `-ann.txt`).

### Typical Workflow
1. Run the Python scripts to download and export the databases.
2. (Optional) Run the optimisation scripts to obtain parameters for your own training set, or use the pre‑optimised values in the evaluation script.
3. Run the evaluation script for each database and algorithm combination to reproduce the results in the paper.

### Notes
- The optimisation scripts use the same preprocessing (bandpass + min‑max) as the evaluation pipeline, so the results are directly comparable.
- For large databases (EDB, NSRDB), evaluation may take several minutes. NSRDB may take more than 1 hour with Pan-Tompkins; optimisation will take longer.

## Usage
- Data: Subject to PhysioNet terms of use
