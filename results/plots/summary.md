# Predictor benchmark summary

## IPC

| benchmark | baseline | static-NT | BHT-1 | BHT-2 | GShare | BHT-2 + JAL | GShare + JAL | BHT-2 full | GShare full |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ubmark-bin-search | 0.7048 | 0.7048 | 0.7865 | 0.7952 | 0.7664 | 0.8215 | 0.7908 | 0.8215 | 0.7908 |
| ubmark-cmplx-mult | 0.7105 | 0.7105 | 0.7236 | 0.7236 | 0.7194 | 0.7239 | 0.7197 | 0.7239 | 0.7197 |
| ubmark-masked-filter | 0.6622 | 0.6622 | 0.7064 | 0.7153 | 0.7115 | 0.7394 | 0.7354 | 0.7394 | 0.7354 |
| ubmark-vvadd | 0.8865 | 0.8865 | 0.9115 | 0.9115 | 0.8830 | 0.9115 | 0.8830 | 0.9115 | 0.8830 |

## Mispredict rate (%)

| benchmark | branches | BHT-1 | BHT-2 | GShare |
|---|---:|---:|---:|---:|
| ubmark-bin-search | 246 | 23.98 | 21.14 | 30.89 |
| ubmark-cmplx-mult | 27 | 11.11 | 11.11 | 37.04 |
| ubmark-masked-filter | 668 | 14.37 | 7.93 | 10.63 |
| ubmark-vvadd | 10 | 20.00 | 20.00 | 100.00 |
