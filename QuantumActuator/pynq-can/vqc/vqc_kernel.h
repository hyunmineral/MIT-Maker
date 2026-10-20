#ifndef VQC_KERNEL_H
#define VQC_KERNEL_H

#define VQC_QUBITS 6
#define VQC_LAYERS 4
#define VQC_DIM    64
#define VQC_OBS    8

typedef struct {
    float W[VQC_LAYERS * VQC_QUBITS * 8];   /* fused RZ*RY*RX per (layer, qubit), complex 2x2 */
    float feat_scale[VQC_QUBITS];
    int   feat_index[VQC_QUBITS];
    float tau_max;
    float out_gain;
} vqc_config_t;

float vqc_expval_z0(const float x[VQC_QUBITS], const float W[VQC_LAYERS * VQC_QUBITS * 8]);
float vqc_expval_z0_cs(const float cs[2 * VQC_QUBITS], const float W[VQC_LAYERS * VQC_QUBITS * 8]);
float vqc_policy(const float obs[VQC_OBS], const vqc_config_t *cfg);
void  vqc_policy_batch(const float *obs, int n, const vqc_config_t *cfg, float *out);

#endif
