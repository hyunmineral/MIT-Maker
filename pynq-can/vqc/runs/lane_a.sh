#!/bin/bash
# VQC seeds 1,2 (seed 0 = vqc_params.json)
cd "$(dirname "$0")/.."
for s in 1 2; do python train.py --model vqc --seed $s --out runs/vqc_s$s.json > runs/vqc_s$s.log 2>&1; done
echo LANE_A_DONE
