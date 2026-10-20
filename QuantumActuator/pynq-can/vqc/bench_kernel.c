/* Pure-C timing of vqc_policy on the PS:  gcc -O3 ... bench_kernel.c vqc_kernel.c -lm */
#include <stdio.h>
#include <time.h>
#include "vqc_kernel.h"

int main(void)
{
    vqc_config_t cfg = {0};
    for (int i = 0; i < VQC_LAYERS * VQC_QUBITS * 8; i++) cfg.W[i] = (i % 8 == 0 || i % 8 == 6) ? 1.0f : 0.0f;
    for (int q = 0; q < VQC_QUBITS; q++) { cfg.feat_scale[q] = 1.0f; cfg.feat_index[q] = q; }
    cfg.tau_max = 0.8f; cfg.out_gain = 2.0f;
    float obs[VQC_OBS] = {0.1f, 0.2f, 0.01f, 0.5f, 0.3f, 1.0f, 2.0f, 0.0f};
    volatile float sink = 0;
    const int n = 100000;
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int i = 0; i < n; i++) { obs[0] = i * 1e-6f; sink += vqc_policy(obs, &cfg); }
    clock_gettime(CLOCK_MONOTONIC, &b);
    printf("vqc_policy: %.2f us/call\n", ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / n / 1e3);
    return 0;
}
