# Predictor benchmark summary

## IPC

| benchmark | baseline | static-NT | BHT-1 | BHT-2 | GShare | BHT-2 + JAL | GShare + JAL | BHT-2 full | GShare full |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ubmark-bin-search | 0.7203 | 0.7203 | 0.8059 | 0.8149 | 0.7847 | 0.8426 | 0.8104 | 0.8426 | 0.8104 |
| ubmark-cmplx-mult | 0.7255 | 0.7255 | 0.7392 | 0.7392 | 0.7348 | 0.7395 | 0.7351 | 0.7395 | 0.7351 |
| ubmark-masked-filter | 0.7818 | 0.7818 | 0.8442 | 0.8568 | 0.8515 | 0.8917 | 0.8859 | 0.8918 | 0.8861 |
| ubmark-vvadd | 0.9618 | 0.9618 | 0.9912 | 0.9912 | 0.9577 | 0.9912 | 0.9577 | 0.9912 | 0.9577 |

## Mispredict rate (%)

| benchmark | branches | BHT-1 | BHT-2 | GShare |
|---|---:|---:|---:|---:|
| ubmark-bin-search | 246 | 23.98 | 21.14 | 30.89 |
| ubmark-cmplx-mult | 27 | 11.11 | 11.11 | 37.04 |
| ubmark-masked-filter | 668 | 14.37 | 7.93 | 10.63 |
| ubmark-vvadd | 10 | 20.00 | 20.00 | 100.00 |
