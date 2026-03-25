# Recreate Vivado project from clean GitHub layout
set proj_name "RoCEv2_AI_Opt"
set proj_dir [file normalize "."]

create_project $proj_name $proj_dir -part xcvu9p-flga2104-2-e -force

add_files [glob -nocomplain src/*.v]
add_files -fileset sim_1 [glob -nocomplain sim/*.v]
add_files -fileset constrs_1 [glob -nocomplain cons/*.xdc]

set_property top roce_ecn_marker [get_filesets sources_1]
set_property top tb_roce_ecn_marker [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "PROJECT_CREATE_OK"
