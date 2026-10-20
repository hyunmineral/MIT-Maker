/*
 * VQC policy kernel: 6 qubits, 4 data-reuploading layers, <Z0> readout.
 * Same arithmetic as vqc_model.py, float32, no dynamic memory, fixed loop
 * bounds -> builds with gcc on the PYNQ PS (ctypes .so) and with Vitis HLS.
 *
 * W[l][q] = RZ(t2) * RY(t1) * RX(t0) is precomputed on the host from the 72
 * trained angles (vqc_runtime.fused_weights) and stored as 8 floats:
 *   {re00, im00, re01, im01, re10, im10, re11, im11}
 * Per call only the encoding RY(x_q) is folded in: U = W[l][q] * RY(x_q).
 * Qubit 0 is the MSB of the 6-bit basis index.
 *
 *   gcc -O3 -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -ffast-math -shared -fPIC \
 *       -o libvqc.so vqc_kernel.c -lm
 */
#include <math.h>
#include "vqc_kernel.h"

/* new_state[i] = old_state[VQC_PERM[i]] after CNOT(0,1) ... CNOT(5,0) */
static const unsigned char VQC_PERM[VQC_DIM] = {
#include "vqc_perm.inc"
};

/* One single-qubit gate: reads (re, im), writes (ore, oim). Out-of-place so that
   pipelined iterations never read what an earlier iteration wrote (II=1 in HLS). */
static void apply_1q(const float re[VQC_DIM], const float im[VQC_DIM],
                     float ore[VQC_DIM], float oim[VQC_DIM], int q, const float u[8])
{
#pragma HLS INLINE
    const int stride = 1 << (VQC_QUBITS - 1 - q);
apply_loop:
    for (int k = 0; k < VQC_DIM / 2; k++) {
#pragma HLS PIPELINE II=1
        /* k-th index with bit (stride) cleared */
        const int i0 = ((k & ~(stride - 1)) << 1) | (k & (stride - 1));
        const int i1 = i0 | stride;
        const float ar = re[i0], ai = im[i0], br = re[i1], bi = im[i1];
        ore[i0] = u[0] * ar - u[1] * ai + u[2] * br - u[3] * bi;
        oim[i0] = u[0] * ai + u[1] * ar + u[2] * bi + u[3] * br;
        ore[i1] = u[4] * ar - u[5] * ai + u[6] * br - u[7] * bi;
        oim[i1] = u[4] * ai + u[5] * ar + u[6] * bi + u[7] * br;
    }
}

float vqc_expval_z0(const float x[VQC_QUBITS], const float W[VQC_LAYERS * VQC_QUBITS * 8])
{
    float cs[2 * VQC_QUBITS];
enc_angles:
    for (int q = 0; q < VQC_QUBITS; q++) {
        cs[2 * q] = cosf(0.5f * x[q]);
        cs[2 * q + 1] = sinf(0.5f * x[q]);
    }
    return vqc_expval_z0_cs(cs, W);
}

/* State-vector part only (what the PL core implements): cs = {cos(x_q/2), sin(x_q/2)} */
float vqc_expval_z0_cs(const float cs[2 * VQC_QUBITS], const float W[VQC_LAYERS * VQC_QUBITS * 8])
{
    float re[VQC_DIM], im[VQC_DIM], tr[VQC_DIM], ti[VQC_DIM];
    /* HLS: keep the 64-amplitude state in registers so the butterflies and the
       CNOT permutation are not limited by BRAM ports (gcc ignores these). */
#pragma HLS ARRAY_PARTITION variable=re complete
#pragma HLS ARRAY_PARTITION variable=im complete
#pragma HLS ARRAY_PARTITION variable=tr complete
#pragma HLS ARRAY_PARTITION variable=ti complete

init_state:
    for (int i = 0; i < VQC_DIM; i++) {
        re[i] = (i == 0) ? 1.0f : 0.0f;
        im[i] = 0.0f;
    }

layers:
    for (int l = 0; l < VQC_LAYERS; l++) {
#pragma HLS LOOP_FLATTEN off
    qubits:
        for (int q = 0; q < VQC_QUBITS; q++) {
#pragma HLS LOOP_FLATTEN off
            const float *w = &W[(l * VQC_QUBITS + q) * 8];
            const float c = cs[2 * q], s = cs[2 * q + 1];
            /* U = W * RY(x),  RY = [[c, -s], [s, c]] (real) */
            float u[8];
            u[0] = w[0] * c + w[2] * s;   u[1] = w[1] * c + w[3] * s;
            u[2] = -w[0] * s + w[2] * c;  u[3] = -w[1] * s + w[3] * c;
            u[4] = w[4] * c + w[6] * s;   u[5] = w[5] * c + w[7] * s;
            u[6] = -w[4] * s + w[6] * c;  u[7] = -w[5] * s + w[7] * c;
            apply_1q(re, im, tr, ti, q, u);
        back:
            for (int i = 0; i < VQC_DIM; i++) {
#pragma HLS UNROLL
                re[i] = tr[i];
                im[i] = ti[i];
            }
        }
    perm:
        for (int i = 0; i < VQC_DIM; i++) {
#pragma HLS UNROLL
            tr[i] = re[VQC_PERM[i]];
            ti[i] = im[VQC_PERM[i]];
        }
    copy:
        for (int i = 0; i < VQC_DIM; i++) {
#pragma HLS UNROLL
            re[i] = tr[i];
            im[i] = ti[i];
        }
    }

    float z = 0.0f;
measure:
    for (int i = 0; i < VQC_DIM; i++) {
#pragma HLS PIPELINE II=1
        const float p = re[i] * re[i] + im[i] * im[i];
        z += (i < VQC_DIM / 2) ? p : -p;
    }
    return z;
}

float vqc_policy(const float obs[VQC_OBS], const vqc_config_t *cfg)
{
    float x[VQC_QUBITS];
features:
    for (int q = 0; q < VQC_QUBITS; q++)
        x[q] = 3.14159265358979f * tanhf(cfg->feat_scale[q] * obs[cfg->feat_index[q]]);
    return cfg->tau_max * tanhf(cfg->out_gain * vqc_expval_z0(x, cfg->W));
}

void vqc_policy_batch(const float *obs, int n, const vqc_config_t *cfg, float *out)
{
    for (int i = 0; i < n; i++)
        out[i] = vqc_policy(&obs[i * VQC_OBS], cfg);
}
