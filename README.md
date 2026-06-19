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

## Usage
- Data: Subject to PhysioNet terms of use
