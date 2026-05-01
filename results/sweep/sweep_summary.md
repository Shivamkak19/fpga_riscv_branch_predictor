# Predictor parameter sweep

## BHT-2 mispredict rate (%) vs table size

| benchmark | idx=5 | idx=6 | idx=7 | idx=8 | idx=9 | idx=10 |
|---|---:|---:|---:|---:|---:|---:|
| ubmark-bin-search | 20.29 | 20.65 | 20.65 | 20.65 | 20.65 | 20.65 |
| ubmark-cmplx-mult | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| ubmark-masked-filter | 4.39 | 4.39 | 4.39 | 4.39 | 4.39 | 4.39 |
| ubmark-vvadd | 1.75 | 1.75 | 1.75 | 1.75 | 1.75 | 1.75 |

## GShare mispredict rate (%) — mean over 4 ubmarks

| HIST_BITS \ INDEX_BITS | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---:|---:|---:|---:|---:|---:|
| hist=4 | - | 9.25 | - | 9.45 | - | 9.45 |
| hist=8 | - | 10.38 | - | 12.63 | - | 12.63 |
| hist=12 | - | 10.38 | - | 12.63 | - | 14.23 |
