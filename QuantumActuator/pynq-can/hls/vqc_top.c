/*
 * Vitis HLS top for the VQC core (AXI4-Lite slave, 100 MHz FCLK0).
 *
 * The PL computes only the state-vector part: 64 complex amplitudes, 24 fused
 * single-qubit gates and 4 CNOT rings, returning <Z0>. The PS does the cheap
 * scalar pre/post-processing (features -> cos/sin(x/2), tau = tau_max*tanh(g*z)).
 * Keeping transcendental functions out of the PL avoided a board-only mismatch:
 * the HLS tanh/exp(double) datapath passed C/RTL co-simulation but returned
 * wrong values for mid-range inputs on the PYNQ-Z2 (see docs report §5).
 */
#include "../vqc/vqc_kernel.h"

void vqc_top(const float cs[2 * VQC_QUBITS],
             const float W[VQC_LAYERS * VQC_QUBITS * 8],
             float *z)
{
#pragma HLS INTERFACE mode=s_axilite port=cs     bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=W      bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=z      bundle=ctrl
#pragma HLS INTERFACE mode=s_axilite port=return bundle=ctrl
    float cs_l[2 * VQC_QUBITS], w_l[VQC_LAYERS * VQC_QUBITS * 8];
copy_cs:
    for (int i = 0; i < 2 * VQC_QUBITS; i++) cs_l[i] = cs[i];
copy_w:
    for (int i = 0; i < VQC_LAYERS * VQC_QUBITS * 8; i++) w_l[i] = W[i];
    *z = vqc_expval_z0_cs(cs_l, w_l);
}
