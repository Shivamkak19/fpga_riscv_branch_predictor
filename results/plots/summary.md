# Predictor benchmark summary

## IPC

| benchmark | baseline | static-NT | BHT-1 | BHT-2 | GShare | BHT-2 + JAL | GShare + JAL | BHT-2 full | GShare full |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ubmark-bin-search | 0.7146 | 0.7146 | 0.8128 | 0.8208 | 0.7799 | 0.8454 | 0.8021 | 0.8454 | 0.8021 |
| ubmark-cmplx-mult | 0.7475 | 0.7475 | 0.9116 | 0.9116 | 0.9019 | 0.9121 | 0.9024 | 0.9121 | 0.9024 |
| ubmark-masked-filter | 0.6819 | 0.6819 | 0.9242 | 0.9222 | 0.9216 | 0.9223 | 0.9217 | 0.9224 | 0.9218 |
| ubmark-vvadd | 0.6986 | 0.6986 | 0.9914 | 0.9914 | 0.9665 | 0.9919 | 0.9670 | 0.9919 | 0.9670 |

## Mispredict rate (%)

| benchmark | branches | BHT-1 | BHT-2 | GShare |
|---|---:|---:|---:|---:|
| ubmark-bin-search | 276 | 23.19 | 20.65 | 34.06 |
| ubmark-cmplx-mult | 600 | 1.00 | 1.00 | 4.17 |
| ubmark-masked-filter | 1868 | 3.85 | 4.39 | 4.55 |
| ubmark-vvadd | 400 | 1.75 | 1.75 | 7.75 |
