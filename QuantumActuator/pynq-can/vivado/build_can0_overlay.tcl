# PYNQ-Z2 overlay: Zynq PS CAN0 routed through EMIO to Pmod JA,
# plus the VQC policy core on AXI4-Lite when the HLS IP has been exported.
#
#   JA1 (Y18)  <- CAN0_PHY_TX  -> SN65HVD230 "CTX"/"D"
#   JA2 (Y19)  -> CAN0_PHY_RX  <- SN65HVD230 "CRX"/"R"
#   JA pin 5/11 = GND, pin 6/12 = 3V3 for the transceiver module
#
# Run (from this directory):
#   vivado -mode batch -nojournal -source build_can0_overlay.tcl [-tclargs can_only]
# Output: ./out/<name>.bit + ./out/<name>.hwh  (copy both to the board, same basename)
#   name = vqc_can0 if ../hls/vqc_hls/sol1/impl/ip exists (run_hls.tcl), else can0

set script_dir [file normalize [file dirname [info script]]]
set out_dir    $script_dir/out
set ip_dir     [file normalize $script_dir/../hls/vqc_hls/sol1/impl/ip]
set with_vqc   [file exists $ip_dir/component.xml]
if {[llength $argv] && [lindex $argv 0] eq "can_only"} { set with_vqc 0 }
set name       [expr {$with_vqc ? "vqc_can0" : "can0"}]
set proj_dir   $script_dir/build/$name

set_param board.repoPaths [list $script_dir/board_files]
file mkdir $out_dir
create_project $name $proj_dir -part xc7z020clg400-1 -force
set_property board_part tul.com.tw:pynq-z2:part0:1.0 [current_project]
if {$with_vqc} {
    set_property ip_repo_paths [list $ip_dir] [current_project]
    update_ip_catalog
}

create_bd_design $name
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} $ps

# CAN0 on EMIO. Loading the bitstream does not rerun ps7_init, so the 100 MHz
# CAN ref clock is actually set by can0-enable.dtbo (assigned-clock-rates);
# the value here only keeps the .hwh consistent.
set_property -dict [list \
    CONFIG.PCW_CAN0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_CAN0_CAN0_IO {EMIO} \
    CONFIG.PCW_CAN_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0 $with_vqc \
    CONFIG.PCW_EN_CLK0_PORT $with_vqc \
    CONFIG.PCW_EN_RST0_PORT $with_vqc \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
] $ps

create_bd_port -dir O can0_tx
create_bd_port -dir I can0_rx
connect_bd_net [get_bd_pins ps7/CAN0_PHY_TX] [get_bd_ports can0_tx]
connect_bd_net [get_bd_pins ps7/CAN0_PHY_RX] [get_bd_ports can0_rx]

if {$with_vqc} {
    create_bd_cell -type ip -vlnv robot:hls:vqc_top:1.0 vqc_top_0
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
        -config {Master "/ps7/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins vqc_top_0/s_axi_ctrl]
}

validate_bd_design
save_bd_design

set xdc $proj_dir/can0_pmod_ja.xdc
set fh [open $xdc w]
puts $fh {set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports can0_tx]}
puts $fh {set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 PULLUP true} [get_ports can0_rx]}
close $fh
add_files -fileset constrs_1 $xdc

set bd_file [get_files $name.bd]
generate_target all $bd_file
make_wrapper -files $bd_file -top
add_files -norecurse [glob $proj_dir/$name.gen/sources_1/bd/$name/hdl/${name}_wrapper.v]
set_property top ${name}_wrapper [current_fileset]

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation failed"
}

open_run impl_1
report_utilization -file $out_dir/${name}_utilization.rpt
report_timing_summary -file $out_dir/${name}_timing.rpt
file copy -force $proj_dir/$name.runs/impl_1/${name}_wrapper.bit $out_dir/$name.bit
file copy -force [glob $proj_dir/$name.gen/sources_1/bd/$name/hw_handoff/$name.hwh] $out_dir/$name.hwh
if {$with_vqc} {
    file copy -force [glob $ip_dir/drivers/vqc_top_v1_0/src/xvqc_top_hw.h] $out_dir/xvqc_top_hw.h
}
puts "BUILD_OK $out_dir/$name.bit (vqc=$with_vqc)"
