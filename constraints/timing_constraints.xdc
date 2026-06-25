create_clock -period 6.666 -name CLK [get_ports CLK]
create_clock -period 3.333 -name REF_CLK_300MHZ [get_ports REF_CLK_300MHZ]

set_clock_uncertainty 0.100 [get_clocks CLK]


set_input_delay -clock CLK -max 1.600 [get_ports {S_AXIS_TVALID {S_AXIS_TDATA[*]} S_AXIS_TLAST {S_AXIS_TKEEP[*]}}]
set_input_delay -clock CLK -min 0.400 [get_ports {S_AXIS_TVALID {S_AXIS_TDATA[*]} S_AXIS_TLAST {S_AXIS_TKEEP[*]}}]

set_input_delay -clock CLK -max 2.000 [get_ports {S_PAYLOAD_LEN[*]}]
set_input_delay -clock CLK -min 0.500 [get_ports {S_PAYLOAD_LEN[*]}]


# set_output_delay -clock CLK -max $OUT_MAX [get_ports {M_AXIS_TVALID M_AXIS_TDATA[*] M_AXIS_TLAST M_AXIS_TKEEP[*]}]
# set_output_delay -clock CLK -min $OUT_MIN [get_ports {M_AXIS_TVALID M_AXIS_TDATA[*] M_AXIS_TLAST M_AXIS_TKEEP[*]}]

# Apply constraints to the upstream backpressure signal (Slave Ready)
set_output_delay -clock CLK -max 1.600 [get_ports S_AXIS_TREADY]
set_output_delay -clock CLK -min 0.200 [get_ports S_AXIS_TREADY]

# Apply constraints to the downstream backpressure input (Master Ready)
set_input_delay -clock CLK -max 1.600 [get_ports M_AXIS_TREADY]
set_input_delay -clock CLK -min 0.400 [get_ports M_AXIS_TREADY]

# set_property IOB TRUE [get_cells output_data_q_reg[*]]

create_generated_clock -name fwd_m_axis_aclk -source [get_pins clk_fwd_inst/C] -divide_by 1 [get_ports M_AXIS_ACLK]


set_output_delay -clock fwd_m_axis_aclk -max 1.600 [get_ports {M_AXIS_TVALID {M_AXIS_TDATA[*]} M_AXIS_TLAST {M_AXIS_TKEEP[*]}}]
set_output_delay -clock fwd_m_axis_aclk -min 0.200 [get_ports {M_AXIS_TVALID {M_AXIS_TDATA[*]} M_AXIS_TLAST {M_AXIS_TKEEP[*]}}]


set_input_delay -clock [get_clocks fwd_m_axis_aclk] -max 1.000 [get_ports M_AXIS_TREADY]
set_input_delay -clock [get_clocks fwd_m_axis_aclk] -min 0.200 [get_ports M_AXIS_TREADY]

# ==============================================================================
# 4. ASYNCHRONOUS / TIMING EXCEPTIONS
# ==============================================================================
# Treat the system reset as an asynchronous signal for recovery/removal analysis.
# This prevents the tool from destroying data-path routing just to meet reset timing.
set_false_path -from [get_ports RST_N]

set_property PACKAGE_PIN K26 [get_ports {M_AXIS_TDATA[31]}]
set_property PACKAGE_PIN K25 [get_ports {M_AXIS_TDATA[30]}]
set_property PACKAGE_PIN L25 [get_ports {M_AXIS_TDATA[29]}]
set_property PACKAGE_PIN L24 [get_ports {M_AXIS_TDATA[28]}]
set_property PACKAGE_PIN K23 [get_ports {M_AXIS_TDATA[27]}]
set_property PACKAGE_PIN K22 [get_ports {M_AXIS_TDATA[26]}]
set_property PACKAGE_PIN J24 [get_ports {M_AXIS_TDATA[25]}]
set_property PACKAGE_PIN J23 [get_ports {M_AXIS_TDATA[24]}]
set_property PACKAGE_PIN G25 [get_ports {M_AXIS_TDATA[23]}]
set_property PACKAGE_PIN G24 [get_ports {M_AXIS_TDATA[22]}]
set_property PACKAGE_PIN H24 [get_ports {M_AXIS_TDATA[21]}]
set_property PACKAGE_PIN H23 [get_ports {M_AXIS_TDATA[20]}]
set_property PACKAGE_PIN J26 [get_ports {M_AXIS_TDATA[19]}]
set_property PACKAGE_PIN J25 [get_ports {M_AXIS_TDATA[18]}]
set_property PACKAGE_PIN F25 [get_ports {M_AXIS_TDATA[17]}]
set_property PACKAGE_PIN F24 [get_ports {M_AXIS_TDATA[16]}]
set_property PACKAGE_PIN G26 [get_ports {M_AXIS_TDATA[15]}]
set_property PACKAGE_PIN H26 [get_ports {M_AXIS_TDATA[14]}]
set_property PACKAGE_PIN H22 [get_ports {M_AXIS_TDATA[13]}]
set_property PACKAGE_PIN H21 [get_ports {M_AXIS_TDATA[12]}]
set_property PACKAGE_PIN E26 [get_ports {M_AXIS_TDATA[11]}]
set_property PACKAGE_PIN E25 [get_ports {M_AXIS_TDATA[10]}]
set_property PACKAGE_PIN E23 [get_ports {M_AXIS_TDATA[9]}]
set_property PACKAGE_PIN F23 [get_ports {M_AXIS_TDATA[8]}]
set_property PACKAGE_PIN D25 [get_ports {M_AXIS_TDATA[7]}]
set_property PACKAGE_PIN D24 [get_ports {M_AXIS_TDATA[6]}]
set_property PACKAGE_PIN C24 [get_ports {M_AXIS_TDATA[5]}]
set_property PACKAGE_PIN D23 [get_ports {M_AXIS_TDATA[4]}]
set_property PACKAGE_PIN C26 [get_ports {M_AXIS_TDATA[3]}]
set_property PACKAGE_PIN D26 [get_ports {M_AXIS_TDATA[2]}]
set_property PACKAGE_PIN B26 [get_ports {M_AXIS_TDATA[1]}]
set_property PACKAGE_PIN B25 [get_ports {M_AXIS_TDATA[0]}]
set_property PACKAGE_PIN L23 [get_ports M_AXIS_TLAST]
set_property PACKAGE_PIN L22 [get_ports M_AXIS_TREADY]
set_property PACKAGE_PIN M24 [get_ports M_AXIS_TVALID]
