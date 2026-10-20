#!/bin/bash
# MLP baselines: small (6-8-1, 65 params) and large (6-64-64-1, 4673 params), seeds 0-2
cd "$(dirname "$0")/.."
for h in 8 64,64; do for s in 0 1 2; do
  python train.py --model mlp --hidden $h --seed $s --out runs/mlp_${h/,/x}_s$s.json > runs/mlp_${h/,/x}_s$s.log 2>&1
done; done
echo LANE_B_DONE
