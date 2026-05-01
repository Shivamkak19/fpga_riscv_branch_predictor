#=========================================================================
# synth_variant.tcl - Vivado batch synthesis for one predictor variant
#=========================================================================
# Usage (on bench host):
#   vivado -mode batch -nojournal -nolog -source synth_variant.tcl \
#          -tclargs <variant>
#
# variant ∈ { baseline | bp_static_nt | bp_bht1 | bp_bht2 | bp_gshare }
#
# Expects an existing Vivado project at ~/riscv-fpga/xilinx_proj/xilinx_proj.xpr
# whose source paths point at ~/ece475-lab4/riscvlong/ (i.e. the lab tree).
#
# This script:
#   1. Overlays the variant's RTL into ~/ece475-lab4/riscvlong/ + adds
#      ~/ece475-lab4/bp/ when the variant is a predictor build.
#   2. Sets the appropriate `BP_*` verilog defines on the project's fileset.
#   3. Resets / re-runs synth and impl, generates the bitstream.
#   4. Exports utilization + timing summary reports to ~/results/<variant>/.

if {[llength $argv] < 1} {
  puts "ERROR: variant argument required"
  exit 1
}
set variant [lindex $argv 0]
set repo_root [file normalize [file dirname [info script]]/../..]
set project_xpr "$::env(HOME)/riscv-fpga/xilinx_proj/xilinx_proj.xpr"
set lab_root    "$::env(HOME)/ece475-lab4"
set results_dir "$::env(HOME)/results/$variant"

file mkdir $results_dir

#-------------------------------------------------------------------------
# 1. Overlay RTL.
#-------------------------------------------------------------------------
puts "[INFO] Overlaying RTL for variant=$variant"

set defines {}
switch -- $variant {
  baseline {
    # Restore the unmodified lab RTL.
    set src_dir "$repo_root/rtl/baseline/riscvlong"
    foreach f [glob -nocomplain "$src_dir/*.v"] {
      file copy -force $f "$lab_root/riscvlong/[file tail $f]"
    }
  }
  bp_static_nt - bp_bht1 - bp_bht2 - bp_gshare {
    # Predictor-aware core + BP modules.
    set core_dir "$repo_root/rtl/core"
    foreach f [glob -nocomplain "$core_dir/*.v"] {
      file copy -force $f "$lab_root/riscvlong/[file tail $f]"
    }
    set bp_dir "$repo_root/rtl/bp"
    file mkdir "$lab_root/bp"
    foreach f [glob -nocomplain "$bp_dir/*.v"] {
      file copy -force $f "$lab_root/bp/[file tail $f]"
    }
    lappend defines "BP_ENABLED"
    switch -- $variant {
      bp_static_nt { lappend defines "BP_STATIC_NT" }
      bp_bht1      { lappend defines "BP_BHT1" }
      bp_bht2      { lappend defines "BP_BHT2" }
      bp_gshare    { lappend defines "BP_GSHARE" }
    }
  }
  default {
    puts "ERROR: unknown variant $variant"
    exit 1
  }
}

#-------------------------------------------------------------------------
# 2. Open project and set defines + add bp dir to include path.
#-------------------------------------------------------------------------
open_project $project_xpr

# Make sure the bp/ folder is on the Verilog include path. Re-add files from
# the riscvlong dir + bp dir as design sources (idempotent — Vivado dedupes).
if {[lsearch -exact [get_filesets sources_1] sources_1] >= 0 || \
    [llength [get_filesets -quiet sources_1]] > 0} {
  set fs [get_filesets sources_1]
  set inc_paths [list "$lab_root/riscvlong" "$lab_root/vc" "$lab_root/imuldiv" "$lab_root/bp"]
  set_property include_dirs $inc_paths $fs
  if {$variant ne "baseline"} {
    foreach f [glob -nocomplain "$lab_root/bp/*.v"] {
      add_files -norecurse -fileset $fs $f
    }
  } else {
    # Remove any bp-* files that may be lingering from a prior predictor run
    foreach f [get_files -of_objects $fs -filter {NAME =~ "*/bp/*.v"}] {
      remove_files -fileset $fs $f
    }
  }
  if {[llength $defines] > 0} {
    set_property verilog_define $defines $fs
  } else {
    set_property verilog_define {} $fs
  }
}

#-------------------------------------------------------------------------
# 3. Reset and rerun.
#-------------------------------------------------------------------------
puts "[INFO] Resetting and re-running synth+impl for $variant"
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

#-------------------------------------------------------------------------
# 4. Export reports.
#-------------------------------------------------------------------------
open_run impl_1
report_utilization -file "$results_dir/utilization.rpt"
report_timing_summary -file "$results_dir/timing_summary.rpt"
report_timing -delay_type max -max_paths 25 -file "$results_dir/timing_paths.rpt"
report_power -file "$results_dir/power.rpt"

# Capture bitstream
set bit "$::env(HOME)/riscv-fpga/xilinx_proj/xilinx_proj.runs/impl_1/fpga_top.bit"
if {[file exists $bit]} {
  file copy -force $bit "$results_dir/fpga_top.bit"
}

puts "[INFO] $variant DONE — reports at $results_dir"
close_project
exit 0
