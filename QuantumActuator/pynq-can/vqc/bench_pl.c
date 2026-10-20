/* Pure-C timing of the PL path (needs root and a loaded vqc_can0 overlay):
#include <math.h>
     gcc -O3 ... bench_pl.c vqc_pl_driver.c vqc_kernel.c -lm && sudo ./bench_pl 0x40000000 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "vqc_kernel.h"

int vqc_pl_open(unsigned base, unsigned cs_off, unsigned w_off, unsigned z_off);
void vqc_pl_load_w(const float *W);
float vqc_pl_expval(const float obs[VQC_OBS], const vqc_config_t *cfg, int *core_polls);
float vqc_pl_policy(const float obs[VQC_OBS], const vqc_config_t *cfg);

static double now_us(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1e6 + t.tv_nsec / 1e3;
}

static int cmp(const void *a, const void *b) { double d = *(double *)a - *(double *)b; return (d > 0) - (d < 0); }

int main(int argc, char **argv)
{
    unsigned base = argc > 1 ? strtoul(argv[1], 0, 0) : 0x40000000u;
    if (vqc_pl_open(base, 0x40, 0x400, 0x10)) { perror("vqc_pl_open"); return 1; }
    vqc_config_t cfg = {0};
    for (int i = 0; i < VQC_LAYERS * VQC_QUBITS * 8; i++) cfg.W[i] = ((i * 37) % 17 - 8) / 8.0f;
    for (int q = 0; q < VQC_QUBITS; q++) { cfg.feat_scale[q] = 1.0f; cfg.feat_index[q] = q; }
    cfg.tau_max = 0.8f; cfg.out_gain = 2.0f;
    vqc_pl_load_w(cfg.W);
    enum { N = 20000 };
    static double pl[N], ps[N];
    float obs[VQC_OBS] = {0.1f, 0.2f, 0.01f, 0.5f, 0.3f, 1.0f, 2.0f, 0.0f};
    double worst = 0;
    for (int i = 0; i < N; i++) {
        obs[0] = (i % 200) * 0.01f - 1.0f;
        double t0 = now_us(); float a = vqc_pl_policy(obs, &cfg);
        double t1 = now_us(); float b = vqc_policy(obs, &cfg);
        double t2 = now_us();
        pl[i] = t1 - t0; ps[i] = t2 - t1;
        if (fabs(a - b) > worst) worst = fabs(a - b);
    }
    qsort(pl, N, sizeof(double), cmp); qsort(ps, N, sizeof(double), cmp);
    printf("PL path (C): p50 %.1f  p99 %.1f  max %.1f us\n", pl[N / 2], pl[N * 99 / 100], pl[N - 1]);
    printf("PS kernel  : p50 %.1f  p99 %.1f  max %.1f us\n", ps[N / 2], ps[N * 99 / 100], ps[N - 1]);
    printf("max |PL - PS| over %d calls = %.2e\n", N, worst);
    return 0;
}
