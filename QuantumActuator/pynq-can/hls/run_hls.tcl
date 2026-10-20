# Vitis HLS: csim + csynth + export IP for the VQC policy core.
#   vitis-run --mode hls --tcl run_hls.tcl      (2024.2+)   or   vitis_hls -f run_hls.tcl
open_project -reset vqc_hls
set_top vqc_top
add_files vqc_top.c
add_files ../vqc/vqc_kernel.c -cflags "-I../vqc"
add_files -tb tb_vqc.c -cflags "-I../vqc"
add_files -tb tb_vectors.h
open_solution -reset sol1 -flow_target vivado
set_part xc7z020clg400-1
create_clock -period 10 -name default
if {![info exists ::env(HLS_SKIP_CSIM)]} { csim_design }
csynth_design
if {![info exists ::env(HLS_SYNTH_ONLY)]} { export_design -format ip_catalog -vendor robot -library hls -version 1.0 -display_name "VQC policy" }
exit
