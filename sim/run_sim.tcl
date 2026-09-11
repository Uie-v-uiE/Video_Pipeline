# Behavioral simulation via xsim CLI
# Usage: vivado -mode batch -source sim/run_sim.tcl

set root [file normalize [file join [file dirname [info script]] ..]]
set work [file join $root vivado_sim]
file mkdir $work
cd $work

set rtl_files [list \
  [file join $root rtl process proc_gray.v] \
  [file join $root rtl process proc_binary.v] \
  [file join $root rtl process proc_invert.v] \
  [file join $root rtl process effect_ctrl.v] \
  [file join $root rtl video video_timing.v] \
  [file join $root rtl video color_bar.v] \
  [file join $root rtl util key_debounce.v] \
  [file join $root rtl process rotate sin_rom.v] \
  [file join $root rtl process rotate cos_rom.v] \
  [file join $root rtl process rotate rotate_mapper.v] \
  [file join $root rtl process rotate angle_ctrl.v] \
]

set tb_list {tb_proc_gray tb_timing tb_uart_decode_bits tb_rotate_mapper}
set tb_files {}
foreach tb $tb_list {
  lappend tb_files [file join $root sim ${tb}.v]
}

puts "INFO: xvlog ..."
if {[catch {exec xvlog {*}$rtl_files {*}$tb_files} msg]} {
  puts $msg
}

foreach tb $tb_list {
  puts "INFO: xelab $tb"
  if {[catch {exec xelab -debug typical $tb -s ${tb}_snap} msg]} {
    puts "ELAB-FAIL $tb"
    puts $msg
    continue
  }
  puts "INFO: xsim $tb"
  set rc [catch {exec xsim ${tb}_snap -R} msg]
  puts $msg
  if {[string match "*PASS*" $msg]} {
    puts "RESULT PASS $tb"
  } else {
    puts "RESULT CHECK $tb"
  }
}

puts "SIM-FINISHED"
