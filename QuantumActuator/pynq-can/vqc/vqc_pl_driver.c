/*
 * Thin user-space driver for the vqc_top PL core (PYNQ-Z2), built into libvqc.so.
 * One call does the PS-side pre/post-processing and the register traffic:
 *   features -> cos/sin(x/2) -> CS regs -> ap_start -> poll ap_done -> Z reg -> tau
 * Python-level MMIO on the Cortex-A9 cost ~250 us per call; this path is one
 * ctypes call. Needs root (/dev/mem); the PL must already be programmed
 * (pynq.Overlay) and the W registers loaded with vqc_pl_load_w().
 */
#include <fcntl.h>
#include <math.h>
#include <stdint.h>
#include <sys/mman.h>
#include <unistd.h>
#include "vqc_kernel.h"

#define VQC_PL_SPAN 0x10000u

static volatile uint32_t *regs;
static uint32_t off_cs, off_w, off_z;

int vqc_pl_open(uint32_t base, uint32_t cs_off, uint32_t w_off, uint32_t z_off)
{
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0)
        return -1;
    void *p = mmap(0, VQC_PL_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
    close(fd);
    if (p == MAP_FAILED)
        return -2;
    regs = (volatile uint32_t *)p;
    off_cs = cs_off / 4;
    off_w = w_off / 4;
    off_z = z_off / 4;
    return 0;
}

void vqc_pl_load_w(const float *W)
{
    for (int i = 0; i < VQC_LAYERS * VQC_QUBITS * 8; i++) {
        union { float f; uint32_t u; } v = { .f = W[i] };
        regs[off_w + i] = v.u;
    }
}

/* Returns <Z0>; *core_polls gets the number of ap_ctrl reads until done. */
float vqc_pl_expval(const float obs[VQC_OBS], const vqc_config_t *cfg, int *core_polls)
{
    for (int q = 0; q < VQC_QUBITS; q++) {
        const float x = 3.14159265358979f * tanhf(cfg->feat_scale[q] * obs[cfg->feat_index[q]]);
        union { float f; uint32_t u; } c = { .f = cosf(0.5f * x) }, s = { .f = sinf(0.5f * x) };
        regs[off_cs + 2 * q] = c.u;
        regs[off_cs + 2 * q + 1] = s.u;
    }
    regs[0] = 1u;                                  /* ap_start */
    int n = 0;
    while (!(regs[0] & 2u)) {                      /* ap_done (clear-on-read) */
        if (++n > 1000000)
            return NAN;
    }
    if (core_polls)
        *core_polls = n;
    union { uint32_t u; float f; } z = { .u = regs[off_z] };
    return z.f;
}

float vqc_pl_policy(const float obs[VQC_OBS], const vqc_config_t *cfg)
{
    return cfg->tau_max * tanhf(cfg->out_gain * vqc_pl_expval(obs, cfg, 0));
}
