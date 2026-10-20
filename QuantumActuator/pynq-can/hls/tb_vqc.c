/* C(/RTL) testbench: PS-side pre/post-processing in C + vqc_top, compared with
   the Python reference vectors in tb_vectors.h (vqc/export_vectors.py). */
#include <math.h>
#include <stdio.h>
#include "../vqc/vqc_kernel.h"
#include "tb_vectors.h"

void vqc_top(const float cs[2 * VQC_QUBITS], const float W[VQC_LAYERS * VQC_QUBITS * 8], float *z);

int main(void)
{
    float worst = 0.0f;
    for (int n = 0; n < TB_N; n++) {
        float cs[2 * VQC_QUBITS], z;
        for (int q = 0; q < VQC_QUBITS; q++) {
            const float x = 3.14159265358979f * tanhf(TB_FEAT_SCALE[q] * TB_OBS[n][TB_FEAT_INDEX[q]]);
            cs[2 * q] = cosf(0.5f * x);
            cs[2 * q + 1] = sinf(0.5f * x);
        }
        vqc_top(cs, TB_W, &z);
        const float tau = TB_TAU_MAX * tanhf(TB_OUT_GAIN * z);
        const float e = fabsf(tau - TB_TAU[n]);
        if (e > worst) worst = e;
    }
    printf("max |tau - ref| = %g over %d vectors\n", worst, TB_N);
    return worst < 1e-4f ? 0 : 1;
}
