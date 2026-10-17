# Build the VQC kernel as a shared library on the PYNQ PS (Cortex-A9).
CFLAGS ?= -O3 -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -ffast-math -fPIC -Wall -Wno-unused-label -Wno-unknown-pragmas

libvqc.so: vqc_kernel.c vqc_pl_driver.c vqc_kernel.h vqc_perm.inc
	$(CC) $(CFLAGS) -shared -o $@ vqc_kernel.c vqc_pl_driver.c -lm

clean:
	rm -f libvqc.so

bench: bench_kernel.c vqc_kernel.c vqc_kernel.h vqc_perm.inc
	$(CC) $(CFLAGS) -o bench bench_kernel.c vqc_kernel.c -lm && ./bench

bench_pl: bench_pl.c vqc_pl_driver.c vqc_kernel.c vqc_kernel.h vqc_perm.inc
	$(CC) $(CFLAGS) -o bench_pl bench_pl.c vqc_pl_driver.c vqc_kernel.c -lm
