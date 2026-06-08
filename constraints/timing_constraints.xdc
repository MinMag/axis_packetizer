create_clock -period 4.000 -name CLK [get_ports CLK]

set_clock_uncertainty 0.100 [get_clocks CLK]

set IN_MAX 1.600
set IN_MIN 0.400

set_input_delay -clock CLK -max $IN_MAX [get_ports {S_AXIS_TVALID S_AXIS_TDATA[*] S_AXIS_TLAST S_AXIS_TKEEP[*]}]
set_input_delay -clock CLK -min $IN_MIN [get_ports {S_AXIS_TVALID S_AXIS_TDATA[*] S_AXIS_TLAST S_AXIS_TKEEP[*]}]

set_input_delay -clock CLK -max 2.000 [get_ports S_PAYLOAD_LEN[*]]
set_input_delay -clock CLK -min 0.500 [get_ports S_PAYLOAD_LEN[*]]

set OUT_MAX 1.600
set OUT_MIN 0.200

set_output_delay -clock CLK -max $OUT_MAX [get_ports {M_AXIS_TVALID M_AXIS_TDATA[*] M_AXIS_TLAST M_AXIS_TKEEP[*]}]
set_output_delay -clock CLK -min $OUT_MIN [get_ports {M_AXIS_TVALID M_AXIS_TDATA[*] M_AXIS_TLAST M_AXIS_TKEEP[*]}]

# Apply constraints to the upstream backpressure signal (Slave Ready)
set_output_delay -clock CLK -max $OUT_MAX [get_ports S_AXIS_TREADY]
set_output_delay -clock CLK -min $OUT_MIN [get_ports S_AXIS_TREADY]

# Apply constraints to the downstream backpressure input (Master Ready)
set_input_delay -clock CLK -max $IN_MAX [get_ports M_AXIS_TREADY]
set_input_delay -clock CLK -min $IN_MIN [get_ports M_AXIS_TREADY]


# ==============================================================================
# 4. ASYNCHRONOUS / TIMING EXCEPTIONS
# ==============================================================================
# Treat the system reset as an asynchronous signal for recovery/removal analysis.
# This prevents the tool from destroying data-path routing just to meet reset timing.
set_false_path -from [get_ports RST_N]