# Predictor benchmark summary

## IPC

| benchmark | baseline | static-NT | BHT-1 | BHT-2 | GShare | BHT-2 + JAL | GShare + JAL | BHT-2 full | GShare full |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ubmark-bin-search | 0.7255 | 0.7255 | 0.8037 | 0.8119 | 0.7857 | 0.8369 | 0.8091 | 0.8369 | 0.8091 |
| ubmark-cmplx-mult | 0.7369 | 0.7369 | 0.7640 | 0.7640 | 0.7556 | 0.7702 | 0.7617 | 0.7702 | 0.7617 |
| ubmark-masked-filter | 0.7201 | 0.7201 | 0.8449 | 0.8535 | 0.8428 | 0.8775 | 0.8662 | 0.8776 | 0.8663 |
| ubmark-vvadd | 0.7455 | 0.7455 | 0.8885 | 0.8885 | 0.8545 | 0.8894 | 0.8554 | 0.8894 | 0.8554 |

## Mispredict rate (%)

| benchmark | branches | BHT-1 | BHT-2 | GShare |
|---|---:|---:|---:|---:|
| ubmark-bin-search | 262 | 26.72 | 24.05 | 32.82 |
| ubmark-cmplx-mult | 271 | 5.17 | 5.17 | 12.55 |
| ubmark-masked-filter | 1170 | 9.23 | 5.64 | 10.09 |
| ubmark-vvadd | 139 | 13.67 | 13.67 | 30.22 |
